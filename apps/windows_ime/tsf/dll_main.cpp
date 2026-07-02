// dll_main.cpp
// ------------
// Điểm vào COM in-proc server (DLL) của text service Bow Go:
//   - DllMain / DllGetClassObject / DllCanUnloadNow: chuẩn COM.
//   - DllRegisterServer / DllUnregisterServer: ghi CLSID vào registry, đăng ký
//     text service với TSF (ITfInputProcessorProfiles — ngôn ngữ Tiếng Việt
//     0x042A) và phân loại (ITfCategoryMgr — TIP bàn phím).
//
// Cài đặt (PowerShell/CMD quyền Administrator):
//   regsvr32 BowGoTSF.dll        # đăng ký
//   regsvr32 /u BowGoTSF.dll     # gỡ
// Sau đó chọn "Bow Go" trong Settings > Time & language > Typing hoặc thanh
// ngôn ngữ (Win+Space).
//
// ⚠️ Chỉ build được trên Windows (Windows SDK + msctf.h). Trên máy khác, file
// này bị loại khỏi build bởi `#if defined(_WIN32)` + CMake `if(WIN32)`.

#if defined(_WIN32)

#include <msctf.h>
#include <windows.h>

#include <new>

#include "BowGoTextService.h"

static HINSTANCE g_instance = nullptr;
static LONG g_dll_ref = 0;

void DllAddRef() { InterlockedIncrement(&g_dll_ref); }
void DllRelease() { InterlockedDecrement(&g_dll_ref); }

HINSTANCE DllInstance() { return g_instance; }

namespace {

// Tiếng Việt (vi-VN). TSF cần LANGID để gắn profile vào đúng ngôn ngữ.
constexpr LANGID kVietnameseLangId = MAKELANGID(LANG_VIETNAMESE, SUBLANG_DEFAULT);

constexpr WCHAR kServiceDescription[] = L"Bow Go";

// ── Class factory ────────────────────────────────────────────────────────────

class BowGoClassFactory : public IClassFactory {
public:
    BowGoClassFactory() : ref_(1) { DllAddRef(); }

    STDMETHODIMP QueryInterface(REFIID riid, void** ppv) override {
        if (!ppv) return E_INVALIDARG;
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
        if (!ppv) return E_INVALIDARG;
        *ppv = nullptr;
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
    ~BowGoClassFactory() { DllRelease(); }
    LONG ref_;
};

// ── Registry helpers ─────────────────────────────────────────────────────────

// Chuỗi "{xxxxxxxx-xxxx-...}" của một GUID.
bool GuidToString(REFGUID guid, WCHAR* buf, int len) {
    return StringFromGUID2(guid, buf, len) > 0;
}

LONG SetKeyValue(HKEY root, const WCHAR* subkey, const WCHAR* name,
                 const WCHAR* value) {
    HKEY key = nullptr;
    LONG err = RegCreateKeyExW(root, subkey, 0, nullptr, REG_OPTION_NON_VOLATILE,
                               KEY_WRITE, nullptr, &key, nullptr);
    if (err != ERROR_SUCCESS) return err;
    err = RegSetValueExW(key, name, 0, REG_SZ,
                         reinterpret_cast<const BYTE*>(value),
                         static_cast<DWORD>((lstrlenW(value) + 1) * sizeof(WCHAR)));
    RegCloseKey(key);
    return err;
}

// Ghi HKCR\CLSID\{clsid}: tên hiển thị + đường dẫn DLL + threading model.
bool RegisterComServer() {
    WCHAR clsid_str[64];
    if (!GuidToString(kBowGoClsid, clsid_str, 64)) return false;

    WCHAR dll_path[MAX_PATH];
    if (!GetModuleFileNameW(g_instance, dll_path, MAX_PATH)) return false;

    WCHAR key_path[128];
    wsprintfW(key_path, L"CLSID\\%s", clsid_str);
    if (SetKeyValue(HKEY_CLASSES_ROOT, key_path, nullptr, kServiceDescription) !=
        ERROR_SUCCESS)
        return false;

    WCHAR inproc_path[160];
    wsprintfW(inproc_path, L"CLSID\\%s\\InprocServer32", clsid_str);
    if (SetKeyValue(HKEY_CLASSES_ROOT, inproc_path, nullptr, dll_path) !=
        ERROR_SUCCESS)
        return false;
    // TSF nạp text service theo apartment model.
    if (SetKeyValue(HKEY_CLASSES_ROOT, inproc_path, L"ThreadingModel",
                    L"Apartment") != ERROR_SUCCESS)
        return false;
    return true;
}

void UnregisterComServer() {
    WCHAR clsid_str[64];
    if (!GuidToString(kBowGoClsid, clsid_str, 64)) return;
    WCHAR key_path[128];
    wsprintfW(key_path, L"CLSID\\%s", clsid_str);
    RegDeleteTreeW(HKEY_CLASSES_ROOT, key_path);
}

// Đăng ký với TSF: profile ngôn ngữ Tiếng Việt + danh mục "TIP bàn phím".
bool RegisterTsfProfiles() {
    ITfInputProcessorProfiles* profiles = nullptr;
    HRESULT hr = CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr,
                                  CLSCTX_INPROC_SERVER,
                                  IID_ITfInputProcessorProfiles,
                                  reinterpret_cast<void**>(&profiles));
    if (FAILED(hr)) return false;

    hr = profiles->Register(kBowGoClsid);
    if (SUCCEEDED(hr)) {
        WCHAR dll_path[MAX_PATH] = {0};
        GetModuleFileNameW(g_instance, dll_path, MAX_PATH);
        hr = profiles->AddLanguageProfile(
            kBowGoClsid, kVietnameseLangId, kBowGoProfileGuid,
            kServiceDescription, static_cast<ULONG>(-1),
            dll_path, static_cast<ULONG>(-1), 0 /*icon index*/);
    }
    profiles->Release();
    if (FAILED(hr)) return false;

    ITfCategoryMgr* categories = nullptr;
    hr = CoCreateInstance(CLSID_TF_CategoryMgr, nullptr, CLSCTX_INPROC_SERVER,
                          IID_ITfCategoryMgr,
                          reinterpret_cast<void**>(&categories));
    if (FAILED(hr)) return false;

    // TIP bàn phím + các cờ để chạy được trong app UWP/immersive, màn hình khoá
    // và trình duyệt hiện đại.
    const GUID* cats[] = {
        &GUID_TFCAT_TIP_KEYBOARD,
        &GUID_TFCAT_TIPCAP_UIELEMENTENABLED,
        &GUID_TFCAT_TIPCAP_COMLESS,
        &GUID_TFCAT_TIPCAP_IMMERSIVESUPPORT,
        &GUID_TFCAT_TIPCAP_SYSTRAYSUPPORT,
    };
    for (const GUID* cat : cats) {
        // Một số danh mục không tồn tại trên Windows cũ -> bỏ qua lỗi từng cái.
        categories->RegisterCategory(kBowGoClsid, *cat, kBowGoClsid);
    }
    categories->Release();
    return true;
}

void UnregisterTsfProfiles() {
    ITfInputProcessorProfiles* profiles = nullptr;
    if (SUCCEEDED(CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr,
                                   CLSCTX_INPROC_SERVER,
                                   IID_ITfInputProcessorProfiles,
                                   reinterpret_cast<void**>(&profiles)))) {
        profiles->Unregister(kBowGoClsid);
        profiles->Release();
    }

    ITfCategoryMgr* categories = nullptr;
    if (SUCCEEDED(CoCreateInstance(CLSID_TF_CategoryMgr, nullptr,
                                   CLSCTX_INPROC_SERVER, IID_ITfCategoryMgr,
                                   reinterpret_cast<void**>(&categories)))) {
        const GUID* cats[] = {
            &GUID_TFCAT_TIP_KEYBOARD,
            &GUID_TFCAT_TIPCAP_UIELEMENTENABLED,
            &GUID_TFCAT_TIPCAP_COMLESS,
            &GUID_TFCAT_TIPCAP_IMMERSIVESUPPORT,
            &GUID_TFCAT_TIPCAP_SYSTRAYSUPPORT,
        };
        for (const GUID* cat : cats) {
            categories->UnregisterCategory(kBowGoClsid, *cat, kBowGoClsid);
        }
        categories->Release();
    }
}

// regsvr32 thường đã CoInitialize sẵn; nếu chưa thì tự init (S_FALSE/đổi mode
// đều coi như "đã có COM", không phải lỗi).
class ScopedCom {
public:
    ScopedCom() {
        HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
        owns_ = SUCCEEDED(hr);
        ok_ = owns_ || hr == RPC_E_CHANGED_MODE;
    }
    ~ScopedCom() {
        if (owns_) CoUninitialize();
    }
    bool ok() const { return ok_; }

private:
    bool owns_ = false;
    bool ok_ = false;
};

}  // namespace

// ── Điểm vào DLL ─────────────────────────────────────────────────────────────

BOOL APIENTRY DllMain(HINSTANCE instance, DWORD reason, LPVOID) {
    if (reason == DLL_PROCESS_ATTACH) {
        g_instance = instance;
        DisableThreadLibraryCalls(instance);
    }
    return TRUE;
}

STDAPI DllGetClassObject(REFCLSID rclsid, REFIID riid, void** ppv) {
    if (!ppv) return E_INVALIDARG;
    *ppv = nullptr;
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
    ScopedCom com;
    if (!com.ok()) return E_FAIL;
    if (!RegisterComServer()) {
        // Thiếu quyền ghi HKCR (cần chạy regsvr32 bằng Administrator).
        UnregisterComServer();
        return E_ACCESSDENIED;
    }
    if (!RegisterTsfProfiles()) {
        UnregisterTsfProfiles();
        UnregisterComServer();
        return E_FAIL;
    }
    return S_OK;
}

STDAPI DllUnregisterServer() {
    ScopedCom com;
    if (!com.ok()) return E_FAIL;
    UnregisterTsfProfiles();
    UnregisterComServer();
    return S_OK;
}

#endif  // _WIN32
