// DLL の入口: COM のクラスファクトリと、登録 (regsvr32) の入口
#include <windows.h>
#include <msctf.h>
#include <wrl/client.h>

#include <string>

#include "globals.h"
#include "text_service.h"

using Microsoft::WRL::ComPtr;
using namespace shunti::win;

namespace {

class ClassFactory : public IClassFactory {
public:
    STDMETHODIMP QueryInterface(REFIID riid, void** ppv) override {
        if (!ppv) return E_INVALIDARG;
        *ppv = nullptr;
        if (IsEqualIID(riid, IID_IUnknown) || IsEqualIID(riid, IID_IClassFactory)) *ppv = static_cast<IClassFactory*>(this);
        if (!*ppv) return E_NOINTERFACE;
        AddRef();
        return S_OK;
    }
    STDMETHODIMP_(ULONG) AddRef() override { dll_add_ref(); return 2; }
    STDMETHODIMP_(ULONG) Release() override { dll_release(); return 1; }
    STDMETHODIMP CreateInstance(IUnknown* outer, REFIID riid, void** ppv) override {
        if (!ppv) return E_INVALIDARG;
        *ppv = nullptr;
        if (outer) return CLASS_E_NOAGGREGATION;
        auto* ts = new (std::nothrow) TextService();
        if (!ts) return E_OUTOFMEMORY;
        HRESULT hr = ts->QueryInterface(riid, ppv);
        ts->Release();
        return hr;
    }
    STDMETHODIMP LockServer(BOOL lock) override {
        if (lock) dll_add_ref(); else dll_release();
        return S_OK;
    }
};

ClassFactory g_factory;

// ---- 登録 ----

// 分類 (キーボードの IME・見せ方の提供・ストアアプリやスタートの検索欄でも使える・タスクバーの表示など)
const GUID* const CATEGORIES[] = {
    &GUID_TFCAT_TIP_KEYBOARD,
    &GUID_TFCAT_DISPLAYATTRIBUTEPROVIDER,
    &GUID_TFCAT_TIPCAP_INPUTMODECOMPARTMENT,
    &GUID_TFCAT_TIPCAP_COMLESS,
    &GUID_TFCAT_TIPCAP_IMMERSIVESUPPORT,
    &GUID_TFCAT_TIPCAP_SYSTRAYSUPPORT,
};

std::wstring guid_str(const GUID& g) {
    wchar_t buf[64];
    StringFromGUID2(g, buf, 64);
    return buf;
}

std::wstring module_path() {
    wchar_t buf[MAX_PATH * 2];
    DWORD n = GetModuleFileNameW(g_inst, buf, DWORD(std::size(buf)));
    return std::wstring(buf, n);
}

HRESULT register_com() {
    std::wstring key = L"Software\\Classes\\CLSID\\" + guid_str(CLSID_TextService);
    HKEY k;
    if (RegCreateKeyExW(HKEY_LOCAL_MACHINE, key.c_str(), 0, nullptr, 0, KEY_WRITE, nullptr, &k, nullptr) != ERROR_SUCCESS) return E_ACCESSDENIED;
    RegSetValueExW(k, nullptr, 0, REG_SZ, reinterpret_cast<const BYTE*>(DISPLAY_NAME), DWORD(sizeof DISPLAY_NAME));
    HKEY s;
    LONG r = RegCreateKeyExW(k, L"InprocServer32", 0, nullptr, 0, KEY_WRITE, nullptr, &s, nullptr);
    RegCloseKey(k);
    if (r != ERROR_SUCCESS) return E_ACCESSDENIED;
    std::wstring path = module_path();
    RegSetValueExW(s, nullptr, 0, REG_SZ, reinterpret_cast<const BYTE*>(path.c_str()), DWORD((path.size() + 1) * sizeof(wchar_t)));
    const wchar_t tm[] = L"Apartment";
    RegSetValueExW(s, L"ThreadingModel", 0, REG_SZ, reinterpret_cast<const BYTE*>(tm), DWORD(sizeof tm));
    RegCloseKey(s);
    return S_OK;
}

void unregister_com() {
    std::wstring key = L"Software\\Classes\\CLSID\\" + guid_str(CLSID_TextService);
    RegDeleteTreeW(HKEY_LOCAL_MACHINE, key.c_str());
}

HRESULT register_profile() {
    ComPtr<ITfInputProcessorProfileMgr> pm;
    HRESULT hr = CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&pm));
    if (FAILED(hr)) return hr;
    std::wstring path = module_path();
    // 登録アイコンはタスクバーの色で白 (0) か黒 (1) を選ぶ (Windows は登録した 1 つを出すだけで、色を変えても切り替えない。
    // タスクバーの色を変えたら、設定画面の「アイコンの色をタスクバーに合わせる」で登録し直す)
    ULONG icon = system_dark() ? 0 : 1;
    hr = pm->RegisterProfile(CLSID_TextService, LANG_JA, GUID_Profile, DISPLAY_NAME, ULONG(wcslen(DISPLAY_NAME)),
                             path.c_str(), ULONG(path.size()), icon, nullptr, 0, TRUE, 0);
    if (FAILED(hr)) return hr;
    ComPtr<ITfCategoryMgr> cm;
    hr = CoCreateInstance(CLSID_TF_CategoryMgr, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&cm));
    if (FAILED(hr)) return hr;
    for (auto* c : CATEGORIES) cm->RegisterCategory(CLSID_TextService, *c, CLSID_TextService);
    return S_OK;
}

void unregister_profile() {
    ComPtr<ITfInputProcessorProfileMgr> pm;
    if (SUCCEEDED(CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&pm))))
        pm->UnregisterProfile(CLSID_TextService, LANG_JA, GUID_Profile, 0);
    ComPtr<ITfCategoryMgr> cm;
    if (SUCCEEDED(CoCreateInstance(CLSID_TF_CategoryMgr, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&cm))))
        for (auto* c : CATEGORIES) cm->UnregisterCategory(CLSID_TextService, *c, CLSID_TextService);
}

}  // namespace

BOOL WINAPI DllMain(HINSTANCE inst, DWORD reason, LPVOID) {
    if (reason == DLL_PROCESS_ATTACH) {
        g_inst = inst;
        DisableThreadLibraryCalls(inst);
    }
    return TRUE;
}

STDAPI DllGetClassObject(REFCLSID clsid, REFIID riid, void** ppv) {
    if (!ppv) return E_INVALIDARG;
    *ppv = nullptr;
    if (!IsEqualCLSID(clsid, CLSID_TextService)) return CLASS_E_CLASSNOTAVAILABLE;
    return g_factory.QueryInterface(riid, ppv);
}

STDAPI DllCanUnloadNow() { return dll_refs() == 0 ? S_OK : S_FALSE; }

STDAPI DllRegisterServer() {
    HRESULT init = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    HRESULT hr = register_com();
    if (SUCCEEDED(hr)) hr = register_profile();
    if (FAILED(hr)) { unregister_profile(); unregister_com(); }
    if (SUCCEEDED(init)) CoUninitialize();
    return hr;
}

STDAPI DllUnregisterServer() {
    HRESULT init = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    unregister_profile();
    unregister_com();
    if (SUCCEEDED(init)) CoUninitialize();
    return S_OK;
}
