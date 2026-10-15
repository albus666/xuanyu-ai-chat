import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/features/role_diagnosis/models/life_atlas_models.dart';

void main() {
  test('人生图鉴档案完整保存可复用AI场景标识和图片地址', () {
    final source = LifeAtlasAchievement(
      id: 'career-one',
      title: '把漫长考成答案',
      quote: '今天终于轮到你的名字出现在答案里。',
      domain: LifeAtlasDomain.career,
      rarityLabel: '稀有',
      eventKey: 'exam_staff_passed',
      sceneKey: 'exam_staff_passed',
      imageUrl: 'https://example.com/life-scene.webp',
      sceneToken: List.filled(64, 'b').join(),
      aiGenerated: true,
    );

    final restored = LifeAtlasAchievement.fromJson(source.toJson());

    expect(restored.imageUrl, source.imageUrl);
    expect(restored.sceneToken, source.sceneToken);
    expect(restored.aiGenerated, isTrue);
    expect(restored.eventKey, source.eventKey);
  });

  test('更新稀有度时不会丢失已经保存的AI场景', () {
    final source = LifeAtlasAchievement(
      id: 'journey-one',
      title: '世界终于不是屏幕',
      quote: '远方第一次真实地落在了脚下。',
      domain: LifeAtlasDomain.journey,
      rarityLabel: '数据积累中',
      sceneToken: List.filled(64, 'c').join(),
      imageUrl: 'https://example.com/journey.webp',
      aiGenerated: true,
    );

    final changed = source.copyWith(rarityLabel: '少见', rarityPercent: 18.5);

    expect(changed.imageUrl, source.imageUrl);
    expect(changed.sceneToken, source.sceneToken);
    expect(changed.aiGenerated, isTrue);
    expect(changed.rarityPercent, 18.5);
  });
}
