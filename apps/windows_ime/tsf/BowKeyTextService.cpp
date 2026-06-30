// BowKeyTextService.cpp
// ---------------------
// ⚠️  CHƯA KIỂM CHỨNG — chỉ build trên Windows (Windows SDK). Xem header.
//
// Phần "cầu nối" giữa phím Windows và VietEngine ở HandleKey là phần thú vị nhất
// và bám sát EventTapController.swift (macOS). Phần ITf* edit session (ReplaceText)
// để dạng stub có chú thích vì nó cần API TSF thật + môi trường Windows để thử.

#if defined(_WIN32)

#include "BowKeyTextService.h"

// GUID giữ chỗ — PHẢI sinh mới (guidgen.exe) cho bản phát hành thật.
const CLSID kBowKeyClsid =
    {0x00000000, 0x0000, 0x0000, {0,0,0,0,0,0,0,0}};
const GUID kBowKeyProfileGuid =
    {0x00000000, 0x0000, 0x0000, {0,0,0,0,0,0,0,1}};
const GUID kBowKeyLangBarGuid =
    {0x00000000, 0x0000, 0x0000, {0,0,0,0,0,0,0,2}};

namespace {

// Dịch virtual-key của Windows (+ trạng thái Shift) sang ký tự. Bản tối giản cho
// chữ cái + số ASCII — đủ cho Telex/VNI. Bản đầy đủ nên dùng ToUnicodeEx theo
// layout thật (tương tự UCKeyTranslate bên macOS) — xem README, mục việc cần làm.
char32_t KeyToChar(WPARAM vk, bool shift) {
    if (vk >= 'A' && vk <= 'Z') {
        char32_t base = static_cast<char32_t>(vk);  // 'A'..'Z'
        return shift ? base : (base + 32);           // mặc định chữ thường
    }
    if (vk >= '0' && vk <= '9') {
        return static_cast<char32_t>(vk);
    }
    return 0;  // phím khác -> không thuộc engine
}

bool IsWordBreakVk(WPARAM vk) {
    return vk == VK_SPACE || vk == VK_RETURN || vk == VK_TAB || vk == VK_ESCAPE;
}

}  // namespace

BowKeyTextService::BowKeyTextService()
    : ref_count_(1),
      thread_mgr_(nullptr),
      client_id_(TF_CLIENTID_NULL),
      thread_mgr_cookie_(TF_INVALID_COOKIE),
      engine_(bowkey::InputMethod::Telex, bowkey::ToneStyle::Modern),
      committed_length_(0) {}

BowKeyTextService::~BowKeyTextService() {}

// ── IUnknown ───────────────────────────────────────────────────────────────

STDMETHODIMP BowKeyTextService::QueryInterface(REFIID riid, void** ppv) {
    if (!ppv) return E_INVALIDARG;
    *ppv = nullptr;
    if (IsEqualIID(riid, IID_IUnknown) ||
        IsEqualIID(riid, IID_ITfTextInputProcessor)) {
        *ppv = static_cast<ITfTextInputProcessor*>(this);
    } else if (IsEqualIID(riid, IID_ITfThreadMgrEventSink)) {
        *ppv = static_cast<ITfThreadMgrEventSink*>(this);
    } else if (IsEqualIID(riid, IID_ITfKeyEventSink)) {
        *ppv = static_cast<ITfKeyEventSink*>(this);
    }
    if (*ppv) {
        AddRef();
        return S_OK;
    }
    return E_NOINTERFACE;
}

STDMETHODIMP_(ULONG) BowKeyTextService::AddRef() {
    return InterlockedIncrement(&ref_count_);
}

STDMETHODIMP_(ULONG) BowKeyTextService::Release() {
    LONG c = InterlockedDecrement(&ref_count_);
    if (c == 0) delete this;
    return c;
}

// ── ITfTextInputProcessor: vòng đời ──────────────────────────────────────────

STDMETHODIMP BowKeyTextService::Activate(ITfThreadMgr* thread_mgr,
                                         TfClientId client_id) {
    thread_mgr_ = thread_mgr;
    thread_mgr_->AddRef();
    client_id_ = client_id;

    // TODO(windows): gắn ITfThreadMgrEventSink (AdviseSink) và đăng ký key event
    // sink qua ITfKeystrokeMgr::AdviseKeyEventSink. Cần môi trường Windows để thử.
    return S_OK;
}

STDMETHODIMP BowKeyTextService::Deactivate() {
    // TODO(windows): gỡ các sink đã gắn (UnadviseSink / UnadviseKeyEventSink).
    if (thread_mgr_) {
        thread_mgr_->Release();
        thread_mgr_ = nullptr;
    }
    client_id_ = TF_CLIENTID_NULL;
    return S_OK;
}

STDMETHODIMP BowKeyTextService::OnSetFocus(ITfDocumentMgr*, ITfDocumentMgr*) {
    // Đổi tài liệu/ô nhập -> chốt âm tiết đang gõ.
    engine_.Clear();
    committed_length_ = 0;
    return S_OK;
}

// ── ITfKeyEventSink ──────────────────────────────────────────────────────────

STDMETHODIMP BowKeyTextService::OnSetFocus(BOOL) { return S_OK; }

STDMETHODIMP BowKeyTextService::OnTestKeyDown(ITfContext*, WPARAM wparam,
                                              LPARAM, BOOL* eaten) {
    // "Test" = hỏi trước xem ta CÓ định xử lý phím này không (không được sửa văn
    // bản ở đây). Coi là ăn nếu là chữ/số ta dịch được hoặc phím backspace.
    bool shift = (GetKeyState(VK_SHIFT) & 0x8000) != 0;
    bool handled = KeyToChar(wparam, shift) != 0 || wparam == VK_BACK;
    *eaten = handled ? TRUE : FALSE;
    return S_OK;
}

STDMETHODIMP BowKeyTextService::OnKeyDown(ITfContext* ctx, WPARAM wparam,
                                          LPARAM, BOOL* eaten) {
    return HandleKey(ctx, wparam, reinterpret_cast<bool*>(eaten)) ? S_OK : S_OK;
}

// ── Cầu nối phím -> engine (bám EventTapController.handle bên macOS) ──────────

bool BowKeyTextService::HandleKey(ITfContext* ctx, WPARAM wparam, bool* out_eaten) {
    BOOL* eaten = reinterpret_cast<BOOL*>(out_eaten);
    *eaten = FALSE;

    // Backspace: lùi trong engine, để phím gốc đi qua (xoá 1 ký tự trên màn).
    if (wparam == VK_BACK) {
        auto rebuilt = engine_.Backspace();
        if (rebuilt.has_value()) {
            committed_length_ = static_cast<int>(rebuilt->size());
        } else {
            committed_length_ = 0;
        }
        *eaten = FALSE;  // để Backspace gốc xoá 1 ký tự
        return false;
    }

    // Phím ngắt âm tiết -> chốt từ, cho đi qua.
    if (IsWordBreakVk(wparam)) {
        engine_.Clear();
        committed_length_ = 0;
        *eaten = FALSE;
        return false;
    }

    bool shift = (GetKeyState(VK_SHIFT) & 0x8000) != 0;
    char32_t ch = KeyToChar(wparam, shift);
    if (ch == 0) {
        // Phím ta không xử lý -> chốt từ, cho đi qua.
        engine_.Clear();
        committed_length_ = 0;
        *eaten = FALSE;
        return false;
    }

    auto rendered = engine_.Process(ch);
    if (!rendered.has_value()) {
        // Engine bảo đây là ngắt từ -> cho đi qua.
        committed_length_ = 0;
        *eaten = FALSE;
        return false;
    }

    // Engine trả chuỗi mới: nuốt phím gốc, gõ thay (xoá cũ + ghi mới).
    int backspaces = committed_length_;
    committed_length_ = static_cast<int>(rendered->size());
    ReplaceText(ctx, backspaces, *rendered);
    *eaten = TRUE;  // nuốt phím gốc
    return true;
}

void BowKeyTextService::ReplaceText(ITfContext* /*ctx*/, int /*backspaces*/,
                                    const std::u32string& /*text*/) {
    // TODO(windows): hiện thực qua ITfEditSession:
    //   1. ctx->RequestEditSession(client_id_, session, TF_ES_READWRITE|TF_ES_SYNC, &hr)
    //   2. Trong session: lấy ITfRange tại con trỏ, lùi `backspaces` ký tự, rồi
    //      range->SetText(...) bằng chuỗi UTF-16 chuyển từ `text` (u32 -> UTF-16).
    // Cần ITfContext thật + môi trường Windows để thử; đây là phần còn lại để làm.
}

#endif  // _WIN32
