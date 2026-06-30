// TextConverterTests.swift
import Testing
import Foundation
@testable import VietEngine

@Suite("Bỏ dấu tiếng Việt")
struct RemoveDiacritics {

    @Test("Bỏ dấu cơ bản")
    func basic() {
        #expect(TextConverter.removeDiacritics("Tiếng Việt") == "Tieng Viet")
        #expect(TextConverter.removeDiacritics("Phở bò Hà Nội") == "Pho bo Ha Noi")
        #expect(TextConverter.removeDiacritics("đường") == "duong")
        #expect(TextConverter.removeDiacritics("Đặng") == "Dang")
    }

    @Test("Đủ mọi nguyên âm có dấu")
    func allVowels() {
        #expect(TextConverter.removeDiacritics("ăâêôơưđ") == "aaeooud")
        #expect(TextConverter.removeDiacritics("ằẳẵặ") == "aaaa")
        #expect(TextConverter.removeDiacritics("ưởng") == "uong")
        #expect(TextConverter.removeDiacritics("nghiêng") == "nghieng")
    }

    @Test("Giữ nguyên ký tự không phải tiếng Việt")
    func keepsOthers() {
        #expect(TextConverter.removeDiacritics("a1b2 café") == "a1b2 cafe")
        #expect(TextConverter.removeDiacritics("100% ổn!") == "100% on!")
    }

    @Test("Hoạt động với cả Unicode tổ hợp (NFD)")
    func worksOnDecomposed() {
        let nfd = "Việt".decomposedStringWithCanonicalMapping
        #expect(TextConverter.removeDiacritics(nfd) == "Viet")
    }
}

@Suite("Hoa / thường")
struct ChangeCase {

    @Test("ALL CAPS / all lower giữ dấu")
    func upperLower() {
        #expect(TextConverter.changeCase("Tiếng Việt", to: .allUpper) == "TIẾNG VIỆT")
        #expect(TextConverter.changeCase("Tiếng Việt", to: .allLower) == "tiếng việt")
        #expect(TextConverter.changeCase("đẹp", to: .allUpper) == "ĐẸP")
    }

    @Test("Hoa đầu câu")
    func capFirst() {
        #expect(TextConverter.changeCase("xin chào. tôi tên là an", to: .capitalizeFirst)
                == "Xin chào. Tôi tên là an")
        #expect(TextConverter.changeCase("a? b! c", to: .capitalizeFirst) == "A? B! C")
        #expect(TextConverter.changeCase("dòng một\ndòng hai", to: .capitalizeFirst)
                == "Dòng một\nDòng hai")
    }

    @Test("Hoa mỗi từ")
    func capWords() {
        #expect(TextConverter.changeCase("nguyễn văn an", to: .capitalizeWords)
                == "Nguyễn Văn An")
        #expect(TextConverter.changeCase("hà nội việt nam", to: .capitalizeWords)
                == "Hà Nội Việt Nam")
    }
}

@Suite("Unicode NFC / NFD")
struct UnicodeForm {

    @Test("Dựng sẵn <-> tổ hợp đảo được nhau")
    func roundTrip() {
        let s = "Tiếng Việt ếẫợ"
        let nfd = TextConverter.toDecomposed(s)
        let nfc = TextConverter.toPrecomposed(nfd)
        #expect(nfc == s.precomposedStringWithCanonicalMapping)
        // NFD có nhiều code point hơn NFC cho cùng nội dung hiển thị.
        #expect(nfd.unicodeScalars.count > nfc.unicodeScalars.count)
    }

    @Test("NFC gộp ký tự dấu rời thành dựng sẵn")
    func composes() {
        // "e" + combining circumflex (U+0302) + combining acute (U+0301) -> "ế"
        let composed = TextConverter.toPrecomposed("e\u{0302}\u{0301}")
        #expect(composed == "ế")
    }
}

@Suite("Bảng mã cũ TCVN3 / VNI-Windows")
struct LegacyCodeTables {

    @Test("Unicode -> TCVN3 -> Unicode khứ hồi (lowercase exact)")
    func tcvnRoundTrip() {
        // TCVN3 không phân biệt hoa/thường ở nguyên âm có dấu nên ta test với
        // chuỗi THƯỜNG để khứ hồi chính xác. (Hoa sẽ mất khi quay lại — đúng bản chất.)
        let samples = ["tiếng việt", "đường phố", "phở bò", "nghiêng ngả",
                       "ước mơ", "đặng thị huệ", "quyển sách"]
        for s in samples {
            let tcvn = TextConverter.convert(s, from: .unicode, to: .tcvn3)
            let back = TextConverter.convert(tcvn, from: .tcvn3, to: .unicode)
            #expect(back == s.precomposedStringWithCanonicalMapping, "TCVN round-trip: \(s)")
        }
    }

    @Test("TCVN3 mất hoa/thường ở nguyên âm có dấu (tính chất bảng mã)")
    func tcvnCaseLossy() {
        // "Ế" và "ế" chung byte -> giải mã trả thường. Đây là HÀNH VI MONG ĐỢI.
        let tcvn = TextConverter.convert("Ế", from: .unicode, to: .tcvn3)
        #expect(TextConverter.convert(tcvn, from: .tcvn3, to: .unicode) == "ế")
    }

    @Test("Unicode -> VNI-Windows -> Unicode khứ hồi")
    func vniRoundTrip() {
        let samples = ["Tiếng Việt", "đường phố", "Phở bò", "nghiêng ngả",
                       "ƯỚC MƠ", "Đặng Thị Huệ", "quyển sách"]
        for s in samples {
            let vni = TextConverter.convert(s, from: .unicode, to: .vniWindows)
            let back = TextConverter.convert(vni, from: .vniWindows, to: .unicode)
            #expect(back == s.precomposedStringWithCanonicalMapping, "VNI round-trip: \(s)")
        }
    }

    @Test("Giá trị TCVN3 / VNI cụ thể đúng chuẩn")
    func knownValues() {
        // đ -> TCVN3 'đ' (0x00B5? thực ra 0xAE 'đ' thường) ; đ VNI -> 'ñ'
        #expect(TextConverter.convert("đ", from: .unicode, to: .vniWindows) == "ñ")
        #expect(TextConverter.convert("ñ", from: .vniWindows, to: .unicode) == "đ")
        // á VNI = "aù"
        #expect(TextConverter.convert("á", from: .unicode, to: .vniWindows) == "aù")
        #expect(TextConverter.convert("aù", from: .vniWindows, to: .unicode) == "á")
    }

    @Test("Ký tự ASCII và khoảng trắng giữ nguyên")
    func keepsAscii() {
        #expect(TextConverter.convert("abc 123 .", from: .unicode, to: .tcvn3) == "abc 123 .")
        #expect(TextConverter.convert("Ha Noi", from: .unicode, to: .vniWindows) == "Ha Noi")
    }

    @Test("Chuyển chéo TCVN3 <-> VNI qua trung gian Unicode")
    func crossConvert() {
        // Đi qua TCVN3 nên dùng chuỗi thường (TCVN3 không giữ hoa nguyên âm có dấu).
        let s = "tiếng việt"
        let tcvn = TextConverter.convert(s, from: .unicode, to: .tcvn3)
        let vni = TextConverter.convert(tcvn, from: .tcvn3, to: .vniWindows)
        let back = TextConverter.convert(vni, from: .vniWindows, to: .unicode)
        #expect(back == s.precomposedStringWithCanonicalMapping)
    }
}
