// settings_page.dart
// ------------------
// Màn hình cài đặt chính của Bow Go, phong cách pixel/8-bit RPG (như Stardew Valley).
// Bố cục dual-pane: Sidebar bên trái, nội dung cài đặt cuộn bên phải.
// Tự động lưu cấu hình xuống file JSON để bộ gõ Swift đồng bộ.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:viet_engine/viet_engine.dart' hide InputMethod, ToneStyle;

import '../models/settings.dart';
import '../services/permission_status_service.dart';
import '../services/preview_engine.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import '../widgets/hotkey_recorder.dart';
import '../widgets/pixel.dart';
import '../widgets/pixel_controls.dart';

/// Các tab chức năng trong menu cài đặt.
enum SettingsTab { general, shortcuts, clipboard, macros, convert, troubleshoot, about }

/// Các phép biến đổi cho công cụ chuyển mã.
enum _Op { none, removeDiacritics, upper, lower, capWords, capFirst }

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.onToggleTheme});

  /// Đổi sáng/tối (nút ở header).
  final VoidCallback onToggleTheme;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _service = SettingsService.instance;
  final _permStatus = PermissionStatusService.instance;
  final _testController = TextEditingController();
  String _preview = '';

  // Tab hiện tại đang chọn
  SettingsTab _activeTab = SettingsTab.general;

  // Trạng thái cho công cụ chuyển mã (Tab Chuyển mã)
  final _input = TextEditingController();
  CodeTable _from = CodeTable.unicode;
  CodeTable _to = CodeTable.unicode;
  _Op _op = _Op.none;

  BowSettings get s => _service.value;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onSettings);
    _permStatus.addListener(_onPermStatus);
    _testController.addListener(_recomputePreview);
    _input.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _service.removeListener(_onSettings);
    _permStatus.removeListener(_onPermStatus);
    _testController.dispose();
    _input.dispose();
    super.dispose();
  }

  void _onPermStatus() {
    if (mounted) setState(() {});
  }

  void _onSettings() {
    if (mounted) {
      setState(_recomputePreview);
    }
  }

  void _recomputePreview() {
    final engine = PreviewEngine(method: s.method, toneStyle: s.toneStyle);
    setState(() => _preview = engine.transform(_testController.text));
  }

  void _save(BowSettings next) => _service.update(next);

  /// Tính kết quả của công cụ chuyển mã.
  String get _convertOutput {
    var text = _input.text;
    if (text.isEmpty) return '';
    if (_from != _to) {
      text = TextConverter.convert(text, from: _from, to: _to);
    }
    switch (_op) {
      case _Op.none:
        break;
      case _Op.removeDiacritics:
        text = TextConverter.removeDiacritics(text);
      case _Op.upper:
        text = TextConverter.changeCase(text, LetterCase.allUpper);
      case _Op.lower:
        text = TextConverter.changeCase(text, LetterCase.allLower);
      case _Op.capWords:
        text = TextConverter.changeCase(text, LetterCase.capitalizeWords);
      case _Op.capFirst:
        text = TextConverter.changeCase(text, LetterCase.capitalizeFirst);
    }
    return text;
  }

  @override
  Widget build(BuildContext context) {
    final ready = s.enabled;
    final t = context.tokens;

    return Scaffold(
      body: ScanlineOverlay(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820, maxHeight: 600),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: PixelPanel(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header
                      _header(context, ready),
                      const SizedBox(height: AppSpacing.sm),
                      Container(height: AppBorders.thin, color: t.outline),
                      const SizedBox(height: AppSpacing.md),

                      // Body Row (Sidebar + Content Panel)
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Left Sidebar (Navigation)
                            _buildSidebar(context),
                            const SizedBox(width: AppSpacing.md),
                            // Phân tách bằng nét liền dọc
                            Container(width: AppBorders.thin, color: t.outline),
                            const SizedBox(width: AppSpacing.md),
                            // Right Content Pane (Detailed Tab settings)
                            Expanded(
                              child: _buildContentPane(context),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: AppSpacing.md),
                      Container(height: AppBorders.thin, color: t.outline),
                      const SizedBox(height: AppSpacing.sm),
                      _footer(context),
                    ],
                  ),
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
        PixelPanel(
          padding: const EdgeInsets.all(8),
          shadowOffset: AppBorders.shadowSm,
          fill: AppColors.blue,
          child: const Icon(Icons.keyboard_alt_rounded,
              color: Colors.white, size: 20),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('BOW GO',
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(fontSize: 16)),
              const SizedBox(height: 2),
              Text('CÀI ĐẶT BỘ GÕ · RETRO RPG EDITION',
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: context.tokens.textMuted, fontSize: 6)),
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
          size: 32,
          iconSize: 16,
          tooltip: 'Đổi sáng/tối',
          onPressed: widget.onToggleTheme,
        ),
      ],
    );
  }

  // ── Sidebar Navigation ──────────────────────────────────────────────────

  Widget _buildSidebar(BuildContext context) {
    return SizedBox(
      width: 175,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSidebarTab(SettingsTab.general, Icons.settings_rounded, 'BỘ GÕ'),
          _buildSidebarTab(SettingsTab.shortcuts, Icons.bolt_rounded, 'PHÍM TẮT'),
          _buildSidebarTab(SettingsTab.clipboard, Icons.assignment_rounded, 'CLIPBOARD'),
          _buildSidebarTab(SettingsTab.macros, Icons.text_snippet_rounded, 'GÕ TẮT'),
          _buildSidebarTab(SettingsTab.convert, Icons.swap_horiz_rounded, 'CHUYỂN MÃ'),
          _buildSidebarTab(SettingsTab.troubleshoot, Icons.build_rounded, 'SỬA LỖI'),
          _buildSidebarTab(SettingsTab.about, Icons.info_outline_rounded, 'THÔNG TIN'),
        ],
      ),
    );
  }

  Widget _buildSidebarTab(SettingsTab tab, IconData icon, String label) {
    final selected = _activeTab == tab;
    final t = context.tokens;

    return PixelHover(
      onTap: () => setState(() => _activeTab = tab),
      builder: (hovering) {
        // Pixel RPG style: chọn thì thụt lùi/nhấn xẹp shadow, hover thì dịch nhẹ sang phải.
        final offset = selected ? 6.0 : (hovering ? 3.0 : 0.0);
        return AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.stepped,
          margin: EdgeInsets.only(left: offset, bottom: AppSpacing.xs),
          child: PixelPanel(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            shadowOffset: selected ? 0.0 : AppBorders.shadowSm,
            fill: selected ? AppColors.blue : (hovering ? t.inset : Colors.transparent),
            borderColor: selected ? t.outline : (hovering ? t.outline : Colors.transparent),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 14,
                  color: selected ? Colors.white : (hovering ? t.textPrimary : t.textSecondary),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontFamily: AppFonts.head,
                      fontSize: 8,
                      color: selected ? Colors.white : (hovering ? t.textPrimary : t.textSecondary),
                    ),
                  ),
                ),
                if (selected)
                  const Text(
                    '◀',
                    style: TextStyle(
                      fontFamily: AppFonts.head,
                      fontSize: 8,
                      color: Colors.white,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Content Area & Tabs ─────────────────────────────────────────────────

  Widget _buildContentPane(BuildContext context) {
    final t = context.tokens;

    return PixelPanel(
      padding: EdgeInsets.zero,
      fill: t.inset,
      child: ClipRRect(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              switch (_activeTab) {
                SettingsTab.general => _buildGeneralTab(context),
                SettingsTab.shortcuts => _buildShortcutsTab(context),
                SettingsTab.clipboard => _buildClipboardTab(context),
                SettingsTab.macros => _buildMacrosTab(context),
                SettingsTab.convert => _buildConvertTab(context),
                SettingsTab.troubleshoot => _buildTroubleshootTab(context),
                SettingsTab.about => _buildAboutTab(context),
              }
            ],
          ),
        ),
      ),
    );
  }

  Widget _tabSectionTitle(String text) {
    final t = context.tokens;
    return Text(
      text,
      style: TextStyle(
        fontFamily: AppFonts.head,
        fontSize: 8,
        color: t.textSecondary,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _tabDivider() {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Container(
        height: AppBorders.thin,
        color: t.outline.withValues(alpha: 0.15),
      ),
    );
  }

  Widget _buildPixelInfoCard(BuildContext context, String title, String content) {
    final t = context.tokens;
    return PixelPanel(
      padding: const EdgeInsets.all(12),
      fill: t.panel,
      shadowOffset: AppBorders.shadowSm,
      borderColor: AppColors.yellow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_rounded, color: AppColors.yellow, size: 14),
              const SizedBox(width: 8),
              Text(
                title.toUpperCase(),
                style: const TextStyle(
                  fontFamily: AppFonts.head,
                  fontSize: 7,
                  color: AppColors.yellow,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: TextStyle(
              fontFamily: AppFonts.body,
              fontSize: 15,
              color: t.textSecondary,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  // ── Tab 1: Bộ gõ ────────────────────────────────────────────────────────

  Widget _buildGeneralTab(BuildContext context) {
    final ready = s.enabled;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _tabSectionTitle('TRẠNG THÁI BỘ GÕ'),
        const SizedBox(height: AppSpacing.sm),
        SettingRow(
          title: 'KÍCH HOẠT BỘ GÕ',
          subtitle: ready ? 'Đang bật gõ tiếng Việt' : 'Đang gõ tiếng Anh thô',
          control: PixelSwitch(
            value: s.enabled,
            onChanged: (v) => _save(s.copyWith(enabled: v)),
          ),
        ),
        _tabDivider(),

        _tabSectionTitle('PHƯƠNG THỨC GÕ'),
        const SizedBox(height: AppSpacing.sm),
        SettingRow(
          title: 'KIỂU GÕ',
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
        _tabDivider(),

        _tabSectionTitle('ĐẶT DẤU THANH'),
        const SizedBox(height: AppSpacing.sm),
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
        _tabDivider(),

        _tabSectionTitle('TÍNH NĂNG THÔNG MINH'),
        const SizedBox(height: AppSpacing.sm),
        SettingRow(
          title: 'SMART SWITCH',
          subtitle: s.smartSwitch
              ? 'Tự nhớ bật/tắt cho mỗi app (${s.perApp.length} app)'
              : 'Tự nhớ trạng thái theo từng app',
          control: PixelSwitch(
            value: s.smartSwitch,
            onChanged: (v) => _save(s.copyWith(smartSwitch: v)),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        SettingRow(
          title: 'TỰ KHÔI PHỤC',
          subtitle: s.autoRestoreEnglish
              ? 'Trả phím gốc khi gõ từ tiếng Anh không hợp lệ'
              : 'Bật để gõ "terminal", "google"… không bị lỗi',
          control: PixelSwitch(
            value: s.autoRestoreEnglish,
            onChanged: (v) => _save(s.copyWith(autoRestoreEnglish: v)),
          ),
        ),
        _tabDivider(),

        _buildTestBoxInline(context),
      ],
    );
  }

  Widget _buildTestBoxInline(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _tabSectionTitle('KHU VỰC GÕ THỬ'),
        const SizedBox(height: AppSpacing.sm),
        Container(
          decoration: BoxDecoration(
            color: t.panel,
            border: Border.all(color: t.outline, width: AppBorders.thin),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: TextField(
            controller: _testController,
            cursorColor: AppColors.blue,
            cursorWidth: 3,
            style: TextStyle(
              fontFamily: AppFonts.body,
              fontSize: 18,
              color: t.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: 'Gõ thử tiếng Việt ở đây…',
              hintStyle: TextStyle(
                  fontFamily: AppFonts.body, color: t.textMuted),
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 44),
          decoration: BoxDecoration(
            color: AppColors.blue.withValues(alpha: 0.12),
            border: Border.all(color: AppColors.blue, width: AppBorders.thin),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          alignment: Alignment.centerLeft,
          child: Text(
            _preview.isEmpty ? '—' : _preview,
            style: TextStyle(
              fontFamily: AppFonts.body,
              fontSize: 18,
              color: _preview.isEmpty ? t.textMuted : AppColors.blueDark,
            ),
          ),
        ),
      ],
    );
  }

  // ── Tab 2: Phím tắt ──────────────────────────────────────────────────────

  Widget _buildShortcutsTab(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _tabSectionTitle('BẬT/TẮT BỘ GÕ'),
        const SizedBox(height: AppSpacing.sm),
        SettingRow(
          title: 'PHÍM TẮT BỘ GÕ',
          subtitle: 'Tổ hợp chuyển chế độ gõ (⌃⇧ mặc định)',
          control: HotkeyRecorder(
            hotkey: s.hotkey,
            onChanged: (hk) => _save(s.copyWith(hotkey: hk)),
          ),
        ),
        _tabDivider(),

        _tabSectionTitle('LỊCH SỬ CLIPBOARD'),
        const SizedBox(height: AppSpacing.sm),
        SettingRow(
          title: 'PHÍM TẮT CLIPBOARD',
          subtitle: 'Mở overlay HUD lịch sử copy (^V mặc định)',
          control: HotkeyRecorder(
            hotkey: s.clipboardHistoryHotkey,
            onChanged: (hk) => _save(s.copyWith(clipboardHistoryHotkey: hk)),
          ),
        ),
        _tabDivider(),

        _buildPixelInfoCard(
          context,
          'LƯU Ý VỀ PHÍM TẮT',
          '• Phím tắt chỉ-modifier (như Ctrl+Shift) cần nhấn đúng các phím và nhả ra để kích hoạt.\n'
          '• Phím tắt có phím chữ (như Ctrl+V) cần được giữ kết hợp cùng phím chữ.\n'
          '• Nhấn Esc hoặc click bên ngoài để đóng bảng lịch sử clipboard.',
        ),
      ],
    );
  }

  // ── Tab 3: Clipboard ────────────────────────────────────────────────────

  Widget _buildClipboardTab(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _tabSectionTitle('LỊCH SỬ SAO CHÉP'),
        const SizedBox(height: AppSpacing.sm),
        SettingRow(
          title: 'BẬT LỊCH SỬ CLIPBOARD',
          subtitle: s.clipboardHistoryEnabled
              ? 'Lưu tạm các văn bản đã sao chép'
              : 'Bật để lưu và xem lại lịch sử copy',
          control: PixelSwitch(
            value: s.clipboardHistoryEnabled,
            onChanged: (v) => _save(s.copyWith(clipboardHistoryEnabled: v)),
          ),
        ),
        if (s.clipboardHistoryEnabled) ...[
          _tabDivider(),
          _tabSectionTitle('GIỚI HẠN BỘ NHỚ'),
          const SizedBox(height: AppSpacing.sm),
          SettingRow(
            title: 'SỐ MỤC TỐI ĐA',
            subtitle: 'Giới hạn tối đa (${s.clipboardHistoryLimit} mục)',
            control: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PixelIconButton(
                  icon: Icons.remove_rounded,
                  iconSize: 14,
                  size: 32,
                  onPressed: s.clipboardHistoryLimit > 10
                      ? () => _save(s.copyWith(clipboardHistoryLimit: s.clipboardHistoryLimit - 10))
                      : () {},
                ),
                Container(
                  width: 48,
                  alignment: Alignment.center,
                  child: Text(
                    '${s.clipboardHistoryLimit}',
                    style: TextStyle(
                      fontFamily: AppFonts.head,
                      fontSize: 10,
                      color: t.textPrimary,
                    ),
                  ),
                ),
                PixelIconButton(
                  icon: Icons.add_rounded,
                  iconSize: 14,
                  size: 32,
                  onPressed: s.clipboardHistoryLimit < 100
                      ? () => _save(s.copyWith(clipboardHistoryLimit: s.clipboardHistoryLimit + 10))
                      : () {},
                ),
              ],
            ),
          ),
        ],
        _tabDivider(),
        _buildPixelInfoCard(
          context,
          'BẢO MẬT AN TOÀN',
          'Bộ gõ tự động bỏ qua các dữ liệu nhạy cảm được sao chép từ các ứng dụng quản lý mật khẩu như Keychain Access, 1Password, Bitwarden, KeePassXC... hoặc các ứng dụng đánh dấu Transient/Concealed.',
        ),
      ],
    );
  }

  // ── Tab 4: Gõ tắt / Macro ───────────────────────────────────────────────

  Widget _buildMacrosTab(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _tabSectionTitle('CẤU HÌNH GÕ TẮT'),
        const SizedBox(height: AppSpacing.sm),
        SettingRow(
          title: 'SỬ DỤNG GÕ TẮT',
          subtitle: s.macroEnabled
              ? 'Gõ từ viết tắt + Space → bung từ đầy đủ'
              : 'Bật để kích hoạt tính năng gõ tắt',
          control: PixelSwitch(
            value: s.macroEnabled,
            onChanged: (v) => _save(s.copyWith(macroEnabled: v)),
          ),
        ),
        if (s.macroEnabled) ...[
          _tabDivider(),
          Row(
            children: [
              _tabSectionTitle('DANH SÁCH MỤC GÕ TẮT'),
              const Spacer(),
              PixelButton(
                label: 'THÊM MỚI',
                icon: Icons.add_rounded,
                color: AppColors.green,
                small: true,
                expand: false,
                height: 32,
                onPressed: () => _editMacro(context, null),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (s.macros.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24),
              alignment: Alignment.center,
              child: Text(
                '(Chưa cấu hình từ viết tắt nào)',
                style: TextStyle(
                  fontFamily: AppFonts.body,
                  fontSize: 16,
                  color: t.textMuted,
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: s.macros.length,
              itemBuilder: (ctx, index) => _macroRow(context, index),
            ),
        ],
      ],
    );
  }

  // ── Tab 5: Chuyển mã (Integrated Convert Tool) ──────────────────────────

  Widget _buildConvertTab(BuildContext context) {
    final t = context.tokens;
    final out = _convertOutput;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _tabSectionTitle('CHUYỂN ĐỔI BẢNG MÃ'),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(child: _codeDropdown(context, _from, (v) => setState(() => _from = v))),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Icon(Icons.arrow_forward_rounded, size: 16),
            ),
            Expanded(child: _codeDropdown(context, _to, (v) => setState(() => _to = v))),
          ],
        ),
        _tabDivider(),

        _tabSectionTitle('PHÉP BIẾN ĐỔI CHỮ'),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            _opChip(context, _Op.none, 'GIỮ NGUYÊN'),
            _opChip(context, _Op.removeDiacritics, 'BỎ DẤU'),
            _opChip(context, _Op.upper, 'HOA HẾT'),
            _opChip(context, _Op.lower, 'THƯỜNG HẾT'),
            _opChip(context, _Op.capWords, 'HOA MỖI TỪ'),
            _opChip(context, _Op.capFirst, 'HOA ĐẦU CÂU'),
          ],
        ),
        _tabDivider(),

        _tabSectionTitle('VĂN BẢN NGUỒN'),
        const SizedBox(height: AppSpacing.sm),
        Container(
          decoration: BoxDecoration(
            color: t.panel,
            border: Border.all(color: t.outline, width: AppBorders.thin),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: TextField(
            controller: _input,
            maxLines: 3,
            minLines: 2,
            cursorColor: AppColors.cyan,
            cursorWidth: 3,
            style: TextStyle(
                fontFamily: AppFonts.body,
                fontSize: 16,
                color: t.textPrimary),
            decoration: InputDecoration(
              hintText: 'Dán hoặc nhập văn bản gốc tại đây…',
              hintStyle: TextStyle(
                  fontFamily: AppFonts.body, color: t.textMuted),
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),
        _tabDivider(),

        _tabSectionTitle('KẾT QUẢ BIẾN ĐỔI'),
        const SizedBox(height: AppSpacing.sm),
        Container(
          constraints: const BoxConstraints(minHeight: 56),
          decoration: BoxDecoration(
            color: AppColors.cyan.withValues(alpha: 0.12),
            border: Border.all(color: AppColors.cyan, width: AppBorders.thin),
          ),
          padding: const EdgeInsets.all(10),
          alignment: Alignment.topLeft,
          child: SelectableText(
            out.isEmpty ? '—' : out,
            style: TextStyle(
              fontFamily: AppFonts.body,
              fontSize: 16,
              color: out.isEmpty ? t.textMuted : t.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        PixelButton(
          label: 'COPY KẾT QUẢ',
          icon: Icons.copy_rounded,
          color: AppColors.cyan,
          height: 38,
          onPressed: out.isEmpty
              ? null
              : () {
                  Clipboard.setData(ClipboardData(text: out));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Đã copy kết quả vào clipboard'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
        ),
      ],
    );
  }

  Widget _codeDropdown(
      BuildContext context, CodeTable value, ValueChanged<CodeTable> onChanged) {
    final t = context.tokens;
    return Container(
      decoration: BoxDecoration(
        color: t.panel,
        border: Border.all(color: t.outline, width: AppBorders.thin),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<CodeTable>(
          value: value,
          isExpanded: true,
          dropdownColor: t.panel,
          style: TextStyle(
              fontFamily: AppFonts.body, fontSize: 16, color: t.textPrimary),
          items: const [
            DropdownMenuItem(value: CodeTable.unicode, child: Text('Unicode')),
            DropdownMenuItem(value: CodeTable.tcvn3, child: Text('TCVN3 (ABC)')),
            DropdownMenuItem(
                value: CodeTable.vniWindows, child: Text('VNI-Windows')),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }

  Widget _opChip(BuildContext context, _Op op, String label) {
    final selected = _op == op;
    final t = context.tokens;
    return GestureDetector(
      onTap: () => setState(() => _op = op),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.purple : t.panel,
          border: Border.all(color: t.outline, width: AppBorders.thin),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: AppFonts.body,
            fontSize: 14,
            color: selected ? Colors.white : t.textSecondary,
          ),
        ),
      ),
    );
  }

  // ── Tab 6: Thông tin ────────────────────────────────────────────────────

  // ── Tab: Sửa lỗi ────────────────────────────────────────────────────────

  Widget _buildTroubleshootTab(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Trạng thái quyền ──────────────────────────────────────────────
        _tabSectionTitle('TRẠNG THÁI QUYỀN'),
        const SizedBox(height: AppSpacing.sm),
        _buildPermissionStatus(context),
        _tabDivider(),

        _tabSectionTitle('KHI GÕ KHÔNG ĐƯỢC TIẾNG VIỆT'),
        const SizedBox(height: AppSpacing.sm),
        PixelPanel(
          padding: const EdgeInsets.all(16),
          fill: t.panel,
          shadowOffset: AppBorders.shadowSm,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Nếu bộ gõ bỗng không nhận tiếng Việt (icon hiện EN, gõ ra '
                'tiếng Anh thô), thử lần lượt 2 bước dưới đây.',
                style: TextStyle(
                  fontFamily: AppFonts.body,
                  fontSize: 15,
                  height: 1.2,
                  color: t.textSecondary,
                ),
              ),
            ],
          ),
        ),
        _tabDivider(),

        // Bước 1: nhẹ
        _tabSectionTitle('BƯỚC 1 — KHỞI ĐỘNG LẠI BỘ GÕ'),
        const SizedBox(height: AppSpacing.sm),
        SettingRow(
          title: 'KHỞI ĐỘNG LẠI BỘ GÕ',
          subtitle: 'Bật lại engine khi bị treo (không đụng quyền)',
          control: PixelButton(
            label: 'CHẠY',
            icon: Icons.refresh_rounded,
            color: AppColors.blue,
            small: true,
            expand: false,
            height: 32,
            onPressed: _restartEngine,
          ),
        ),
        _tabDivider(),

        // Bước 2: mạnh
        _tabSectionTitle('BƯỚC 2 — SỬA LỖI QUYỀN'),
        const SizedBox(height: AppSpacing.sm),
        SettingRow(
          title: 'RESET & CẤP LẠI QUYỀN',
          subtitle: 'Khi đã cấp quyền mà vẫn không gõ được',
          control: PixelButton(
            label: 'SỬA',
            icon: Icons.lock_reset_rounded,
            color: AppColors.red,
            small: true,
            expand: false,
            height: 32,
            onPressed: () => _repairPermissions(context),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        PixelPanel(
          padding: const EdgeInsets.all(14),
          fill: t.inset,
          shadowOffset: AppBorders.shadowSm,
          borderWidth: AppBorders.thin,
          child: Text(
            'Vì sao cần "Sửa lỗi quyền"? Mỗi lần cập nhật app, macOS có thể '
            'quên quyền cũ dù công tắc vẫn xanh. Thao tác này xoá quyền cũ rồi '
            'mở Cài đặt để bạn bật lại — gắn quyền với bản app hiện tại.',
            style: TextStyle(
              fontFamily: AppFonts.body,
              fontSize: 14,
              height: 1.2,
              color: t.textMuted,
            ),
          ),
        ),
      ],
    );
  }

  /// Khối "Trạng thái quyền": cho biết quyền nào đã/chưa cấp, ngay trong app.
  /// Dữ liệu do bộ gõ Swift ghi ra status.json, cập nhật mỗi vài giây.
  Widget _buildPermissionStatus(BuildContext context) {
    final t = context.tokens;
    final st = _permStatus.value;

    if (!st.known) {
      // Chưa đọc được status (bộ gõ chưa chạy lần nào trên máy này).
      return PixelPanel(
        padding: const EdgeInsets.all(14),
        fill: t.inset,
        shadowOffset: AppBorders.shadowSm,
        borderWidth: AppBorders.thin,
        child: Text(
          'Chưa rõ trạng thái quyền — hãy mở bộ gõ Bow Go ít nhất một lần. '
          'Sau khi bộ gõ chạy, mục này sẽ hiện quyền nào đã/chưa cấp.',
          style: TextStyle(
            fontFamily: AppFonts.body,
            fontSize: 14,
            height: 1.2,
            color: t.textMuted,
          ),
        ),
      );
    }

    return PixelPanel(
      padding: const EdgeInsets.all(16),
      fill: t.panel,
      shadowOffset: AppBorders.shadowSm,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (st.ready)
            _permSummaryLine(
              context,
              ok: true,
              text: 'Đã cấp đủ quyền — bộ gõ sẵn sàng hoạt động.',
            )
          else
            _permSummaryLine(
              context,
              ok: false,
              text: 'Còn thiếu quyền — bộ gõ chưa gõ được tiếng Việt.',
            ),
          const SizedBox(height: AppSpacing.sm),
          _permissionRow(
            context,
            label: 'Accessibility (Trợ năng)',
            sub: 'Để gõ thay ký tự vào ứng dụng khác',
            granted: st.accessibility,
            settingsUrl:
                'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility',
          ),
          const SizedBox(height: AppSpacing.sm),
          _permissionRow(
            context,
            label: 'Input Monitoring (Giám sát đầu vào)',
            sub: 'Để đọc phím bạn gõ',
            granted: st.inputMonitoring,
            settingsUrl:
                'x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent',
          ),
        ],
      ),
    );
  }

  /// Dòng tóm tắt trên cùng (đủ quyền / thiếu quyền).
  Widget _permSummaryLine(BuildContext context,
      {required bool ok, required String text}) {
    return Row(
      children: [
        Icon(
          ok ? Icons.check_circle_rounded : Icons.error_rounded,
          color: ok ? AppColors.green : AppColors.red,
          size: 20,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontFamily: AppFonts.body,
              fontSize: 15,
              height: 1.2,
              color: context.tokens.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  /// Một dòng quyền: trạng thái đã/chưa cấp + nút mở trang Settings tương ứng.
  Widget _permissionRow(
    BuildContext context, {
    required String label,
    required String sub,
    required bool granted,
    required String settingsUrl,
  }) {
    final t = context.tokens;
    return Row(
      children: [
        Icon(
          granted ? Icons.check_circle_rounded : Icons.cancel_rounded,
          color: granted ? AppColors.green : AppColors.red,
          size: 18,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
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
        if (!granted)
          PixelButton(
            label: 'CẤP',
            icon: Icons.open_in_new_rounded,
            color: AppColors.blue,
            small: true,
            expand: false,
            height: 32,
            onPressed: () => _openSettingsUrl(settingsUrl),
          ),
      ],
    );
  }

  /// Mở một trang con trong System Settings.
  Future<void> _openSettingsUrl(String url) async {
    try {
      await Process.run('open', [url]);
      // Đọc lại trạng thái sớm để UI cập nhật ngay sau khi người dùng bật quyền.
      await _permStatus.refresh();
    } catch (_) {
      if (mounted) _showSnack('Không mở được Cài đặt.');
    }
  }

  /// Bước 1 — nhẹ: bảo bộ gõ Swift tự khởi động lại qua menu/relaunch.
  /// Cách đơn giản & chắc: kill tiến trình "Bow Go" để nó được mở lại sạch.
  Future<void> _restartEngine() async {
    try {
      // Bộ gõ Swift có healthCheck tự bật lại tap; cách chắc là relaunch nó.
      await Process.run('pkill', ['-x', 'Bow Go']);
      // Mở lại app bộ gõ (đường dẫn cài chuẩn).
      await Process.run('open', ['-n', '/Applications/Bow Go.app']);
      if (mounted) {
        _showSnack('Đã khởi động lại bộ gõ.');
      }
    } catch (_) {
      if (mounted) _showSnack('Không khởi động lại được — thử qua menu bar.');
    }
  }

  /// Bước 2 — mạnh: reset quyền TCC cho bộ gõ rồi mở Settings + relaunch.
  Future<void> _repairPermissions(BuildContext context) async {
    final ok = await _confirmDialog(
      context,
      title: 'Sửa lỗi quyền?',
      message: 'Sẽ xoá quyền cũ của Bow Go (Accessibility + Input Monitoring), '
          'mở Cài đặt để bạn bật lại, rồi khởi động lại bộ gõ.',
      confirmLabel: 'SỬA NGAY',
    );
    if (!ok) return;

    const bundleId = 'com.bowgo.keyboard';
    for (final service in ['Accessibility', 'ListenEvent', 'PostEvent']) {
      try {
        await Process.run('tccutil', ['reset', service, bundleId]);
      } catch (_) {/* bỏ qua */}
    }

    // Mở 2 trang Settings liên quan.
    await Process.run('open', [
      'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility'
    ]);
    await Process.run('open', [
      'x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent'
    ]);

    // Khởi động lại bộ gõ để gắn quyền mới.
    await Process.run('pkill', ['-x', 'Bow Go']);
    await Process.run('open', ['-n', '/Applications/Bow Go.app']);

    if (mounted) {
      _showSnack('Đã reset quyền. Bật lại Bow Go trong Cài đặt vừa mở.');
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<bool> _confirmDialog(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final t = context.tokens;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: PixelPanel(
          padding: const EdgeInsets.all(18),
          fill: t.panel,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title.toUpperCase(),
                style: const TextStyle(
                  fontFamily: AppFonts.head,
                  fontSize: 11,
                  color: AppColors.red,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                message,
                style: TextStyle(
                  fontFamily: AppFonts.body,
                  fontSize: 15,
                  height: 1.2,
                  color: t.textSecondary,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: PixelButton(
                      label: 'HUỶ',
                      color: t.textMuted,
                      height: 38,
                      onPressed: () => Navigator.of(ctx).pop(false),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: PixelButton(
                      label: confirmLabel,
                      color: AppColors.red,
                      height: 38,
                      onPressed: () => Navigator.of(ctx).pop(true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    return result ?? false;
  }

  Widget _buildAboutTab(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _tabSectionTitle('VỀ BOW GO'),
        const SizedBox(height: AppSpacing.sm),
        PixelPanel(
          padding: const EdgeInsets.all(16),
          fill: t.panel,
          shadowOffset: AppBorders.shadowSm,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'BOW GO',
                style: TextStyle(
                  fontFamily: AppFonts.head,
                  fontSize: 16,
                  color: AppColors.blueDark,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Phiên bản v1.0.1',
                style: TextStyle(
                  fontFamily: AppFonts.body,
                  fontSize: 15,
                  color: t.textMuted,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Bộ gõ tiếng Việt mã nguồn mở thiết kế theo phong cách 8-bit retro độc đáo cho macOS.',
                style: TextStyle(
                  fontFamily: AppFonts.body,
                  fontSize: 16,
                  color: t.textSecondary,
                ),
              ),
            ],
          ),
        ),
        _tabDivider(),

        _tabSectionTitle('ĐƯỜNG DẪN CẤU HÌNH'),
        const SizedBox(height: AppSpacing.xs),
        SelectableText(
          _service.path,
          style: TextStyle(
            fontFamily: AppFonts.body,
            fontSize: 14,
            color: t.textMuted,
          ),
        ),
      ],
    );
  }

  // ── Macro Row & dialogs ─────────────────────────────────────────────────

  Widget _macroRow(BuildContext context, int index) {
    final t = context.tokens;
    final m = s.macros[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Container(
        decoration: BoxDecoration(
          color: t.panel,
          border: Border.all(color: t.outline, width: AppBorders.thin),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
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
          shape: const RoundedRectangleBorder(
            side: BorderSide(color: Colors.black, width: AppBorders.thin),
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
                Navigator.pop(ctx, MacroEntry(keyword: kw, content: ct));
              },
            ),
          ],
        );
      },
    );

    if (result == null) return;
    final next = [...s.macros];
    next.removeWhere((m) => m.keyword == result.keyword &&
        (index == null || s.macros[index].keyword != result.keyword));
    if (index != null) {
      next[index] = result;
    } else {
      next.add(result);
    }
    _save(s.copyWith(macros: next));
  }

  Widget _dialogField(BuildContext context, TextEditingController ctrl, String hint) {
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
          hintStyle: TextStyle(fontFamily: AppFonts.body, color: t.textMuted),
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  Widget _footer(BuildContext context) {
    final t = context.tokens;
    return Text(
      'Tự động lưu • Swift & Flutter đồng bộ cấu hình',
      textAlign: TextAlign.center,
      style: Theme.of(context)
          .textTheme
          .bodyMedium
          ?.copyWith(color: t.textMuted, fontSize: 13),
    );
  }
}
