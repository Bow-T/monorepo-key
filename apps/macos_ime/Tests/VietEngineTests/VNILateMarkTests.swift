// VNILateMarkTests.swift
// ----------------------
// Regression: VNI gõ số MŨ/TRĂNG (6/8) khi nguyên âm đích KHÔNG phải chữ cuối.
//
// BUG (đã sửa): `setMarkOrToggle` chỉ áp mũ/trăng lên chữ CUỐI của âm tiết. Khi gõ
// VNI "muoi6" (mũ phải lên 'o' ở giữa, sau nó còn 'i'), 'i' không nhận được mũ ->
// số '6' lọt thành ký tự thô -> "muoi6" thay vì "muôi". Ảnh hưởng loạt từ rất phổ
// biến: muỗi, tuổi, buổi, cuội, chuối, đuôi, xuôi, nhuộm...
//
// SỬA: `setMarkOnNucleus` tìm nguyên âm nhận được mark trong CỤM NGUYÊN ÂM (qua
// `vowelNucleusRange`), giống cách `applyHornVNI` (số 7) đã làm cho móc.

import Testing
import Foundation
@testable import VietEngine

@Suite("VNI: mũ/trăng (6/8) gõ SAU nguyên âm/phụ âm khác")
struct VNILateMark {
    private func type(_ keys: String) -> String {
        let e = VietEngine(method: .vni)
        var out = ""
        for ch in keys {
            if let r = e.process(ch) { out = r }
            else { out += String(ch); e.clear() }
        }
        return out
    }

    @Test("Mũ (6) lên nguyên âm giữa cụm — muỗi/tuổi/buổi/chuối...")
    func circumflexMidCluster() {
        #expect(type("muoi64") == "muỗi")
        #expect(type("tuoi63") == "tuổi")
        #expect(type("buoi63") == "buổi")
        #expect(type("chuoi61") == "chuối")
        #expect(type("xuoi61") == "xuối")
        #expect(type("muon61") == "muốn")
        #expect(type("con6") == "côn")
    }

    @Test("Trăng (8) gõ sau phụ âm cuối — tăng/măn...")
    func breveAfterFinal() {
        #expect(type("tang8") == "tăng")
        #expect(type("man8") == "măn")
        #expect(type("nang8") == "năng")
    }

    @Test("Toggle: gõ lại số-biến-âm trùng -> gỡ + số thô")
    func toggle() {
        #expect(type("a6") == "â")
        #expect(type("a66") == "a6")   // gõ 6 lần 2 -> gỡ mũ + '6' thô
        #expect(type("tang8") == "tăng")
        #expect(type("tang88") == "tang8")
    }

    @Test("Không phá các ca VNI đã đúng (regression)")
    func noRegression() {
        #expect(type("tie61ng") == "tiếng")
        #expect(type("vie65t") == "việt")
        #expect(type("nuoc71") == "nước")   // móc (7) vẫn đúng
        #expect(type("thuong72") == "thường")
        #expect(type("quy1") == "quý")
        #expect(type("d9") == "đ")           // đ (9) áp lên phụ âm đầu
    }
}
