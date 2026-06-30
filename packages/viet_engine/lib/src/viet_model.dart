// viet_model.dart
// ----------------
// Mô hình hoá tiếng Việt cho bộ gõ. Đây là "ngôn ngữ" mà engine dùng để suy nghĩ.
//
// Ý tưởng cốt lõi: một nguyên âm tiếng Việt = (chữ cái gốc) + (dấu biến âm) + (dấu thanh).
//   Ví dụ "ế" = e (gốc) + mũ (biến âm) + sắc (thanh).
// Engine làm việc trên 3 trục này thay vì nhớ cứng từng ký tự Unicode.

/// Dấu thanh (5 dấu + thanh ngang/không dấu).
enum Tone {
  none, // ngang  (a)
  acute, // sắc    (á)
  grave, // huyền  (à)
  hook, // hỏi    (ả)
  tilde, // ngã    (ã)
  dot, // nặng   (ạ)
}

/// Dấu biến âm gắn vào chữ cái (mũ, móc, trăng...).
enum Mark {
  none,
  circumflex, // dấu mũ:    a->â, e->ê, o->ô
  breve, // dấu trăng:  a->ă
  horn, // dấu móc:    o->ơ, u->ư
  dyet, // gạch ngang  d->đ (chỉ áp dụng cho 'd')
}

/// Phương thức gõ.
enum InputMethod { telex, vni }

/// Kiểu đặt dấu thanh:
/// - [modern]: hoà, quý, khoẻ (đuôi mở oa/oe/uy đặt dấu lên nguyên âm sau).
/// - [old]:    hòa, qúy, khỏe (đặt dấu lên nguyên âm trước).
enum ToneStyle { modern, old }

extension ToneIndex on Tone {
  /// Vị trí của thanh trong mảng 6 biến thể [ngang, sắc, huyền, hỏi, ngã, nặng].
  int get index {
    switch (this) {
      case Tone.none:
        return 0;
      case Tone.acute:
        return 1;
      case Tone.grave:
        return 2;
      case Tone.hook:
        return 3;
      case Tone.tilde:
        return 4;
      case Tone.dot:
        return 5;
    }
  }
}
