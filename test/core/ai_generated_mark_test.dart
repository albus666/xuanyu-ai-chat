import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/core/utils/ai_generated_mark.dart';
import 'package:xuanyu/core/widgets/ai_generated_image.dart';

void main() {
  test('AI 文本末尾追加【本内容由AI生成】且可随复制保留', () {
    const body = '今日宜静养，少做重大决定。';
    final marked = AiGeneratedMark.ensureTextMark(body);
    expect(marked, contains('AI'));
    expect(marked, contains('生成'));
    expect(marked.endsWith(AiGeneratedMark.textSuffix), isTrue);
    expect(AiGeneratedMark.ensureTextMark(marked), marked);
  });

  test('系统错误文案不加生成标识', () {
    expect(AiGeneratedMark.ensureTextMark('请先登录'), '请先登录');
    expect(AiGeneratedMark.ensureTextMark('网络异常，请稍后重试'),
        '网络异常，请稍后重试');
  });

  test('图片水印文案同时包含 AI 与生成', () {
    expect(AiGeneratedMark.imageWatermark, 'AI生成内容');
    expect(AiGeneratedMark.imageWatermark.contains('AI'), isTrue);
    expect(AiGeneratedMark.imageWatermark.contains('生成'), isTrue);
  });

  testWidgets('图片水印在右下角可见', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomRight,
            child: AiGeneratedImageWatermark(),
          ),
        ),
      ),
    );
    expect(find.text('AI生成内容'), findsOneWidget);
  });
}

