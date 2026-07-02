import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Kênh để UI Flutter tự kiểm tra quyền TCC TRỰC TIẾP trong tiến trình của
    // chính nó — thay vì phụ thuộc status.json mà bộ gõ Swift ghi ngầm mỗi vài
    // giây. Đọc thẳng như thế là realtime, không trễ, không kẹt trạng thái cũ
    // khi bộ gõ relaunch hoặc chạy nhiều instance.
    PermissionChannel.register(with: flutterViewController)

    super.awakeFromNib()
  }
}
