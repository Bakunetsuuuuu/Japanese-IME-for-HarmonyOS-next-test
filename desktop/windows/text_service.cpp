#include "text_service.h"

#include <wrl/client.h>

#include "display_attr.h"
#include "globals.h"
#include "langbar.h"

using Microsoft::WRL::ComPtr;

namespace shunti {
namespace win {

namespace {
constexpr LONG CTX_CHARS = 40;   // 変換の文脈に読むカーソルの左の字数 (モデルの文脈の長さ)

const wchar_t* W(const u16& s) { return reinterpret_cast<const wchar_t*>(s.c_str()); }

// 関数を 1 つ持つだけの編集の枠 (TSF では入力欄の文字を触るのはこの中だけ)
class EditSession : public ITfEditSession {
public:
    explicit EditSession(std::function<void(TfEditCookie)> f) : f_(std::move(f)) { dll_add_ref(); }
    STDMETHODIMP QueryInterface(REFIID riid, void** ppv) override {
        if (!ppv) return E_INVALIDARG;
        *ppv = nullptr;
        if (IsEqualIID(riid, IID_IUnknown) || IsEqualIID(riid, IID_ITfEditSession)) *ppv = static_cast<ITfEditSession*>(this);
        if (!*ppv) return E_NOINTERFACE;
        AddRef();
        return S_OK;
    }
    STDMETHODIMP_(ULONG) AddRef() override { return ULONG(InterlockedIncrement(&refs_)); }
    STDMETHODIMP_(ULONG) Release() override {
        LONG n = InterlockedDecrement(&refs_);
        if (!n) delete this;
        return ULONG(n);
    }
    STDMETHODIMP DoEditSession(TfEditCookie ec) override {
        f_(ec);
        return S_OK;
    }

private:
    ~EditSession() { dll_release(); }
    LONG refs_ = 1;
    std::function<void(TfEditCookie)> f_;
};

// 日本語入力のオン・オフを切り替えるキー (半角/全角・漢字・Alt+`)
struct Preserved { const GUID guid; UINT vk; UINT mods; };
// {5A9F1B06-7C3E-4E0B-9E8D-2B6A1F4C7D11} など。この IME の中だけで使う印
const Preserved PRESERVED[] = {
    {{0x5a9f1b06, 0x7c3e, 0x4e0b, {0x9e, 0x8d, 0x2b, 0x6a, 0x1f, 0x4c, 0x7d, 0x11}}, VK_KANJI, TF_MOD_IGNORE_ALL_MODIFIER},
    {{0x5a9f1b07, 0x7c3e, 0x4e0b, {0x9e, 0x8d, 0x2b, 0x6a, 0x1f, 0x4c, 0x7d, 0x11}}, VK_OEM_AUTO, TF_MOD_IGNORE_ALL_MODIFIER},
    {{0x5a9f1b08, 0x7c3e, 0x4e0b, {0x9e, 0x8d, 0x2b, 0x6a, 0x1f, 0x4c, 0x7d, 0x11}}, VK_OEM_ENLW, TF_MOD_IGNORE_ALL_MODIFIER},
    {{0x5a9f1b09, 0x7c3e, 0x4e0b, {0x9e, 0x8d, 0x2b, 0x6a, 0x1f, 0x4c, 0x7d, 0x11}}, VK_OEM_3, TF_MOD_ALT},
};
}  // namespace

TextService::TextService() { dll_add_ref(); }
TextService::~TextService() { dll_release(); }

// ---------------------------------------------------------------- IUnknown

STDMETHODIMP TextService::QueryInterface(REFIID riid, void** ppv) {
    if (!ppv) return E_INVALIDARG;
    *ppv = nullptr;
    if (IsEqualIID(riid, IID_IUnknown) || IsEqualIID(riid, IID_ITfTextInputProcessor) || IsEqualIID(riid, IID_ITfTextInputProcessorEx))
        *ppv = static_cast<ITfTextInputProcessorEx*>(this);
    else if (IsEqualIID(riid, IID_ITfThreadMgrEventSink))
        *ppv = static_cast<ITfThreadMgrEventSink*>(this);
    else if (IsEqualIID(riid, IID_ITfKeyEventSink))
        *ppv = static_cast<ITfKeyEventSink*>(this);
    else if (IsEqualIID(riid, IID_ITfCompositionSink))
        *ppv = static_cast<ITfCompositionSink*>(this);
    else if (IsEqualIID(riid, IID_ITfDisplayAttributeProvider))
        *ppv = static_cast<ITfDisplayAttributeProvider*>(this);
    else if (IsEqualIID(riid, IID_ITfCompartmentEventSink))
        *ppv = static_cast<ITfCompartmentEventSink*>(this);
    if (!*ppv) return E_NOINTERFACE;
    AddRef();
    return S_OK;
}
STDMETHODIMP_(ULONG) TextService::AddRef() { return ULONG(InterlockedIncrement(&refs_)); }
STDMETHODIMP_(ULONG) TextService::Release() {
    LONG n = InterlockedDecrement(&refs_);
    if (!n) delete this;
    return ULONG(n);
}

// ---------------------------------------------------------------- 始まりと終わり

STDMETHODIMP TextService::Activate(ITfThreadMgr* tm, TfClientId cid) { return ActivateEx(tm, cid, 0); }

STDMETHODIMP TextService::ActivateEx(ITfThreadMgr* tm, TfClientId cid, DWORD) {
    tm_ = tm;
    tm_->AddRef();
    cid_ = cid;

    Core& c = core();
    composer_ = std::make_unique<Composer>(c.conv.ok() ? &c.conv : nullptr, &c.learning, &c.dict);
    composer_->set_context_provider([this] { return left_ctx_; });
    cand_.on_click = [this](int i) { on_candidate_clicked(i); };

    ComPtr<ITfSource> src;
    if (SUCCEEDED(tm_->QueryInterface(IID_PPV_ARGS(&src))))
        src->AdviseSink(IID_ITfThreadMgrEventSink, static_cast<ITfThreadMgrEventSink*>(this), &tm_sink_cookie_);
    init_key_sink();
    init_preserved_keys();

    ComPtr<ITfCategoryMgr> cat;
    if (SUCCEEDED(CoCreateInstance(CLSID_TF_CategoryMgr, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&cat)))) {
        cat->RegisterGUID(GUID_AttrInput, &atom_input_);
        cat->RegisterGUID(GUID_AttrConverted, &atom_converted_);
        cat->RegisterGUID(GUID_AttrFocused, &atom_focused_);
    }

    advise_compartment(GUID_COMPARTMENT_KEYBOARD_OPENCLOSE, open_cookie_);
    advise_compartment(GUID_COMPARTMENT_KEYBOARD_INPUTMODE_CONVERSION, conv_cookie_);

    langbar_ = new LangBarButton(this);
    ComPtr<ITfLangBarItemMgr> lbm;
    if (SUCCEEDED(tm_->QueryInterface(IID_PPV_ARGS(&lbm)))) lbm->AddItem(langbar_);

    set_open(true);   // 切り替えてきたら日本語入力から
    return S_OK;
}

STDMETHODIMP TextService::Deactivate() {
    finish_composition();
    cand_.destroy();
    if (langbar_) {
        ComPtr<ITfLangBarItemMgr> lbm;
        if (tm_ && SUCCEEDED(tm_->QueryInterface(IID_PPV_ARGS(&lbm)))) lbm->RemoveItem(langbar_);
        langbar_->detach();
        langbar_->Release();
        langbar_ = nullptr;
    }
    unadvise_compartment(GUID_COMPARTMENT_KEYBOARD_OPENCLOSE, open_cookie_);
    unadvise_compartment(GUID_COMPARTMENT_KEYBOARD_INPUTMODE_CONVERSION, conv_cookie_);
    uninit_preserved_keys();
    uninit_key_sink();
    if (tm_ && tm_sink_cookie_ != TF_INVALID_COOKIE) {
        ComPtr<ITfSource> src;
        if (SUCCEEDED(tm_->QueryInterface(IID_PPV_ARGS(&src)))) src->UnadviseSink(tm_sink_cookie_);
        tm_sink_cookie_ = TF_INVALID_COOKIE;
    }
    if (comp_) { comp_->Release(); comp_ = nullptr; }
    if (comp_ctx_) { comp_ctx_->Release(); comp_ctx_ = nullptr; }
    composer_.reset();
    if (tm_) { tm_->Release(); tm_ = nullptr; }
    cid_ = TF_CLIENTID_NULL;
    return S_OK;
}

bool TextService::init_key_sink() {
    ComPtr<ITfKeystrokeMgr> km;
    if (FAILED(tm_->QueryInterface(IID_PPV_ARGS(&km)))) return false;
    return SUCCEEDED(km->AdviseKeyEventSink(cid_, static_cast<ITfKeyEventSink*>(this), TRUE));
}

void TextService::uninit_key_sink() {
    ComPtr<ITfKeystrokeMgr> km;
    if (tm_ && SUCCEEDED(tm_->QueryInterface(IID_PPV_ARGS(&km)))) km->UnadviseKeyEventSink(cid_);
}

bool TextService::init_preserved_keys() {
    ComPtr<ITfKeystrokeMgr> km;
    if (FAILED(tm_->QueryInterface(IID_PPV_ARGS(&km)))) return false;
    for (auto& p : PRESERVED) {
        TF_PRESERVEDKEY k = {p.vk, p.mods};
        km->PreserveKey(cid_, p.guid, &k, L"", 0);
    }
    return true;
}

void TextService::uninit_preserved_keys() {
    ComPtr<ITfKeystrokeMgr> km;
    if (!tm_ || FAILED(tm_->QueryInterface(IID_PPV_ARGS(&km)))) return;
    for (auto& p : PRESERVED) {
        TF_PRESERVEDKEY k = {p.vk, p.mods};
        km->UnpreserveKey(p.guid, &k);
    }
}

// ---------------------------------------------------------------- オン・オフ (コンパートメント)

bool TextService::advise_compartment(const GUID& g, DWORD& cookie) {
    ComPtr<ITfCompartmentMgr> cm;
    ComPtr<ITfCompartment> c;
    ComPtr<ITfSource> src;
    if (FAILED(tm_->QueryInterface(IID_PPV_ARGS(&cm))) || FAILED(cm->GetCompartment(g, &c)) || FAILED(c.As(&src))) return false;
    return SUCCEEDED(src->AdviseSink(IID_ITfCompartmentEventSink, static_cast<ITfCompartmentEventSink*>(this), &cookie));
}

void TextService::unadvise_compartment(const GUID& g, DWORD& cookie) {
    if (!tm_ || cookie == TF_INVALID_COOKIE) return;
    ComPtr<ITfCompartmentMgr> cm;
    ComPtr<ITfCompartment> c;
    ComPtr<ITfSource> src;
    if (SUCCEEDED(tm_->QueryInterface(IID_PPV_ARGS(&cm))) && SUCCEEDED(cm->GetCompartment(g, &c)) && SUCCEEDED(c.As(&src)))
        src->UnadviseSink(cookie);
    cookie = TF_INVALID_COOKIE;
}

void TextService::set_compartment(const GUID& g, DWORD v) {
    ComPtr<ITfCompartmentMgr> cm;
    ComPtr<ITfCompartment> c;
    if (!tm_ || FAILED(tm_->QueryInterface(IID_PPV_ARGS(&cm))) || FAILED(cm->GetCompartment(g, &c))) return;
    VARIANT var;
    VariantInit(&var);
    var.vt = VT_I4;
    var.lVal = LONG(v);
    c->SetValue(cid_, &var);
}

DWORD TextService::get_compartment(const GUID& g, bool* ok) {
    if (ok) *ok = false;
    ComPtr<ITfCompartmentMgr> cm;
    ComPtr<ITfCompartment> c;
    if (!tm_ || FAILED(tm_->QueryInterface(IID_PPV_ARGS(&cm))) || FAILED(cm->GetCompartment(g, &c))) return 0;
    VARIANT var;
    VariantInit(&var);
    if (c->GetValue(&var) != S_OK || var.vt != VT_I4) return 0;
    if (ok) *ok = true;
    return DWORD(var.lVal);
}

bool TextService::is_open() { return get_compartment(GUID_COMPARTMENT_KEYBOARD_OPENCLOSE) != 0; }

void TextService::set_open(bool open) {
    if (!open) finish_composition();
    set_compartment(GUID_COMPARTMENT_KEYBOARD_OPENCLOSE, open ? 1 : 0);
    update_mode_ui();
}

void TextService::update_mode_ui() {
    if (is_open()) {
        // タスクバーの表示は変換モードも見る: ひらがな (全角・ローマ字)
        const DWORD want = TF_CONVERSIONMODE_NATIVE | TF_CONVERSIONMODE_FULLSHAPE | TF_CONVERSIONMODE_ROMAN;
        bool ok = false;
        if (get_compartment(GUID_COMPARTMENT_KEYBOARD_INPUTMODE_CONVERSION, &ok) != want || !ok)
            set_compartment(GUID_COMPARTMENT_KEYBOARD_INPUTMODE_CONVERSION, want);
    }
    if (langbar_) langbar_->update();
}

STDMETHODIMP TextService::OnChange(REFGUID guid) {
    if (IsEqualGUID(guid, GUID_COMPARTMENT_KEYBOARD_OPENCLOSE)) {
        if (!is_open()) finish_composition();
        update_mode_ui();
    } else if (IsEqualGUID(guid, GUID_COMPARTMENT_KEYBOARD_INPUTMODE_CONVERSION)) {
        // タスクバーの入力モードのメニューで「半角英数」などを選んだ: 日本語入力を切る
        bool ok = false;
        DWORD m = get_compartment(GUID_COMPARTMENT_KEYBOARD_INPUTMODE_CONVERSION, &ok);
        if (ok && !(m & TF_CONVERSIONMODE_NATIVE) && is_open()) set_open(false);
        else if (ok && (m & TF_CONVERSIONMODE_NATIVE) && !is_open()) set_open(true);
    }
    return S_OK;
}

// ---------------------------------------------------------------- キー

namespace {
// かな入力 (JIS 配列の刻印どおり)。Shift は小さい字 (ぁぃぅぇぉゃゅょっ・を・「」、。・)
char16_t kana_for_vk(WPARAM vk, bool shift) {
    struct K { WPARAM vk; char16_t base, shifted; };
    static const K KEYS[] = {
        {'1', u'ぬ', 0}, {'2', u'ふ', 0}, {'3', u'あ', u'ぁ'}, {'4', u'う', u'ぅ'}, {'5', u'え', u'ぇ'},
        {'6', u'お', u'ぉ'}, {'7', u'や', u'ゃ'}, {'8', u'ゆ', u'ゅ'}, {'9', u'よ', u'ょ'}, {'0', u'わ', u'を'},
        {VK_OEM_MINUS, u'ほ', 0}, {VK_OEM_7, u'へ', 0}, {VK_OEM_5, u'ー', 0},
        {'Q', u'た', 0}, {'W', u'て', 0}, {'E', u'い', u'ぃ'}, {'R', u'す', 0}, {'T', u'か', 0}, {'Y', u'ん', 0},
        {'U', u'な', 0}, {'I', u'に', 0}, {'O', u'ら', 0}, {'P', u'せ', 0}, {VK_OEM_3, 0x309B, 0}, {VK_OEM_4, 0x309C, u'「'},
        {'A', u'ち', 0}, {'S', u'と', 0}, {'D', u'し', 0}, {'F', u'は', 0}, {'G', u'き', 0}, {'H', u'く', 0},
        {'J', u'ま', 0}, {'K', u'の', 0}, {'L', u'り', 0}, {VK_OEM_PLUS, u'れ', 0}, {VK_OEM_1, u'け', 0}, {VK_OEM_6, u'む', u'」'},
        {'Z', u'つ', u'っ'}, {'X', u'さ', 0}, {'C', u'そ', 0}, {'V', u'ひ', 0}, {'B', u'こ', 0}, {'N', u'み', 0},
        {'M', u'も', 0}, {VK_OEM_COMMA, u'ね', u'、'}, {VK_OEM_PERIOD, u'る', u'。'}, {VK_OEM_2, u'め', u'・'},
        {VK_OEM_102, u'ろ', 0},
    };
    for (auto& k : KEYS)
        if (k.vk == vk) return shift && k.shifted ? k.shifted : k.base;
    return 0;
}
}  // namespace

void TextService::apply_settings() {
    Core& c = core();
    c.settings.refresh();
    const Settings& s = c.settings.get();
    if (composer_) {
        composer_->options.live = s.live;
        composer_->options.live_commit = s.live_commit;
        composer_->options.space_fullwidth = s.space_fullwidth;
        composer_->options.punct = s.punct;
        composer_->options.digits_fullwidth = s.digits_fullwidth;
    }
    cand_.theme = s.theme;
}

bool TextService::to_key_event(WPARAM vk, LPARAM lp, KeyEvent& ev) {
    ev = KeyEvent();
    ev.shift = GetKeyState(VK_SHIFT) < 0;
    ev.ctrl = GetKeyState(VK_CONTROL) < 0;
    ev.alt = GetKeyState(VK_MENU) < 0;
    switch (vk) {
        case VK_SPACE: ev.key = Key::Space; return true;
        case VK_RETURN: ev.key = Key::Enter; return true;
        case VK_BACK: ev.key = Key::Backspace; return true;
        case VK_DELETE: ev.key = Key::Delete; return true;
        case VK_ESCAPE: ev.key = Key::Escape; return true;
        case VK_LEFT: ev.key = Key::Left; return true;
        case VK_RIGHT: ev.key = Key::Right; return true;
        case VK_UP: ev.key = Key::Up; return true;
        case VK_DOWN: ev.key = Key::Down; return true;
        case VK_HOME: ev.key = Key::Home; return true;
        case VK_END: ev.key = Key::End; return true;
        case VK_TAB: ev.key = Key::Tab; return true;
        case VK_PRIOR: ev.key = Key::PageUp; return true;
        case VK_NEXT: ev.key = Key::PageDown; return true;
        case VK_F6: ev.key = Key::F6; return true;
        case VK_F7: ev.key = Key::F7; return true;
        case VK_F8: ev.key = Key::F8; return true;
        case VK_F9: ev.key = Key::F9; return true;
        case VK_F10: ev.key = Key::F10; return true;
        case VK_CONVERT: ev.key = Key::Henkan; return true;
        case VK_NONCONVERT: ev.key = Key::Muhenkan; return true;
        case VK_MULTIPLY: ev.ch = u'*'; break;
        case VK_ADD: ev.ch = u'+'; break;
        case VK_SUBTRACT: ev.ch = u'-'; break;
        case VK_DECIMAL: ev.ch = u'.'; break;
        case VK_DIVIDE: ev.ch = u'/'; break;
        default:
            if (vk >= VK_NUMPAD0 && vk <= VK_NUMPAD9) ev.ch = char16_t(u'0' + (vk - VK_NUMPAD0));
            break;
    }
    ev.key = Key::Char;
    if (ev.ch) {   // テンキー: 打ったまま (かなや全角にしない)
        ev.raw = true;
        return true;
    }
    if (ev.ctrl || ev.alt) return false;
    if (core().settings.get().input == "kana") {
        if (char16_t k = kana_for_vk(vk, ev.shift)) {
            ev.ch = k;
            return true;
        }
    }
    BYTE ks[256];
    if (!GetKeyboardState(ks)) return false;
    WCHAR buf[4];
    int n = ToUnicodeEx(UINT(vk), UINT((lp >> 16) & 0xFF), ks, buf, 4, 0x4 /* キーボードの状態を変えない */, GetKeyboardLayout(0));
    if (n != 1 || buf[0] < 0x20 || buf[0] == 0x7F) return false;
    ev.ch = char16_t(buf[0]);
    return true;
}

TextService::Action TextService::classify(WPARAM vk, LPARAM lp, KeyEvent& ev) {
    if (!composer_) return Action::None;
    bool composing = composer_->composing();
    if (!composing) apply_settings();   // 設定画面で変えた分 (ファイルの更新を見るだけなので軽い)
    if (vk == VK_SPACE && core().settings.get().ctrl_space && GetKeyState(VK_CONTROL) < 0 && GetKeyState(VK_MENU) >= 0)
        return Action::Toggle;
    bool open = is_open();
    if (!composing) {
        // 変換キー・ひらがなキーでオン、無変換キーでオフ (MS-IME と同じ)
        if (vk == VK_CONVERT || vk == 0xF2 /* VK_DBE_HIRAGANA */) return open ? Action::None : Action::Open;
        if (vk == VK_NONCONVERT) return open ? Action::Close : Action::None;
    }
    if (!open) return Action::None;
    if (!to_key_event(vk, lp, ev)) return Action::None;
    return composer_->will_handle(ev) ? Action::Compose : Action::None;
}

STDMETHODIMP TextService::OnTestKeyDown(ITfContext*, WPARAM wp, LPARAM lp, BOOL* eaten) {
    KeyEvent ev;
    *eaten = classify(wp, lp, ev) != Action::None;
    return S_OK;
}

STDMETHODIMP TextService::OnKeyDown(ITfContext* ctx, WPARAM wp, LPARAM lp, BOOL* eaten) {
    KeyEvent ev;
    Action a = classify(wp, lp, ev);
    *eaten = a != Action::None;
    switch (a) {
        case Action::Open: set_open(true); break;
        case Action::Close: set_open(false); break;
        case Action::Toggle: set_open(!is_open()); break;
        case Action::Compose: {
            ComPtr<ITfContext> keep(ctx);
            edit(ctx, TF_ES_ASYNCDONTCARE | TF_ES_READWRITE, [this, keep, ev](TfEditCookie ec) {
                if (!composer_) return;
                if (!composer_->composing()) left_ctx_ = read_left_context(ec, keep.Get());
                composer_->press(ev);
                apply(ec, keep.Get());
            });
            break;
        }
        case Action::None: break;
    }
    return S_OK;
}

STDMETHODIMP TextService::OnPreservedKey(ITfContext*, REFGUID, BOOL* eaten) {
    set_open(!is_open());
    *eaten = TRUE;
    return S_OK;
}

// ---------------------------------------------------------------- 入力欄への反映

HRESULT TextService::edit(ITfContext* ctx, DWORD flags, std::function<void(TfEditCookie)> fn) {
    if (!ctx) return E_INVALIDARG;
    auto* es = new EditSession(std::move(fn));
    HRESULT hr = E_FAIL;
    HRESULT r = ctx->RequestEditSession(cid_, es, flags, &hr);
    es->Release();
    return FAILED(r) ? r : hr;
}

u16 TextService::read_left_context(TfEditCookie ec, ITfContext* ctx) {
    TF_SELECTION sel = {};
    ULONG n = 0;
    if (FAILED(ctx->GetSelection(ec, TF_DEFAULT_SELECTION, 1, &sel, &n)) || n == 0 || !sel.range) return u16();
    ComPtr<ITfRange> r;
    r.Attach(sel.range);
    r->Collapse(ec, TF_ANCHOR_START);
    LONG moved = 0;
    r->ShiftStart(ec, -CTX_CHARS, &moved, nullptr);
    WCHAR buf[CTX_CHARS + 8];
    ULONG got = 0;
    if (FAILED(r->GetText(ec, 0, buf, CTX_CHARS + 8, &got))) return u16();
    return u16(reinterpret_cast<const char16_t*>(buf), got);
}

void TextService::set_attributes(TfEditCookie ec, ITfContext* ctx, ITfRange* comp_range, const View& v) {
    ComPtr<ITfProperty> prop;
    if (FAILED(ctx->GetProperty(GUID_PROP_ATTRIBUTE, &prop))) return;
    prop->Clear(ec, comp_range);
    for (auto& sp : v.spans) {
        TfGuidAtom atom = sp.kind == SpanKind::Input ? atom_input_ : sp.kind == SpanKind::Converted ? atom_converted_ : atom_focused_;
        if (atom == TF_INVALID_GUIDATOM) continue;
        ComPtr<ITfRange> r;
        if (FAILED(comp_range->Clone(&r))) continue;
        LONG moved = 0;
        r->Collapse(ec, TF_ANCHOR_START);
        r->ShiftEnd(ec, sp.start + sp.len, &moved, nullptr);
        r->ShiftStart(ec, sp.start, &moved, nullptr);
        VARIANT var;
        VariantInit(&var);
        var.vt = VT_I4;
        var.lVal = LONG(atom);
        prop->SetValue(ec, r.Get(), &var);
    }
}

void TextService::end_composition(TfEditCookie ec, ITfContext* ctx) {
    if (!comp_) return;
    ComPtr<ITfRange> r;
    if (SUCCEEDED(comp_->GetRange(&r))) {
        ComPtr<ITfProperty> prop;
        if (SUCCEEDED(ctx->GetProperty(GUID_PROP_ATTRIBUTE, &prop))) prop->Clear(ec, r.Get());
    }
    comp_->EndComposition(ec);
    comp_->Release();
    comp_ = nullptr;
    if (comp_ctx_) { comp_ctx_->Release(); comp_ctx_ = nullptr; }
}

void TextService::apply(TfEditCookie ec, ITfContext* ctx) {
    u16 commit = composer_->take_commit();
    const View& v = composer_->view();
    auto set_caret = [&](ITfRange* at) {
        TF_SELECTION sel = {};
        sel.range = at;
        sel.style.ase = TF_AE_NONE;
        sel.style.fInterimChar = FALSE;
        ctx->SetSelection(ec, 1, &sel);
    };

    // 確定する文: 入力中の文字があればそれを置き換えて終わらせる。無ければカーソルの所に入れる
    if (!commit.empty()) {
        if (comp_) {
            ComPtr<ITfRange> r;
            if (SUCCEEDED(comp_->GetRange(&r))) {
                r->SetText(ec, 0, W(commit), LONG(commit.size()));
                ComPtr<ITfRange> end;
                if (SUCCEEDED(r->Clone(&end))) {
                    end->Collapse(ec, TF_ANCHOR_END);
                    set_caret(end.Get());
                }
            }
            end_composition(ec, ctx);
        } else {
            ComPtr<ITfInsertAtSelection> ins;
            ComPtr<ITfRange> r;
            if (SUCCEEDED(ctx->QueryInterface(IID_PPV_ARGS(&ins))) &&
                SUCCEEDED(ins->InsertTextAtSelection(ec, 0, W(commit), LONG(commit.size()), &r)) && r) {
                r->Collapse(ec, TF_ANCHOR_END);
                set_caret(r.Get());
            }
        }
    }

    // 入力中の文字
    if (!v.text.empty()) {
        if (!comp_) {
            ComPtr<ITfInsertAtSelection> ins;
            ComPtr<ITfRange> r;
            ComPtr<ITfContextComposition> cc;
            if (FAILED(ctx->QueryInterface(IID_PPV_ARGS(&ins))) ||
                FAILED(ins->InsertTextAtSelection(ec, TF_IAS_QUERYONLY, nullptr, 0, &r)) || !r ||
                FAILED(ctx->QueryInterface(IID_PPV_ARGS(&cc))) ||
                FAILED(cc->StartComposition(ec, r.Get(), static_cast<ITfCompositionSink*>(this), &comp_)) || !comp_) {
                comp_ = nullptr;
                cand_.hide();
                return;
            }
            comp_ctx_ = ctx;
            comp_ctx_->AddRef();
        }
        ComPtr<ITfRange> r;
        if (FAILED(comp_->GetRange(&r))) return;
        r->SetText(ec, 0, W(v.text), LONG(v.text.size()));
        set_attributes(ec, ctx, r.Get(), v);
        ComPtr<ITfRange> c;
        if (SUCCEEDED(r->Clone(&c))) {
            LONG moved = 0;
            c->Collapse(ec, TF_ANCHOR_START);
            c->ShiftStart(ec, v.caret, &moved, nullptr);
            c->Collapse(ec, TF_ANCHOR_START);
            set_caret(c.Get());
        }
    } else if (comp_) {
        ComPtr<ITfRange> r;
        if (SUCCEEDED(comp_->GetRange(&r))) r->SetText(ec, 0, L"", 0);
        end_composition(ec, ctx);
    }
    update_candidates(ec, ctx, v);
}

void TextService::update_candidates(TfEditCookie ec, ITfContext* ctx, const View& v) {
    if (!v.cand_open || !comp_) { cand_.hide(); return; }
    ComPtr<ITfContextView> view;
    ComPtr<ITfRange> r, a;
    RECT rc = {};
    BOOL clipped = FALSE;
    HWND hwnd = nullptr;
    bool ok = SUCCEEDED(ctx->GetActiveView(&view)) && SUCCEEDED(comp_->GetRange(&r)) && SUCCEEDED(r->Clone(&a));
    if (ok) {
        LONG moved = 0;
        a->Collapse(ec, TF_ANCHOR_START);
        a->ShiftEnd(ec, v.anchor + 1, &moved, nullptr);
        a->ShiftStart(ec, v.anchor, &moved, nullptr);
        ok = view->GetTextExt(ec, a.Get(), &rc, &clipped) == S_OK && (rc.right > rc.left || rc.bottom > rc.top);
        view->GetWnd(&hwnd);
    }
    if (!ok) {   // 位置を教えてくれないアプリ: キャレットの位置の下に出す
        GUITHREADINFO gi = {sizeof gi};
        if (GetGUIThreadInfo(0, &gi) && gi.hwndCaret) {
            rc = gi.rcCaret;
            MapWindowPoints(gi.hwndCaret, nullptr, reinterpret_cast<POINT*>(&rc), 2);
            if (!hwnd) hwnd = gi.hwndCaret;
        }
    }
    if (!hwnd) hwnd = GetFocus();
    cand_.show(v.cands, v.cand_sel, rc, hwnd);
}

void TextService::finish_composition() {
    if (!composer_ || !composer_->composing() || !comp_ctx_) {
        cand_.hide();
        return;
    }
    ComPtr<ITfContext> keep(comp_ctx_);
    edit(keep.Get(), TF_ES_ASYNCDONTCARE | TF_ES_READWRITE, [this, keep](TfEditCookie ec) {
        if (!composer_) return;
        composer_->finish();
        apply(ec, keep.Get());
    });
}

void TextService::on_candidate_clicked(int index) {
    if (!composer_ || !comp_ctx_) return;
    ComPtr<ITfContext> keep(comp_ctx_);
    edit(keep.Get(), TF_ES_ASYNCDONTCARE | TF_ES_READWRITE, [this, keep, index](TfEditCookie ec) {
        if (!composer_) return;
        composer_->select_candidate(index);
        apply(ec, keep.Get());
    });
}

STDMETHODIMP TextService::OnCompositionTerminated(TfEditCookie, ITfComposition* comp) {
    // アプリが入力中の文字を終わらせた (クリックで別の所に移ったなど)。文字はそのまま残るので、こちらは忘れるだけ
    if (comp_ && comp == comp_) {
        comp_->Release();
        comp_ = nullptr;
        if (comp_ctx_) { comp_ctx_->Release(); comp_ctx_ = nullptr; }
    }
    if (composer_) composer_->cancel();
    cand_.hide();
    return S_OK;
}

STDMETHODIMP TextService::OnSetFocus(ITfDocumentMgr*, ITfDocumentMgr*) {
    // 別の入力欄に移った: 入力中のものは確定し、文脈の代わりに覚えていた文を忘れる
    finish_composition();
    cand_.hide();
    if (composer_) composer_->reset_history();
    return S_OK;
}

// ---------------------------------------------------------------- 見せ方の提供

STDMETHODIMP TextService::EnumDisplayAttributeInfo(IEnumTfDisplayAttributeInfo** out) {
    if (!out) return E_INVALIDARG;
    *out = new shunti::win::EnumDisplayAttributeInfo();
    return S_OK;
}

STDMETHODIMP TextService::GetDisplayAttributeInfo(REFGUID guid, ITfDisplayAttributeInfo** out) {
    if (!out) return E_INVALIDARG;
    *out = make_display_attribute(guid);
    return *out ? S_OK : E_INVALIDARG;
}

}  // namespace win
}  // namespace shunti
