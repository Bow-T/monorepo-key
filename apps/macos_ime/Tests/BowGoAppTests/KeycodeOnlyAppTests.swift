// KeycodeOnlyAppTests.swift
// -------------------------
// iOS Simulator chỉ đọc MÃ PHÍM của sự kiện: mọi ký tự bộ gõ gửi thay (virtualKey 0
// = A + chuỗi Unicode) đều thành "a" -> gõ gì cũng ra "aaa". Ở đó bộ gõ phải nhả tay.

import Testing
@testable import BowGoApp

@Suite("App chỉ đọc mã phím (iOS Simulator)")
struct KeycodeOnlyAppTests {

    @Test("iOS Simulator: bộ gõ nhả phím")
    func simulatorPassesThrough() {
        #expect(EventTapController.passesKeysThrough("com.apple.iphonesimulator"))
    }

    @Test("App thường và máy ảo (gõ thay từng ký tự) KHÔNG bị nhả")
    func othersStillTyped() {
        for id in ["com.apple.TextEdit", "com.google.Chrome", "com.parallels.desktop.console",
                   "com.vmware.fusion", "com.utmapp.UTM"] {
            #expect(!EventTapController.passesKeysThrough(id), "\(id)")
        }
    }
}
