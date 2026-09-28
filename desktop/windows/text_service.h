// TSF のテキストサービス本体。キーを受けて Composer (desktop/core) に渡し、入力中の文字 (composition) と
// 候補の窓を出し、確定した文を入力欄に入れる。
#pragma once
#include <windows.h>
#include <msctf.h>

#include <functional>
#include <memory>

#include "../core/composer.h"
#include "cand_window.h"

namespace shunti {
namespace win {

class LangBarButton;

class TextService : public ITfTextInputProcessorEx,
                    public ITfThreadMgrEventSink,
                    public ITfKeyEventSink,
                    public ITfCompositionSink,
                    public ITfDisplayAttributeProvider,
                    public ITfCompartmentEventSink {
public:
    TextService();
    ~TextService();

    // IUnknown
    STDMETHODIMP QueryInterface(REFIID riid, void** ppv) override;
    STDMETHODIMP_(ULONG) AddRef() override;
    STDMETHODIMP_(ULONG) Release() override;

    // ITfTextInputProcessor(Ex)
    STDMETHODIMP Activate(ITfThreadMgr* tm, TfClientId cid) override;
    STDMETHODIMP Deactivate() override;
    STDMETHODIMP ActivateEx(ITfThreadMgr* tm, TfClientId cid, DWORD flags) override;

    // ITfThreadMgrEventSink
    STDMETHODIMP OnInitDocumentMgr(ITfDocumentMgr*) override { return S_OK; }
    STDMETHODIMP OnUninitDocumentMgr(ITfDocumentMgr*) override { return S_OK; }
    STDMETHODIMP OnSetFocus(ITfDocumentMgr* focus, ITfDocumentMgr* prev) override;
    STDMETHODIMP OnPushContext(ITfContext*) override { return S_OK; }
    STDMETHODIMP OnPopContext(ITfContext*) override { return S_OK; }

    // ITfKeyEventSink
    STDMETHODIMP OnSetFocus(BOOL) override { return S_OK; }
    STDMETHODIMP OnTestKeyDown(ITfContext* ctx, WPARAM wp, LPARAM lp, BOOL* eaten) override;
    STDMETHODIMP OnKeyDown(ITfContext* ctx, WPARAM wp, LPARAM lp, BOOL* eaten) override;
    STDMETHODIMP OnTestKeyUp(ITfContext*, WPARAM, LPARAM, BOOL* eaten) override { *eaten = FALSE; return S_OK; }
    STDMETHODIMP OnKeyUp(ITfContext*, WPARAM, LPARAM, BOOL* eaten) override { *eaten = FALSE; return S_OK; }
    STDMETHODIMP OnPreservedKey(ITfContext* ctx, REFGUID guid, BOOL* eaten) override;

    // ITfCompositionSink
    STDMETHODIMP OnCompositionTerminated(TfEditCookie ec, ITfComposition* comp) override;

    // ITfDisplayAttributeProvider
    STDMETHODIMP EnumDisplayAttributeInfo(IEnumTfDisplayAttributeInfo** out) override;
    STDMETHODIMP GetDisplayAttributeInfo(REFGUID guid, ITfDisplayAttributeInfo** out) override;

    // ITfCompartmentEventSink
    STDMETHODIMP OnChange(REFGUID guid) override;

    // 日本語入力のオン・オフ
    bool is_open();
    void set_open(bool open);
    // 候補の窓をマウスで選んだ
    void on_candidate_clicked(int index);

private:
    enum class Action { None, Compose, Open, Close, Toggle };
    void apply_settings();
    bool is_secure_field(TfEditCookie ec, ITfContext* ctx);   // パスワードの欄か (入力の記録を止める)
    Action classify(WPARAM vk, LPARAM lp, KeyEvent& ev);
    bool to_key_event(WPARAM vk, LPARAM lp, KeyEvent& ev);
    HRESULT edit(ITfContext* ctx, DWORD flags, std::function<void(TfEditCookie)> fn);
    void apply(TfEditCookie ec, ITfContext* ctx);
    u16 read_left_context(TfEditCookie ec, ITfContext* ctx);
    void set_attributes(TfEditCookie ec, ITfContext* ctx, ITfRange* comp_range, const View& v);
    void update_candidates(TfEditCookie ec, ITfContext* ctx, const View& v);
    void end_composition(TfEditCookie ec, ITfContext* ctx);
    void finish_composition();
    bool init_key_sink();
    void uninit_key_sink();
    bool init_preserved_keys();
    void uninit_preserved_keys();
    bool advise_compartment(const GUID& g, DWORD& cookie);
    void unadvise_compartment(const GUID& g, DWORD& cookie);
    void set_compartment(const GUID& g, DWORD v);
    DWORD get_compartment(const GUID& g, bool* ok = nullptr);
    void update_mode_ui();

    LONG refs_ = 1;
    ITfThreadMgr* tm_ = nullptr;
    TfClientId cid_ = TF_CLIENTID_NULL;
    DWORD tm_sink_cookie_ = TF_INVALID_COOKIE;
    DWORD open_cookie_ = TF_INVALID_COOKIE;
    DWORD conv_cookie_ = TF_INVALID_COOKIE;
    ITfComposition* comp_ = nullptr;
    ITfContext* comp_ctx_ = nullptr;
    TfGuidAtom atom_input_ = TF_INVALID_GUIDATOM, atom_converted_ = TF_INVALID_GUIDATOM, atom_focused_ = TF_INVALID_GUIDATOM;
    std::unique_ptr<Composer> composer_;
    u16 left_ctx_;
    bool secure_ = false;   // いまの入力欄がパスワードの欄 (デバッグ用のビルドの入力の記録だけが使う)
    CandWindow cand_;
    LangBarButton* langbar_ = nullptr;
};

}  // namespace win
}  // namespace shunti
