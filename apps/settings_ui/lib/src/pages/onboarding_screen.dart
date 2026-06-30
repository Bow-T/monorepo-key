// onboarding_screen.dart
// ----------------------
// Màn chào mừng / cấp quyền, hiện khi bộ gõ còn thiếu quyền macOS. Thay cho dialog
// modal tự nhảy lên (kiểu cũ, gây phiền). Lấy cảm hứng từ onboarding của Raycast,
// Rectangle, Loop: liệt kê các quyền, TỪNG dòng tự đổi sang ✓ theo realtime khi
// người dùng bật quyền trong System Settings — không bật dialog mới, không chặn.
//
// Trạng thái quyền đọc từ status.json (bộ gõ Swift ghi ngầm), poll bởi
// PermissionStatusService. Khi đủ cả 2 quyền, màn này hiện "Sẵn sàng" rồi cho phép
// vào app.

import 'dart:io';

import 'package:flutter/material.dart';

import '../services/permission_status_service.dart';
import '../theme/app_theme.dart';
import '../widgets/pixel.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onContinue});

  /// Gọi khi người dùng chọn vào app (đã đủ quyền hoặc bấm "Để sau").
  final VoidCallback onContinue;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _perm = PermissionStatusService.instance;

  @override
  void initState() {
    super.initState();
    _perm.addListener(_onChange);
  }

  @override
  void dispose() {
    _perm.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  Future<void> _openSettings(String url) async {
    try {
      await Process.run('open', [url]);
      await _perm.refresh();
    } catch (_) {/* bỏ qua */}
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final st = _perm.value;
    final ready = st.ready;

    return Scaffold(
      backgroundColor: t.background,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Tiêu đề chào mừng
                Text(
                  ready ? 'TẤT CẢ ĐÃ SẴN SÀNG' : 'CHÀO MỪNG ĐẾN BOW GO',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AppFonts.head,
                    fontSize: 13,
                    height: 1.5,
                    letterSpacing: 0.5,
                    color: ready ? AppColors.green : t.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  ready
                      ? 'Bộ gõ đã có đủ quyền — gõ tiếng Việt được rồi. '
                          'Bấm “Bắt đầu dùng” để mở cài đặt.'
                      : 'Để gõ tiếng Việt, Bow Go cần 2 quyền của macOS. '
                          'Bật xong quyền nào, dòng đó sẽ tự chuyển sang ✓.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AppFonts.body,
                    fontSize: 15,
                    height: 1.3,
                    color: t.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                // Hai dòng quyền
                _PermStep(
                  index: 1,
                  title: 'Accessibility (Trợ năng)',
                  sub: 'Để gõ thay ký tự vào ứng dụng khác',
                  granted: st.accessibility,
                  onGrant: () => _openSettings(
                    'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                _PermStep(
                  index: 2,
                  title: 'Input Monitoring (Giám sát đầu vào)',
                  sub: 'Để đọc phím bạn gõ',
                  granted: st.inputMonitoring,
                  onGrant: () => _openSettings(
                    'x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent',
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                // Hành động
                if (ready)
                  PixelButton(
                    label: 'Bắt đầu dùng',
                    icon: Icons.check_rounded,
                    color: AppColors.green,
                    onPressed: widget.onContinue,
                  )
                else ...[
                  PixelButton(
                    label: 'Để sau',
                    color: t.textMuted,
                    onPressed: widget.onContinue,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Mẹo: sau khi bật quyền, không cần làm gì thêm — bộ gõ '
                    'tự nhận và bắt đầu chạy.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: AppFonts.body,
                      fontSize: 13,
                      height: 1.3,
                      color: t.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Một bước cấp quyền: số thứ tự + tiêu đề + trạng thái (đã cấp / nút Cấp quyền).
class _PermStep extends StatelessWidget {
  const _PermStep({
    required this.index,
    required this.title,
    required this.sub,
    required this.granted,
    required this.onGrant,
  });

  final int index;
  final String title;
  final String sub;
  final bool granted;
  final VoidCallback onGrant;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return PixelPanel(
      padding: const EdgeInsets.all(14),
      fill: t.panel,
      borderColor: granted ? AppColors.green : null,
      shadowOffset: AppBorders.shadowSm,
      child: Row(
        children: [
          // Huy hiệu: số thứ tự, hoặc ✓ khi đã cấp.
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: granted ? AppColors.green : t.inset,
              border: Border.all(color: t.outline, width: AppBorders.thin),
            ),
            child: granted
                ? const Icon(Icons.check_rounded, size: 18, color: Colors.white)
                : Text(
                    '$index',
                    style: TextStyle(
                      fontFamily: AppFonts.head,
                      fontSize: 10,
                      color: t.textPrimary,
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: AppFonts.body,
                    fontSize: 14,
                    color: t.textPrimary,
                  ),
                ),
                Text(
                  granted ? 'Đã cấp' : sub,
                  style: TextStyle(
                    fontFamily: AppFonts.body,
                    fontSize: 12,
                    color: granted ? AppColors.green : t.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (!granted)
            PixelButton(
              label: 'Cấp quyền',
              icon: Icons.open_in_new_rounded,
              color: AppColors.blue,
              small: true,
              expand: false,
              height: 32,
              onPressed: onGrant,
            ),
        ],
      ),
    );
  }
}
