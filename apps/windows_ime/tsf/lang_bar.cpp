// lang_bar.cpp — xem lang_bar.h.

#if defined(_WIN32)

#include "lang_bar.h"

#include <olectl.h>  // CONNECT_E_*

#include <new>

#include "badge_icon.h"

// GUID nút trên langbar (khai báo ở BowGoTextService.cpp).
extern const GUID kBowGoLangBarGuid;

namespace bowgo {

LangBarButton::LangBarButton(TfClientId client_id, ToggleCallback on_toggle)
    : ref_count_(1),
      client_id_(client_id),
      on_toggle_(std::move(on_toggle)),
      vietnamese_(true),
      sink_(nullptr),
      sink_cookie_(TF_INVALID_COOKIE) {
    info_.clsidService = GUID_NULL;  // đặt bởi text service khi thêm nếu cần
    info_.guidItem = kBowGoLangBarGuid;
    info_.dwStyle = TF_LBI_STYLE_BTN_BUTTON | TF_LBI_STYLE_SHOWNINTRAY;
    info_.ulSort = 0;
    lstrcpynW(info_.szDescription, L"Bow Go", ARRAYSIZE(info_.szDescription));
}

LangBarButton::~LangBarButton() {
    if (sink_) sink_->Release();
}

void LangBarButton::SetVietnamese(bool vietnamese) {
    if (vietnamese_ == vietnamese) return;
    vietnamese_ = vietnamese;
    NotifyUpdate();
}

void LangBarButton::NotifyUpdate() {
    if (sink_) {
        // Báo langbar: icon + tooltip có thể đã đổi -> vẽ lại.
        sink_->OnUpdate(TF_LBI_ICON | TF_LBI_TOOLTIP | TF_LBI_TEXT);
    }
}

HRESULT LangBarButton::AddTo(ITfThreadMgr* thread_mgr) {
    ITfLangBarItemMgr* mgr = nullptr;
    HRESULT hr = thread_mgr->QueryInterface(IID_ITfLangBarItemMgr,
                                            reinterpret_cast<void**>(&mgr));
    if (FAILED(hr)) return hr;
    hr = mgr->AddItem(this);
    mgr->Release();
    return hr;
}

HRESULT LangBarButton::RemoveFrom(ITfThreadMgr* thread_mgr) {
    ITfLangBarItemMgr* mgr = nullptr;
    HRESULT hr = thread_mgr->QueryInterface(IID_ITfLangBarItemMgr,
                                            reinterpret_cast<void**>(&mgr));
    if (FAILED(hr)) return hr;
    hr = mgr->RemoveItem(this);
    mgr->Release();
    return hr;
}

// ── IUnknown ─────────────────────────────────────────────────────────────────

STDMETHODIMP LangBarButton::QueryInterface(REFIID riid, void** ppv) {
    if (!ppv) return E_INVALIDARG;
    *ppv = nullptr;
    if (IsEqualIID(riid, IID_IUnknown) || IsEqualIID(riid, IID_ITfLangBarItem) ||
        IsEqualIID(riid, IID_ITfLangBarItemButton)) {
        *ppv = static_cast<ITfLangBarItemButton*>(this);
    } else if (IsEqualIID(riid, IID_ITfSource)) {
        *ppv = static_cast<ITfSource*>(this);
    }
    if (*ppv) {
        AddRef();
        return S_OK;
    }
    return E_NOINTERFACE;
}

STDMETHODIMP_(ULONG) LangBarButton::AddRef() {
    return InterlockedIncrement(&ref_count_);
}

STDMETHODIMP_(ULONG) LangBarButton::Release() {
    LONG c = InterlockedDecrement(&ref_count_);
    if (c == 0) delete this;
    return c;
}

// ── ITfLangBarItem ───────────────────────────────────────────────────────────

STDMETHODIMP LangBarButton::GetInfo(TF_LANGBARITEMINFO* info) {
    if (!info) return E_INVALIDARG;
    *info = info_;
    return S_OK;
}

STDMETHODIMP LangBarButton::GetStatus(DWORD* status) {
    if (!status) return E_INVALIDARG;
    *status = 0;  // luôn hiện & bấm được
    return S_OK;
}

STDMETHODIMP LangBarButton::Show(BOOL /*show*/) { return S_OK; }

STDMETHODIMP LangBarButton::GetTooltipString(BSTR* tooltip) {
    if (!tooltip) return E_INVALIDARG;
    const WCHAR* s = vietnamese_ ? L"Bow Go — Tiếng Việt (bấm để tắt)"
                                 : L"Bow Go — English (bấm để bật)";
    *tooltip = SysAllocString(s);
    return *tooltip ? S_OK : E_OUTOFMEMORY;
}

// ── ITfLangBarItemButton ─────────────────────────────────────────────────────

STDMETHODIMP LangBarButton::OnClick(TfLBIClick click, POINT /*pt*/,
                                     const RECT* /*area*/) {
    if (click == TF_LBI_CLK_LEFT && on_toggle_) {
        on_toggle_();  // đảo VI/EN; text service sẽ gọi SetVietnamese để cập nhật
    }
    return S_OK;
}

STDMETHODIMP LangBarButton::InitMenu(ITfMenu* /*menu*/) { return S_OK; }
STDMETHODIMP LangBarButton::OnMenuSelect(UINT /*id*/) { return S_OK; }

STDMETHODIMP LangBarButton::GetIcon(HICON* icon) {
    if (!icon) return E_INVALIDARG;
    // Langbar sở hữu HICON trả về -> nó tự DestroyIcon. Ta tạo mới mỗi lần.
    *icon = CreateBadgeIcon(vietnamese_, 16);
    return *icon ? S_OK : E_FAIL;
}

STDMETHODIMP LangBarButton::GetText(BSTR* text) {
    if (!text) return E_INVALIDARG;
    *text = SysAllocString(vietnamese_ ? L"VI" : L"EN");
    return *text ? S_OK : E_OUTOFMEMORY;
}

// ── ITfSource ────────────────────────────────────────────────────────────────

STDMETHODIMP LangBarButton::AdviseSink(REFIID riid, IUnknown* punk, DWORD* cookie) {
    if (!IsEqualIID(riid, IID_ITfLangBarItemSink)) return CONNECT_E_CANNOTCONNECT;
    if (sink_) return CONNECT_E_ADVISELIMIT;  // chỉ một sink
    HRESULT hr = punk->QueryInterface(IID_ITfLangBarItemSink,
                                      reinterpret_cast<void**>(&sink_));
    if (FAILED(hr)) return hr;
    sink_cookie_ = 0;
    *cookie = sink_cookie_;
    return S_OK;
}

STDMETHODIMP LangBarButton::UnadviseSink(DWORD cookie) {
    if (cookie != sink_cookie_ || !sink_) return CONNECT_E_NOCONNECTION;
    sink_->Release();
    sink_ = nullptr;
    sink_cookie_ = TF_INVALID_COOKIE;
    return S_OK;
}

}  // namespace bowgo

#endif  // _WIN32
