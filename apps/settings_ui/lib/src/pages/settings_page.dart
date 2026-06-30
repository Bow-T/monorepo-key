// settings_page.dart
// ------------------
// Màn hình cài đặt chính của Bow Key, phong cách pixel/8-bit. Mọi thay đổi được
// auto-save xuống file JSON (SettingsService) để bộ gõ Swift đọc.

import 'package:flutter/material.dart';

import '../models/settings.dart';
import '../services/preview_engine.dart';
import 'convert_tool_page.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import '../widgets/hotkey_recorder.dart';
import '../widgets/pixel.dart';
import '../widgets/pixel_controls.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.onToggleTheme});

  /// Đổi sáng/tối (nút ở header).
  final VoidCallback onToggleTheme;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _service = SettingsService.instance;
  final _testController = TextEditingController();
  String _preview = '';

  BowSettings get s => _service.value;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onSettings);
    _testController.addListener(_recomputePreview);
  }

  @override
  void dispose() {
    _service.removeListener(_onSettings);
    _testController.dispose();
    super.dispose();
  }

  void _onSettings() {
    if (mounted) {
      setState(_recomputePreview);
    }
  }

  void _recomputePreview() {
    final engine =
        PreviewEngine(method: s.method, toneStyle: s.toneStyle);
    setState(() => _preview = engine.transform(_testController.text));
  }

  void _save(BowSettings next) => _service.update(next);

  @override
  Widget build(BuildContext context) {
    final ready = s.enabled;

    return Scaffold(
      body: ScanlineOverlay(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(context, ready),
                    const SizedBox(height: AppSpacing.lg),

                    // ── Nhóm 1: Trạng thái + bật/tắt ──────────────────────
                    PixelPanel(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: SettingRow(
                        title: 'BẬT BỘ GÕ',
                        subtitle: ready
                            ? 'Đang gõ tiếng Việt'
                            : 'Đang tắt — gõ tiếng Anh',
                        control: PixelSwitch(
                          value: s.enabled,
                          onChanged: (v) => _save(s.copyWith(enabled: v)),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),

                    // ── Nhóm 2: Kiểu gõ ───────────────────────────────────
                    _panelWithTitle(
                      context,
                      'KIỂU GÕ',
                      SettingRow(
                        title: 'PHƯƠNG THỨC',
                        subtitle: s.method == InputMethod.telex
                            ? 'aa→â, w→ư, s/f/r/x/j → dấu'
                            : '6→mũ, 7→móc, 8→trăng, 1-5 → dấu',
                        control: PixelSegmented<InputMethod>(
                          value: s.method,
                          options: const [
                            (InputMethod.telex, 'TELEX'),
                            (InputMethod.vni, 'VNI'),
                          ],
                          onChanged: (v) => _save(s.copyWith(method: v)),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),

                    // ── Nhóm 3: Kiểu đặt dấu ──────────────────────────────
                    _panelWithTitle(
                      context,
                      'ĐẶT DẤU THANH',
                      SettingRow(
                        title: 'CHÍNH TẢ',
                        subtitle: s.toneStyle.example,
                        control: PixelSegmented<ToneStyle>(
                          color: AppColors.purple,
                          value: s.toneStyle,
                          options: const [
                            (ToneStyle.modern, 'HIỆN ĐẠI'),
                            (ToneStyle.old, 'KIỂU CŨ'),
                          ],
                          onChanged: (v) => _save(s.copyWith(toneStyle: v)),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),

                    // ── Nhóm 4: Phím tắt ──────────────────────────────────
                    _panelWithTitle(
                      context,
                      'PHÍM TẮT',
                      SettingRow(
                        title: 'BẬT/TẮT NHANH',
                        subtitle: 'Bấm rồi giữ tổ hợp phím mới',
                        control: HotkeyRecorder(
                          hotkey: s.hotkey,
                          onChanged: (hk) => _save(s.copyWith(hotkey: hk)),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),

                    // ── Nhóm 5: Smart Switch ──────────────────────────────
                    _panelWithTitle(
                      context,
                      'SMART SWITCH',
                      SettingRow(
                        title: 'NHỚ THEO APP',
                        subtitle: s.smartSwitch
                            ? 'Tự nhớ bật/tắt cho mỗi app (${s.perApp.length} app)'
                            : 'Bật để tự nhớ trạng thái theo từng app',
                        control: PixelSwitch(
                          value: s.smartSwitch,
                          onChanged: (v) => _save(s.copyWith(smartSwitch: v)),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),

                    // ── Nhóm 6: Tự khôi phục tiếng Anh ────────────────────
                    _panelWithTitle(
                      context,
                      'TỰ KHÔI PHỤC TIẾNG ANH',
                      SettingRow(
                        title: 'KHÔI PHỤC TỪ ANH',
                        subtitle: s.autoRestoreEnglish
                            ? 'Từ biến dạng & không phải tiếng Việt → trả phím gốc'
                            : 'Bật để gõ "terminal", "google"… không bị biến dạng',
                        control: PixelSwitch(
                          value: s.autoRestoreEnglish,
                          onChanged: (v) =>
                              _save(s.copyWith(autoRestoreEnglish: v)),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),

                    // ── Nhóm 7: Gõ tắt / Macro ────────────────────────────
                    _macroPanel(context),
                    const SizedBox(height: AppSpacing.md),

                    // ── Nhóm 8: Gõ thử ────────────────────────────────────
                    _testBox(context),
                    const SizedBox(height: AppSpacing.md),

                    // ── Nhóm 9: Công cụ chuyển mã ─────────────────────────
                    PixelButton(
                      label: 'CÔNG CỤ CHUYỂN MÃ',
                      icon: Icons.swap_horiz_rounded,
                      color: AppColors.cyan,
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const ConvertToolPage(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: AppSpacing.lg),

                    _footer(context),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, bool ready) {
    return Row(
      children: [
        // "Logo" mũi tên pixel.
        PixelPanel(
          padding: const EdgeInsets.all(10),
          shadowOffset: AppBorders.shadowSm,
          fill: AppColors.blue,
          child: const Icon(Icons.keyboard_alt_rounded,
              color: Colors.white, size: 24),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('BOW KEY',
                  style: Theme.of(context).textTheme.displaySmall),
              const SizedBox(height: 4),
              Text('CÀI ĐẶT BỘ GÕ',
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: context.tokens.textMuted)),
            ],
          ),
        ),
        PixelBadge(
          label: ready ? 'VN' : 'EN',
          color: ready ? AppColors.green : AppColors.stone,
          blink: ready,
        ),
        const SizedBox(width: AppSpacing.xs),
        PixelIconButton(
          icon: context.tokens.isDark
              ? Icons.light_mode_rounded
              : Icons.dark_mode_rounded,
          tooltip: 'Đổi sáng/tối',
          onPressed: widget.onToggleTheme,
        ),
      ],
    );
  }

  Widget _panelWithTitle(BuildContext context, String title, Widget body) {
    return PixelPanel(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: context.tokens.textSecondary)),
          const SizedBox(height: AppSpacing.sm),
          body,
        ],
      ),
    );
  }

  Widget _testBox(BuildContext context) {
    final t = context.tokens;
    return PixelPanel(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('GÕ THỬ',
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: t.textSecondary)),
              const Spacer(),
              Text(
                'thử: tieengs · vieejt · hoaf',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: t.textMuted, fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          // Ô nhập thô.
          Container(
            decoration: BoxDecoration(
              color: t.inset,
              border: Border.all(color: t.outline, width: AppBorders.thin),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: TextField(
              controller: _testController,
              cursorColor: AppColors.blue,
              cursorWidth: 3,
              style: TextStyle(
                fontFamily: AppFonts.body,
                fontSize: 20,
                color: t.textPrimary,
                letterSpacing: 0.5,
              ),
              decoration: InputDecoration(
                hintText: 'Gõ ở đây…',
                hintStyle: TextStyle(
                    fontFamily: AppFonts.body, color: t.textMuted),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // Kết quả tiếng Việt.
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 48),
            decoration: BoxDecoration(
              color: AppColors.blue.withValues(alpha: 0.12),
              border: Border.all(color: AppColors.blue, width: AppBorders.thin),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            alignment: Alignment.centerLeft,
            child: Text(
              _preview.isEmpty ? '—' : _preview,
              style: TextStyle(
                fontFamily: AppFonts.body,
                fontSize: 22,
                color: _preview.isEmpty ? t.textMuted : AppColors.blueDark,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Gõ tắt / Macro ──────────────────────────────────────────────────────

  Widget _macroPanel(BuildContext context) {
    final t = context.tokens;
    return PixelPanel(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('GÕ TẮT',
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: t.textSecondary)),
          const SizedBox(height: AppSpacing.sm),
          SettingRow(
            title: 'BẬT GÕ TẮT',
            subtitle: s.macroEnabled
                ? 'Gõ từ khoá + dấu cách → bung nội dung (${s.macros.length} mục)'
                : 'Bật để dùng gõ tắt (vd "vn" → Việt Nam)',
            control: PixelSwitch(
              value: s.macroEnabled,
              onChanged: (v) => _save(s.copyWith(macroEnabled: v)),
            ),
          ),
          if (s.macroEnabled) ...[
            const SizedBox(height: AppSpacing.sm),
            for (var i = 0; i < s.macros.length; i++) _macroRow(context, i),
            const SizedBox(height: AppSpacing.sm),
            PixelButton(
              label: 'THÊM GÕ TẮT',
              icon: Icons.add_rounded,
              color: AppColors.green,
              small: true,
              onPressed: () => _editMacro(context, null),
            ),
          ],
        ],
      ),
    );
  }

  Widget _macroRow(BuildContext context, int index) {
    final t = context.tokens;
    final m = s.macros[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Container(
        decoration: BoxDecoration(
          color: t.inset,
          border: Border.all(color: t.outline, width: AppBorders.thin),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            // Từ khoá (badge)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              color: AppColors.green.withValues(alpha: 0.18),
              child: Text(
                m.keyword,
                style: TextStyle(
                    fontFamily: AppFonts.body,
                    fontSize: 16,
                    color: t.textPrimary),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_forward_rounded, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                m.type == 'staticText' ? m.content : '${m.content}  (${m.type})',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontFamily: AppFonts.body,
                    fontSize: 16,
                    color: t.textSecondary),
              ),
            ),
            PixelIconButton(
              icon: Icons.edit_rounded,
              iconSize: 15,
              size: 32,
              tooltip: 'Sửa',
              onPressed: () => _editMacro(context, index),
            ),
            const SizedBox(width: 4),
            PixelIconButton(
              icon: Icons.delete_outline_rounded,
              iconSize: 15,
              size: 32,
              tooltip: 'Xoá',
              color: AppColors.red,
              onPressed: () {
                final next = [...s.macros]..removeAt(index);
                _save(s.copyWith(macros: next));
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Mở hộp thoại thêm/sửa macro. `index` null = thêm mới.
  Future<void> _editMacro(BuildContext context, int? index) async {
    final existing = index != null ? s.macros[index] : null;
    final keywordCtrl = TextEditingController(text: existing?.keyword ?? '');
    final contentCtrl = TextEditingController(text: existing?.content ?? '');

    final result = await showDialog<MacroEntry>(
      context: context,
      builder: (ctx) {
        final t = ctx.tokens;
        return AlertDialog(
          backgroundColor: t.panel,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: t.outline, width: AppBorders.thin),
            borderRadius: BorderRadius.zero,
          ),
          title: Text(index == null ? 'THÊM GÕ TẮT' : 'SỬA GÕ TẮT',
              style: Theme.of(ctx).textTheme.labelSmall),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('TỪ KHOÁ (vd: vn)',
                  style: Theme.of(ctx)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: t.textMuted, fontSize: 13)),
              const SizedBox(height: 4),
              _dialogField(ctx, keywordCtrl, 'vn'),
              const SizedBox(height: 12),
              Text('NỘI DUNG (vd: Việt Nam)',
                  style: Theme.of(ctx)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: t.textMuted, fontSize: 13)),
              const SizedBox(height: 4),
              _dialogField(ctx, contentCtrl, 'Việt Nam'),
            ],
          ),
          actions: [
            PixelButton(
              label: 'HUỶ',
              color: AppColors.stone,
              small: true,
              expand: false,
              onPressed: () => Navigator.pop(ctx),
            ),
            PixelButton(
              label: 'LƯU',
              color: AppColors.green,
              small: true,
              expand: false,
              onPressed: () {
                final kw = keywordCtrl.text.trim();
                final ct = contentCtrl.text;
                if (kw.isEmpty) return;
                Navigator.pop(
                    ctx, MacroEntry(keyword: kw, content: ct));
              },
            ),
          ],
        );
      },
    );

    if (result == null) return;
    final next = [...s.macros];
    // Bỏ macro trùng từ khoá (giữ bản mới).
    next.removeWhere((m) => m.keyword == result.keyword &&
        (index == null || s.macros[index].keyword != result.keyword));
    if (index != null) {
      next[index] = result;
    } else {
      next.add(result);
    }
    _save(s.copyWith(macros: next));
  }

  Widget _dialogField(
      BuildContext context, TextEditingController ctrl, String hint) {
    final t = context.tokens;
    return Container(
      decoration: BoxDecoration(
        color: t.inset,
        border: Border.all(color: t.outline, width: AppBorders.thin),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: TextField(
        controller: ctrl,
        cursorColor: AppColors.green,
        cursorWidth: 3,
        style: TextStyle(
            fontFamily: AppFonts.body, fontSize: 18, color: t.textPrimary),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle:
              TextStyle(fontFamily: AppFonts.body, color: t.textMuted),
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  Widget _footer(BuildContext context) {
    final t = context.tokens;
    return Column(
      children: [
        Text(
          'Tự động lưu • bộ gõ Swift đọc cùng file',
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: t.textMuted, fontSize: 15),
        ),
        const SizedBox(height: 4),
        Text(
          _service.path,
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: t.textMuted, fontSize: 13),
        ),
      ],
    );
  }
}
