//! Gọi C ABI như Swift/C++ gọi: vòng đời engine, chuỗi hiển thị UTF-8, phím không hợp lệ.

use viet_core::*;

fn text(e: *mut BowEngine) -> String {
    let mut len = 0;
    unsafe {
        let p = bow_engine_text(e, &mut len);
        String::from_utf8(std::slice::from_raw_parts(p, len).to_vec()).unwrap()
    }
}

fn type_keys(e: *mut BowEngine, keys: &str) {
    for ch in keys.chars() {
        assert!(unsafe { bow_engine_process(e, ch as u32) }, "phím {ch:?} phải thuộc âm tiết");
    }
}

#[test]
fn telex_roundtrip_and_word_break() {
    let e = bow_engine_new(0, 0);
    type_keys(e, "tieengs");
    assert_eq!(text(e), "tiếng");
    unsafe {
        assert!(bow_engine_backspace(e));
        assert_eq!(text(e), "tiêng");
        assert!(!bow_engine_process(e, ' ' as u32));
        assert_eq!(text(e), "");
        assert!(!bow_engine_backspace(e));
        bow_engine_free(e);
        bow_engine_free(std::ptr::null_mut());
    }
}

#[test]
fn vni_digit_is_word_char_only_inside_syllable() {
    let e = bow_engine_new(1, 0);
    unsafe {
        assert!(!bow_engine_is_word_char(e, '1' as u32));
        type_keys(e, "a");
        assert!(bow_engine_is_word_char(e, '1' as u32));
        assert!(bow_engine_process(e, '1' as u32));
        assert_eq!(text(e), "á");
        bow_engine_free(e);
    }
}

#[test]
fn old_tone_style() {
    let e = bow_engine_new(0, 1);
    type_keys(e, "hoaf");
    assert_eq!(text(e), "hòa");
    unsafe { bow_engine_free(e) };
}

#[test]
fn invalid_scalars_break_word_and_astral_letters_roundtrip() {
    let e = bow_engine_new(0, 0);
    unsafe {
        assert!(!bow_engine_process(e, 0xD800));
        assert!(!bow_engine_process(e, 0x11_0000));
        assert!(bow_engine_process(e, 0x1D400)); // 𝐀: UTF-8 4 byte
        assert_eq!(text(e), "\u{1D400}");
        bow_engine_free(e);
    }
}
