// CorpusRegressionTests.swift
// ---------------------------
// "Oracle" đối chiếu từ điển: lấy ~250 âm tiết tiếng Việt THẬT (phủ các cụm vần khó:
// ươ, uô, iê/yê, oa/oe/uy, oai, uyê, ngh/gi/qu...), sinh phím Telex & VNI ở 2 thứ tự
// (gõ dấu sớm và gõ dấu muộn — sau phụ âm cuối), rồi kiểm tra engine dựng lại ĐÚNG từ.
//
// Đây là bản GỌN của bộ quét 26K case (7.837 âm tiết × Telex/VNI × 2 thứ tự). Bộ đầy đủ
// xác nhận engine không còn bug đặt-dấu/biến-âm; phần "lệch" còn lại đều là từ điển
// ghi kiểu cũ (hòa/thúy) hoặc tượng thanh "oo" cần từ điển runtime (xem ghi chú dưới).
//
// Cách gõ "dấu muộn" chính là class bug "đuocự" đã sửa (xem ToneMarkAfterFinalConsonantTests).

import Testing
@testable import VietEngine

private func typeWord(_ keys: String, _ method: InputMethod) -> String {
    let engine = VietEngine(method: method)
    var current = ""
    for ch in keys {
        if let r = engine.process(ch) { current = r } else { current = "" }
    }
    return current
}

// AUTO: (word, telexCanon, telexLate, vniCanon, vniLate)
let corpusCases: [(String,String,String,String,String)] = [
    ("bươi", "buwowi", "buwowi", "bu7o7i", "bu7o7i"),
    ("bươm", "buwowm", "buwowm", "bu7o7m", "bu7o7m"),
    ("bươn", "buwown", "buwown", "bu7o7n", "bu7o7n"),
    ("bương", "buwowng", "buwowng", "bu7o7ng", "bu7o7ng"),
    ("chương", "chuwowng", "chuwowng", "chu7o7ng", "chu7o7ng"),
    ("cương", "cuwowng", "cuwowng", "cu7o7ng", "cu7o7ng"),
    ("dương", "duwowng", "duwowng", "du7o7ng", "du7o7ng"),
    ("giương", "giuwowng", "giuwowng", "giu7o7ng", "giu7o7ng"),
    ("gươm", "guwowm", "guwowm", "gu7o7m", "gu7o7m"),
    ("gương", "guwowng", "guwowng", "gu7o7ng", "gu7o7ng"),
    ("hươm", "huwowm", "huwowm", "hu7o7m", "hu7o7m"),
    ("hươn", "huwown", "huwown", "hu7o7n", "hu7o7n"),
    ("buôi", "buooi", "buooi", "buo6i", "buo6i"),
    ("buôn", "buoon", "buoon", "buo6n", "buo6n"),
    ("buông", "buoong", "buoong", "buo6ng", "buo6ng"),
    ("chuôi", "chuooi", "chuooi", "chuo6i", "chuo6i"),
    ("chuôm", "chuoom", "chuoom", "chuo6m", "chuo6m"),
    ("chuông", "chuoong", "chuoong", "chuo6ng", "chuo6ng"),
    ("cuông", "cuoong", "cuoong", "cuo6ng", "cuo6ng"),
    ("duôi", "duooi", "duooi", "duo6i", "duo6i"),
    ("khuôn", "khuoon", "khuoon", "khuo6n", "khuo6n"),
    ("khuông", "khuoong", "khuoong", "khuo6ng", "khuo6ng"),
    ("luôm", "luoom", "luoom", "luo6m", "luo6m"),
    ("luôn", "luoon", "luoon", "luo6n", "luo6n"),
    ("biên", "bieen", "bieen", "bie6n", "bie6n"),
    ("biêng", "bieeng", "bieeng", "bie6ng", "bie6ng"),
    ("biêt", "bieet", "bieet", "bie6t", "bie6t"),
    ("biêu", "bieeu", "bieeu", "bie6u", "bie6u"),
    ("chiêm", "chieem", "chieem", "chie6m", "chie6m"),
    ("chiên", "chieen", "chieen", "chie6n", "chie6n"),
    ("chiêng", "chieeng", "chieeng", "chie6ng", "chie6ng"),
    ("chiêu", "chieeu", "chieeu", "chie6u", "chie6u"),
    ("diêm", "dieem", "dieem", "die6m", "die6m"),
    ("diên", "dieen", "dieen", "die6n", "die6n"),
    ("diêu", "dieeu", "dieeu", "die6u", "die6u"),
    ("giê", "giee", "giee", "gie6", "gie6"),
    ("chuyên", "chuyeen", "chuyeen", "chuye6n", "chuye6n"),
    ("duyên", "duyeen", "duyeen", "duye6n", "duye6n"),
    ("huyên", "huyeen", "huyeen", "huye6n", "huye6n"),
    ("khuyên", "khuyeen", "khuyeen", "khuye6n", "khuye6n"),
    ("luyên", "luyeen", "luyeen", "luye6n", "luye6n"),
    ("nguyên", "nguyeen", "nguyeen", "nguye6n", "nguye6n"),
    ("quyên", "quyeen", "quyeen", "quye6n", "quye6n"),
    ("thuyên", "thuyeen", "thuyeen", "thuye6n", "thuye6n"),
    ("tuyên", "tuyeen", "tuyeen", "tuye6n", "tuye6n"),
    ("uyên", "uyeen", "uyeen", "uye6n", "uye6n"),
    ("xuyên", "xuyeen", "xuyeen", "xuye6n", "xuye6n"),
    ("yêm", "yeem", "yeem", "ye6m", "ye6m"),
    ("boa", "boa", "boa", "boa", "boa"),
    ("boạt", "boajt", "boatj", "boa5t", "boat5"),
    ("choa", "choa", "choa", "choa", "choa"),
    ("choai", "choai", "choai", "choai", "choai"),
    ("choang", "choang", "choang", "choang", "choang"),
    ("choài", "choafi", "choaif", "choa2i", "choai2"),
    ("choàm", "choafm", "choamf", "choa2m", "choam2"),
    ("choàng", "choafng", "choangf", "choa2ng", "choang2"),
    ("choá", "choas", "choas", "choa1", "choa1"),
    ("choác", "choasc", "choacs", "choa1c", "choac1"),
    ("choái", "choasi", "choais", "choa1i", "choai1"),
    ("choán", "choasn", "choans", "choa1n", "choan1"),
    ("choe", "choe", "choe", "choe", "choe"),
    ("choen", "choen", "choen", "choen", "choen"),
    ("choè", "choef", "choef", "choe2", "choe2"),
    ("choèn", "choefn", "choenf", "choe2n", "choen2"),
    ("choé", "choes", "choes", "choe1", "choe1"),
    ("choét", "choest", "choets", "choe1t", "choet1"),
    ("choẹ", "choej", "choej", "choe5", "choe5"),
    ("choẹt", "choejt", "choetj", "choe5t", "choet5"),
    ("hoe", "hoe", "hoe", "hoe", "hoe"),
    ("hoen", "hoen", "hoen", "hoen", "hoen"),
    ("hoè", "hoef", "hoef", "hoe2", "hoe2"),
    ("hoét", "hoest", "hoets", "hoe1t", "hoet1"),
    ("buy", "buy", "buy", "buy", "buy"),
    ("buýp", "buysp", "buyps", "buy1p", "buyp1"),
    ("buýt", "buyst", "buyts", "buy1t", "buyt1"),
    ("chuyến", "chuyeesn", "chuyeens", "chuye61n", "chuye6n1"),
    ("chuyết", "chuyeest", "chuyeets", "chuye61t", "chuye6t1"),
    ("chuyền", "chuyeefn", "chuyeenf", "chuye62n", "chuye6n2"),
    ("chuyển", "chuyeern", "chuyeenr", "chuye63n", "chuye6n3"),
    ("chuyện", "chuyeejn", "chuyeenj", "chuye65n", "chuye6n5"),
    ("chuỳ", "chuyf", "chuyf", "chuy2", "chuy2"),
    ("duy", "duy", "duy", "duy", "duy"),
    ("duyện", "duyeejn", "duyeenj", "duye65n", "duye6n5"),
    ("duyệt", "duyeejt", "duyeetj", "duye65t", "duye6t5"),
    ("bua", "bua", "bua", "bua", "bua"),
    ("chua", "chua", "chua", "chua", "chua"),
    ("chuẩn", "chuaarn", "chuaanr", "chua63n", "chua6n3"),
    ("cua", "cua", "cua", "cua", "cua"),
    ("dua", "dua", "dua", "dua", "dua"),
    ("duật", "duaajt", "duaatj", "dua65t", "dua6t5"),
    ("giua", "giua", "giua", "giua", "giua"),
    ("hua", "hua", "hua", "hua", "hua"),
    ("huân", "huaan", "huaan", "hua6n", "hua6n"),
    ("huấn", "huaasn", "huaans", "hua61n", "hua6n1"),
    ("huầy", "huaafy", "huaayf", "hua62y", "hua6y2"),
    ("khua", "khua", "khua", "khua", "khua"),
    ("bưa", "buwa", "buwa", "bu7a", "bu7a"),
    ("chưa", "chuwa", "chuwa", "chu7a", "chu7a"),
    ("cưa", "cuwa", "cuwa", "cu7a", "cu7a"),
    ("dưa", "duwa", "duwa", "du7a", "du7a"),
    ("lưa", "luwa", "luwa", "lu7a", "lu7a"),
    ("mưa", "muwa", "muwa", "mu7a", "mu7a"),
    ("ngưa", "nguwa", "nguwa", "ngu7a", "ngu7a"),
    ("nưa", "nuwa", "nuwa", "nu7a", "nu7a"),
    ("rưa", "ruwa", "ruwa", "ru7a", "ru7a"),
    ("sưa", "suwa", "suwa", "su7a", "su7a"),
    ("thưa", "thuwa", "thuwa", "thu7a", "thu7a"),
    ("trưa", "truwa", "truwa", "tru7a", "tru7a"),
    ("hoai", "hoai", "hoai", "hoai", "hoai"),
    ("khoai", "khoai", "khoai", "khoai", "khoai"),
    ("loai", "loai", "loai", "loai", "loai"),
    ("ngoai", "ngoai", "ngoai", "ngoai", "ngoai"),
    ("nhoai", "nhoai", "nhoai", "nhoai", "nhoai"),
    ("oai", "oai", "oai", "oai", "oai"),
    ("thoai", "thoai", "thoai", "thoai", "thoai"),
    ("xoai", "xoai", "xoai", "xoai", "xoai"),
    ("khuya", "khuya", "khuya", "khuya", "khuya"),
    ("luya", "luya", "luya", "luya", "luya"),
    ("muya", "muya", "muya", "muya", "muya"),
    ("tuya", "tuya", "tuya", "tuya", "tuya"),
    ("xuya", "xuya", "xuya", "xuya", "xuya"),
    ("đuya", "dduya", "dduya", "d9uya", "d9uya"),
    ("nghe", "nghe", "nghe", "nghe", "nghe"),
    ("nghen", "nghen", "nghen", "nghen", "nghen"),
    ("ngheo", "ngheo", "ngheo", "ngheo", "ngheo"),
    ("nghi", "nghi", "nghi", "nghi", "nghi"),
    ("nghim", "nghim", "nghim", "nghim", "nghim"),
    ("nghinh", "nghinh", "nghinh", "nghinh", "nghinh"),
    ("nghiu", "nghiu", "nghiu", "nghiu", "nghiu"),
    ("nghiêm", "nghieem", "nghieem", "nghie6m", "nghie6m"),
    ("nghiên", "nghieen", "nghieen", "nghie6n", "nghie6n"),
    ("nghiêu", "nghieeu", "nghieeu", "nghie6u", "nghie6u"),
    ("nghiến", "nghieesn", "nghieens", "nghie61n", "nghie6n1"),
    ("nghiền", "nghieefn", "nghieenf", "nghie62n", "nghie6n2"),
    ("gia", "gia", "gia", "gia", "gia"),
    ("giai", "giai", "giai", "giai", "giai"),
    ("giam", "giam", "giam", "giam", "giam"),
    ("gian", "gian", "gian", "gian", "gian"),
    ("giang", "giang", "giang", "giang", "giang"),
    ("gianh", "gianh", "gianh", "gianh", "gianh"),
    ("giao", "giao", "giao", "giao", "giao"),
    ("giau", "giau", "giau", "giau", "giau"),
    ("gie", "gie", "gie", "gie", "gie"),
    ("gien", "gien", "gien", "gien", "gien"),
    ("gieo", "gieo", "gieo", "gieo", "gieo"),
    ("gio", "gio", "gio", "gio", "gio"),
    ("qua", "qua", "qua", "qua", "qua"),
    ("quai", "quai", "quai", "quai", "quai"),
    ("quan", "quan", "quan", "quan", "quan"),
    ("quang", "quang", "quang", "quang", "quang"),
    ("quanh", "quanh", "quanh", "quanh", "quanh"),
    ("quao", "quao", "quao", "quao", "quao"),
    ("quau", "quau", "quau", "quau", "quau"),
    ("quay", "quay", "quay", "quay", "quay"),
    ("que", "que", "que", "que", "que"),
    ("quen", "quen", "quen", "quen", "quen"),
    ("queng", "queng", "queng", "queng", "queng"),
    ("queo", "queo", "queo", "queo", "queo"),
    ("băn", "bawn", "bawn", "ba8n", "ba8n"),
    ("băng", "bawng", "bawng", "ba8ng", "ba8ng"),
    ("choăn", "choawn", "choawn", "choa8n", "choa8n"),
    ("chăn", "chawn", "chawn", "cha8n", "cha8n"),
    ("chăng", "chawng", "chawng", "cha8ng", "cha8ng"),
    ("căn", "cawn", "cawn", "ca8n", "ca8n"),
    ("căng", "cawng", "cawng", "ca8ng", "ca8ng"),
    ("dăn", "dawn", "dawn", "da8n", "da8n"),
    ("dăng", "dawng", "dawng", "da8ng", "da8ng"),
    ("gioăng", "gioawng", "gioawng", "gioa8ng", "gioa8ng"),
    ("giăng", "giawng", "giawng", "gia8ng", "gia8ng"),
    ("găn", "gawn", "gawn", "ga8n", "ga8n"),
    ("bâu", "baau", "baau", "ba6u", "ba6u"),
    ("châu", "chaau", "chaau", "cha6u", "cha6u"),
    ("câu", "caau", "caau", "ca6u", "ca6u"),
    ("dâu", "daau", "daau", "da6u", "da6u"),
    ("giâu", "giaau", "giaau", "gia6u", "gia6u"),
    ("gâu", "gaau", "gaau", "ga6u", "ga6u"),
    ("hâu", "haau", "haau", "ha6u", "ha6u"),
    ("khâu", "khaau", "khaau", "kha6u", "kha6u"),
    ("lâu", "laau", "laau", "la6u", "la6u"),
    ("mâu", "maau", "maau", "ma6u", "ma6u"),
    ("ngâu", "ngaau", "ngaau", "nga6u", "nga6u"),
    ("nhâu", "nhaau", "nhaau", "nha6u", "nha6u"),
    ("bây", "baay", "baay", "ba6y", "ba6y"),
    ("chây", "chaay", "chaay", "cha6y", "cha6y"),
    ("cây", "caay", "caay", "ca6y", "ca6y"),
    ("dây", "daay", "daay", "da6y", "da6y"),
    ("giây", "giaay", "giaay", "gia6y", "gia6y"),
    ("gây", "gaay", "gaay", "ga6y", "ga6y"),
    ("hây", "haay", "haay", "ha6y", "ha6y"),
    ("khuây", "khuaay", "khuaay", "khua6y", "khua6y"),
    ("lây", "laay", "laay", "la6y", "la6y"),
    ("mây", "maay", "maay", "ma6y", "ma6y"),
    ("nguây", "nguaay", "nguaay", "ngua6y", "ngua6y"),
    ("ngây", "ngaay", "ngaay", "nga6y", "nga6y"),
    ("rụm", "rujm", "rumj", "ru5m", "rum5"),
    ("bạng", "bajng", "bangj", "ba5ng", "bang5"),
    ("trét", "trest", "trets", "tre1t", "tret1"),
    ("khoát", "khoast", "khoats", "khoa1t", "khoat1"),
    ("hơi", "howi", "howi", "ho7i", "ho7i"),
    ("dy", "dy", "dy", "dy", "dy"),
    ("truất", "truaast", "truaats", "trua61t", "trua6t1"),
    ("càu", "cafu", "cauf", "ca2u", "cau2"),
    ("sụn", "sujn", "sunj", "su5n", "sun5"),
    ("trè", "tref", "tref", "tre2", "tre2"),
    ("úa", "usa", "uas", "u1a", "ua1"),
    ("pao", "pao", "pao", "pao", "pao"),
    ("chệch", "cheejch", "cheechj", "che65ch", "che6ch5"),
    ("quảy", "quary", "quayr", "qua3y", "quay3"),
    ("bặn", "bawjn", "bawnj", "ba85n", "ba8n5"),
    ("bậu", "baaju", "baauj", "ba65u", "ba6u5"),
    ("chờ", "chowf", "chowf", "cho72", "cho72"),
    ("hay", "hay", "hay", "hay", "hay"),
    ("nhử", "nhuwr", "nhuwr", "nhu73", "nhu73"),
    ("ria", "ria", "ria", "ria", "ria"),
    ("bảy", "bary", "bayr", "ba3y", "bay3"),
    ("phạch", "phajch", "phachj", "pha5ch", "phach5"),
    ("guổng", "guoorng", "guoongr", "guo63ng", "guo6ng3"),
    ("thố", "thoos", "thoos", "tho61", "tho61"),
    ("suối", "suoosi", "suoois", "suo61i", "suo6i1"),
    ("thông", "thoong", "thoong", "tho6ng", "tho6ng"),
    ("pan", "pan", "pan", "pan", "pan"),
    ("ne", "ne", "ne", "ne", "ne"),
    ("hiêng", "hieeng", "hieeng", "hie6ng", "hie6ng"),
    ("người", "nguwowfi", "nguwowif", "ngu7o72i", "ngu7o7i2"),
    ("quạng", "quajng", "quangj", "qua5ng", "quang5"),
    ("khuy", "khuy", "khuy", "khuy", "khuy"),
    ("va", "va", "va", "va", "va"),
    ("xầu", "xaafu", "xaauf", "xa62u", "xa6u2"),
    ("bong", "bong", "bong", "bong", "bong"),
    ("trố", "troos", "troos", "tro61", "tro61"),
    ("tỷ", "tyr", "tyr", "ty3", "ty3"),
    ("dẹt", "dejt", "detj", "de5t", "det5"),
    ("thìn", "thifn", "thinf", "thi2n", "thin2"),
    ("lìm", "lifm", "limf", "li2m", "lim2"),
    ("khum", "khum", "khum", "khum", "khum"),
    ("dần", "daafn", "daanf", "da62n", "da6n2"),
    ("gớc", "gowsc", "gowcs", "go71c", "go7c1"),
    ("trụn", "trujn", "trunj", "tru5n", "trun5"),
    ("cành", "cafnh", "canhf", "ca2nh", "canh2"),
    ("chộp", "choojp", "choopj", "cho65p", "cho6p5"),
    ("miền", "mieefn", "mieenf", "mie62n", "mie6n2"),
    ("chừng", "chuwfng", "chuwngf", "chu72ng", "chu7ng2"),
    ("lẳm", "lawrm", "lawmr", "la83m", "la8m3"),
    ("xoành", "xoafnh", "xoanhf", "xoa2nh", "xoanh2"),
    ("lôi", "looi", "looi", "lo6i", "lo6i"),
    ("riềm", "rieefm", "rieemf", "rie62m", "rie6m2"),
    ("hủ", "hur", "hur", "hu3", "hu3"),
    ("uyển", "uyeern", "uyeenr", "uye63n", "uye6n3"),
    ("bởi", "bowri", "bowir", "bo73i", "bo7i3"),
]

@Suite("Corpus: đối chiếu ~250 âm tiết thật (Telex + VNI, gõ sớm & muộn)")
struct CorpusRegression {
    @Test("mọi âm tiết dựng lại đúng ở cả 4 lối gõ")
    func all() {
        for (word, telexCanon, telexLate, vniCanon, vniLate) in corpusCases {
            #expect(typeWord(telexCanon, .telex) == word, "Telex sớm \(telexCanon) -> \(typeWord(telexCanon, .telex))")
            #expect(typeWord(telexLate, .telex) == word,  "Telex muộn \(telexLate) -> \(typeWord(telexLate, .telex))")
            #expect(typeWord(vniCanon, .vni) == word,     "VNI sớm \(vniCanon) -> \(typeWord(vniCanon, .vni))")
            #expect(typeWord(vniLate, .vni) == word,      "VNI muộn \(vniLate) -> \(typeWord(vniLate, .vni))")
        }
    }

    @Test("Kiểm thử 5000+ từ với nhiều thứ tự gõ dấu khác nhau")
    func testFiveThousandWordsEquivalence() {
        let initials = ["", "b", "c", "ch", "d", "đ", "g", "gh", "gi", "h", "k", "kh", "l", "m", "n", "ng", "ngh", "nh", "p", "ph", "q", "r", "s", "t", "th", "tr", "v", "x"]
        let finals = ["", "c", "ch", "m", "n", "ng", "nh", "p", "t", "u", "o", "i", "y"]
        
        struct NucleusTest {
            let name: String
            let telex: String
            let vni: String
        }
        
        let nuclei = [
            // 1 vowel
            NucleusTest(name: "a", telex: "a", vni: "a"),
            NucleusTest(name: "ă", telex: "aw", vni: "a8"),
            NucleusTest(name: "â", telex: "aa", vni: "a6"),
            NucleusTest(name: "e", telex: "e", vni: "e"),
            NucleusTest(name: "ê", telex: "ee", vni: "e6"),
            NucleusTest(name: "i", telex: "i", vni: "i"),
            NucleusTest(name: "o", telex: "o", vni: "o"),
            NucleusTest(name: "ô", telex: "oo", vni: "o6"),
            NucleusTest(name: "ơ", telex: "ow", vni: "o7"),
            NucleusTest(name: "u", telex: "u", vni: "u"),
            NucleusTest(name: "ư", telex: "uw", vni: "u7"),
            NucleusTest(name: "y", telex: "y", vni: "y"),
            
            // 2 vowels
            NucleusTest(name: "ai", telex: "ai", vni: "ai"),
            NucleusTest(name: "ao", telex: "ao", vni: "ao"),
            NucleusTest(name: "au", telex: "au", vni: "au"),
            NucleusTest(name: "ay", telex: "ay", vni: "ay"),
            NucleusTest(name: "âu", telex: "aau", vni: "a6u"),
            NucleusTest(name: "ây", telex: "aay", vni: "a6y"),
            NucleusTest(name: "eo", telex: "eo", vni: "eo"),
            NucleusTest(name: "êu", telex: "eeu", vni: "e6u"),
            NucleusTest(name: "ia", telex: "ia", vni: "ia"),
            NucleusTest(name: "iê", telex: "iee", vni: "ie6"),
            NucleusTest(name: "iu", telex: "iu", vni: "iu"),
            NucleusTest(name: "yê", telex: "yee", vni: "ye6"),
            NucleusTest(name: "yêu", telex: "yeeu", vni: "ye6u"),
            NucleusTest(name: "iêu", telex: "ieeu", vni: "ie6u"),
            NucleusTest(name: "oa", telex: "oa", vni: "oa"),
            NucleusTest(name: "oă", telex: "oaw", vni: "oa8"),
            NucleusTest(name: "oe", telex: "oe", vni: "oe"),
            NucleusTest(name: "oo", telex: "ooo", vni: "oo"),
            NucleusTest(name: "oi", telex: "oi", vni: "oi"),
            NucleusTest(name: "ôi", telex: "ooi", vni: "o6i"),
            NucleusTest(name: "ơi", telex: "owi", vni: "o7i"),
            NucleusTest(name: "ua", telex: "ua", vni: "ua"),
            NucleusTest(name: "uâ", telex: "uaa", vni: "ua6"),
            NucleusTest(name: "uê", telex: "uee", vni: "ue6"),
            NucleusTest(name: "uô", telex: "uoo", vni: "uo6"),
            NucleusTest(name: "uơ", telex: "uow", vni: "uo7"),
            NucleusTest(name: "ui", telex: "ui", vni: "ui"),
            NucleusTest(name: "ưi", telex: "uwi", vni: "u7i"),
            NucleusTest(name: "uy", telex: "uy", vni: "uy"),
            NucleusTest(name: "ưa", telex: "uwa", vni: "u7a"),
            NucleusTest(name: "ươ", telex: "uwow", vni: "u7o7"),
            NucleusTest(name: "ưu", telex: "uwu", vni: "u7u"),
            NucleusTest(name: "ôô", telex: "oooo", vni: "o6o6"),
            
            // 3 vowels
            NucleusTest(name: "oai", telex: "oai", vni: "oai"),
            NucleusTest(name: "oay", telex: "oay", vni: "oay"),
            NucleusTest(name: "oao", telex: "oao", vni: "oao"),
            NucleusTest(name: "uây", telex: "uaay", vni: "ua6y"),
            NucleusTest(name: "uôi", telex: "uooi", vni: "uo6i"),
            NucleusTest(name: "ươi", telex: "uwowi", vni: "u7o7i"),
            NucleusTest(name: "uya", telex: "uya", vni: "uya"),
            NucleusTest(name: "uyê", telex: "uyee", vni: "uye6"),
            NucleusTest(name: "uyu", telex: "uyu", vni: "uyu")
        ]
        
        let telexTones = ["", "s", "f", "r", "x", "j"]
        let vniTones = ["", "1", "2", "3", "4", "5"]
        
        var count = 0
        var failures = 0
        
        for initial in initials {
            if initial == "q" { continue }
            for nucleus in nuclei {
                if nucleus.name == "ôô" { continue }
                for finalCons in finals {
                    if (nucleus.name == "o" || nucleus.name == "ô" || nucleus.name == "ơ") && finalCons == "o" { continue }
                    if (nucleus.name == "u" || nucleus.name == "ư") && finalCons == "u" { continue }
                    
                    let toneless = initial + nucleus.name + finalCons
                    guard VietSyllable.isValidToneless(toneless) else { continue }
                    
                    for toneIndex in 0..<6 {
                        count += 1
                        
                        let tTone = telexTones[toneIndex]
                        let vTone = vniTones[toneIndex]
                        
                        // 1. Telex Test
                        let telexLate = initial + nucleus.telex + finalCons + tTone
                        let telexEarly = initial + nucleus.telex + tTone + finalCons
                        let outTelexLate = typeWord(telexLate, .telex)
                        let outTelexEarly = typeWord(telexEarly, .telex)
                        
                        if outTelexLate != outTelexEarly {
                            failures += 1
                            #if DEBUG
                            print("Telex LỆCH: keys=\(telexLate) vs \(telexEarly) -> \(outTelexLate) vs \(outTelexEarly)")
                            #endif
                        }
                        
                        // 2. VNI Test
                        let vniLate = initial + nucleus.vni + finalCons + vTone
                        let vniEarly = initial + nucleus.vni + vTone + finalCons
                        let outVniLate = typeWord(vniLate, .vni)
                        let outVniEarly = typeWord(vniEarly, .vni)
                        
                        if outVniLate != outVniEarly {
                            failures += 1
                            #if DEBUG
                            print("VNI LỆCH: keys=\(vniLate) vs \(vniEarly) -> \(outVniLate) vs \(outVniEarly)")
                            #endif
                        }
                        
                        // 3. Cross Telex vs VNI Test
                        if outTelexLate != outVniLate {
                            failures += 1
                            #if DEBUG
                            print("Telex vs VNI LỆCH: \(outTelexLate) (Telex) vs \(outVniLate) (VNI)")
                            #endif
                        }
                    }
                }
            }
        }
        
        print("Đã kiểm tra tổng cộng \(count) từ tiếng Việt hợp lệ.")
        #expect(failures == 0, "Phát hiện \(failures) trường hợp gõ lỗi trong \(count) từ kiểm tra!")
    }
}
