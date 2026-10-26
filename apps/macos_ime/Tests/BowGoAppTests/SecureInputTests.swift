// SecureInputTests.swift
// ----------------------
// Nhập bảo mật bật = event tap không nhận phím thường -> Bow Go "chết" im lặng. Kiểm:
//   • monitor chỉ báo khi bật LIÊN TỤC ≥ 30s, và chỉ một lần mỗi đợt;
//   • khoá màn hình thì im; đã bật trước khi khoá mà mở khoá vẫn bật thì báo lại sớm;
//   • không hiện tên loginwindow (macOS ghi nó khi không rõ app giữ);
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

    @Test("đã báo trước khi khoá, khoá/mở khoá mà vẫn bật -> báo lại sau 3s với câu sau-mở-khoá")
    func reportsAgainWhenStillOnAfterUnlock() {
        var m = SecureInputMonitor()
        let t0 = Date()
        #expect(m.update(isOn: true, now: t0) == nil)
        #expect(m.update(isOn: true, now: t0.addingTimeInterval(30)) == .stuck)
        #expect(!m.lockDidNotHelp)

        // Màn khoá: ô mật khẩu của loginwindow bật nó — bao lâu cũng không báo.
        #expect(m.update(isOn: true, screenLocked: true, now: t0.addingTimeInterval(100)) == nil)
        #expect(m.update(isOn: true, screenLocked: true, now: t0.addingTimeInterval(500)) == nil)

        let unlock = t0.addingTimeInterval(600)
        #expect(m.update(isOn: true, now: unlock) == nil)
        #expect(m.lockDidNotHelp)   // menu bỏ bước khoá màn hình ngay từ lúc này
        #expect(m.update(isOn: true, now: unlock.addingTimeInterval(2.999)) == nil)
        #expect(m.update(isOn: true, now: unlock.addingTimeInterval(3)) == .stillStuckAfterUnlock)
        #expect(m.update(isOn: true, now: unlock.addingTimeInterval(60)) == nil)   // không báo lặp

        #expect(m.update(isOn: false, now: unlock.addingTimeInterval(61)) == nil)  // app giữ nhả
        #expect(!m.lockDidNotHelp)
    }

    @Test("khoá/mở khoá 2 lần liền (như log 11:58) -> mỗi lần thử nhận một kết quả")
    func eachLockAttemptGetsAnAnswer() {
        var m = SecureInputMonitor()
        let t0 = Date()
        #expect(m.update(isOn: true, now: t0) == nil)
        #expect(m.update(isOn: true, screenLocked: true, now: t0.addingTimeInterval(1)) == nil)
        #expect(m.update(isOn: true, now: t0.addingTimeInterval(5)) == nil)
        #expect(m.update(isOn: true, now: t0.addingTimeInterval(8)) == .stillStuckAfterUnlock)
        #expect(m.update(isOn: true, screenLocked: true, now: t0.addingTimeInterval(13)) == nil)
        #expect(m.update(isOn: true, now: t0.addingTimeInterval(16)) == nil)
        #expect(m.update(isOn: true, now: t0.addingTimeInterval(19)) == .stillStuckAfterUnlock)
    }

    @Test("trước khi khoá chưa bật, mở khoá ra gặp ô mật khẩu -> không báo 'khoá không gỡ được', ngưỡng 30s")
    func legitPasswordFieldAfterUnlockUsesNormalThreshold() {
        var m = SecureInputMonitor()
        let t0 = Date()
        #expect(m.update(isOn: false, now: t0) == nil)
        #expect(m.update(isOn: true, screenLocked: true, now: t0.addingTimeInterval(1)) == nil)

        let unlock = t0.addingTimeInterval(60)
        #expect(m.update(isOn: true, now: unlock) == nil)
        #expect(!m.lockDidNotHelp)
        #expect(m.update(isOn: true, now: unlock.addingTimeInterval(10)) == nil)
        #expect(m.update(isOn: true, now: unlock.addingTimeInterval(30)) == .stuck)
    }

    @Test("Bow Go khởi động lúc đang khoá: im suốt lúc khoá, mở khoá thì như thường")
    func launchedWhileLocked() {
        var m = SecureInputMonitor()
        let t0 = Date()
        #expect(m.update(isOn: true, screenLocked: true, now: t0) == nil)
        #expect(m.update(isOn: true, screenLocked: true, now: t0.addingTimeInterval(3600)) == nil)

        let unlock = t0.addingTimeInterval(3700)
        #expect(m.update(isOn: false, now: unlock) == nil)
        #expect(m.update(isOn: true, now: unlock.addingTimeInterval(1)) == nil)
        #expect(m.update(isOn: true, now: unlock.addingTimeInterval(31)) == .stuck)
    }

    @Test("mở khoá xong nhả ngay -> không báo; đợt sau lại dùng ngưỡng 30s")
    func unlockThenReleasedFallsBackToNormalThreshold() {
        var m = SecureInputMonitor()
        let t0 = Date()
        #expect(m.update(isOn: true, now: t0) == nil)
        #expect(m.update(isOn: true, screenLocked: true, now: t0.addingTimeInterval(1)) == nil)
        let unlock = t0.addingTimeInterval(20)
        #expect(m.update(isOn: true, now: unlock) == nil)
        #expect(m.update(isOn: false, now: unlock.addingTimeInterval(1)) == nil)   // app giữ đã nhả

        let t1 = unlock.addingTimeInterval(10)
        #expect(m.update(isOn: true, now: t1) == nil)
        #expect(m.update(isOn: true, now: t1.addingTimeInterval(5)) == nil)
        #expect(m.update(isOn: true, now: t1.addingTimeInterval(30)) == .stuck)
    }

    @Test("vừa gõ mật khẩu (bật 1 nhịp) rồi khoá, mở khoá ô vẫn focus -> báo nhanh (đánh đổi đã chọn: không phân biệt được với kẹt thật)")
    func shortHoldBeforeLockCountsAsStuck() {
        var m = SecureInputMonitor()
        let t0 = Date()
        #expect(m.update(isOn: true, now: t0) == nil)
        #expect(m.update(isOn: true, screenLocked: true, now: t0.addingTimeInterval(1)) == nil)
        #expect(m.update(isOn: true, now: t0.addingTimeInterval(60)) == nil)
        #expect(m.update(isOn: true, now: t0.addingTimeInterval(63)) == .stillStuckAfterUnlock)
    }

    @Test("Bow Go tự giữ xen giữa (isOn=false) -> hết 'khoá không gỡ được', đợt sau ngưỡng 30s")
    func selfHoldInterleavedResetsLockDidNotHelp() {
        var m = SecureInputMonitor()
        let t0 = Date()
        _ = m.update(isOn: true, now: t0)
        _ = m.update(isOn: true, screenLocked: true, now: t0.addingTimeInterval(1))
        _ = m.update(isOn: true, now: t0.addingTimeInterval(10))
        #expect(m.lockDidNotHelp)
        #expect(m.update(isOn: false, now: t0.addingTimeInterval(11)) == nil)
        #expect(!m.lockDidNotHelp)
        #expect(m.update(isOn: true, now: t0.addingTimeInterval(12)) == nil)
        #expect(m.update(isOn: true, now: t0.addingTimeInterval(15)) == nil)
        #expect(m.update(isOn: true, now: t0.addingTimeInterval(42)) == .stuck)
    }

    @Test("loginwindow bật trước khi cờ khoá hiện, rồi nhả khi mở khoá -> sạch, không báo nhanh")
    func loginwindowHoldSeenBeforeLockFlagThenReleased() {
        var m = SecureInputMonitor()
        let t0 = Date()
        #expect(m.update(isOn: true, now: t0) == nil)
        #expect(m.update(isOn: true, screenLocked: true, now: t0.addingTimeInterval(1)) == nil)
        #expect(m.update(isOn: false, now: t0.addingTimeInterval(20)) == nil)
        #expect(!m.lockDidNotHelp)
        #expect(m.update(isOn: true, now: t0.addingTimeInterval(21)) == nil)
        #expect(m.update(isOn: true, now: t0.addingTimeInterval(30)) == nil)
    }

    @Test("kẹt -> khoá -> app giữ nhả trong lúc khoá -> mở khoá sạch, đợt mới dùng 30s")
    func holderReleasedDuringLock() {
        var m = SecureInputMonitor()
        let t0 = Date()
        _ = m.update(isOn: true, now: t0)
        #expect(m.update(isOn: true, now: t0.addingTimeInterval(31)) == .stuck)
        _ = m.update(isOn: false, screenLocked: true, now: t0.addingTimeInterval(40))
        #expect(m.update(isOn: false, now: t0.addingTimeInterval(50)) == nil)
        #expect(!m.lockDidNotHelp)
        #expect(m.update(isOn: true, now: t0.addingTimeInterval(51)) == nil)
        #expect(m.update(isOn: true, now: t0.addingTimeInterval(54)) == nil)
        #expect(m.update(isOn: true, now: t0.addingTimeInterval(81)) == .stuck)
    }

    @Test("đọc được trạng thái khoá màn hình (máy đang dùng = không khoá)")
    func readsScreenUnlocked() {
        #expect(!SecureInput.screenIsLocked)
    }

    @Test("không gọi loginwindow là app giữ; app thường vẫn đọc được tên",
          .enabled(if: !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.loginwindow").isEmpty
                    && !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").isEmpty,
                   "không có phiên GUI đủ loginwindow + Finder"))
    func hidesLoginwindowName() throws {
        let loginwindow = try #require(
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.loginwindow").first)
        #expect(SecureInput.appName(pid: loginwindow.processIdentifier) == nil)
        let finder = try #require(
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first)
        #expect(SecureInput.appName(pid: finder.processIdentifier) == finder.localizedName)
        #expect(finder.localizedName != nil)
    }

    @Test("app khác đang giữ Secure Input: đọc được tên app giữ",
          .enabled(if: IsSecureEventInputEnabled(), "không app nào đang giữ Secure Input"))
    func namesCurrentOwner() {
        let name = SecureInput.ownerName()
        print("Secure Input đang do: \(name ?? "nil")")
        // Trạng thái THẬT của máy: app kia có thể vừa nhả giữa lúc kiểm điều kiện
        // và lúc đọc, hoặc đã tắt mà macOS vẫn kẹt PID cũ -> chỉ fail khi VẪN đang
        // bật, app giữ còn sống mà không đọc được tên. loginwindow cố ý không có tên.
        if name == nil {
            let ownerNameable = SecureInput.ownerPID().map {
                kill($0, 0) == 0
                    && NSRunningApplication(processIdentifier: $0)?.bundleIdentifier != "com.apple.loginwindow"
            } ?? true
            #expect(!SecureInput.isOn || !ownerNameable, "đang bật mà không đọc được app giữ")
        }
    }

    @Test("nút \"Khoá màn hình ngay\" có hàm hệ thống để gọi")
    func lockScreenFunctionResolves() {
        // Private API: bản macOS mới mà bỏ nó thì nút thành vô dụng -> test này báo.
        #expect(SecureInput.lockScreenFunction != nil)
    }

    @Test("phát hiện thật: tiến trình bật Secure Input -> isOn và đúng app giữ",
          .enabled(if: !IsSecureEventInputEnabled(), "app khác đang giữ Secure Input"))
    func detectsRealSecureInput() {
        // Điều kiện `.enabled` xét lúc nạp test; app khác (vd Edge) có thể bật lại
        // ngay sau đó -> xét lại lúc chạy.
        guard !SecureInput.isOn else { return }
        EnableSecureEventInput()
        defer { DisableSecureEventInput() }
        #expect(SecureInput.isOn)
        // Hai tiến trình cùng giữ thì IOConsoleUsers chỉ ghi MỘT PID -> chỉ khẳng
        // định khi PID ghi nhận đúng là chính mình.
        guard SecureInput.ownerPID() == ProcessInfo.processInfo.processIdentifier else { return }
        // Chính mình giữ (vd ô nhập API key) -> không cảnh báo "app khác chặn bộ gõ".
        #expect(!SecureInput.heldByOtherApp)
    }
}
