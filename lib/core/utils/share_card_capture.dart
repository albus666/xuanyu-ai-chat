import 'dart:typed_data';

import 'ai_content.dart';

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// RepaintBoundary → PNG → 系统分享
class ShareCardCapture {
  ShareCardCapture._();

  static Future<void> shareWidget({
    required GlobalKey repaintKey,
    String? shareText,
    bool aiGenerated = false,
    bool Function()? shouldShare,
    bool hasVisibleAiLabel = false,
  }) async {
    if (shouldShare != null && !shouldShare()) return;
    if (repaintKey.currentContext?.findRenderObject() == null) return;
    final file = await captureWidget(
      repaintKey: repaintKey,
      aiGenerated: aiGenerated,
      hasVisibleAiLabel: hasVisibleAiLabel,
    );
    if (shouldShare != null && !shouldShare()) return;
    await Share.shareXFiles(
      [file],
      text: aiGenerated
          ? AiContent.markedText(shareText ?? '', 'AI生成内容')
          : shareText,
    );
  }

  static Future<XFile> captureWidget({
    required GlobalKey repaintKey,
    bool aiGenerated = false,
    bool hasVisibleAiLabel = false,
  }) async {
    final boundary =
        repaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) throw StateError('分享图片尚未就绪');

    final image = await boundary.toImage(pixelRatio: 3);
    ByteData? byteData;
    try {
      byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    } finally {
      image.dispose();
    }
    if (byteData == null) throw StateError('无法生成分享图片');

    final tempDir = await getTemporaryDirectory();
    final file = File(
      '${tempDir.path}/xuanyu_share_${DateTime.now().millisecondsSinceEpoch}.png',
    );
    final bytes = byteData.buffer.asUint8List();
    await file.writeAsBytes(aiGenerated
        ? await prepareAiImage(bytes, hasVisibleLabel: hasVisibleAiLabel)
        : bytes);
    return XFile(file.path);
  }

  /// Only set hasVisibleLabel when the captured widget already paints the label.
  /// Keep that design intact while always adding file provenance.
  static Future<Uint8List> prepareAiImage(Uint8List bytes,
      {bool hasVisibleLabel = false}) async {
    if (!hasVisibleLabel) return labelImage(bytes);
    return AiContent.pngMetadata(bytes, AiContent.metadata(bytes));
  }

  /// Burn the visible label into exported pixels before embedding provenance.
  static Future<Uint8List> labelImage(
    List<int> bytes, {
    String label = 'AI生成内容',
    Map? source,
    bool propagated = false,
  }) async {
    final codec = await ui.instantiateImageCodec(Uint8List.fromList(bytes));
    final frame = await codec.getNextFrame();
    final sourceImage = frame.image;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImage(sourceImage, Offset.zero, Paint());
    final fontSize = (sourceImage.width / 40).clamp(14.0, 40.0).toDouble();
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: Colors.white,
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: sourceImage.width.toDouble());
    final top = sourceImage.height - painter.height - 16;
    canvas.drawRect(
      Rect.fromLTWH(
        0,
        top - 8,
        sourceImage.width.toDouble(),
        painter.height + 24,
      ),
      Paint()..color = const Color(0xDD171717),
    );
    painter.paint(canvas, Offset(8, top));
    final picture = recorder.endRecording();
    final image = await picture.toImage(sourceImage.width, sourceImage.height);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    sourceImage.dispose();
    picture.dispose();
    codec.dispose();
    painter.dispose();
    if (data == null) throw StateError('无法生成带标识的分享图片');
    final png = data.buffer.asUint8List();
    return AiContent.pngMetadata(
      png,
      AiContent.metadata(
        png,
        label: label.startsWith('疑似')
            ? '3'
            : (propagated ? (source?['Label']?.toString() ?? '2') : '1'),
        source: source,
        propagated: propagated,
      ),
    );
  }
}
