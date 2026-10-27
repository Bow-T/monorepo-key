//! Bảng tra (chữ gốc, dấu biến âm, dấu thanh) -> ký tự tiếng Việt dựng sẵn.
//! Port từ apps/macos_ime/Sources/VietEngine/VietTable.swift.

/// Dấu thanh, theo thứ tự cột của bảng biến thể.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Tone {
    None,
    Acute,
    Grave,
    Hook,
    Tilde,
    Dot,
}

/// Dấu biến âm gắn vào chữ cái.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Mark {
    None,
    Circumflex,
    Breve,
    Horn,
    Dyet,
}

/// Chữ thường của `c` khi nó chỉ có MỘT ký tự chữ thường, ngược lại giữ nguyên `c`
/// (giống so sánh `Character(c.lowercased())` của bản Swift với chữ ASCII).
pub fn low(c: char) -> char {
    let mut it = c.to_lowercase();
    match (it.next(), it.next()) {
        (Some(l), None) => l,
        _ => c,
    }
}

fn up(c: char) -> char {
    let mut it = c.to_uppercase();
    match (it.next(), it.next()) {
        (Some(u), None) => u,
        _ => c,
    }
}

/// Ký tự tiếng Việt dựng sẵn cho (base + mark + tone), hoặc None nếu tổ hợp không
/// hợp lệ (engine giữ nguyên chữ gốc).
pub fn compose(base: char, mark: Mark, tone: Tone) -> Option<char> {
    let mut lower = base.to_lowercase();
    let lower = match (lower.next(), lower.next()) {
        (Some(l), None) => l,
        _ => return None,
    };
    let variants = match (lower, mark) {
        ('a', Mark::None) => "aáàảãạ",
        ('a', Mark::Circumflex) => "âấầẩẫậ",
        ('a', Mark::Breve) => "ăắằẳẵặ",
        ('e', Mark::None) => "eéèẻẽẹ",
        ('e', Mark::Circumflex) => "êếềểễệ",
        ('i', Mark::None) => "iíìỉĩị",
        ('o', Mark::None) => "oóòỏõọ",
        ('o', Mark::Circumflex) => "ôốồổỗộ",
        ('o', Mark::Horn) => "ơớờởỡợ",
        ('u', Mark::None) => "uúùủũụ",
        ('u', Mark::Horn) => "ưứừửữự",
        ('y', Mark::None) => "yýỳỷỹỵ",
        ('d', Mark::Dyet) => "đđđđđđ",
        _ => return None,
    };
    let c = variants.chars().nth(tone as usize)?;
    Some(if base.is_uppercase() { up(c) } else { c })
}
