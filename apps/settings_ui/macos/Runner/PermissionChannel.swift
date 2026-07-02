// PermissionChannel.swift
// -----------------------
// Cho phép UI Flutter tự KIỂM TRA quyền TCC của macOS ngay trong tiến trình của
// nó, thay vì chỉ đọc status.json do bộ gõ Swift ghi ngầm. Vì sao cần:
//
//   - status.json chỉ được ghi lại mỗi ~5s và có thể "đóng băng" ở trạng thái
//     cũ đúng lúc bộ gõ relaunch để áp quyền mới -> UI báo "chưa cấp" dù đã cấp.
//   - Nhiều instance bộ gõ chạy song song có thể ghi đè nhau -> trạng thái sai.
//
// Đọc thẳng TCC API ở đây là realtime và luôn đúng với chính app UI. Kết quả này
// là NGUỒN CHÍNH; status.json chỉ còn là dự phòng (và cho Windows, nơi không có
// mô hình quyền kiểu này).
//
// LƯU Ý: TCC gắn theo TỪNG app (bundle id + chữ ký). Quyền của app UI và của bộ
// gõ là RIÊNG BIỆT. Ở đây ta chỉ trả lời "chính app UI có quyền chưa" cho mục
// đích onboarding/hiển thị; đó cũng chính là cái người dùng vừa bật trong System
// Settings khi được app UI dẫn tới.

import ApplicationServices
import CoreGraphics
import FlutterMacOS
import Foundation

enum PermissionChannel {
  /// Đăng ký kênh method channel `bowgo/permissions` lên FlutterViewController.
  static func register(with controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "bowgo/permissions",
      binaryMessenger: controller.engine.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "check":
        // AXIsProcessTrusted / CGPreflight* KHÔNG hiện prompt — chỉ đọc trạng
        // thái. An toàn để gọi lặp lại (poll / khi app được focus lại).
        let acc = AXIsProcessTrusted()
        let im = CGPreflightListenEventAccess()
        let sr = CGPreflightScreenCaptureAccess()
        result([
          "accessibility": acc,
          "inputMonitoring": im,
          "screenRecording": sr,
          "ready": acc && im,
        ])
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
