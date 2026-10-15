import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

class ChartCaseNotebook extends StatelessWidget {
  const ChartCaseNotebook({
    super.key,
    required this.scrollController,
    required this.titleController,
    required this.reasoningController,
    required this.commentaryController,
    required this.onSave,
    required this.onClose,
  });

  final ScrollController scrollController;
  final TextEditingController titleController;
  final TextEditingController reasoningController;
  final TextEditingController commentaryController;
  final Future<void> Function() onSave;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFFBFEFD),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFCDEDEA)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 6),
              child: Row(
                children: [
                  const Icon(Icons.note_alt_outlined,
                      color: AppColors.primaryDark),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('档案笔记',
                        style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary)),
                  ),
                  TextButton.icon(
                    onPressed: onSave,
                    icon: const Icon(Icons.save_outlined, size: 18),
                    label: const Text('保存'),
                  ),
                  IconButton(
                    tooltip: '收起',
                    onPressed: onClose,
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE2F2F0)),
            Expanded(
              child: ListView(
                controller: scrollController,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(
                  16,
                  14,
                  16,
                  24 + MediaQuery.viewInsetsOf(context).bottom,
                ),
                children: [
                  TextField(
                    controller: titleController,
                    maxLength: 80,
                    decoration: _caseDecoration('笔记标题', '例如：关系与事业重点'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: reasoningController,
                    minLines: 7,
                    maxLines: 18,
                    decoration: _caseDecoration('看盘判断', '记录你的判断依据与重要线索…'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: commentaryController,
                    minLines: 7,
                    maxLines: 18,
                    decoration: _caseDecoration('现实反馈', '记录已验证的经历与后续变化…'),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  InputDecoration _caseDecoration(String label, String hint) => InputDecoration(
        labelText: label,
        hintText: hint,
        alignLabelWithHint: true,
        filled: true,
        fillColor: Colors.white,
        counterText: '',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      );
}
