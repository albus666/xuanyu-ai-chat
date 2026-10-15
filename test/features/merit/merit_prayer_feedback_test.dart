import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/features/merit/services/merit_prayer_feedback_service.dart';

void main() {
  test('敲击弹出文案支持不限条数并按后台顺序读取', () {
    final raw = List.generate(
      240,
      (index) => {
        'id': 'copy_$index',
        'content': '文案 $index',
        'enabled': true,
        'sortOrder': 239 - index,
      },
    );

    final result = parseMeritPrayerFeedbackTexts(raw);

    expect(result, hasLength(240));
    expect(result.first, '文案 239');
    expect(result.last, '文案 0');
  });

  test('敲击弹出文案过滤停用和空白项', () {
    final result = parseMeritPrayerFeedbackTexts([
      {'content': '第二条', 'enabled': true, 'sortOrder': 2},
      {'content': '已停用', 'enabled': false, 'sortOrder': 0},
      {'content': '  ', 'enabled': true, 'sortOrder': 1},
      {'content': '第一条', 'sortOrder': 1},
    ]);

    expect(result, ['第一条', '第二条']);
  });

  test('后台没有可用文案时回退本地默认值', () {
    expect(
      parseMeritPrayerFeedbackTexts(const []),
      meritPrayerFeedbackTexts,
    );
  });
}
