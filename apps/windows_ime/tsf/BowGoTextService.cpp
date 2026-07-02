// BowGoTextService.cpp
// ---------------------
// Phần "keo dán" Win32/TSF. Logic bộ gõ nằm ở common/ime_controller.* (đã test
// đa nền). Ở đây:
//   - Activate/Deactivate: gắn/gỡ key sink + thread mgr sink.
//   - OnTestKeyDown/OnKeyDown: dịch phím theo layout thật -> ImeController ->
//     thi hành KeyAction (sửa văn bản qua edit session).
//   - EditSession: xoá N ký tự + chèn chuỗi UTF-16 tại con trỏ.
//   - LoadSettings: đọc %APPDATA%\BowGo\settings.json.
//
// ⚠️ Chỉ build trên Windows (Windows SDK + msctf.h).

#if defined(_WIN32)

#include "BowGoTextService.h"

#include <cstdlib>  // _wdupenv_s, free
#include <new>
#include <vector>

#include "../common/bow_config.h"
#include "../common/text_codec.h"

using bowgo::BreakKey;
using bowgo::KeyAction;

// GUID thật (uuidgen). Trùng với các GUID đăng ký trong dll_main.cpp.
const CLSID kBowGoClsid = {
    0x40C17F41, 0x21E3, 0x4AD9, {0x94, 0x01, 0xDF, 0x06, 0x1E, 0x55, 0xD0, 0xA0}};
const GUID kBowGoProfileGuid = {
    0x4D821E5D, 0xDCBA, 0x4DF4, {0x87, 0xE6, 0xDA, 0x4D, 0x8D, 0x44, 0xD6, 0x41}};
const GUID kBowGoLangBarGuid = {
    0xA80D9A67, 0x4DF4, 0x4209, {0xBD, 0xDD, 0xD3, 0x69, 0x89, 0xCC, 0x0D, 0x12}};

// GUID phím tắt "giữ chỗ" bật/tắt VI-EN (uuidgen).
static const GUID kBowGoToggleKeyGuid = {
    0x9F2C1B84, 0x7E45, 0x4C3A, {0xA1, 0x0B, 0x2D, 0x8E, 0x6F, 0x11, 0x93, 0x5C}};

namespace {

// VK là phím ngắt từ nào (nullopt = không phải phím ngắt).
bool WordBreakOf(WPARAM vk, BreakKey* out) {
    switch (vk) {
        case VK_SPACE: *out = BreakKey::Space; return true;
        case VK_RETURN: *out = BreakKey::Enter; return true;
        case VK_TAB: *out = BreakKey::Tab; return true;
        case VK_ESCAPE: *out = BreakKey::Escape; return true;
        default: return false;
    }
}

// Phím điều hướng / sửa con trỏ -> chốt âm tiết (giống click chuột bên macOS).
bool IsCaretMovementKey(WPARAM vk) {
    switch (vk) {
        case VK_LEFT: case VK_RIGHT: case VK_UP: case VK_DOWN:
        case VK_HOME: case VK_END: case VK_PRIOR: case VK_NEXT:
        case VK_DELETE: case VK_INSERT:
            return true;
        default:
            return false;
    }
}

bool ModifierDown(int vk) { return (GetKeyState(vk) & 0x8000) != 0; }

// Có đang giữ Ctrl hoặc Alt (không tính AltGr thuần)? -> phím tắt, không gõ chữ.
bool CtrlOrAltDown() {
    bool ctrl = ModifierDown(VK_CONTROL);
    bool alt = ModifierDown(VK_MENU);
    // AltGr = Ctrl+Alt (bàn phím EU): KHÔNG coi là phím tắt — để ToUnicodeEx ra
    // ký tự (vd '@' trên vài layout). Chỉ Ctrl-mình hoặc Alt-mình mới là tắt.
    if (ctrl && alt) return false;
    return ctrl || alt;
}

}  // namespace

// ── EditSession: ghi văn bản (xoá backspaces + chèn text) ─────────────────────

namespace {

class ReplaceEditSession : public ITfEditSession {
public:
    ReplaceEditSession(ITfContext* ctx, TfClientId client_id, int backspaces,
                       std::wstring text)
        : ref_(1),
          ctx_(ctx),
          client_id_(client_id),
          backspaces_(backspaces),
          text_(std::move(text)) {
        ctx_->AddRef();
    }

    STDMETHODIMP QueryInterface(REFIID riid, void** ppv) override {
        if (!ppv) return E_INVALIDARG;
        if (IsEqualIID(riid, IID_IUnknown) || IsEqualIID(riid, IID_ITfEditSession)) {
            *ppv = static_cast<ITfEditSession*>(this);
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

    STDMETHODIMP DoEditSession(TfEditCookie ec) override {
        ITfInsertAtSelection* insert = nullptr;
        if (FAILED(ctx_->QueryInterface(IID_ITfInsertAtSelection,
                                        reinterpret_cast<void**>(&insert)))) {
            return E_FAIL;
        }

        HRESULT hr = S_OK;
        ITfRange* range = nullptr;
        // Lấy range rỗng tại con trỏ (đầu vùng chọn hiện tại).
        hr = insert->InsertTextAtSelection(ec, TF_IAS_QUERYONLY, nullptr, 0, &range);
        if (SUCCEEDED(hr) && range) {
            // Lùi `backspaces_` ký tự về trước để bao trọn phần cần xoá.
            if (backspaces_ > 0) {
                LONG shifted = 0;
                range->ShiftStart(ec, -backspaces_, &shifted, nullptr);
                // shifted có thể < backspaces_ ở đầu tài liệu — vẫn ghi đè phần có.
            }
            // Đặt văn bản mới cho toàn range (xoá cũ + chèn mới trong một bước).
            hr = range->SetText(ec, 0, text_.c_str(),
                                static_cast<LONG>(text_.size()));
            // Đưa con trỏ về CUỐI văn bản vừa chèn.
            if (SUCCEEDED(hr)) {
                range->Collapse(ec, TF_ANCHOR_END);
                TF_SELECTION sel;
                sel.range = range;
                sel.style.ase = TF_AE_NONE;
                sel.style.fInterimChar = FALSE;
                ctx_->SetSelection(ec, 1, &sel);
            }
            range->Release();
        }
        insert->Release();
        return hr;
    }

private:
    ~ReplaceEditSession() { ctx_->Release(); }
    LONG ref_;
    ITfContext* ctx_;
    TfClientId client_id_;
    int backspaces_;
    std::wstring text_;
};

}  // namespace

// ── BowGoTextService ─────────────────────────────────────────────────────────

BowGoTextService::BowGoTextService()
    : ref_count_(1),
      thread_mgr_(nullptr),
      client_id_(TF_CLIENTID_NULL),
      thread_mgr_cookie_(TF_INVALID_COOKIE),
      key_sink_advised_(false),
      lang_bar_(nullptr),
      toggle_key_preserved_(false) {
    DllAddRef();
    settings_mtime_ = {0, 0};
    LoadSettings();
}

BowGoTextService::~BowGoTextService() { DllRelease(); }

// ── IUnknown ───────────────────────────────────────────────────────────────

STDMETHODIMP BowGoTextService::QueryInterface(REFIID riid, void** ppv) {
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

STDMETHODIMP_(ULONG) BowGoTextService::AddRef() {
    return InterlockedIncrement(&ref_count_);
}

STDMETHODIMP_(ULONG) BowGoTextService::Release() {
    LONG c = InterlockedDecrement(&ref_count_);
    if (c == 0) delete this;
    return c;
}

// ── ITfTextInputProcessor: vòng đời ──────────────────────────────────────────

STDMETHODIMP BowGoTextService::Activate(ITfThreadMgr* thread_mgr,
                                         TfClientId client_id) {
    thread_mgr_ = thread_mgr;
    thread_mgr_->AddRef();
    client_id_ = client_id;

    // Gắn ITfThreadMgrEventSink (theo dõi focus tài liệu).
    ITfSource* source = nullptr;
    if (SUCCEEDED(thread_mgr_->QueryInterface(IID_ITfSource,
                                              reinterpret_cast<void**>(&source)))) {
        source->AdviseSink(IID_ITfThreadMgrEventSink,
                           static_cast<ITfThreadMgrEventSink*>(this),
                           &thread_mgr_cookie_);
        source->Release();
    }

    // Đăng ký key event sink (nhận OnKeyDown/OnTestKeyDown).
    ITfKeystrokeMgr* keystroke = nullptr;
    if (SUCCEEDED(thread_mgr_->QueryInterface(IID_ITfKeystrokeMgr,
                                              reinterpret_cast<void**>(&keystroke)))) {
        if (SUCCEEDED(keystroke->AdviseKeyEventSink(
                client_id_, static_cast<ITfKeyEventSink*>(this), TRUE))) {
            key_sink_advised_ = true;
        }
        keystroke->Release();
    }

    // Phím tắt bật/tắt VI-EN (Ctrl+Shift) qua PreserveKey.
    RegisterToggleHotkey();

    // Nút VI/EN trên khay ngôn ngữ. Bấm -> đảo trạng thái (ToggleEnabled).
    lang_bar_ = new (std::nothrow) bowgo::LangBarButton(
        client_id_, [this]() { ToggleEnabled(); });
    if (lang_bar_) {
        lang_bar_->SetVietnamese(controller_.enabled());
        lang_bar_->AddTo(thread_mgr_);
    }

    return S_OK;
}

STDMETHODIMP BowGoTextService::Deactivate() {
    if (lang_bar_) {
        if (thread_mgr_) lang_bar_->RemoveFrom(thread_mgr_);
        lang_bar_->Release();
        lang_bar_ = nullptr;
    }
    UnregisterToggleHotkey();
    if (thread_mgr_) {
        if (key_sink_advised_) {
            ITfKeystrokeMgr* keystroke = nullptr;
            if (SUCCEEDED(thread_mgr_->QueryInterface(
                    IID_ITfKeystrokeMgr, reinterpret_cast<void**>(&keystroke)))) {
                keystroke->UnadviseKeyEventSink(client_id_);
                keystroke->Release();
            }
            key_sink_advised_ = false;
        }
        if (thread_mgr_cookie_ != TF_INVALID_COOKIE) {
            ITfSource* source = nullptr;
            if (SUCCEEDED(thread_mgr_->QueryInterface(
                    IID_ITfSource, reinterpret_cast<void**>(&source)))) {
                source->UnadviseSink(thread_mgr_cookie_);
                source->Release();
            }
            thread_mgr_cookie_ = TF_INVALID_COOKIE;
        }
        thread_mgr_->Release();
        thread_mgr_ = nullptr;
    }
    client_id_ = TF_CLIENTID_NULL;
    return S_OK;
}

STDMETHODIMP BowGoTextService::OnSetFocus(ITfDocumentMgr* /*focus*/,
                                           ITfDocumentMgr* /*prev*/) {
    // Đổi tài liệu/ô nhập -> chốt âm tiết + nạp lại settings nếu vừa đổi.
    controller_.ResetSyllable();
    ReloadSettingsIfChanged();
    return S_OK;
}

// ── ITfKeyEventSink ──────────────────────────────────────────────────────────

STDMETHODIMP BowGoTextService::OnSetFocus(BOOL) { return S_OK; }

// ── Phím tắt bật/tắt (preserved key) + nút langbar ───────────────────────────

void BowGoTextService::ToggleEnabled() {
    controller_.ToggleEnabled();
    if (lang_bar_) lang_bar_->SetVietnamese(controller_.enabled());
}

void BowGoTextService::RegisterToggleHotkey() {
    if (!thread_mgr_ || toggle_key_preserved_) return;
    ITfKeystrokeMgr* keystroke = nullptr;
    if (FAILED(thread_mgr_->QueryInterface(IID_ITfKeystrokeMgr,
                                           reinterpret_cast<void**>(&keystroke)))) {
        return;
    }
    // Ctrl+Shift+Space. LƯU Ý: preserved key của TSF PHẢI là một phím THẬT
    // (không phải phím bổ trợ) — tổ hợp chỉ-modifier kiểu ⌃⇧ bên macOS không
    // kích hoạt được qua PreserveKey (cần raw hook, ngoài mô hình TSF). Dùng
    // Space làm phím chính; có thể mở rộng đọc từ settings sau.
    TF_PRESERVEDKEY pk;
    pk.uVKey = VK_SPACE;
    pk.uModifiers = TF_MOD_CONTROL | TF_MOD_SHIFT;
    WCHAR desc[] = L"Bow Go: bật/tắt tiếng Việt";
    if (SUCCEEDED(keystroke->PreserveKey(client_id_, kBowGoToggleKeyGuid, &pk, desc,
                                         ARRAYSIZE(desc) - 1))) {
        toggle_key_preserved_ = true;
    }
    keystroke->Release();
}

void BowGoTextService::UnregisterToggleHotkey() {
    if (!thread_mgr_ || !toggle_key_preserved_) return;
    ITfKeystrokeMgr* keystroke = nullptr;
    if (SUCCEEDED(thread_mgr_->QueryInterface(
            IID_ITfKeystrokeMgr, reinterpret_cast<void**>(&keystroke)))) {
        TF_PRESERVEDKEY pk;
        pk.uVKey = VK_SPACE;
        pk.uModifiers = TF_MOD_CONTROL | TF_MOD_SHIFT;
        keystroke->UnpreserveKey(kBowGoToggleKeyGuid, &pk);
        keystroke->Release();
    }
    toggle_key_preserved_ = false;
}

STDMETHODIMP BowGoTextService::OnPreservedKey(ITfContext* /*ctx*/, REFGUID rguid,
                                               BOOL* eaten) {
    if (IsEqualGUID(rguid, kBowGoToggleKeyGuid)) {
        ToggleEnabled();
        *eaten = TRUE;
        return S_OK;
    }
    *eaten = FALSE;
    return S_OK;
}

char32_t BowGoTextService::TranslateKey(WPARAM vk) {
    BYTE kbd[256];
    if (!GetKeyboardState(kbd)) return 0;

    // Layout của luồng đang focus (theo bàn phím thật người dùng chọn).
    HKL hkl = GetKeyboardLayout(0);
    UINT scan = MapVirtualKeyEx(static_cast<UINT>(vk), MAPVK_VK_TO_VSC, hkl);

    WCHAR buf[8] = {0};
    // Cờ 4 = không đổi trạng thái bàn phím (không nuốt dead key của hệ thống).
    int n = ToUnicodeEx(static_cast<UINT>(vk), scan, kbd, buf,
                        static_cast<int>(sizeof(buf) / sizeof(buf[0])), 4, hkl);
    if (n <= 0) return 0;  // dead key (-1) hoặc không ra ký tự -> bỏ

    // Lấy code point đầu (dựng lại từ surrogate pair nếu có).
    if (n >= 2 && buf[0] >= 0xD800 && buf[0] <= 0xDBFF && buf[1] >= 0xDC00 &&
        buf[1] <= 0xDFFF) {
        return 0x10000 + ((buf[0] - 0xD800) << 10) + (buf[1] - 0xDC00);
    }
    char32_t ch = buf[0];
    // Ký tự điều khiển (ví dụ Ctrl+ký tự) -> không phải chữ gõ.
    if (ch < 0x20) return 0;
    return ch;
}

bool BowGoTextService::WillHandle(WPARAM vk, KeyAction* action_out, bool* is_edit) {
    *is_edit = false;
    if (!controller_.enabled()) return false;

    // Backspace: ta xử lý khi đang gõ dở (cần đồng bộ màn = engine).
    if (vk == VK_BACK) {
        // "Hỏi trước" không được đổi trạng thái -> chỉ nhận nếu đang gõ dở.
        return controller_.HasPendingSyllable();
    }

    // Phím ngắt từ: nhận nếu sẽ biến đổi (macro / khôi phục / tự sửa).
    BreakKey bk;
    if (WordBreakOf(vk, &bk)) {
        return controller_.WordBreakNeedsEdit(bk);
    }

    // Con trỏ nhảy chỗ / phím điều khiển đang giữ -> KHÔNG nhận (để hệ thống xử
    // lý), chỉ báo caller reset trạng thái ở OnKeyDown.
    if (IsCaretMovementKey(vk) || CtrlOrAltDown()) return false;

    // Ký tự in được: nhận nếu dịch được ra chữ engine xử lý.
    char32_t ch = TranslateKey(vk);
    if (ch == 0) return false;
    // Đây chỉ là "hỏi trước" — engine có thể coi ch là ngắt từ, nhưng ta vẫn
    // nhận phím để tự chốt (không để lọt ký tự lạ vào giữa âm tiết đang gõ).
    (void)action_out;
    return true;
}

STDMETHODIMP BowGoTextService::OnTestKeyDown(ITfContext* /*ctx*/, WPARAM wparam,
                                              LPARAM /*lparam*/, BOOL* eaten) {
    KeyAction ignore;
    bool is_edit;
    *eaten = WillHandle(wparam, &ignore, &is_edit) ? TRUE : FALSE;
    return S_OK;
}

STDMETHODIMP BowGoTextService::OnKeyDown(ITfContext* ctx, WPARAM wparam,
                                          LPARAM /*lparam*/, BOOL* eaten) {
    *eaten = FALSE;
    if (!controller_.enabled()) return S_OK;

    // Con trỏ nhảy chỗ / phím tắt Ctrl-Alt -> chốt từ, để phím đi qua.
    if (IsCaretMovementKey(wparam) || CtrlOrAltDown()) {
        controller_.ResetSyllable();
        return S_OK;
    }

    KeyAction action;
    if (wparam == VK_BACK) {
        action = controller_.HandleBackspace();
    } else {
        BreakKey bk;
        if (WordBreakOf(wparam, &bk)) {
            action = controller_.HandleWordBreak(bk);
        } else {
            char32_t ch = TranslateKey(wparam);
            if (ch == 0) {
                controller_.ResetSyllable();
                return S_OK;
            }
            action = controller_.HandleChar(ch);
        }
    }

    if (action.kind != KeyAction::Kind::Replace) {
        // Pass-through: để phím gốc đi tới ứng dụng.
        return S_OK;
    }

    // Ghi văn bản mới. Nếu thất bại (không có context ghi được) -> để phím đi qua.
    if (FAILED(ApplyReplace(ctx, action.backspaces, action.text))) {
        controller_.ResetSyllable();
        return S_OK;
    }

    // Với Enter/Tab/Esc bung macro/sửa từ: đã ghi văn bản, giờ GỬI LẠI phím gốc
    // để ứng dụng nhận đúng hành vi (Enter gửi form, Tab nhảy ô). Nuốt phím này,
    // rồi bơm lại một sự kiện gõ thật.
    if (action.resend_original_key) {
        *eaten = TRUE;
        INPUT in[2] = {};
        in[0].type = INPUT_KEYBOARD;
        in[0].ki.wVk = static_cast<WORD>(wparam);
        in[1] = in[0];
        in[1].ki.dwFlags = KEYEVENTF_KEYUP;
        SendInput(2, in, sizeof(INPUT));
        return S_OK;
    }

    *eaten = TRUE;  // nuốt phím gốc (ta đã tự ghi văn bản)
    return S_OK;
}

HRESULT BowGoTextService::ApplyReplace(ITfContext* ctx, int backspaces,
                                        const std::u32string& text) {
    if (!ctx) return E_FAIL;
    std::u16string u16 = bowgo::U32ToUtf16(text);
    std::wstring w(u16.begin(), u16.end());  // wchar_t = UTF-16 trên Windows

    ReplaceEditSession* session =
        new (std::nothrow) ReplaceEditSession(ctx, client_id_, backspaces, std::move(w));
    if (!session) return E_OUTOFMEMORY;

    HRESULT hr_session = S_OK;
    // Đồng bộ + đọc-ghi: sửa văn bản NGAY trong nhịp xử lý phím này (không async)
    // — quan trọng để tránh gõ đôi ở ô autocomplete, tương tự lý do post đồng bộ
    // qua proxy bên macOS.
    HRESULT hr = ctx->RequestEditSession(client_id_, session,
                                         TF_ES_READWRITE | TF_ES_SYNC, &hr_session);
    session->Release();
    if (FAILED(hr)) {
        // Vài ứng dụng từ chối SYNC -> thử lại ASYNC (đành chịu, hiếm).
        session = new (std::nothrow)
            ReplaceEditSession(ctx, client_id_, backspaces,
                               std::wstring(w.begin(), w.end()));
        if (!session) return E_OUTOFMEMORY;
        hr = ctx->RequestEditSession(client_id_, session,
                                     TF_ES_READWRITE | TF_ES_ASYNCDONTCARE,
                                     &hr_session);
        session->Release();
    }
    return FAILED(hr) ? hr : hr_session;
}

// ── Settings ─────────────────────────────────────────────────────────────────

void BowGoTextService::LoadSettings() {
    if (settings_path_.empty()) {
        WCHAR* appdata = nullptr;
        size_t len = 0;
        if (_wdupenv_s(&appdata, &len, L"APPDATA") == 0 && appdata) {
            settings_path_ = std::wstring(appdata) + L"\\BowGo\\settings.json";
            free(appdata);
        }
    }
    if (settings_path_.empty()) return;

    HANDLE h = CreateFileW(settings_path_.c_str(), GENERIC_READ,
                           FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr,
                           OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (h == INVALID_HANDLE_VALUE) return;

    // Nhớ mtime để phát hiện thay đổi.
    GetFileTime(h, nullptr, nullptr, &settings_mtime_);

    std::string data;
    char buf[4096];
    DWORD read = 0;
    while (ReadFile(h, buf, sizeof(buf), &read, nullptr) && read > 0) {
        data.append(buf, read);
    }
    CloseHandle(h);

    // Bỏ BOM UTF-8 nếu có.
    if (data.size() >= 3 && static_cast<unsigned char>(data[0]) == 0xEF &&
        static_cast<unsigned char>(data[1]) == 0xBB &&
        static_cast<unsigned char>(data[2]) == 0xBF) {
        data.erase(0, 3);
    }

    if (auto cfg = bowgo::ParseBowConfig(data)) {
        controller_.Apply(*cfg);
    }
}

void BowGoTextService::ReloadSettingsIfChanged() {
    if (settings_path_.empty()) return;
    WIN32_FILE_ATTRIBUTE_DATA info;
    if (!GetFileAttributesExW(settings_path_.c_str(), GetFileExInfoStandard, &info)) {
        return;
    }
    if (CompareFileTime(&info.ftLastWriteTime, &settings_mtime_) != 0) {
        LoadSettings();  // LoadSettings cập nhật lại settings_mtime_
    }
}

#endif  // _WIN32
