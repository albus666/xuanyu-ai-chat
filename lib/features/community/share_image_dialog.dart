import '../../core/utils/ai_content.dart';
import '../../core/utils/share_card_capture.dart';

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

/// 展示带 APP 二维码的分享图，支持「分享此图」到系统（微信、朋友圈等）
void showShareImageDialog(BuildContext context, Map<String, dynamic> postItem) {
  final content =
      (postItem['content'] as String? ?? '').replaceAll('\n', ' ').trim();
  final aiLabel = AiContent.label(postItem);
  final rawSnippet =
      content.length > 60 ? '${content.substring(0, 60)}...' : content;
  final snippet = AiContent.markedText(rawSnippet, aiLabel);
  final nickname = postItem['nickname'] as String? ?? '用户';

  showDialog<void>(
    context: context,
    barrierColor: Colors.black54,
    builder: (ctx) => _ShareImageDialog(
      snippet: snippet,
      nickname: nickname,
      onShare: () async {
        final boundary = _ShareImageDialogState.repaintKey.currentContext
            ?.findRenderObject() as RenderRepaintBoundary?;
        if (boundary == null) return;
        final image = await boundary.toImage(pixelRatio: 3);
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        if (byteData == null) return;
        final tempDir = await getTemporaryDirectory();
        final file = File(
          '${tempDir.path}/xuanyu_share_${DateTime.now().millisecondsSinceEpoch}.png',
        );
        final bytes = byteData.buffer.asUint8List();
        await file.writeAsBytes(
          aiLabel.isEmpty
              ? bytes
              : await ShareCardCapture.labelImage(
                  bytes,
                  label: aiLabel,
                  source:
                      postItem['AIGC'] is Map ? postItem['AIGC'] as Map : null,
                  propagated: true,
                ),
        );
        await Share.shareXFiles(
          [XFile(file.path)],
          text:
              '【${AppConstants.appNameForShare}】$snippet\n${AppConstants.appDownloadHint}',
        );
        if (ctx.mounted) Navigator.of(ctx).pop();
      },
    ),
  );
}

class _ShareImageDialog extends StatefulWidget {
  const _ShareImageDialog({
    required this.snippet,
    required this.nickname,
    required this.onShare,
  });

  final String snippet;
  final String nickname;
  final VoidCallback onShare;

  @override
  State<_ShareImageDialog> createState() => _ShareImageDialogState();
}

class _ShareImageDialogState extends State<_ShareImageDialog> {
  static final GlobalKey repaintKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .85),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RepaintBoundary(
                key: repaintKey,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '【${AppConstants.appNameForShare}】',
                        style: AppTextStyles.titleSmall.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        widget.snippet,
                        style: AppTextStyles.bodySmall.copyWith(height: 1.5),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '— ${widget.nickname}',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textHint,
                        ),
                      ),
                      const SizedBox(height: 16),
                      QrImageView(
                        data: AppConstants.appDownloadUrl,
                        version: QrVersions.auto,
                        size: 100,
                        backgroundColor: Colors.white,
                        eyeStyle: const QrEyeStyle(
                          eyeShape: QrEyeShape.square,
                          color: AppColors.primary,
                        ),
                        dataModuleStyle: const QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.square,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        AppConstants.appDownloadHint,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textHint,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton.icon(
                      onPressed: widget.onShare,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(48),
                      ),
                      icon: const Icon(Icons.share_rounded, size: 20),
                      label: const Text('分享此图到微信、朋友圈等',
                          textAlign: TextAlign.center),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: const Color(0xFFF4F6F8),
                        foregroundColor: AppColors.textPrimary,
                        minimumSize: const Size.fromHeight(48),
                        side: const BorderSide(color: AppColors.divider),
                      ),
                      child: const Text('关闭'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
