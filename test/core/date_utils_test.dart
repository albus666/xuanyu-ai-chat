import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/core/utils/date_utils.dart';

void main() {
  test('个人主页瞬间时间精确到北京时间分钟', () {
    expect(
      AppDateUtils.formatPostDateTime('2024-01-02T03:04:45Z'),
      '2024年01月02日 11:04',
    );
  });
}
