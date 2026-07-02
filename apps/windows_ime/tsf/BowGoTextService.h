// BowGoTextService.h
// -------------------
// TSF text service cho bộ gõ Bow Go trên Windows.
//
// Kiến trúc TSF (Text Services Framework):
//   - Bộ gõ là một COM in-proc server (DLL) hiện thực ITfTextInputProcessor.
//   - Khi kích hoạt: gắn key event sink (ITfKeyEventSink) + thread mgr sink.
//   - Mỗi phím: dịch VK -> ký tự theo layout thật (ToUnicodeEx) -> đưa qua
//     ImeController (logic dùng chung, đã test đa nền) -> nếu controller trả
//     KeyAction::Replace thì ghi văn bản mới vào tài liệu qua ITfEditSession.
//
// PHẦN LOGIC (word-break, macro, khôi phục tiếng Anh, tự sửa lỗi, backspace
// đồng bộ) NẰM Ở common/ime_controller.* — đã có 66 ca test xanh trên mọi nền.
// File này chỉ còn phần "keo dán" Win32/TSF, không thể test ngoài Windows.
//
// ⚠️ Chỉ build được trên Windows (Windows SDK + msctf.h).

#pragma once

#if defined(_WIN32)

#include <msctf.h>
#include <windows.h>

#include <string>

#include "../common/ime_controller.h"
#include "lang_bar.h"

// CLSID & profile GUID thật của text service (sinh bằng uuidgen).
extern const CLSID kBowGoClsid;
extern const GUID kBowGoProfileGuid;
extern const GUID kBowGoLangBarGuid;

// Các hàm/biến dùng chung với dll_main.cpp.
void DllAddRef();
void DllRelease();
HINSTANCE DllInstance();

// Text service: hiện thực các interface TSF tối thiểu để nhận phím và sửa văn bản.
class BowGoTextService : public ITfTextInputProcessor,
                          public ITfThreadMgrEventSink,
                          public ITfKeyEventSink {
public:
    BowGoTextService();

    // IUnknown
    STDMETHODIMP QueryInterface(REFIID riid, void** ppv) override;
    STDMETHODIMP_(ULONG) AddRef() override;
    STDMETHODIMP_(ULONG) Release() override;

    // ITfTextInputProcessor — vòng đời service.
    STDMETHODIMP Activate(ITfThreadMgr* thread_mgr, TfClientId client_id) override;
    STDMETHODIMP Deactivate() override;

    // ITfThreadMgrEventSink — theo dõi focus tài liệu.
    STDMETHODIMP OnInitDocumentMgr(ITfDocumentMgr*) override { return S_OK; }
    STDMETHODIMP OnUninitDocumentMgr(ITfDocumentMgr*) override { return S_OK; }
    STDMETHODIMP OnSetFocus(ITfDocumentMgr* focus, ITfDocumentMgr* prev) override;
    STDMETHODIMP OnPushContext(ITfContext*) override { return S_OK; }
    STDMETHODIMP OnPopContext(ITfContext*) override { return S_OK; }

    // ITfKeyEventSink — nơi nhận phím người dùng gõ.
    STDMETHODIMP OnSetFocus(BOOL focus) override;
    STDMETHODIMP OnTestKeyDown(ITfContext* ctx, WPARAM wparam, LPARAM lparam,
                               BOOL* eaten) override;
    STDMETHODIMP OnKeyDown(ITfContext* ctx, WPARAM wparam, LPARAM lparam,
                           BOOL* eaten) override;
    STDMETHODIMP OnTestKeyUp(ITfContext*, WPARAM, LPARAM, BOOL* eaten) override {
        *eaten = FALSE;
        return S_OK;
    }
    STDMETHODIMP OnKeyUp(ITfContext*, WPARAM, LPARAM, BOOL* eaten) override {
        *eaten = FALSE;
        return S_OK;
    }
    // Phím tắt bật/tắt VI-EN đã "giữ chỗ" (preserved key) — Ctrl+Shift.
    STDMETHODIMP OnPreservedKey(ITfContext* ctx, REFGUID rguid, BOOL* eaten) override;

private:
    ~BowGoTextService();

    // Bật/tắt bộ gõ + cập nhật icon langbar. Dùng cho cả preserved key lẫn nút.
    void ToggleEnabled();

    // Đăng ký / gỡ phím tắt bật/tắt (Ctrl+Shift) qua ITfKeystrokeMgr::PreserveKey.
    void RegisterToggleHotkey();
    void UnregisterToggleHotkey();

    // Tra xem một phím CÓ được ta xử lý không (không đổi trạng thái) — cho
    // OnTestKeyDown. Nếu xử lý, xuất ra `action` để OnKeyDown dùng lại.
    bool WillHandle(WPARAM vk, bowgo::KeyAction* action_out, bool* is_edit);

    // Dịch VK (+ trạng thái phím bổ trợ hiện tại) -> ký tự Unicode theo layout
    // bàn phím THẬT bằng ToUnicodeEx. Trả 0 nếu không ra ký tự in được.
    char32_t TranslateKey(WPARAM vk);

    // Thi hành KeyAction: ghi (xoá `backspaces` + chèn `text`) qua edit session.
    HRESULT ApplyReplace(ITfContext* ctx, int backspaces, const std::u32string& text);

    // Nạp/nạp lại settings.json (đọc bằng API wide để không vướng ANSI codepage).
    void LoadSettings();
    // Nếu file settings thay đổi từ lần đọc trước -> nạp lại. Gọi khi focus đổi.
    void ReloadSettingsIfChanged();

    LONG ref_count_;
    ITfThreadMgr* thread_mgr_;
    TfClientId client_id_;
    DWORD thread_mgr_cookie_;   // cookie AdviseSink cho ITfThreadMgrEventSink
    bool key_sink_advised_;

    bowgo::ImeController controller_;

    bowgo::LangBarButton* lang_bar_;  // nút VI/EN trên khay ngôn ngữ
    bool toggle_key_preserved_;       // đã PreserveKey phím tắt chưa

    std::wstring settings_path_;
    FILETIME settings_mtime_;   // mtime lần đọc gần nhất (để phát hiện đổi)
};

#endif  // _WIN32
