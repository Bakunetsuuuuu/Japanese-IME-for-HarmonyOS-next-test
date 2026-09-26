// 入力中の文字の見せ方 (下線の種類) を TSF に教えるもの。入力中 = 点線、変換済み = 細い線、選んでいる文節 = 太い線
#pragma once
#include <windows.h>
#include <msctf.h>

namespace shunti {
namespace win {

class DisplayAttributeInfo : public ITfDisplayAttributeInfo {
public:
    DisplayAttributeInfo(const GUID& guid, const TF_DISPLAYATTRIBUTE& attr, const wchar_t* desc);
    STDMETHODIMP QueryInterface(REFIID riid, void** ppv) override;
    STDMETHODIMP_(ULONG) AddRef() override;
    STDMETHODIMP_(ULONG) Release() override;
    STDMETHODIMP GetGUID(GUID* guid) override;
    STDMETHODIMP GetDescription(BSTR* desc) override;
    STDMETHODIMP GetAttributeInfo(TF_DISPLAYATTRIBUTE* attr) override;
    STDMETHODIMP SetAttributeInfo(const TF_DISPLAYATTRIBUTE*) override { return E_NOTIMPL; }
    STDMETHODIMP Reset() override { return S_OK; }

private:
    ~DisplayAttributeInfo();
    LONG refs_ = 1;
    GUID guid_;
    TF_DISPLAYATTRIBUTE attr_;
    const wchar_t* desc_;
};

class EnumDisplayAttributeInfo : public IEnumTfDisplayAttributeInfo {
public:
    EnumDisplayAttributeInfo();
    STDMETHODIMP QueryInterface(REFIID riid, void** ppv) override;
    STDMETHODIMP_(ULONG) AddRef() override;
    STDMETHODIMP_(ULONG) Release() override;
    STDMETHODIMP Clone(IEnumTfDisplayAttributeInfo** out) override;
    STDMETHODIMP Next(ULONG n, ITfDisplayAttributeInfo** out, ULONG* fetched) override;
    STDMETHODIMP Reset() override { index_ = 0; return S_OK; }
    STDMETHODIMP Skip(ULONG n) override;

private:
    ~EnumDisplayAttributeInfo();
    LONG refs_ = 1;
    ULONG index_ = 0;
};

// guid の見せ方 (無ければ nullptr)。呼んだ側が Release する
DisplayAttributeInfo* make_display_attribute(const GUID& guid);

}  // namespace win
}  // namespace shunti
