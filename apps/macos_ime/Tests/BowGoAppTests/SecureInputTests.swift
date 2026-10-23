// SecureInputTests.swift
// ----------------------
// Nhập bảo mật bật = event tap không nhận phím thường -> Bow Go "chết" im lặng. Kiểm:
//   • monitor chỉ báo khi bật LIÊN TỤC ≥ 30s, và chỉ một lần mỗi đợt;
//   • phát hiện thật: chính tiến trình test bật Secure Input -> isOn + đúng tên app giữ.

import Testing
import Foundation
import AppKit
import Carbon.HIToolbox
@testable import BowGoApp

@Suite("Nhập bảo mật (Secure Input)", .serialized)
struct SecureInputTests {

    @Test("bật chốc lát (gõ mật khẩu) không báo; bật liên tục ≥ 30s báo đúng 1 lần")
    func monitorReportsOnlyWhenStuck() {
        var m = SecureInputMonitor()
        let t0 = Date()
        #expect(m.update(isOn: true, now: t0) == nil)
        #expect(m.update(isOn: true, now: t0.addingTimeInterval(10)) == nil)
        #expect(m.update(isOn: false, now: t0.addingTimeInterval(12)) == nil)   // gõ mật khẩu xong

        let t1 = t0.addingTimeInterval(20)
        #expect(m.update(isOn: true, now: t1) == nil)
        #expect(m.update(isOn: true, now: t1.addingTimeInterval(29)) == nil)
        #expect(m.update(isOn: true, now: t1.addingTimeInterval(30)) == .stuck)
        #expect(m.update(isOn: true, now: t1.addingTimeInterval(90)) == nil)    // không báo lặp

        #expect(m.update(isOn: false, now: t1.addingTimeInterval(91)) == nil)
        let t2 = t1.addingTimeInterval(100)
        #expect(m.update(isOn: true, now: t2) == nil)
        #expect(m.update(isOn: true, now: t2.addingTimeInterval(31)) == .stuck) // đợt mới báo lại
    }

    @Test("app khác đang giữ Secure Input: đọc được tên app giữ",
          .enabled(if: IsSecureEventInputEnabled(), "không app nào đang giữ Secure Input"))
    func namesCurrentOwner() {
        let name = SecureInput.ownerName()
        print("Secure Input đang do: \(name ?? "nil")")
        #expect(name != nil)
    }

    @Test("phát hiện thật: tiến trình bật Secure Input -> isOn và đúng app giữ",
          .enabled(if: !IsSecureEventInputEnabled(), "app khác đang giữ Secure Input"))
    func detectsRealSecureInput() {
        #expect(!SecureInput.isOn)
        EnableSecureEventInput()
        defer { DisableSecureEventInput() }
        #expect(SecureInput.isOn)
        #expect(SecureInput.ownerName() == NSRunningApplication.current.localizedName)
    }
}
