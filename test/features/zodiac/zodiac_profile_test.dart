import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/features/zodiac/zodiac_profile.dart';

void main() {
  group('ZodiacReading', () {
    test('uses the traditional beginning-of-spring boundary', () {
      expect(
        ZodiacReading.fromBirthDate(DateTime(2024, 2, 3)).companion.animal,
        '兔',
      );
      expect(
        ZodiacReading.fromBirthDate(DateTime(2024, 2, 5)).companion.animal,
        '龙',
      );
      expect(
        ZodiacReading.fromBirthDate(DateTime(2025, 2, 2)).companion.animal,
        '龙',
      );
      expect(
        ZodiacReading.fromBirthDate(DateTime(2025, 2, 4)).companion.animal,
        '蛇',
      );
    });

    test('provides one distinct companion and illustration per zodiac', () {
      expect(ZodiacCompanion.all, hasLength(12));
      expect(
        ZodiacCompanion.all.map((item) => item.animal).toSet(),
        hasLength(12),
      );
      expect(
        ZodiacCompanion.all.map((item) => item.assetPath).toSet(),
        hasLength(12),
      );
      expect(
        ZodiacCompanion.all.every(
          (item) =>
              item.sparks.length == 3 &&
              item.quote.isNotEmpty &&
              item.suggestion.isNotEmpty &&
              item.coreReading.length >= 60 &&
              item.relationshipReading.length >= 80 &&
              item.pressureReading.length >= 70 &&
              item.growthReading.length >= 70,
        ),
        isTrue,
      );
    });

    test('builds the expected traditional relationship labels', () {
      final snake = ZodiacCompanion.byAnimal('蛇');

      expect(snake.sanHe, <String>['牛', '鸡']);
      expect(snake.liuHe, '猴');
      expect(snake.clash, '猪');
      expect(snake.harm, '虎');
    });

    test('每个生肖都提供四段可追溯的长解读', () {
      for (final item in ZodiacCompanion.all) {
        expect(item.relationshipReading, contains(item.sanHeText));
        expect(item.relationshipReading, contains(item.liuHe));
        expect(item.relationshipReading, contains(item.clash));
        expect(item.pressureReading, contains(item.tiredAt));
        expect(item.pressureReading, contains(item.suggestion));
        expect(item.growthReading, contains(item.branchElement));
        expect(item.growthReading, contains('${item.yinYang}支'));
      }
    });
  });
}
