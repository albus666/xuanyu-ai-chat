import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/features/community/post_card.dart';

void main() {
  test('仅展示用户主动选择的作品位置', () {
    expect(
      postDisplayLocation(<String, dynamic>{
        'locationCode': '河南省 驻马店市 驿城区',
        'locationSource': 'user',
      }),
      '河南省 驻马店市 驿城区',
    );
    expect(
      postDisplayLocation(<String, dynamic>{
        'locationCode': '河南省 驻马店市',
        'locationSource': 'automatic',
      }),
      isNull,
    );
    expect(
      postDisplayLocation(<String, dynamic>{
        'locationCode': '河南省 驻马店市',
      }),
      isNull,
    );
  });
}
