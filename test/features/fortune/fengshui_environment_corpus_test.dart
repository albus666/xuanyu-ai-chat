import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/features/fortune/fengshui_environment_corpus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('环境分析二态结果', () {
    test('传统规则中的适宜主判断只返回适宜状态', () {
      final status = FengshuiEnvironmentCorpus.deriveEnvironmentStatus(
        itemKey: '树林',
        sourceText: '震宫见茂密树林，主家宅平顺吉利；若有树枝断裂、枯败倒伏之象，则需留意。',
      );

      expect(status, FengshuiEnvironmentCorpus.suitableStatus);
    });

    test('传统规则中的不利主判断只返回需留意', () {
      final status = FengshuiEnvironmentCorpus.deriveEnvironmentStatus(
        itemKey: '变压器',
        sourceText: '乾宫设变压器为大凶之局，后续原始断语不向用户展示。',
      );

      expect(status, FengshuiEnvironmentCorpus.attentionStatus);
    });

    test('缺损潮湿等现实物品状态优先返回需留意', () {
      for (final key in ['潮湿', '渗水', '发霉', '墙皮裂纹', '电线杆倒伏']) {
        final status = FengshuiEnvironmentCorpus.deriveEnvironmentStatus(
          itemKey: key,
          sourceText: '无明显吉凶之象，整体平稳。',
        );
        expect(
          status,
          FengshuiEnvironmentCorpus.attentionStatus,
          reason: key,
        );
      }
    });

    test('平稳或未见负面主判断归入适宜状态', () {
      final status = FengshuiEnvironmentCorpus.deriveEnvironmentStatus(
        itemKey: '空地',
        sourceText: '坎宫见平整空地，无明显吉凶之象，主家宅运势平稳。',
      );

      expect(status, FengshuiEnvironmentCorpus.suitableStatus);
    });

    test('结果值严格限定为两种', () {
      final samples = [
        ('大山', '坎宫见端庄大山拱护，为上吉合局。'),
        ('水井', '坎宫绝对不可设水井。'),
        ('空地', '无明显吉凶之象。'),
      ];

      for (final sample in samples) {
        final status = FengshuiEnvironmentCorpus.deriveEnvironmentStatus(
          itemKey: sample.$1,
          sourceText: sample.$2,
        );
        expect(
          {
            FengshuiEnvironmentCorpus.suitableStatus,
            FengshuiEnvironmentCorpus.attentionStatus,
          },
          contains(status),
        );
      }
    });

    test('完整八宫词库的所有条目都只能生成二态结果', () async {
      final document = await FengshuiEnvironmentCorpus.loadStructuredDocument();
      var entryCount = 0;

      for (final palace in document.values) {
        if (palace is! Map) continue;
        for (final field in ['outdoor', 'indoor', 'malformation']) {
          final entries = palace[field];
          if (entries is! List) continue;
          for (final entry in entries) {
            if (entry is! Map) continue;
            entryCount++;
            final status = FengshuiEnvironmentCorpus.deriveEnvironmentStatus(
              itemKey: '${entry['key'] ?? ''}',
              sourceText: '${entry['text'] ?? ''}',
            );
            expect(
              {
                FengshuiEnvironmentCorpus.suitableStatus,
                FengshuiEnvironmentCorpus.attentionStatus,
              },
              contains(status),
            );
          }
        }
      }

      expect(entryCount, greaterThan(800));
    });
  });
}
