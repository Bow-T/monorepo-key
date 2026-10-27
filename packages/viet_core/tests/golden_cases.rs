//! Chạy BỘ CA GÕ CHUẨN DÙNG CHUNG (packages/viet_engine/spec/typing_cases.tsv) qua core
//! Rust — cùng file với runner Dart; Swift/C++ chạy nó qua lớp bọc FFI.

use std::path::Path;

use viet_core::{Engine, InputMethod, ToneStyle};

/// Gõ `keys` vào một engine mới ('<' = Backspace), trả chuỗi âm tiết sau phím cuối.
fn type_keys(keys: &str, method: InputMethod, style: ToneStyle) -> String {
    let mut engine = Engine::new(method, style);
    let mut current = String::new();
    for ch in keys.chars() {
        current = if ch == '<' { engine.backspace() } else { engine.process(ch) }.unwrap_or_default();
    }
    current
}

#[test]
fn shared_spec() {
    let path = Path::new(env!("CARGO_MANIFEST_DIR")).join("../viet_engine/spec/typing_cases.tsv");
    let text = std::fs::read_to_string(&path).expect("đọc typing_cases.tsv");
    let text = text.strip_prefix('\u{FEFF}').unwrap_or(&text);

    let mut count = 0;
    let mut failures = Vec::new();
    for (i, line) in text.lines().enumerate() {
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let cols: Vec<&str> = line.split('\t').collect();
        let parsed = match cols.as_slice() {
            [m, s, keys, expected] if !keys.is_empty() && !expected.is_empty() => {
                let method = match *m {
                    "telex" => Some(InputMethod::Telex),
                    "vni" => Some(InputMethod::Vni),
                    _ => None,
                };
                let style = match *s {
                    "modern" => Some(ToneStyle::Modern),
                    "old" => Some(ToneStyle::Old),
                    _ => None,
                };
                method.zip(style).map(|(m, s)| (m, s, *keys, *expected))
            }
            _ => None,
        };
        let Some((method, style, keys, expected)) = parsed else {
            panic!("typing_cases.tsv dòng {}: sai định dạng: {line}", i + 1);
        };
        let expected = if expected == "∅" { "" } else { expected };
        let got = type_keys(keys, method, style);
        if got != expected {
            failures.push(format!("{line} -> {got}"));
        }
        count += 1;
    }
    assert!(count > 0, "không nạp được ca nào từ {}", path.display());
    assert!(failures.is_empty(), "{} ca lệch:\n{}", failures.len(), failures.join("\n"));
}
