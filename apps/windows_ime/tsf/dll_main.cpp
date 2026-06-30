// dll_main.cpp
// ------------
// ⚠️  CHƯA KIỂM CHỨNG — chỉ build trên Windows. Điểm vào COM in-proc server (DLL):
// DllMain + DllGetClassObject (class factory) + Dll(Un)RegisterServer. Đây là khung
// tối thiểu để Windows nạp text service; phần đăng ký với TSF (ITfInputProcessorProfiles,
// ITfCategoryMgr) còn để TODO vì cần môi trường Windows để thử.

#if defined(_WIN32)

#include <msctf.h>
#include <windows.h>

#include "BowGoTextService.h"

static HINSTANCE g_instance = nullptr;
static LONG g_dll_ref = 0;

void DllAddRef() { InterlockedIncrement(&g_dll_ref); }
void DllRelease() { InterlockedDecrement(&g_dll_ref); }

// Class factory tạo BowGoTextService.
class BowGoClassFactory : public IClassFactory {
public:
    BowGoClassFactory() : ref_(1) {}

    STDMETHODIMP QueryInterface(REFIID riid, void** ppv) override {
        if (IsEqualIID(riid, IID_IUnknown) || IsEqualIID(riid, IID_IClassFactory)) {
            *ppv = static_cast<IClassFactory*>(this);
            AddRef();
            return S_OK;
        }
        *ppv = nullptr;
        return E_NOINTERFACE;
    }
    STDMETHODIMP_(ULONG) AddRef() override { return InterlockedIncrement(&ref_); }
    STDMETHODIMP_(ULONG) Release() override {
        LONG c = InterlockedDecrement(&ref_);
        if (c == 0) delete this;
        return c;
    }

    STDMETHODIMP CreateInstance(IUnknown* outer, REFIID riid, void** ppv) override {
        if (outer) return CLASS_E_NOAGGREGATION;
        BowGoTextService* svc = new (std::nothrow) BowGoTextService();
        if (!svc) return E_OUTOFMEMORY;
        HRESULT hr = svc->QueryInterface(riid, ppv);
        svc->Release();
        return hr;
    }
    STDMETHODIMP LockServer(BOOL lock) override {
        if (lock) DllAddRef(); else DllRelease();
        return S_OK;
    }

private:
    LONG ref_;
};

BOOL APIENTRY DllMain(HINSTANCE instance, DWORD reason, LPVOID) {
    if (reason == DLL_PROCESS_ATTACH) {
        g_instance = instance;
        DisableThreadLibraryCalls(instance);
    }
    return TRUE;
}

STDAPI DllGetClassObject(REFCLSID rclsid, REFIID riid, void** ppv) {
    if (IsEqualCLSID(rclsid, kBowGoClsid)) {
        BowGoClassFactory* factory = new (std::nothrow) BowGoClassFactory();
        if (!factory) return E_OUTOFMEMORY;
        HRESULT hr = factory->QueryInterface(riid, ppv);
        factory->Release();
        return hr;
    }
    return CLASS_E_CLASSNOTAVAILABLE;
}

STDAPI DllCanUnloadNow() {
    return g_dll_ref == 0 ? S_OK : S_FALSE;
}

STDAPI DllRegisterServer() {
    // TODO(windows): ghi CLSID vào registry + đăng ký text service với TSF qua
    // ITfInputProcessorProfiles::Register / AddLanguageProfile và phân loại qua
    // ITfCategoryMgr (TF_CATEGORY_TIP_KEYBOARD). Cần Windows để thử.
    return S_OK;
}

STDAPI DllUnregisterServer() {
    // TODO(windows): gỡ đăng ký TSF + xoá khoá registry.
    return S_OK;
}

#endif  // _WIN32
