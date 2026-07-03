// settings_page.dart
// ------------------
// Màn hình cài đặt chính của Bow Go, phong cách pixel/8-bit RPG (như Stardew Valley).
// Bố cục dual-pane: Sidebar bên trái, nội dung cài đặt cuộn bên phải.
// Tự động lưu cấu hình xuống file JSON để bộ gõ Swift đồng bộ.

import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:flutter/services.dart';
import 'package:viet_engine/viet_engine.dart' hide InputMethod, ToneStyle;

import '../models/settings.dart';
import '../services/permission_status_service.dart';
import '../services/stats_service.dart';
import '../services/preview_engine.dart';
import '../services/settings_service.dart';
import '../services/update_service.dart';
import '../theme/app_theme.dart';
import '../widgets/hotkey_recorder.dart';
import '../widgets/pixel.dart';
import '../widgets/pixel_controls.dart';

/// Các tab chức năng trong menu cài đặt.
enum SettingsTab { general, shortcuts, clipboard, screenshot, macros, autocorrect, convert, stats, troubleshoot, update, about }

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
  final _stats = StatsService.instance;
  final _testController = TextEditingController();
  String _preview = '';

  // Ô tìm kiếm trong tab Tự sửa lỗi (lọc theo cả "sai" và "đúng").
  final _autoCorrectSearch = TextEditingController();

  // Tab hiện tại đang chọn
  SettingsTab _activeTab = SettingsTab.general;

  // Trạng thái kiểm tra cập nhật (Tab Cập nhật).
  UpdateResult _update = UpdateResult.idle;
  // Tăng mỗi lần kiểm tra để card kết quả luôn fade-in lại (kể cả trùng trạng thái).
  int _updateCheckSeq = 0;

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
    _stats.addListener(_onStats);
    _testController.addListener(_recomputePreview);
    _input.addListener(() => setState(() {}));
    _autoCorrectSearch.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _service.removeListener(_onSettings);
    _permStatus.removeListener(_onPermStatus);
    _stats.removeListener(_onStats);
    _testController.dispose();
    _input.dispose();
    _autoCorrectSearch.dispose();
    super.dispose();
  }

  void _onPermStatus() {
    if (mounted) setState(() {});
  }

  void _onStats() {
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
          child: const Icon(Iconsax.keyboard,
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
        PixelStatusToggle(
          ready: ready,
          onToggleTheme: widget.onToggleTheme,
        ),
      ],
    );
  }

  // ── Sidebar Navigation ──────────────────────────────────────────────────

  Widget _buildSidebar(BuildContext context) {
    // Cuộn được để trên cửa sổ thấp vẫn với tới các tab cuối (Cập nhật/Thông tin).
    // Padding phải chừa chỗ cho hiệu ứng dịch-phải khi hover/chọn tab.
    return SizedBox(
      width: 175,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(right: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSidebarTab(SettingsTab.general, Iconsax.setting_2, 'BỘ GÕ'),
            _buildSidebarTab(SettingsTab.shortcuts, Iconsax.flash, 'PHÍM TẮT'),
            _buildSidebarTab(SettingsTab.clipboard, Iconsax.clipboard_text, 'CLIPBOARD'),
            _buildSidebarTab(SettingsTab.screenshot, Iconsax.camera, 'CHỤP HÌNH'),
            _buildSidebarTab(SettingsTab.macros, Iconsax.document_text, 'GÕ TẮT'),
            _buildSidebarTab(SettingsTab.autocorrect, Iconsax.magicpen, 'TỰ SỬA LỖI'),
            _buildSidebarTab(SettingsTab.convert, Iconsax.arrow_swap_horizontal, 'CHUYỂN MÃ'),
            _buildSidebarTab(SettingsTab.stats, Iconsax.chart_2, 'THỐNG KÊ'),
            _buildSidebarTab(SettingsTab.troubleshoot, Iconsax.setting_2, 'SỬA LỖI'),
            _buildSidebarTab(SettingsTab.update, Iconsax.cloud_change, 'CẬP NHẬT'),
            _buildSidebarTab(SettingsTab.about, Iconsax.info_circle, 'THÔNG TIN'),
          ],
        ),
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
                SettingsTab.screenshot => _buildScreenshotTab(context),
                SettingsTab.macros => _buildMacrosTab(context),
                SettingsTab.autocorrect => _buildAutoCorrectTab(context),
                SettingsTab.convert => _buildConvertTab(context),
                SettingsTab.stats => _buildStatsTab(context),
                SettingsTab.troubleshoot => _buildTroubleshootTab(context),
                SettingsTab.update => _buildUpdateTab(context),
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
              const Icon(Iconsax.info_circle, color: AppColors.yellow, size: 14),
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
          title: 'KHỞI ĐỘNG CÙNG HỆ THỐNG',
          subtitle: s.launchAtLogin
              ? 'Bộ gõ tự chạy khi đăng nhập máy'
              : 'Bật để bộ gõ tự chạy khi mở máy',
          control: PixelSwitch(
            value: s.launchAtLogin,
            onChanged: (v) => _save(s.copyWith(launchAtLogin: v)),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
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

        _tabSectionTitle('CHỤP MÀN HÌNH'),
        const SizedBox(height: AppSpacing.sm),
        SettingRow(
          title: 'PHÍM TẮT CHỤP MÀN HÌNH',
          subtitle: 'Chọn vùng màn hình để chụp (⌃⇧S mặc định)',
          control: HotkeyRecorder(
            hotkey: s.screenshotHotkey,
            onChanged: (hk) => _save(s.copyWith(screenshotHotkey: hk)),
          ),
        ),
        _tabDivider(),

        _tabSectionTitle('BIẾN ĐỔI CHỮ ĐÃ CHỌN'),
        const SizedBox(height: AppSpacing.sm),
        SettingRow(
          title: 'BẬT BIẾN ĐỔI CHỮ',
          subtitle: s.textTransformEnabled
              ? 'Bôi đen chữ → phím tắt → bỏ dấu/IN HOA/chuyển mã'
              : 'Bật để biến đổi nhanh vùng chữ đã bôi đen',
          control: PixelSwitch(
            value: s.textTransformEnabled,
            onChanged: (v) => _save(s.copyWith(textTransformEnabled: v)),
          ),
        ),
        if (s.textTransformEnabled) ...[
          const SizedBox(height: AppSpacing.sm),
          SettingRow(
            title: 'PHÍM TẮT BIẾN ĐỔI CHỮ',
            subtitle: 'Mở bảng chọn thao tác tại con trỏ (⌃⇧T mặc định)',
            control: HotkeyRecorder(
              hotkey: s.textTransformHotkey,
              onChanged: (hk) => _save(s.copyWith(textTransformHotkey: hk)),
            ),
          ),
        ],
        _tabDivider(),

        _tabSectionTitle('GÕ NHANH KÝ TỰ & EMOJI'),
        const SizedBox(height: AppSpacing.sm),
        SettingRow(
          title: 'BẬT BẢNG GÕ NHANH',
          subtitle: s.symbolPickerEnabled
              ? 'Mở bảng chọn ký tự đặc biệt & emoji để chèn nhanh'
              : 'Bật để mở bảng chọn ký tự bằng phím tắt',
          control: PixelSwitch(
            value: s.symbolPickerEnabled,
            onChanged: (v) => _save(s.copyWith(symbolPickerEnabled: v)),
          ),
        ),
        if (s.symbolPickerEnabled) ...[
          const SizedBox(height: AppSpacing.sm),
          SettingRow(
            title: 'PHÍM TẮT BẢNG KÝ TỰ',
            subtitle: 'Mở bảng ký tự tại con trỏ (⌃⇧K mặc định)',
            control: HotkeyRecorder(
              hotkey: s.symbolPickerHotkey,
              onChanged: (hk) => _save(s.copyWith(symbolPickerHotkey: hk)),
            ),
          ),
        ],
        _tabDivider(),

        _tabSectionTitle('DÁN STICKER (EMOJI ẢNH)'),
        const SizedBox(height: AppSpacing.sm),
        SettingRow(
          title: 'BẬT BẢNG STICKER',
          subtitle: s.stickerPickerEnabled
              ? 'Chọn emoji ảnh để dán ẢNH vào tin nhắn/ghi chú'
              : 'Bật để mở bảng dán sticker bằng phím tắt',
          control: PixelSwitch(
            value: s.stickerPickerEnabled,
            onChanged: (v) => _save(s.copyWith(stickerPickerEnabled: v)),
          ),
        ),
        if (s.stickerPickerEnabled) ...[
          const SizedBox(height: AppSpacing.sm),
          SettingRow(
            title: 'PHÍM TẮT BẢNG STICKER',
            subtitle: 'Mở bảng sticker tại con trỏ (⌃⇧J mặc định)',
            control: HotkeyRecorder(
              hotkey: s.stickerPickerHotkey,
              onChanged: (hk) => _save(s.copyWith(stickerPickerHotkey: hk)),
            ),
          ),
        ],
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
                  icon: Iconsax.minus,
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
                  icon: Iconsax.add,
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

  // ── Tab: Chụp màn hình ──────────────────────────────────────────────────

  Widget _buildScreenshotTab(BuildContext context) {
    final st = _permStatus.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _tabSectionTitle('CHỤP MÀN HÌNH'),
        const SizedBox(height: AppSpacing.sm),
        SettingRow(
          title: 'BẬT CHỤP MÀN HÌNH',
          subtitle: s.screenshotEnabled
              ? 'Chọn vùng, vẽ chú thích, tự copy vào clipboard'
              : 'Bật để chụp và chú thích vùng màn hình',
          control: PixelSwitch(
            value: s.screenshotEnabled,
            onChanged: (v) => _save(s.copyWith(screenshotEnabled: v)),
          ),
        ),
        if (s.screenshotEnabled) ...[
          _tabDivider(),
          _tabSectionTitle('PHÍM TẮT'),
          const SizedBox(height: AppSpacing.sm),
          SettingRow(
            title: 'PHÍM TẮT CHỤP',
            subtitle: 'Nhấn để bắt đầu chọn vùng (⌃⇧S mặc định)',
            control: HotkeyRecorder(
              hotkey: s.screenshotHotkey,
              onChanged: (hk) => _save(s.copyWith(screenshotHotkey: hk)),
            ),
          ),
          _tabDivider(),
          _tabSectionTitle('QUYỀN GHI MÀN HÌNH'),
          const SizedBox(height: AppSpacing.sm),
          if (st.known)
            _permissionRow(
              context,
              label: 'Screen Recording (Ghi màn hình)',
              sub: 'Để chụp được nội dung màn hình',
              granted: st.screenRecording,
              settingsUrl:
                  'x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture',
            )
          else
            _buildPixelInfoCard(
              context,
              'CHƯA RÕ TRẠNG THÁI QUYỀN',
              'Hãy mở bộ gõ Bow Go ít nhất một lần để kiểm tra quyền Ghi màn hình.',
            ),
        ],
        _tabDivider(),
        _buildPixelInfoCard(
          context,
          'CÁCH DÙNG',
          '• Nhấn phím tắt rồi kéo chuột chọn vùng cần chụp.\n'
          '• Dùng thanh công cụ để vẽ: bút, mũi tên, khung, chữ.\n'
          '• COPY (hoặc Enter): copy ảnh vào clipboard — tự lưu vào lịch sử Clipboard.\n'
          '• COPY TEXT: mở ảnh như Preview của macOS — trỏ vào chữ (kể cả tiếng Việt), '
          'bôi đen đoạn cần rồi ⌘C, hoặc bấm COPY HẾT.\n'
          '• LƯU: lưu ảnh ra file PNG. Esc: thoát.\n'
          '• Mục ảnh trong lịch sử Clipboard cũng có nút copy chữ trong ảnh.',
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
        const SizedBox(height: AppSpacing.sm),
        SettingRow(
          title: 'GÕ TẮT EMOJI',
          subtitle: s.emojiShortcutsEnabled
              ? 'Gõ :cry: → 😢 · :fire: → 🔥 · :vn: → 🇻🇳'
              : 'Bật để gõ emoji bằng shortcode kiểu :tên:',
          control: PixelSwitch(
            value: s.emojiShortcutsEnabled,
            onChanged: (v) => _save(s.copyWith(emojiShortcutsEnabled: v)),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SettingRow(
          title: 'HOÀN TÁC KHI BUNG',
          subtitle: s.undoExpansionEnabled
              ? 'Backspace ngay sau bung → về lại chữ gốc (vn ← Việt Nam)'
              : 'Bật để Backspace hoàn tác gõ tắt/emoji/tự-sửa vừa bung',
          control: PixelSwitch(
            value: s.undoExpansionEnabled,
            onChanged: (v) => _save(s.copyWith(undoExpansionEnabled: v)),
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
                icon: Iconsax.add,
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

  // ── Tab: Tự sửa lỗi gõ nhanh ────────────────────────────────────────────

  Widget _buildAutoCorrectTab(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _tabSectionTitle('TỰ SỬA LỖI GÕ NHANH'),
        const SizedBox(height: AppSpacing.sm),
        SettingRow(
          title: 'BẬT TỰ SỬA LỖI',
          subtitle: s.autoCorrect
              ? 'Gõ nhanh sai dấu tự sửa khi kết thúc từ: "giừo"→"giờ"'
              : 'Bật để tự sửa lỗi đặt dấu sai khi gõ nhanh',
          control: PixelSwitch(
            value: s.autoCorrect,
            onChanged: (v) => _save(s.copyWith(autoCorrect: v)),
          ),
        ),
        if (s.autoCorrect) ...[
          _tabDivider(),
          _tabSectionTitle('DANH SÁCH TỪ TỰ SỬA'),
          const SizedBox(height: AppSpacing.sm),
          // Nhập/Xuất danh sách để mang sang máy khác (settings không tự
          // đồng bộ giữa các máy — mỗi máy có file riêng). Dùng Wrap để cụm
          // nút tự xuống dòng khi cửa sổ hẹp, tránh tràn ngang.
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              PixelButton(
                label: 'NHẬP',
                icon: Iconsax.import_1,
                color: AppColors.blue,
                small: true,
                expand: false,
                height: 32,
                onPressed: () => _importAutoCorrectPairs(context),
              ),
              PixelButton(
                label: 'XUẤT',
                icon: Iconsax.export_1,
                color: AppColors.stone,
                small: true,
                expand: false,
                height: 32,
                onPressed: s.autoCorrectPairs.isEmpty
                    ? null
                    : () => _exportAutoCorrectPairs(context),
              ),
              PixelButton(
                label: 'THÊM MỚI',
                icon: Iconsax.add,
                color: AppColors.green,
                small: true,
                expand: false,
                height: 32,
                onPressed: () => _editAutoCorrectPair(context, null),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Gõ ra từ bên trái → tự thay bằng từ bên phải. Sửa/xoá tuỳ ý.',
            style: TextStyle(
                fontFamily: AppFonts.body, fontSize: 13, color: t.textMuted),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (s.autoCorrectPairs.isNotEmpty) ...[
            _autoCorrectSearchBox(context),
            const SizedBox(height: AppSpacing.sm),
          ],
          _autoCorrectList(context),
        ],
      ],
    );
  }

  /// Ô tìm kiếm lọc danh sách cặp tự-sửa theo cả "sai" và "đúng".
  Widget _autoCorrectSearchBox(BuildContext context) {
    final t = context.tokens;
    return Container(
      decoration: BoxDecoration(
        color: t.panel,
        border: Border.all(color: t.outline, width: AppBorders.thin),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Icon(Iconsax.search_normal, size: 18, color: t.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _autoCorrectSearch,
              cursorColor: AppColors.blue,
              cursorWidth: 3,
              style: TextStyle(
                fontFamily: AppFonts.body,
                fontSize: 18,
                color: t.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'Tìm từ (sai hoặc đúng)…',
                hintStyle:
                    TextStyle(fontFamily: AppFonts.body, color: t.textMuted),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          if (_autoCorrectSearch.text.isNotEmpty)
            PixelIconButton(
              icon: Iconsax.close_circle,
              iconSize: 15,
              size: 30,
              tooltip: 'Xoá tìm kiếm',
              onPressed: () => _autoCorrectSearch.clear(),
            ),
        ],
      ),
    );
  }

  /// Danh sách cặp tự-sửa (đã lọc theo ô tìm kiếm nếu có).
  Widget _autoCorrectList(BuildContext context) {
    final query = _autoCorrectSearch.text.trim().toLowerCase();
    final pairs = query.isEmpty
        ? s.autoCorrectPairs
        : s.autoCorrectPairs
            .where((p) =>
                p.wrong.toLowerCase().contains(query) ||
                p.right.toLowerCase().contains(query))
            .toList();

    if (s.autoCorrectPairs.isEmpty) {
      return _autoCorrectEmpty(context, '(Chưa có cặp từ nào)');
    }
    if (pairs.isEmpty) {
      return _autoCorrectEmpty(context, 'Không tìm thấy cặp từ nào');
    }
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: pairs.length,
      itemBuilder: (ctx, i) => _autoCorrectRow(context, pairs[i]),
    );
  }

  Widget _autoCorrectEmpty(BuildContext context, String message) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24),
      alignment: Alignment.center,
      child: Text(
        message,
        style: TextStyle(
          fontFamily: AppFonts.body,
          fontSize: 16,
          color: t.textMuted,
        ),
      ),
    );
  }

  Widget _autoCorrectRow(BuildContext context, AutoCorrectPair p) {
    final t = context.tokens;
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
              color: AppColors.red.withValues(alpha: 0.15),
              child: Text(
                p.wrong,
                style: TextStyle(
                    fontFamily: AppFonts.body,
                    fontSize: 16,
                    color: t.textPrimary),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Iconsax.arrow_right, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                color: AppColors.green.withValues(alpha: 0.15),
                child: Text(
                  p.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontFamily: AppFonts.body,
                      fontSize: 16,
                      color: t.textPrimary),
                ),
              ),
            ),
            const SizedBox(width: 8),
            PixelIconButton(
              icon: Iconsax.edit_2,
              iconSize: 15,
              size: 32,
              tooltip: 'Sửa',
              onPressed: () {
                final i = s.autoCorrectPairs.indexWhere(
                    (e) => e.wrong == p.wrong && e.right == p.right);
                if (i >= 0) _editAutoCorrectPair(context, i);
              },
            ),
            const SizedBox(width: 4),
            PixelIconButton(
              icon: Iconsax.trash,
              iconSize: 15,
              size: 32,
              tooltip: 'Xoá',
              color: AppColors.red,
              onPressed: () {
                final next = [...s.autoCorrectPairs]..removeWhere(
                    (e) => e.wrong == p.wrong && e.right == p.right);
                _save(s.copyWith(autoCorrectPairs: next));
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editAutoCorrectPair(BuildContext context, int? index) async {
    final existing = index != null ? s.autoCorrectPairs[index] : null;
    final wrongCtrl = TextEditingController(text: existing?.wrong ?? '');
    final rightCtrl = TextEditingController(text: existing?.right ?? '');

    final result = await showDialog<AutoCorrectPair>(
      context: context,
      builder: (ctx) {
        final t = ctx.tokens;
        return AlertDialog(
          backgroundColor: t.panel,
          shape: const RoundedRectangleBorder(
            side: BorderSide(color: Colors.black, width: AppBorders.thin),
            borderRadius: BorderRadius.zero,
          ),
          title: Text(index == null ? 'THÊM TỪ TỰ SỬA' : 'SỬA TỪ TỰ SỬA',
              style: Theme.of(ctx).textTheme.labelSmall),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('TỪ GÕ SAI (vd: giừo)',
                  style: Theme.of(ctx)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: t.textMuted, fontSize: 13)),
              const SizedBox(height: 4),
              _dialogField(ctx, wrongCtrl, 'giừo'),
              // Cảnh báo khi "từ gõ sai" thật ra là một từ ĐÚNG chính tả
              // (vd "dạy", "đẻ") — dễ vô tình biến từ đúng thành từ khác.
              // Dùng isRealWord (dấu ĐÚNG vị trí chuẩn) nên không báo nhầm các
              // typo dấu-sai-chỗ (nhiêù, giừo).
              ListenableBuilder(
                listenable: wrongCtrl,
                builder: (ctx, _) {
                  final w = wrongCtrl.text.trim();
                  if (w.isEmpty || !AutoCorrectDictionary.isRealWord(w)) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Iconsax.warning_2,
                            size: 16, color: AppColors.red),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '"$w" là từ đúng chính tả — '
                            'thêm cặp này sẽ tự đổi nó thành từ khác mỗi khi gõ.',
                            style: TextStyle(
                                fontFamily: AppFonts.body,
                                fontSize: 13,
                                color: AppColors.red),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              Text('TỪ ĐÚNG (vd: giờ)',
                  style: Theme.of(ctx)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: t.textMuted, fontSize: 13)),
              const SizedBox(height: 4),
              _dialogField(ctx, rightCtrl, 'giờ'),
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
                final w = wrongCtrl.text.trim();
                final r = rightCtrl.text.trim();
                if (w.isEmpty || r.isEmpty || w == r) return;
                Navigator.pop(ctx, AutoCorrectPair(wrong: w, right: r));
              },
            ),
          ],
        );
      },
    );

    if (result == null) return;
    final next = [...s.autoCorrectPairs];
    // Xoá trùng vế 'wrong' (không phân biệt bản đang sửa), rồi thêm/ghi đè.
    next.removeWhere((p) => p.wrong == result.wrong &&
        (index == null || s.autoCorrectPairs[index].wrong != result.wrong));
    if (index != null) {
      next[index] = result;
    } else {
      next.add(result);
    }
    _save(s.copyWith(autoCorrectPairs: next));
  }

  // ── Xuất/Nhập danh sách cặp tự-sửa (chuyển giữa các máy) ────────────────
  //
  // Settings không tự đồng bộ giữa các máy; mỗi máy có file riêng. Hai hàm này
  // cho phép ghi danh sách ra file .json và nạp lại ở máy khác.

  /// Xuất danh sách cặp tự-sửa ra file .json do người dùng chọn.
  Future<void> _exportAutoCorrectPairs(BuildContext context) async {
    final pairs = s.autoCorrectPairs;
    if (pairs.isEmpty) return;

    // Định dạng riêng, tự nhận diện khi nhập; vẫn là JSON thuần dễ đọc/sửa tay.
    final payload = <String, dynamic>{
      '_type': 'bowgo.autoCorrectPairs',
      '_version': 1,
      'autoCorrectPairs': pairs.map((p) => p.toJson()).toList(),
    };
    final jsonStr = const JsonEncoder.withIndent('  ').convert(payload);

    try {
      final location = await getSaveLocation(
        suggestedName: 'bowgo-tu-sua-loi.json',
        acceptedTypeGroups: const [
          XTypeGroup(label: 'JSON', extensions: ['json']),
        ],
      );
      if (location == null) return; // người dùng huỷ

      var path = location.path;
      if (!path.toLowerCase().endsWith('.json')) path = '$path.json';
      await File(path).writeAsString(jsonStr);

      if (!context.mounted) return;
      _showSnack('Đã xuất ${pairs.length} cặp ra file.');
    } catch (e) {
      if (!context.mounted) return;
      _showSnack('Không xuất được: $e', error: true);
    }
  }

  /// Nhập danh sách cặp tự-sửa từ file .json. Hỏi Gộp hay Ghi đè trước khi áp.
  Future<void> _importAutoCorrectPairs(BuildContext context) async {
    final List<AutoCorrectPair> imported;
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'JSON', extensions: ['json']),
        ],
      );
      if (file == null) return; // người dùng huỷ

      final raw = await file.readAsString();
      imported = _parseImportedPairs(raw);
    } catch (e) {
      if (!context.mounted) return;
      _showSnack('File không hợp lệ: $e', error: true);
      return;
    }

    if (imported.isEmpty) {
      if (!context.mounted) return;
      _showSnack('File không có cặp tự-sửa nào.', error: true);
      return;
    }

    if (!context.mounted) return;
    // Nếu chưa có gì thì nạp thẳng, khỏi hỏi Gộp/Ghi đè.
    if (s.autoCorrectPairs.isEmpty) {
      _save(s.copyWith(autoCorrectPairs: imported));
      _showSnack('Đã nhập ${imported.length} cặp.');
      return;
    }

    final mode = await _askImportMode(context, imported.length);
    if (mode == null) return; // huỷ

    if (mode == _ImportMode.replace) {
      _save(s.copyWith(autoCorrectPairs: imported));
      _showSnack('Đã thay bằng ${imported.length} cặp từ file.');
      return;
    }

    // Gộp: giữ cặp cũ, cặp mới trùng vế 'wrong' thì ghi đè theo file.
    final byWrong = <String, AutoCorrectPair>{
      for (final p in s.autoCorrectPairs) p.wrong: p,
    };
    // Chốt trạng thái GỐC (trước khi nạp) để đếm cho đúng: nếu file có nhiều cặp
    // trùng cùng 'wrong', mỗi 'wrong' chỉ tính một lần — so với danh sách cũ,
    // không so với cặp vừa nạp trong cùng vòng lặp.
    final originalByWrong = Map<String, AutoCorrectPair>.of(byWrong);
    final touched = <String>{}; // các 'wrong' đã tính rồi, tránh đếm trùng
    var added = 0;
    var updated = 0;
    for (final p in imported) {
      if (touched.add(p.wrong)) {
        final old = originalByWrong[p.wrong];
        if (old == null) {
          added++;
        } else if (old.right != p.right) {
          updated++;
        }
      }
      byWrong[p.wrong] = p;
    }
    _save(s.copyWith(autoCorrectPairs: byWrong.values.toList()));
    _showSnack('Đã gộp: thêm $added, cập nhật $updated cặp.');
  }

  /// Bóc danh sách cặp từ nội dung file. Chấp nhận cả file xuất riêng lẫn
  /// file settings.json đầy đủ (đều có khoá "autoCorrectPairs").
  List<AutoCorrectPair> _parseImportedPairs(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) throw const FormatException('Không phải JSON hợp lệ');
    final list = decoded['autoCorrectPairs'];
    if (list is! List) throw const FormatException('Thiếu "autoCorrectPairs"');

    final result = <AutoCorrectPair>[];
    for (final item in list) {
      if (item is! Map) continue;
      final wrong = (item['wrong'] as String?)?.trim() ?? '';
      final right = (item['right'] as String?)?.trim() ?? '';
      if (wrong.isEmpty || right.isEmpty || wrong == right) continue;
      result.add(AutoCorrectPair(wrong: wrong, right: right));
    }
    return result;
  }

  // ── Sao lưu / khôi phục TOÀN BỘ cấu hình ──────────────────────────────────

  /// Xuất toàn bộ cài đặt ra 1 file JSON. Bọc `_type`/`_version` để nhận diện khi
  /// nhập; body chính là `settings.toJson()` (đầy đủ mọi khoá). KHÔNG kèm `perApp`
  /// vì đó là bộ nhớ riêng từng máy (do bộ gõ quản lý).
  Future<void> _exportAllSettings(BuildContext context) async {
    final body = s.toJson()..remove('perApp');
    final payload = <String, dynamic>{
      '_type': 'bowgo.settings',
      '_version': 1,
      'settings': body,
    };
    final jsonStr = const JsonEncoder.withIndent('  ').convert(payload);

    try {
      final location = await getSaveLocation(
        suggestedName: 'bowgo-cai-dat.json',
        acceptedTypeGroups: const [
          XTypeGroup(label: 'JSON', extensions: ['json']),
        ],
      );
      if (location == null) return; // người dùng huỷ

      var path = location.path;
      if (!path.toLowerCase().endsWith('.json')) path = '$path.json';
      await File(path).writeAsString(jsonStr);

      if (!context.mounted) return;
      _showSnack('Đã xuất toàn bộ cài đặt ra file.');
    } catch (e) {
      if (!context.mounted) return;
      _showSnack('Không xuất được: $e', error: true);
    }
  }

  /// Nhập toàn bộ cài đặt từ file đã xuất. Ghi đè cấu hình hiện tại (có xác nhận),
  /// nhưng GIỮ NGUYÊN `perApp` của máy này. Chấp nhận cả file bọc `_type` lẫn file
  /// settings.json thô.
  Future<void> _importAllSettings(BuildContext context) async {
    final BowSettings imported;
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'JSON', extensions: ['json']),
        ],
      );
      if (file == null) return; // người dùng huỷ

      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) throw const FormatException('Không phải JSON hợp lệ');
      // File bọc -> lấy trường "settings"; file thô -> dùng thẳng.
      final map = decoded['settings'] is Map
          ? (decoded['settings'] as Map).cast<String, dynamic>()
          : decoded.cast<String, dynamic>();
      imported = BowSettings.fromJson(map);
    } catch (e) {
      if (!context.mounted) return;
      _showSnack('File không hợp lệ: $e', error: true);
      return;
    }

    if (!context.mounted) return;
    final ok = await _confirmImportAll(context);
    if (ok != true) return;

    // Giữ perApp hiện tại (bộ nhớ riêng máy) — không nằm trong file xuất.
    _save(imported.copyWith(perApp: s.perApp));
    _showSnack('Đã khôi phục toàn bộ cài đặt từ file.');
  }

  /// Xác nhận trước khi ghi đè toàn bộ cấu hình (thao tác không hoàn tác được).
  Future<bool?> _confirmImportAll(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ghi đè toàn bộ cài đặt?'),
        content: const Text(
          'Cấu hình hiện tại (bộ gõ, gõ tắt, tự sửa lỗi, phím tắt…) sẽ bị thay '
          'bằng nội dung trong file. Thao tác này không hoàn tác được.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Huỷ'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ghi đè'),
          ),
        ],
      ),
    );
  }

  /// Hỏi người dùng chọn Gộp hay Ghi đè khi nhập vào danh sách đã có sẵn.
  Future<_ImportMode?> _askImportMode(BuildContext context, int count) {
    return showDialog<_ImportMode>(
      context: context,
      builder: (ctx) {
        final t = ctx.tokens;
        return AlertDialog(
          backgroundColor: t.panel,
          shape: const RoundedRectangleBorder(
            side: BorderSide(color: Colors.black, width: AppBorders.thin),
            borderRadius: BorderRadius.zero,
          ),
          title: Text('NHẬP $count CẶP', style: Theme.of(ctx).textTheme.labelSmall),
          content: Text(
            'Bạn đã có ${s.autoCorrectPairs.length} cặp. Chọn cách nhập:\n\n'
            '• GỘP: giữ cặp cũ, thêm cặp mới (trùng thì lấy theo file).\n'
            '• GHI ĐÈ: xoá hết cặp cũ, chỉ giữ nội dung trong file.',
            style: TextStyle(
                fontFamily: AppFonts.body, fontSize: 14, color: t.textPrimary),
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
              label: 'GHI ĐÈ',
              color: AppColors.red,
              small: true,
              expand: false,
              onPressed: () => Navigator.pop(ctx, _ImportMode.replace),
            ),
            PixelButton(
              label: 'GỘP',
              color: AppColors.green,
              small: true,
              expand: false,
              onPressed: () => Navigator.pop(ctx, _ImportMode.merge),
            ),
          ],
        );
      },
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
              child: Icon(Iconsax.arrow_right, size: 16),
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
          icon: Iconsax.copy,
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

  // ── Tab: Thống kê gõ ────────────────────────────────────────────────────

  Widget _buildStatsTab(BuildContext context) {
    final st = _stats.value;

    if (!st.known) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _tabSectionTitle('THỐNG KÊ GÕ'),
          const SizedBox(height: AppSpacing.sm),
          _buildPixelInfoCard(
            context,
            'CHƯA CÓ SỐ LIỆU',
            'Hãy mở bộ gõ Bow Go và gõ vài từ. Sau đó số liệu sẽ hiện ở đây '
                '(cập nhật mỗi vài giây). Mọi thống kê chỉ lưu trên máy này.',
          ),
        ],
      );
    }

    final ratioPct = (st.vietRatio * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Chuỗi ngày (streak) — điểm nhấn tạo động lực.
        _buildStreakBanner(context, st.streak, st.wordsToday),
        _tabDivider(),

        _tabSectionTitle('TỔNG QUAN'),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _buildStatCard(context, Iconsax.keyboard, 'PHÍM ĐÃ GÕ',
                _formatCount(st.keystrokes), AppColors.blue),
            _buildStatCard(context, Iconsax.text, 'TỪ TIẾNG VIỆT',
                _formatCount(st.vietWords), AppColors.green),
            _buildStatCard(context, Iconsax.flash, 'PHÍM TIẾT KIỆM',
                _formatCount(st.charsSaved), AppColors.yellow),
            _buildStatCard(context, Iconsax.chart, 'TỈ LỆ TIẾNG VIỆT',
                '$ratioPct%', AppColors.cyan),
          ],
        ),
        _tabDivider(),

        _buildPixelInfoCard(
          context,
          'RIÊNG TƯ TUYỆT ĐỐI',
          'Thống kê chỉ đếm SỐ LƯỢNG (phím, từ) — KHÔNG lưu nội dung bạn gõ, '
              'KHÔNG gửi đi đâu. Tất cả nằm trong file stats.json trên máy này. '
              '"Phím tiết kiệm" là số ký tự bạn khỏi phải gõ nhờ gõ tắt & emoji.',
        ),
      ],
    );
  }

  /// Banner chuỗi ngày liên tiếp (streak) — to, nổi bật, tạo động lực.
  Widget _buildStreakBanner(BuildContext context, int streak, int wordsToday) {
    final t = context.tokens;
    return PixelPanel(
      padding: const EdgeInsets.all(16),
      fill: t.panel,
      shadowOffset: AppBorders.shadowSm,
      borderColor: AppColors.red,
      child: Row(
        children: [
          const Icon(Iconsax.flash_1, color: AppColors.red, size: 32),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$streak NGÀY LIÊN TIẾP',
                style: const TextStyle(
                  fontFamily: AppFonts.head,
                  fontSize: 12,
                  color: AppColors.red,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                streak > 0
                    ? 'Hôm nay đã gõ $wordsToday từ tiếng Việt. Giữ chuỗi nhé!'
                    : 'Gõ tiếng Việt hôm nay để bắt đầu chuỗi ngày.',
                style: TextStyle(
                  fontFamily: AppFonts.body,
                  fontSize: 14,
                  color: t.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Ô số liệu pixel: icon + nhãn + số lớn, viền màu theo loại.
  Widget _buildStatCard(BuildContext context, IconData icon, String label,
      String value, Color color) {
    final t = context.tokens;
    return SizedBox(
      width: 175,
      child: PixelPanel(
        padding: const EdgeInsets.all(14),
        fill: t.panel,
        shadowOffset: AppBorders.shadowSm,
        borderColor: color,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 14),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontFamily: AppFonts.head,
                      fontSize: 7,
                      color: t.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: TextStyle(
                fontFamily: AppFonts.head,
                fontSize: 16,
                color: t.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Định dạng số lớn gọn: 1234 -> "1.234", 1_200_000 -> "1.2M".
  String _formatCount(int n) {
    if (n >= 1000000) {
      final m = n / 1000000;
      return '${m.toStringAsFixed(m >= 10 ? 0 : 1)}M';
    }
    final str = n.toString();
    // Chèn dấu chấm ngăn cách hàng nghìn (kiểu VN).
    final buf = StringBuffer();
    for (var i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) buf.write('.');
      buf.write(str[i]);
    }
    return buf.toString();
  }

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
            icon: Iconsax.refresh,
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
            icon: Iconsax.lock,
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
        _tabDivider(),

        // ── Sao lưu & khôi phục toàn bộ cấu hình ─────────────────────────
        _tabSectionTitle('SAO LƯU & KHÔI PHỤC'),
        const SizedBox(height: AppSpacing.sm),
        SettingRow(
          title: 'XUẤT TOÀN BỘ CÀI ĐẶT',
          subtitle: 'Lưu bộ gõ + gõ tắt + tự sửa lỗi + phím tắt ra 1 file',
          control: PixelButton(
            label: 'XUẤT',
            icon: Iconsax.export_1,
            color: AppColors.blue,
            small: true,
            expand: false,
            height: 32,
            onPressed: () => _exportAllSettings(context),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SettingRow(
          title: 'NHẬP CÀI ĐẶT TỪ FILE',
          subtitle: 'Khôi phục cấu hình đã xuất (đổi máy / cài lại)',
          control: PixelButton(
            label: 'NHẬP',
            icon: Iconsax.import_1,
            color: AppColors.green,
            small: true,
            expand: false,
            height: 32,
            onPressed: () => _importAllSettings(context),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        PixelPanel(
          padding: const EdgeInsets.all(14),
          fill: t.inset,
          shadowOffset: AppBorders.shadowSm,
          borderWidth: AppBorders.thin,
          child: Text(
            'File xuất là JSON thuần, gồm mọi cài đặt trừ bộ nhớ bật/tắt theo app '
            '(perApp) — cái đó riêng từng máy. Nhập vào sẽ ghi đè cấu hình hiện tại.',
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
          const SizedBox(height: AppSpacing.sm),
          _permissionRow(
            context,
            label: 'Screen Recording (Ghi màn hình)',
            sub: 'Chỉ cần cho tính năng chụp màn hình',
            granted: st.screenRecording,
            settingsUrl:
                'x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture',
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
          ok ? Iconsax.tick_circle : Iconsax.danger,
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
          granted ? Iconsax.tick_circle : Iconsax.close_circle,
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
            icon: Iconsax.export_3,
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
    // Sửa lỗi quyền là luồng đặc thù macOS (TCC). Trên Windows không có bước này.
    if (!Platform.isMacOS) {
      if (mounted) _showSnack('Chức năng này chỉ có trên macOS.');
      return;
    }
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
    if (!Platform.isMacOS) {
      // Trên Windows: bộ gõ là DLL TSF do Windows nạp; "khởi động lại" tương
      // đương chọn lại bộ gõ khác rồi chọn lại (Win+Space), không cần ở đây.
      if (mounted) _showSnack('Trên Windows: đổi bộ gõ bằng Win+Space nếu cần.');
      return;
    }
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
    if (!Platform.isMacOS) {
      if (mounted) _showSnack('Sửa lỗi quyền chỉ áp dụng cho macOS.');
      return;
    }
    final ok = await _confirmDialog(
      context,
      title: 'Sửa lỗi quyền?',
      message: 'Sẽ xoá quyền cũ của Bow Go (Accessibility + Input Monitoring '
          '+ Screen Recording), mở Cài đặt để bạn bật lại, rồi khởi động lại bộ gõ.',
      confirmLabel: 'SỬA NGAY',
    );
    if (!ok) return;

    const bundleId = 'com.bowgo.keyboard';
    // ScreenCapture = Ghi màn hình (tính năng chụp màn hình) — cũng "mồ côi"
    // sau mỗi lần build lại như 2 quyền gõ phím.
    for (final service in ['Accessibility', 'ListenEvent', 'PostEvent', 'ScreenCapture']) {
      try {
        await Process.run('tccutil', ['reset', service, bundleId]);
      } catch (_) {/* bỏ qua */}
    }

    // Mở các trang Settings liên quan — System Settings chỉ hiện 1 trang mỗi
    // lúc, mở Screen Recording trước để 2 quyền gõ phím nằm trên cùng.
    await Process.run('open', [
      'x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture'
    ]);
    await Process.run('open', [
      'x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent'
    ]);
    await Process.run('open', [
      'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility'
    ]);

    // Khởi động lại bộ gõ để gắn quyền mới.
    await Process.run('pkill', ['-x', 'Bow Go']);
    await Process.run('open', ['-n', '/Applications/Bow Go.app']);

    if (mounted) {
      _showSnack('Đã reset quyền. Bật lại Bow Go trong Cài đặt vừa mở.');
    }
  }

  void _showSnack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg,
            style: const TextStyle(fontFamily: AppFonts.body, fontSize: 15)),
        backgroundColor: error ? AppColors.red : AppColors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
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

  // ── Tab: Cập nhật ────────────────────────────────────────────────────────

  /// Gọi GitHub Releases để kiểm tra bản mới, cập nhật UI theo trạng thái.
  Future<void> _checkForUpdates() async {
    if (_update.state == UpdateState.checking) return;
    setState(() {
      _update = UpdateResult.checking;
      _updateCheckSeq++; // đổi key → card kết quả fade-in lại mỗi lần kiểm tra
    });
    final result = await UpdateService.instance.check();
    if (mounted) setState(() => _update = result);
  }

  Widget _buildUpdateTab(BuildContext context) {
    final t = context.tokens;
    final checking = _update.state == UpdateState.checking;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _tabSectionTitle('PHIÊN BẢN HIỆN TẠI'),
        const SizedBox(height: AppSpacing.sm),
        PixelPanel(
          padding: const EdgeInsets.all(16),
          fill: t.panel,
          shadowOffset: AppBorders.shadowSm,
          child: Row(
            children: [
              PixelPanel(
                padding: const EdgeInsets.all(8),
                shadowOffset: AppBorders.shadowSm,
                fill: AppColors.blue,
                child: const Icon(Iconsax.keyboard, color: Colors.white, size: 20),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'BOW GO',
                      style: TextStyle(
                        fontFamily: AppFonts.head,
                        fontSize: 12,
                        color: AppColors.blueDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Phiên bản v$kAppVersion',
                      style: TextStyle(
                        fontFamily: AppFonts.body,
                        fontSize: 15,
                        color: t.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        _tabDivider(),

        _tabSectionTitle('KIỂM TRA BẢN MỚI'),
        const SizedBox(height: AppSpacing.sm),
        SettingRow(
          title: 'KIỂM TRA CẬP NHẬT',
          subtitle: 'Hỏi GitHub xem đã có bản mới hơn chưa',
          control: PixelButton(
            label: checking ? 'ĐANG KIỂM…' : 'KIỂM TRA',
            icon: Iconsax.cloud_change,
            color: AppColors.blue,
            small: true,
            expand: false,
            height: 32,
            onPressed: checking ? null : _checkForUpdates,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _buildUpdateStatus(context),
      ],
    );
  }

  /// Khối kết quả kiểm tra cập nhật (thay đổi theo _update.state).
  Widget _buildUpdateStatus(BuildContext context) {
    final t = context.tokens;

    switch (_update.state) {
      case UpdateState.idle:
        return const SizedBox.shrink();

      case UpdateState.checking:
        // Thanh nạp 8-bit thay vòng xoay tròn — hợp phong cách pixel.
        return PixelPanel(
          padding: const EdgeInsets.all(14),
          fill: t.inset,
          shadowOffset: AppBorders.shadowSm,
          borderWidth: AppBorders.thin,
          child: Row(
            children: [
              const PixelLoadingBar(
                color: AppColors.blue,
                width: 120,
                segments: 10,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Đang hỏi GitHub…',
                  style: TextStyle(
                    fontFamily: AppFonts.body,
                    fontSize: 15,
                    color: t.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        );

      case UpdateState.upToDate:
        // Card kết quả hiện dần cho mượt (không nhảy đột ngột).
        return PixelFadeIn(
          key: ValueKey(_updateCheckSeq),
          child: _buildUpdateResultCard(
            context,
            icon: Iconsax.tick_circle,
            color: AppColors.green,
            text: 'Bạn đang dùng bản mới nhất (v$kAppVersion).',
          ),
        );

      case UpdateState.updateAvailable:
        return PixelFadeIn(
          key: ValueKey(_updateCheckSeq),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildUpdateResultCard(
                context,
                icon: Iconsax.arrow_circle_up,
                color: AppColors.yellow,
                text: 'Đã có bản mới: v${_update.latestVersion}. '
                    'Bạn đang dùng v$kAppVersion.',
              ),
              if (_update.releaseUrl != null) ...[
                const SizedBox(height: AppSpacing.sm),
                PixelButton(
                  label: 'TẢI BẢN MỚI',
                  icon: Iconsax.export_3,
                  color: AppColors.green,
                  height: 38,
                  onPressed: () => _openSettingsUrl(_update.releaseUrl!),
                ),
              ],
            ],
          ),
        );

      case UpdateState.error:
        return PixelFadeIn(
          key: ValueKey(_updateCheckSeq),
          child: _buildUpdateResultCard(
            context,
            icon: Iconsax.danger,
            color: AppColors.red,
            text: _update.message ?? 'Không kiểm tra được cập nhật.',
          ),
        );
    }
  }

  Widget _buildUpdateResultCard(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String text,
  }) {
    final t = context.tokens;
    return PixelPanel(
      padding: const EdgeInsets.all(16),
      fill: t.panel,
      shadowOffset: AppBorders.shadowSm,
      borderColor: color,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontFamily: AppFonts.body,
                fontSize: 15,
                height: 1.2,
                color: t.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
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
                'Phiên bản v$kAppVersion',
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
            const Icon(Iconsax.arrow_right, size: 16),
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
              icon: Iconsax.edit_2,
              iconSize: 15,
              size: 32,
              tooltip: 'Sửa',
              onPressed: () => _editMacro(context, index),
            ),
            const SizedBox(width: 4),
            PixelIconButton(
              icon: Iconsax.trash,
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
    var type = existing?.type ?? 'staticText';

    final result = await showDialog<MacroEntry>(
      context: context,
      builder: (ctx) {
        final t = ctx.tokens;
        return StatefulBuilder(
          builder: (ctx, setDialog) {
            // Gợi ý nội dung theo loại đang chọn.
            final contentHint = switch (type) {
              'date' => 'dd/MM/yyyy',
              'time' => 'HH:mm:ss',
              'dateTime' => 'dd/MM/yyyy HH:mm',
              'random' => 'a, b, c',
              'counter' => '#',
              'calc' => '150000*3',
              'clipboard' => '(không cần — dán clipboard)',
              _ => 'Việt Nam',
            };
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
                  Text('LOẠI',
                      style: Theme.of(ctx)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: t.textMuted, fontSize: 13)),
                  const SizedBox(height: 4),
                  _macroTypeDropdown(ctx, type, (v) => setDialog(() => type = v)),
                  const SizedBox(height: 12),
                  Text('NỘI DUNG',
                      style: Theme.of(ctx)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: t.textMuted, fontSize: 13)),
                  const SizedBox(height: 4),
                  // Loại clipboard không cần nội dung.
                  if (type == 'clipboard')
                    Text('Sẽ dán nội dung đang copy khi gõ từ khoá.',
                        style: Theme.of(ctx)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: t.textMuted, fontSize: 13))
                  else
                    _dialogField(ctx, contentCtrl, contentHint),
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
                    final ct = type == 'clipboard' ? '' : contentCtrl.text;
                    if (kw.isEmpty) return;
                    Navigator.pop(ctx, MacroEntry(keyword: kw, content: ct, type: type));
                  },
                ),
              ],
            );
          },
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

  /// Dropdown chọn LOẠI macro. Giá trị chuỗi khớp `type` phía Swift (parseMacroType).
  Widget _macroTypeDropdown(
      BuildContext context, String value, ValueChanged<String> onChanged) {
    final t = context.tokens;
    const options = <(String, String)>[
      ('staticText', 'Văn bản cố định'),
      ('date', 'Ngày'),
      ('time', 'Giờ'),
      ('dateTime', 'Ngày giờ'),
      ('random', 'Ngẫu nhiên'),
      ('counter', 'Bộ đếm'),
      ('clipboard', 'Dán clipboard'),
      ('calc', 'Tính toán'),
    ];
    return Container(
      decoration: BoxDecoration(
        color: t.inset,
        border: Border.all(color: t.outline, width: AppBorders.thin),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          dropdownColor: t.panel,
          style: TextStyle(
              fontFamily: AppFonts.body, fontSize: 16, color: t.textPrimary),
          items: [
            for (final (val, label) in options)
              DropdownMenuItem(value: val, child: Text(label)),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
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

/// Cách nhập danh sách cặp tự-sửa khi máy đã có sẵn cặp: gộp thêm hay ghi đè.
enum _ImportMode { merge, replace }
