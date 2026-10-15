import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/features/fortune/paipan/bazi_calculation_cache.dart';

void main() {
  setUp(BaziCalculationCache.clear);

  test('预热后的八字结果可直接复用', () async {
    final birth = DateTime(1995, 6, 18, 9, 30);
    final first = await BaziCalculationCache.calculate(
      birth,
      isFemale: false,
    );
    final second = BaziCalculationCache.peek(birth, isFemale: false);

    expect(second, same(first));
  });

  test('性别不同不会复用同一缓存项', () async {
    final birth = DateTime(1995, 6, 18, 9, 30);
    final male = await BaziCalculationCache.calculate(
      birth,
      isFemale: false,
    );
    final female = await BaziCalculationCache.calculate(
      birth,
      isFemale: true,
    );

    expect(female, isNot(same(male)));
  });
}
