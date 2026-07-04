import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // KHÔNG đăng ký kênh kiểm-tra-quyền native nữa. Gọi AXIsProcessTrusted /
    // CGPreflight* trong tiến trình app Cài đặt sẽ khiến macOS ĐĂNG KÝ app này
    // vào danh sách quyền (Accessibility/Input Monitoring…) như một entry "Bow
    // Go" thừa — dù app Cài đặt KHÔNG cần các quyền đó (chỉ bộ gõ cần). Thay vào
    // đó, app Cài đặt chỉ ĐỌC status.json do bộ gõ ghi (mỗi ~1s), nên nó không
    // bao giờ chạm TCC API và không xuất hiện trong danh sách quyền.

    super.awakeFromNib()
  }
}
