// convert_tool_page.dart
// ----------------------
// Công cụ chuyển mã / biến đổi văn bản tiếng Việt. Dán text -> chọn phép chuyển
// -> xem kết quả -> copy. Dùng TextConverter của package viet_engine (dùng chung
// spec với engine native).

import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:flutter/services.dart';
import 'package:viet_engine/viet_engine.dart';

import '../theme/app_theme.dart';
import '../widgets/pixel.dart';

/// Các phép biến đổi áp dụng được (theo thứ tự).
enum _Op { none, removeDiacritics, upper, lower, capWords, capFirst }

class ConvertToolPage extends StatefulWidget {
  const ConvertToolPage({super.key});

  @override
  State<ConvertToolPage> createState() => _ConvertToolPageState();
}

class _ConvertToolPageState extends State<ConvertToolPage> {
  final _input = TextEditingController();
  CodeTable _from = CodeTable.unicode;
  CodeTable _to = CodeTable.unicode;
  _Op _op = _Op.none;

  @override
  void initState() {
    super.initState();
    _input.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  /// Tính kết quả: chuyển bảng mã trước, rồi áp phép biến đổi.
  String get _output {
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
    final t = context.tokens;
    final out = _output;

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
                    _header(context),
                    const SizedBox(height: AppSpacing.lg),

                    // ── Bảng mã: từ → đến ─────────────────────────────────
                    _panel(context, 'BẢNG MÃ', Row(
                      children: [
                        Expanded(child: _codeDropdown(context, _from,
                            (v) => setState(() => _from = v))),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Icon(Iconsax.arrow_right, size: 18),
                        ),
                        Expanded(child: _codeDropdown(context, _to,
                            (v) => setState(() => _to = v))),
                      ],
                    )),
                    const SizedBox(height: AppSpacing.md),

                    // ── Phép biến đổi ─────────────────────────────────────
                    _panel(context, 'BIẾN ĐỔI', Wrap(
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
                    )),
                    const SizedBox(height: AppSpacing.md),

                    // ── Input ─────────────────────────────────────────────
                    _panel(context, 'VĂN BẢN NGUỒN', Container(
                      decoration: BoxDecoration(
                        color: t.inset,
                        border: Border.all(color: t.outline, width: AppBorders.thin),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: TextField(
                        controller: _input,
                        maxLines: 4,
                        minLines: 3,
                        cursorColor: AppColors.cyan,
                        cursorWidth: 3,
                        style: TextStyle(
                            fontFamily: AppFonts.body,
                            fontSize: 18,
                            color: t.textPrimary),
                        decoration: InputDecoration(
                          hintText: 'Dán hoặc gõ văn bản…',
                          hintStyle: TextStyle(
                              fontFamily: AppFonts.body, color: t.textMuted),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    )),
                    const SizedBox(height: AppSpacing.md),

                    // ── Output ────────────────────────────────────────────
                    _panel(context, 'KẾT QUẢ', Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          constraints: const BoxConstraints(minHeight: 72),
                          decoration: BoxDecoration(
                            color: AppColors.cyan.withValues(alpha: 0.12),
                            border: Border.all(
                                color: AppColors.cyan, width: AppBorders.thin),
                          ),
                          padding: const EdgeInsets.all(12),
                          alignment: Alignment.topLeft,
                          child: SelectableText(
                            out.isEmpty ? '—' : out,
                            style: TextStyle(
                              fontFamily: AppFonts.body,
                              fontSize: 18,
                              color: out.isEmpty ? t.textMuted : t.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        PixelButton(
                          label: 'COPY KẾT QUẢ',
                          icon: Iconsax.copy,
                          color: AppColors.cyan,
                          onPressed: out.isEmpty
                              ? null
                              : () {
                                  Clipboard.setData(ClipboardData(text: out));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Đã copy kết quả'),
                                      duration: Duration(seconds: 1),
                                    ),
                                  );
                                },
                        ),
                      ],
                    )),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Row(
      children: [
        PixelIconButton(
          icon: Iconsax.arrow_left,
          tooltip: 'Quay lại',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('CHUYỂN MÃ',
                  style: Theme.of(context).textTheme.displaySmall),
              const SizedBox(height: 4),
              Text('UNICODE · TCVN3 · VNI · BỎ DẤU',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: context.tokens.textMuted)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _panel(BuildContext context, String title, Widget body) {
    return PixelPanel(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: context.tokens.textSecondary)),
          const SizedBox(height: AppSpacing.sm),
          body,
        ],
      ),
    );
  }

  Widget _codeDropdown(
      BuildContext context, CodeTable value, ValueChanged<CodeTable> onChanged) {
    final t = context.tokens;
    return Container(
      decoration: BoxDecoration(
        color: t.inset,
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.purple : t.inset,
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
}
