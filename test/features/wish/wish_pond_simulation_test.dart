import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/features/wish/models/wish_pond_simulation.dart';

void main() {
  WishPondSimulation pond(int seed, {Size size = const Size(430, 900)}) =>
      WishPondSimulation(random: math.Random(seed))..resize(size);

  test('鱼儿尚未吃完时追加鱼食，保留旧颗粒且每颗只吃一次', () {
    final scene = pond(8)..feed(1);
    scene.advance(1);
    final oldGrains = List.of(scene.grains);
    final positions = scene.fish.map((f) => f.position).toList();
    scene.feed(3);
    expect(scene.grains.length, 20);
    expect(scene.grains.take(8), oldGrains);
    expect(scene.fish.map((f) => f.position).toList(), positions);
    scene.advance(90);
    expect(scene.isFeeding, isFalse);
    expect(scene.bites.length, 20);
    expect(scene.bites.map((b) => b.grainId).toSet().length, 20);
  });

  test('鱼嘴接触落水颗粒才吃掉，吃完后不会重现', () {
    for (var seed = 0; seed < 20; seed++) {
      final scene = pond(seed)..feed(3);
      scene.advance(0.3);
      expect(scene.bites, isEmpty);
      scene.advance(44.7);
      expect(scene.isFeeding, isFalse, reason: 'seed $seed');
      expect(scene.bites.length, scene.grains.length, reason: 'seed $seed');
      expect(scene.bites.map((bite) => bite.grainId).toSet().length,
          scene.grains.length);
      for (final bite in scene.bites) {
        expect((bite.mouth - bite.foodPosition).distance, lessThanOrEqualTo(3));
        expect(bite.time,
            greaterThanOrEqualTo(scene.grains[bite.grainId].landsAt));
      }
      scene.advance(10);
      expect(scene.grains.every((grain) => grain.eatenAt != null), isTrue);
    }
  });

  test('多份投喂、小屏和横屏都能完成；未接触的鱼食不会超时消失', () {
    for (final size in [
      const Size(320, 640),
      const Size(430, 932),
      const Size(900, 430)
    ]) {
      for (var seed = 0; seed < 10; seed++) {
        final scene = pond(seed, size: size)..feed(10);
        scene.advance(55);
        expect(scene.isFeeding, isFalse, reason: '$size seed $seed');
        expect(scene.bites.length, 26);
      }
    }
    final scene = pond(4)..feed(1);
    for (final fish in scene.fish) {
      fish.reactAt = 1000;
    }
    scene.advance(20);
    expect(scene.isFeeding, isTrue);
    expect(scene.grains.every((grain) => grain.eatenAt == null), isTrue);
  });

  test('鱼转向及移动连续，散开错峰且再次投喂不重置位置', () {
    final scene = pond(6)..feed(1);
    final departures = <int, double>{};
    for (var frame = 0; frame < 45 * 60; frame++) {
      final previous =
          scene.fish.map((fish) => (fish.position, fish.heading)).toList();
      scene.advance(1 / 60);
      for (final fish in scene.fish) {
        expect((fish.position - previous[fish.index].$1).distance,
            lessThanOrEqualTo(0.71));
        expect((fish.heading - previous[fish.index].$2).abs(),
            lessThanOrEqualTo(2.61 / 60));
        if (fish.activity == WishFishActivity.leaving) {
          departures.putIfAbsent(fish.index, () => scene.time);
        }
      }
    }
    expect(departures.length, 3);
    expect(departures.values.toSet().length, 3);
    final positions = scene.fish.map((fish) => fish.position).toList();
    scene.feed(1);
    expect(scene.fish.map((fish) => fish.position).toList(), positions);
    scene.advance(45);
    expect(scene.isFeeding, isFalse);
    expect(scene.bites.length, 8);
  });

  test('旋转屏幕保留已吃掉的颗粒和正在进行的投喂', () {
    final scene = pond(9)..feed(3);
    scene.advance(4);
    final eaten = scene.bites.length;
    scene.resize(const Size(900, 430));
    expect(scene.bites.length, eaten);
    scene.advance(45);
    expect(scene.isFeeding, isFalse);
    expect(scene.bites.length, 12);
  });
}
