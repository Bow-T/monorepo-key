// bow_paths.dart
// --------------
// Nơi DUY NHẤT xác định thư mục dùng chung "BowGo" giữa UI Flutter và bộ gõ
// nền tảng. Đặt sai chỗ là đứt "đường dây" cấu hình, nên tập trung một chỗ:
//
//     macOS  : ~/Library/Application Support/BowGo
//     Windows: %APPDATA%\BowGo        (khớp bow_config.cpp / text service TSF)
//
// Trên Windows PHẢI là %APPDATA% (Roaming) trực tiếp, KHÔNG dùng thư mục con
// <company>\<product> mà getApplicationSupportDirectory() sinh ra — vì DLL bộ
// gõ đọc thẳng %APPDATA%\BowGo\settings.json.

import 'dart:io';

import 'package:path_provider/path_provider.dart';

class BowPaths {
  /// Thư mục "BowGo" dùng chung (tạo nếu chưa có).
  static Future<Directory> sharedDir() async {
    Directory dir;
    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'];
      if (appData != null && appData.isNotEmpty) {
        dir = Directory('$appData\\BowGo');
      } else {
        final support = await getApplicationSupportDirectory();
        dir = Directory('${support.parent.path}\\BowGo');
      }
    } else {
      final support = await getApplicationSupportDirectory();
      dir = Directory('${support.parent.path}/BowGo');
    }
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  /// File con trong thư mục dùng chung (vd "settings.json", "status.json").
  static Future<File> sharedFile(String name) async {
    final dir = await sharedDir();
    return File('${dir.path}${Platform.pathSeparator}$name');
  }
}
