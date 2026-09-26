#include "langbar.h"

#include "globals.h"
#include "text_service.h"

namespace shunti {
namespace win {

namespace {
constexpr DWORD SINK_COOKIE = 0x5348;   // 流し先は 1 つだけ

// 「あ」か「A」を描いたアイコン (タスクバーの色に合わせた 1 色。字の形を透明度にする)
HICON make_icon(const wchar_t* text) {
    int size = GetSystemMetrics(SM_CXSMICON);
    UINT dpi = GetDpiForSystem();
    BITMAPINFO bi = {};
    bi.bmiHeader.biSize = sizeof bi.bmiHeader;
    bi.bmiHeader.biWidth = size;
    bi.bmiHeader.biHeight = -size;
    bi.bmiHeader.biPlanes = 1;
    bi.bmiHeader.biBitCount = 32;
    bi.bmiHeader.biCompression = BI_RGB;
    void* bits = nullptr;
    HDC dc = CreateCompatibleDC(nullptr);
    HBITMAP color = CreateDIBSection(dc, &bi, DIB_RGB_COLORS, &bits, nullptr, 0);
    if (!color) { DeleteDC(dc); return nullptr; }
    HGDIOBJ old = SelectObject(dc, color);
    RECT rc = {0, 0, size, size};
    FillRect(dc, &rc, static_cast<HBRUSH>(GetStockObject(BLACK_BRUSH)));
    HFONT font = CreateFontW(-MulDiv(size, 15, 16), 0, 0, 0, FW_NORMAL, 0, 0, 0, DEFAULT_CHARSET, 0, 0, ANTIALIASED_QUALITY, 0, L"Yu Gothic UI");
    HGDIOBJ oldf = SelectObject(dc, font);
    SetBkMode(dc, TRANSPARENT);
    SetTextColor(dc, RGB(255, 255, 255));
    DrawTextW(dc, text, -1, &rc, DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX);
    SelectObject(dc, oldf);
    DeleteObject(font);
    GdiFlush();
    (void)dpi;
    // 白く描いた字の明るさを透明度に、色はタスクバーに合わせる
    BYTE fg = system_dark() ? 255 : 0;
    auto* px = static_cast<BYTE*>(bits);
    for (int i = 0; i < size * size; i++) {
        BYTE a = px[i * 4 + 1];
        px[i * 4 + 0] = BYTE(fg * a / 255);
        px[i * 4 + 1] = BYTE(fg * a / 255);
        px[i * 4 + 2] = BYTE(fg * a / 255);
        px[i * 4 + 3] = a;
    }
    SelectObject(dc, old);
    DeleteDC(dc);
    HBITMAP mask = CreateBitmap(size, size, 1, 1, nullptr);
    ICONINFO ii = {TRUE, 0, 0, mask, color};
    HICON icon = CreateIconIndirect(&ii);
    DeleteObject(mask);
    DeleteObject(color);
    return icon;
}
}  // namespace

LangBarButton::LangBarButton(TextService* ts) : ts_(ts) { dll_add_ref(); }
LangBarButton::~LangBarButton() { dll_release(); }

STDMETHODIMP LangBarButton::QueryInterface(REFIID riid, void** ppv) {
    if (!ppv) return E_INVALIDARG;
    *ppv = nullptr;
    if (IsEqualIID(riid, IID_IUnknown) || IsEqualIID(riid, IID_ITfLangBarItem) || IsEqualIID(riid, IID_ITfLangBarItemButton))
        *ppv = static_cast<ITfLangBarItemButton*>(this);
    else if (IsEqualIID(riid, IID_ITfSource))
        *ppv = static_cast<ITfSource*>(this);
    if (!*ppv) return E_NOINTERFACE;
    AddRef();
    return S_OK;
}
STDMETHODIMP_(ULONG) LangBarButton::AddRef() { return ULONG(InterlockedIncrement(&refs_)); }
STDMETHODIMP_(ULONG) LangBarButton::Release() {
    LONG n = InterlockedDecrement(&refs_);
    if (!n) delete this;
    return ULONG(n);
}

STDMETHODIMP LangBarButton::GetInfo(TF_LANGBARITEMINFO* info) {
    if (!info) return E_INVALIDARG;
    info->clsidService = CLSID_TextService;
    info->guidItem = GUID_LBI_INPUTMODE;   // タスクバーの入力モードの表示になる
    info->dwStyle = TF_LBI_STYLE_BTN_BUTTON | TF_LBI_STYLE_SHOWNINTRAY;
    info->ulSort = 0;
    wcscpy_s(info->szDescription, L"入力モード");
    return S_OK;
}
STDMETHODIMP LangBarButton::GetStatus(DWORD* status) {
    if (!status) return E_INVALIDARG;
    *status = 0;
    return S_OK;
}
STDMETHODIMP LangBarButton::GetTooltipString(BSTR* tip) {
    if (!tip) return E_INVALIDARG;
    *tip = SysAllocString(ts_ && ts_->is_open() ? L"ひらがな (shunti IME)" : L"半角英数 (shunti IME)");
    return *tip ? S_OK : E_OUTOFMEMORY;
}
STDMETHODIMP LangBarButton::OnClick(TfLBIClick click, POINT, const RECT*) {
    if (click == TF_LBI_CLK_LEFT && ts_) ts_->set_open(!ts_->is_open());
    return S_OK;
}
STDMETHODIMP LangBarButton::GetIcon(HICON* icon) {
    if (!icon) return E_INVALIDARG;
    *icon = make_icon(ts_ && ts_->is_open() ? L"あ" : L"A");
    return *icon ? S_OK : E_FAIL;
}
STDMETHODIMP LangBarButton::GetText(BSTR* text) {
    if (!text) return E_INVALIDARG;
    *text = SysAllocString(ts_ && ts_->is_open() ? L"あ" : L"A");
    return *text ? S_OK : E_OUTOFMEMORY;
}

STDMETHODIMP LangBarButton::AdviseSink(REFIID riid, IUnknown* sink, DWORD* cookie) {
    if (!IsEqualIID(riid, IID_ITfLangBarItemSink)) return CONNECT_E_CANNOTCONNECT;
    if (sink_) return CONNECT_E_ADVISELIMIT;
    if (FAILED(sink->QueryInterface(IID_ITfLangBarItemSink, reinterpret_cast<void**>(&sink_)))) { sink_ = nullptr; return E_NOINTERFACE; }
    *cookie = SINK_COOKIE;
    return S_OK;
}
STDMETHODIMP LangBarButton::UnadviseSink(DWORD cookie) {
    if (cookie != SINK_COOKIE || !sink_) return CONNECT_E_NOCONNECTION;
    sink_->Release();
    sink_ = nullptr;
    return S_OK;
}

void LangBarButton::update() {
    if (sink_) sink_->OnUpdate(TF_LBI_ICON | TF_LBI_TEXT | TF_LBI_TOOLTIP);
}

}  // namespace win
}  // namespace shunti
