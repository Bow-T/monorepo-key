// VirtualMachineTypingTests.swift
// -------------------------------
// KIỂM CHỨNG "MẤT CHỮ KHI GÕ VÀO MÁY ẢO / SIMULATOR" và cách sửa bằng gõ TỪNG KÝ TỰ
// (step-by-step) + delay + precomposed (NFC).
//
// CƠ CHẾ LỖI: cửa sổ VM (Parallels/VMware/UTM/VirtualBox) và iOS Simulator xử lý sự
// kiện phím khác app native. Bộ gõ "gõ thay" bằng CGEvent virtualKey:0 +
// keyboardSetUnicodeString gửi CẢ CỤM Unicode trong MỘT event; tới VM quá nhanh ->
// guest OS không nhận kịp -> RỚT KÝ TỰ (mất chữ).
//   Gõ "tieengs" -> engine dựng "tiếng" (5 ký tự) trong 1 event -> VM chỉ nhận được
//   vài ký tự đầu.  ❌
//
// CÁCH SỬA (giống PHTV): khi frontmost app là VM, gõ lại chuỗi mới TỪNG KÝ TỰ MỘT
// (mỗi ký tự một event) + delay nhỏ giữa các ký tự, và chuẩn hoá về PRECOMPOSED (NFC)
// vì nhiều guest không dựng lại được ký tự tổ hợp rời rạc.  ✅

import Testing
import Foundation
@testable import VietEngine

/// Mô hình CỬA SỔ MÁY ẢO / SIMULATOR "rớt ký tự khi nhận cả cụm một lần".
///
/// - `typeBatch`: gõ CẢ CỤM Unicode trong một event (sendString). VM chỉ giữ được
///   `maxPerEvent` ký tự đầu, phần còn lại RỚT -> mất chữ.
/// - `typeStepByStep`: gõ TỪNG KÝ TỰ một, mỗi ký tự một event -> VM nhận đủ.
/// - `backspace`: keyCode thật 51 -> VM xoá được.
private struct VMField {
    private(set) var text = ""
    /// VM chỉ tiêu hoá được tối đa 2 ký tự nếu tới trong CÙNG một event (mô hình bi
    /// quan cho hành vi "rớt ký tự khi gõ cả cụm quá nhanh").
    let maxPerEvent: Int

    init(maxPerEvent: Int = 2) { self.maxPerEvent = maxPerEvent }

    /// Gõ cả cụm trong 1 event: chỉ `maxPerEvent` ký tự đầu vào được, phần sau rớt.
    mutating func typeBatch(_ s: String) {
        text.append(contentsOf: s.prefix(maxPerEvent))
    }

    /// Gõ từng ký tự một (mỗi event 1 ký tự): luôn ≤ maxPerEvent -> nhận đủ.
    mutating func typeStepByStep(_ s: String) {
        for ch in s { text.append(ch) }   // mỗi ký tự là một "event" riêng
    }

    mutating func backspace() {
        if !text.isEmpty { text.removeLast() }
    }
}

/// Mô phỏng luồng controller gõ chuỗi Telex vào cửa sổ VM.
/// - `useStepByStep`: true = bản MỚI (gõ từng ký tự + NFC); false = bản CŨ (gõ cả cụm).
private func typeIntoVM(_ keys: String, useStepByStep: Bool) -> String {
    let engine = VietEngine(method: .telex)
    var field = VMField()
    var committedLength = 0

    func replace(backspaces: Int, with text: String) {
        for _ in 0..<backspaces { field.backspace() }
        if useStepByStep {
            // NFC + gõ từng ký tự (khớp KeyOutput.sendStringStepByStep).
            field.typeStepByStep(text.precomposedStringWithCanonicalMapping)
        } else {
            field.typeBatch(text)
        }
    }

    for ch in keys {
        if ch == " " { engine.clear(); committedLength = 0; field.typeStepByStep(" "); continue }
        guard let rendered = engine.process(ch) else {
            committedLength = 0; field.typeStepByStep(String(ch)); continue
        }
        let bs = committedLength
        committedLength = rendered.count
        replace(backspaces: bs, with: rendered)
    }
    // So sánh ở dạng NFC để không lệ thuộc cách biểu diễn tổ hợp.
    return field.text.precomposedStringWithCanonicalMapping
}

/// Kết quả "đúng lý tưởng" của engine (ô thường, mọi thao tác đều nhận), dạng NFC.
private func typeIntoPlain(_ keys: String) -> String {
    let engine = VietEngine(method: .telex)
    var text = ""
    var committedLength = 0
    for ch in keys {
        if ch == " " { engine.clear(); committedLength = 0; text.append(" "); continue }
        guard let rendered = engine.process(ch) else {
            committedLength = 0; text.append(ch); continue
        }
        if committedLength > 0 { text.removeLast(committedLength) }
        committedLength = rendered.count
        text.append(rendered)
    }
    return text.precomposedStringWithCanonicalMapping
}

/// Mô phỏng nhận diện VM theo TIỀN TỐ bundle id (khớp `isVirtualMachineApp`).
private func isVirtualMachineApp(_ bundleID: String) -> Bool {
    let prefixes = [
        "com.parallels.",
        "com.vmware.fusion",
        "com.utmapp.",
        "com.osy.UTM",
        "org.virtualbox.",
        "com.apple.iphonesimulator",
    ]
    return prefixes.contains { bundleID.hasPrefix($0) }
}

@Suite("Gõ vào máy ảo / simulator (mất chữ + sửa bằng step-by-step + NFC)")
struct VirtualMachineTyping {

    @Test("Bản CŨ (gõ cả cụm) MẤT CHỮ; bản MỚI (từng ký tự) gõ đúng 'tiếng'")
    func lostCharsFixed() {
        #expect(typeIntoVM("tieengs", useStepByStep: false) != "tiếng")   // rớt ký tự
        #expect(typeIntoVM("tieengs", useStepByStep: true) == "tiếng")    // đủ chữ
    }

    @Test("Nhiều âm tiết có dấu vào VM khớp kết quả engine ô thường")
    func syllablesMatchPlain() {
        for word in ["tieengs", "vieejt", "dda", "nghieng", "thuowng", "nghieeng", "ddi hoc"] {
            let inVM = typeIntoVM(word, useStepByStep: true)
            let plain = typeIntoPlain(word)
            #expect(inVM == plain, "khác nhau ở '\(word)': vm=\(inVM) plain=\(plain)")
        }
    }

    @Test("Ký tự có dấu được gửi dạng PRECOMPOSED (NFC) — 1 scalar mỗi ký tự")
    func precomposedNFC() {
        // "ế" ở NFC là MỘT scalar; ở NFD là "e" + 2 combining marks (3 scalar).
        let nfc = "ế".precomposedStringWithCanonicalMapping
        #expect(nfc.unicodeScalars.count == 1)
        // Chuỗi step-by-step phải khớp engine sau khi chuẩn hoá NFC.
        #expect(typeIntoVM("tieesng", useStepByStep: true) == "tiếng".precomposedStringWithCanonicalMapping)
    }

    @Test("Nhận diện app máy ảo theo tiền tố bundle id")
    func detectVMApps() {
        #expect(isVirtualMachineApp("com.parallels.desktop.console"))
        #expect(isVirtualMachineApp("com.parallels.winapp.something"))
        #expect(isVirtualMachineApp("com.vmware.fusion"))
        #expect(isVirtualMachineApp("com.utmapp.UTM"))
        #expect(isVirtualMachineApp("com.osy.UTM"))
        #expect(isVirtualMachineApp("org.virtualbox.app.VirtualBoxVM"))
        #expect(isVirtualMachineApp("com.apple.iphonesimulator"))

        #expect(!isVirtualMachineApp("com.apple.Safari"))
        #expect(!isVirtualMachineApp("com.google.Chrome"))
        #expect(!isVirtualMachineApp("com.microsoft.VSCode"))
        #expect(!isVirtualMachineApp("com.apple.Terminal"))
        #expect(!isVirtualMachineApp(""))
    }
}
