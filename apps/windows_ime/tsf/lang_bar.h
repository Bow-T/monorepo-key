// lang_bar.h
// ----------
// Nút trên khay ngôn ngữ (language bar) hiện icon VI/EN, bấm để bật/tắt bộ gõ —
// bản Windows của icon menu bar VI/EN bên macOS.
//
// Hiện thực ITfLangBarItemButton + ITfSource. Text service (BowGoTextService)
// sở hữu một nút này, cập nhật icon mỗi khi trạng thái VI/EN đổi.
//
// ⚠️ Chỉ build trên Windows (msctf.h + GDI).

#pragma once

#if defined(_WIN32)

#include <msctf.h>
#include <windows.h>

#include <functional>

namespace bowgo {

// Callback khi người dùng bấm nút (đảo trạng thái). Do text service cung cấp.
using ToggleCallback = std::function<void()>;

class LangBarButton : public ITfLangBarItemButton, public ITfSource {
public:
    LangBarButton(TfClientId client_id, ToggleCallback on_toggle);

    // Cập nhật icon + tooltip theo trạng thái VI/EN (gọi từ text service).
    void SetVietnamese(bool vietnamese);

    // Đăng ký / gỡ nút vào ITfLangBarItemMgr của thread manager.
    HRESULT AddTo(ITfThreadMgr* thread_mgr);
    HRESULT RemoveFrom(ITfThreadMgr* thread_mgr);

    // IUnknown
    STDMETHODIMP QueryInterface(REFIID riid, void** ppv) override;
    STDMETHODIMP_(ULONG) AddRef() override;
    STDMETHODIMP_(ULONG) Release() override;

    // ITfLangBarItem
    STDMETHODIMP GetInfo(TF_LANGBARITEMINFO* info) override;
    STDMETHODIMP GetStatus(DWORD* status) override;
    STDMETHODIMP Show(BOOL show) override;
    STDMETHODIMP GetTooltipString(BSTR* tooltip) override;

    // ITfLangBarItemButton
    STDMETHODIMP OnClick(TfLBIClick click, POINT pt, const RECT* area) override;
    STDMETHODIMP InitMenu(ITfMenu* menu) override;
    STDMETHODIMP OnMenuSelect(UINT id) override;
    STDMETHODIMP GetIcon(HICON* icon) override;
    STDMETHODIMP GetText(BSTR* text) override;

    // ITfSource
    STDMETHODIMP AdviseSink(REFIID riid, IUnknown* punk, DWORD* cookie) override;
    STDMETHODIMP UnadviseSink(DWORD cookie) override;

private:
    ~LangBarButton();

    void NotifyUpdate();  // báo langbar vẽ lại (icon/tooltip đổi)

    LONG ref_count_;
    TfClientId client_id_;
    ToggleCallback on_toggle_;
    bool vietnamese_;

    TF_LANGBARITEMINFO info_;
    ITfLangBarItemSink* sink_;  // nơi báo "cập nhật"
    DWORD sink_cookie_;
};

}  // namespace bowgo

#endif  // _WIN32
