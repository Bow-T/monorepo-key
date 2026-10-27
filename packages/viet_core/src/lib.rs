//! viet_core — engine gõ tiếng Việt dùng chung, gọi từ Swift (macOS/iOS) và C++
//! (Windows/Android) qua C ABI khai báo ở include/viet_core.h.

mod engine;
mod table;

pub use engine::{Engine, InputMethod, ToneStyle};

/// Đối tượng engine phía C: engine + bộ đệm UTF-8 của chuỗi hiển thị hiện tại.
pub struct BowEngine {
    engine: Engine,
    text: String,
}

/// Tạo engine. `method`: 0 = Telex, 1 = VNI. `tone_style`: 0 = modern, 1 = old.
#[no_mangle]
pub extern "C" fn bow_engine_new(method: u32, tone_style: u32) -> *mut BowEngine {
    let method = if method == 1 { InputMethod::Vni } else { InputMethod::Telex };
    let style = if tone_style == 1 { ToneStyle::Old } else { ToneStyle::Modern };
    Box::into_raw(Box::new(BowEngine { engine: Engine::new(method, style), text: String::new() }))
}

/// # Safety
/// `engine` là con trỏ do `bow_engine_new` trả về (hoặc NULL), chưa được giải phóng.
#[no_mangle]
pub unsafe extern "C" fn bow_engine_free(engine: *mut BowEngine) {
    if !engine.is_null() {
        drop(Box::from_raw(engine));
    }
}

/// Phím `ch` (Unicode scalar) có thuộc âm tiết không. Sai -> `bow_engine_process` sẽ chốt từ.
///
/// # Safety
/// `engine` hợp lệ, không NULL.
#[no_mangle]
pub unsafe extern "C" fn bow_engine_is_word_char(engine: *const BowEngine, ch: u32) -> bool {
    (*engine).engine.is_word_char(to_char(ch))
}

/// Nhận một phím. true: phím thuộc âm tiết (chuỗi mới ở `bow_engine_text`); false: phím
/// ngắt từ, âm tiết đã chốt — caller xuất phím nguyên bản.
///
/// # Safety
/// `engine` hợp lệ, không NULL.
#[no_mangle]
pub unsafe extern "C" fn bow_engine_process(engine: *mut BowEngine, ch: u32) -> bool {
    (*engine).engine.process(to_char(ch)).is_some()
}

/// Backspace: true nếu đã lùi một phím thô (chuỗi mới ở `bow_engine_text`); false nếu
/// buffer rỗng — caller để Backspace đi qua.
///
/// # Safety
/// `engine` hợp lệ, không NULL.
#[no_mangle]
pub unsafe extern "C" fn bow_engine_backspace(engine: *mut BowEngine) -> bool {
    (*engine).engine.backspace().is_some()
}

/// Reset âm tiết (con trỏ nhảy chỗ, click chuột...).
///
/// # Safety
/// `engine` hợp lệ, không NULL.
#[no_mangle]
pub unsafe extern "C" fn bow_engine_clear(engine: *mut BowEngine) {
    (*engine).engine.clear();
}

/// Chuỗi hiển thị (UTF-8, không kết thúc bằng NUL) của âm tiết hiện tại; độ dài byte
/// ghi vào `*len`. Con trỏ hợp lệ tới lần gọi kế tiếp vào engine này.
///
/// # Safety
/// `engine` hợp lệ, không NULL; `len` trỏ tới vùng ghi được.
#[no_mangle]
pub unsafe extern "C" fn bow_engine_text(engine: *mut BowEngine, len: *mut usize) -> *const u8 {
    let e = &mut *engine;
    e.text = e.engine.render();
    *len = e.text.len();
    e.text.as_ptr()
}

/// Scalar không hợp lệ (surrogate, > U+10FFFF) coi như U+FFFD — một phím ngắt từ.
fn to_char(ch: u32) -> char {
    char::from_u32(ch).unwrap_or(char::REPLACEMENT_CHARACTER)
}
