import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/features/fortune/paipan/mingling_identity.dart';

void main() {
  test('十日主使用固定官方命灵身份与立绘', () {
    const expected = <String, (String, String, String)>{
      '甲': ('木', '青角鹿', 'jia_full_v3'),
      '乙': ('木', '藤耳兔', 'yi_full_v3'),
      '丙': ('火', '曜阳狮', 'bing_full_v3'),
      '丁': ('火', '灯角羊', 'ding_lamb_full_v3'),
      '戊': ('土', '山灵熊', 'wu_full_v3'),
      '己': ('土', '云田狸', 'ji_full_v3'),
      '庚': ('金', '银纹虎', 'geng_full_v3'),
      '辛': ('金', '月羽鹤', 'xin_full_v3'),
      '壬': ('水', '沧浪龙灵', 'ren_full_v3'),
      '癸': ('水', '雨耳獭', 'gui_full_v3'),
    };

    for (final entry in expected.entries) {
      final identity = minglingIdentityForDayGan(entry.key);
      expect(identity, isNotNull);
      expect(identity!.element, entry.value.$1);
      expect(identity.name, entry.value.$2);
      expect(identity.assetKey, entry.value.$3);
      expect(
          identity.title, '${entry.key}${entry.value.$1} · ${entry.value.$2}');
      expect(
        identity.assetPath,
        'assets/mingling_v2/${entry.value.$3}.png',
      );
    }
  });

  test('未知日主不伪造命灵', () {
    expect(minglingIdentityForDayGan(''), isNull);
    expect(minglingIdentityForDayGan('未知'), isNull);
  });
}
