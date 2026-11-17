// KeycodeOnlyAppTests.swift
// -------------------------
// iOS Simulator, máy ảo (Parallels/VMware/UTM/VirtualBox) và app điều khiển máy từ xa
// (Remote Desktop, AnyDesk, TeamViewer…) chỉ đọc MÃ PHÍM của sự kiện: mọi ký tự bộ gõ
// gửi thay (virtualKey 0 = A + chuỗi Unicode) đều thành "a" -> gõ gì cũng ra "aaa".
// Ở đó bộ gõ phải nhả tay.

import Testing
@testable import BowGoApp

@Suite("App chỉ đọc mã phím (Simulator / máy ảo / remote)")
struct KeycodeOnlyAppTests {

    @Test("Simulator, máy ảo, remote desktop: bộ gõ nhả phím")
    func keycodeOnlyAppsPassThrough() {
        for id in ["com.apple.iphonesimulator",
                   "com.parallels.desktop.console", "com.parallels.winapp.notepad",
                   "com.vmware.fusion", "com.utmapp.UTM", "com.osy.UTM",
                   "org.virtualbox.app.VirtualBoxVM", "codes.rambo.VirtualBuddy",
                   "com.microsoft.rdc.macos", "com.apple.ScreenSharing",
                   "com.apple.RemoteDesktop",
                   "com.philandro.anydesk", "com.teamviewer.TeamViewer",
                   "com.carriez.rustdesk", "tv.parsec.www", "com.p5sys.jump.mac.viewer",
                   "com.edovia.screens5.mac", "com.realvnc.vncviewer",
                   "com.citrix.receiver.nomas", "com.vmware.horizon"] {
            #expect(EventTapController.passesKeysThrough(id), "\(id)")
        }
    }

    @Test("App thường vẫn được gõ thay")
    func othersStillTyped() {
        for id in ["com.apple.TextEdit", "com.google.Chrome", "com.microsoft.VSCode",
                   "com.microsoft.Word", "com.apple.Terminal", ""] {
            #expect(!EventTapController.passesKeysThrough(id), "\(id)")
        }
    }

    @Test("Id gần giống tiền tố nhưng là app khác: không bị nhả")
    func lookalikesNotPassedThrough() {
        for id in ["com.microsoft.Excel", "com.microsoft.rdc", "com.apple.Screen",
                   "com.apple.ScreenTime", "com.vmware", "com.teamviewer", "com.apple.iphone",
                   "tv.parsec", "com.citrix.Workspace"] {
            #expect(!EventTapController.passesKeysThrough(id), "\(id)")
        }
    }
}
