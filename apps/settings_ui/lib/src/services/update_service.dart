// update_service.dart
// -------------------
// Kiểm tra bản cập nhật Bow Go bằng cách hỏi GitHub Releases (releases/latest).
// So sánh phiên bản hiện tại với tag mới nhất (dạng vX.Y.Z) rồi báo có bản mới.
// Không thêm dependency ngoài: dùng HttpClient của dart:io.

import 'dart:convert';
import 'dart:io';

/// Phiên bản app hiện tại (nguồn sự thật cho toàn UI).
/// Cập nhật hằng này mỗi lần phát hành để tab Thông tin & Kiểm tra cập nhật đồng bộ.
const String kAppVersion = '1.0.4';

/// Kho phát hành trên GitHub (owner/repo) — nơi lấy release mới nhất.
const String _kGithubRepo = 'Bow-T/monorepo-key';

/// Trạng thái của một lần kiểm tra cập nhật.
enum UpdateState {
  /// Chưa kiểm tra lần nào.
  idle,

  /// Đang gọi mạng.
  checking,

  /// Đã là bản mới nhất.
  upToDate,

  /// Có bản mới hơn.
  updateAvailable,

  /// Lỗi (mạng, không có release…).
  error,
}

/// Kết quả một lần kiểm tra cập nhật.
class UpdateResult {
  const UpdateResult(this.state, {this.latestVersion, this.releaseUrl, this.message});

  final UpdateState state;

  /// Phiên bản mới nhất trên GitHub (không kèm chữ "v"), nếu đọc được.
  final String? latestVersion;

  /// URL trang release để người dùng mở tải bản mới.
  final String? releaseUrl;

  /// Thông báo lỗi (khi state == error).
  final String? message;

  static const idle = UpdateResult(UpdateState.idle);
  static const checking = UpdateResult(UpdateState.checking);
}

/// Dịch vụ kiểm tra cập nhật qua GitHub Releases API.
class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  /// Hỏi GitHub release mới nhất và so sánh với [kAppVersion].
  Future<UpdateResult> check() async {
    final uri = Uri.https(
      'api.github.com',
      '/repos/$_kGithubRepo/releases/latest',
    );

    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
      final request = await client.getUrl(uri);
      // GitHub API yêu cầu User-Agent; nhận JSON dạng v3.
      request.headers.set(HttpHeaders.userAgentHeader, 'BowGo/$kAppVersion');
      request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      final response = await request.close();

      if (response.statusCode != 200) {
        return UpdateResult(
          UpdateState.error,
          message: 'Không kiểm tra được (mã ${response.statusCode}).',
        );
      }

      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;

      final tag = (json['tag_name'] as String?)?.trim();
      final htmlUrl = json['html_url'] as String?;
      if (tag == null || tag.isEmpty) {
        return const UpdateResult(
          UpdateState.error,
          message: 'Không đọc được thông tin phiên bản.',
        );
      }

      // tag dạng "v1.0.4" -> "1.0.4".
      final latest = tag.startsWith('v') ? tag.substring(1) : tag;
      final newer = _isNewer(latest, kAppVersion);

      return UpdateResult(
        newer ? UpdateState.updateAvailable : UpdateState.upToDate,
        latestVersion: latest,
        releaseUrl: htmlUrl,
      );
    } on SocketException {
      return const UpdateResult(
        UpdateState.error,
        message: 'Không có kết nối mạng.',
      );
    } catch (_) {
      return const UpdateResult(
        UpdateState.error,
        message: 'Có lỗi khi kiểm tra cập nhật.',
      );
    } finally {
      client?.close(force: true);
    }
  }

  /// So sánh semver: [candidate] có mới hơn [current] không.
  /// So từng số major.minor.patch; phần thiếu coi như 0. Hậu tố (pre-release)
  /// bị bỏ qua để giữ đơn giản (chỉ so phần số).
  static bool _isNewer(String candidate, String current) {
    final a = _parse(candidate);
    final b = _parse(current);
    for (var i = 0; i < 3; i++) {
      if (a[i] != b[i]) return a[i] > b[i];
    }
    return false;
  }

  /// Tách "1.0.4" (kể cả "1.0.4-beta", "1.0" ) thành [major, minor, patch].
  static List<int> _parse(String v) {
    final core = v.split(RegExp(r'[-+]')).first;
    final parts = core.split('.');
    return List<int>.generate(
      3,
      (i) => i < parts.length ? (int.tryParse(parts[i]) ?? 0) : 0,
    );
  }
}
