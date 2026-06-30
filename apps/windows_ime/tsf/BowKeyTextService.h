// BowKeyTextService.h
// -------------------
// Skeleton TSF text service cho bộ gõ Bow Key trên Windows.
//
// ⚠️  CHƯA KIỂM CHỨNG: file này chỉ build được trên Windows (cần Windows SDK +
//     msctf.h). KHÔNG biên dịch/chạy được trên macOS. Đây là khung cấu trúc để
//     bắt đầu, bám theo mẫu TSF chính thức của Microsoft; phần engine (../engine)
//     mới là phần đã kiểm chứng (81/81 ca test xanh).
//
// Kiến trúc TSF (Text Services Framework):
//   - Bộ gõ là một COM in-proc server (DLL) hiện thực ITfTextInputProcessor.
//   - Khi được kích hoạt, nó gắn các "sink" để nhận sự kiện bàn phím
//     (ITfKeyEventSink): OnKeyDown nhận phím -> đưa qua VietEngine -> nếu engine
//     biến đổi chuỗi thì ta "ghi" văn bản mới vào tài liệu qua ITfContext.
//
// File này khai báo lớp service; phần ghi văn bản qua edit session để ở .cpp.

#pragma once

#if defined(_WIN32)

#include <msctf.h>
#include <windows.h>

#include "../engine/engine.h"

// CLSID & profile GUID của text service (sinh mới bằng guidgen; đây là chỗ giữ chỗ).
// Phải đăng ký trong registry + qua ITfInputProcessorProfiles khi cài.
extern const CLSID kBowKeyClsid;
extern const GUID kBowKeyProfileGuid;
extern const GUID kBowKeyLangBarGuid;

// Text service: hiện thực các interface TSF tối thiểu để nhận phím và sửa văn bản.
class BowKeyTextService : public ITfTextInputProcessor,
                          public ITfThreadMgrEventSink,
                          public ITfKeyEventSink {
public:
    BowKeyTextService();

    // IUnknown
    STDMETHODIMP QueryInterface(REFIID riid, void** ppv) override;
    STDMETHODIMP_(ULONG) AddRef() override;
    STDMETHODIMP_(ULONG) Release() override;

    // ITfTextInputProcessor — vòng đời service.
    STDMETHODIMP Activate(ITfThreadMgr* thread_mgr, TfClientId client_id) override;
    STDMETHODIMP Deactivate() override;

    // ITfThreadMgrEventSink — theo dõi focus tài liệu (rút gọn).
    STDMETHODIMP OnInitDocumentMgr(ITfDocumentMgr*) override { return S_OK; }
    STDMETHODIMP OnUninitDocumentMgr(ITfDocumentMgr*) override { return S_OK; }
    STDMETHODIMP OnSetFocus(ITfDocumentMgr*, ITfDocumentMgr*) override;
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
    STDMETHODIMP OnPreservedKey(ITfContext*, REFGUID, BOOL* eaten) override {
        *eaten = FALSE;
        return S_OK;
    }

private:
    ~BowKeyTextService();

    // Quyết định một phím có thuộc bộ gõ không, và xử lý nó qua engine. Trả true
    // nếu engine "nuốt" phím (đã thay văn bản); false nếu để phím đi qua.
    bool HandleKey(ITfContext* ctx, WPARAM wparam, bool* out_eaten);

    // Ghi chuỗi thay thế vào tài liệu (qua edit session). `backspaces` = số ký tự
    // cũ cần xoá, `text` = chuỗi tiếng Việt mới. Để ở .cpp.
    void ReplaceText(ITfContext* ctx, int backspaces, const std::u32string& text);

    LONG ref_count_;
    ITfThreadMgr* thread_mgr_;
    TfClientId client_id_;
    DWORD thread_mgr_cookie_;

    bowkey::VietEngine engine_;
    int committed_length_;  // số ký tự thô đã hiện cho âm tiết hiện tại
};

#endif  // _WIN32
