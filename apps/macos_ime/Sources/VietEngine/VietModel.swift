// VietModel.swift
// ----------------
// Mô hình hoá tiếng Việt cho bộ gõ. Đây là "ngôn ngữ" mà engine dùng để suy nghĩ.
//
// Ý tưởng cốt lõi: một nguyên âm tiếng Việt = (chữ cái gốc) + (dấu biến âm) + (dấu thanh).
//   Ví dụ "ế" = e (gốc) + mũ (biến âm) + sắc (thanh).
// Engine làm việc trên 3 trục này thay vì nhớ cứng từng ký tự Unicode.

/// Dấu thanh (5 dấu + thanh ngang/không dấu).
public enum Tone: Equatable, Sendable {
    case none      // ngang  (a)
    case acute     // sắc    (á)
    case grave     // huyền  (à)
    case hook      // hỏi    (ả)
    case tilde     // ngã    (ã)
    case dot       // nặng   (ạ)
}

/// Dấu biến âm gắn vào chữ cái (mũ, móc, trăng...).
public enum Mark: Equatable, Sendable {
    case none
    case circumflex   // dấu mũ:   a->â, e->ê, o->ô
    case breve        // dấu trăng: a->ă
    case horn         // dấu móc:  o->ơ, u->ư
    case dyet         // gạch ngang d->đ (chỉ áp dụng cho 'd')
}

/// Phương thức gõ.
public enum InputMethod {
    case telex
    case vni
}
