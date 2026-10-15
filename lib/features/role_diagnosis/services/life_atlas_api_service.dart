import '../../../core/network/api_session_scope.dart';
import '../engine/life_atlas_narrative_fallback.dart';
import '../models/life_atlas_models.dart';
import '../models/role_diagnosis_models.dart';

class LifeAtlasApiService {
  LifeAtlasApiService._();

  static Future<Map<String, LifeAtlasRarityStat>> syncAnswers(
      Map<String, LifeAtlasAnswer> answers,
      {ApiSessionScope? session}) async {
    if (answers.isEmpty) return const {};
    final response = await (session ?? ApiSessionScope()).post(
      '/api/fortune/life-atlas/answers',
      data: {
        'answers': {
          for (final item in answers.entries) item.key: item.value.storageValue,
        },
      },
    );
    final body = response.data;
    if (body == null || body['code'] != 0 || body['data'] is! Map) {
      return const {};
    }
    final data = Map<String, dynamic>.from(body['data'] as Map);
    final raw = Map<String, dynamic>.from(
      data['statistics'] as Map? ?? const {},
    );
    return {
      for (final item in raw.entries)
        if (item.value is Map)
          item.key: LifeAtlasRarityStat.fromJson(
            Map<String, dynamic>.from(item.value as Map),
          ),
    };
  }

  static Future<LifeAtlasEventAnalysis> analyzeEvent(String eventText,
      {ApiSessionScope? session}) async {
    final bound = session ?? ApiSessionScope();
    try {
      final response = await bound.post(
        '/api/fortune/life-atlas/analyze',
        data: {'eventText': eventText.trim()},
      );
      final body = response.data;
      if (body == null || body['code'] != 0 || body['data'] is! Map) {
        throw StateError(body?['message']?.toString() ?? '暂时无法理解这件事');
      }
      return LifeAtlasEventAnalysis.fromJson(
        Map<String, dynamic>.from(body['data'] as Map),
      );
    } catch (_) {
      return LifeAtlasNarrativeFallback.analyze(eventText);
    }
  }

  static Future<LifeAtlasGeneratedTitles> generateEvent({
    ApiSessionScope? session,
    required String eventText,
    required LifeAtlasEventAnalysis analysis,
    required LifeAtlasMeaningOption meaning,
    required RoleDiagnosisReport report,
  }) async {
    try {
      final response = await (session ?? ApiSessionScope()).post(
        '/api/fortune/life-atlas/generate',
        data: {
          'eventText': eventText.trim(),
          'analysis': analysis.toJson(),
          'meaning': {'id': meaning.id, 'label': meaning.label},
          'bazi': {
            'pillars': report.pillars,
            'dayMaster': report.dayMaster,
            'dominantGod': report.dominantGod,
          },
        },
      );
      final body = response.data;
      if (body == null || body['code'] != 0 || body['data'] is! Map) {
        throw StateError(body?['message']?.toString() ?? '称号生成失败');
      }
      final data = Map<String, dynamic>.from(body['data'] as Map);
      final serverAnalysis = LifeAtlasEventAnalysis.fromJson(
        Map<String, dynamic>.from(
            data['analysis'] as Map? ?? analysis.toJson()),
      );
      final candidates = (data['candidates'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => LifeAtlasAchievement.fromJson(
                Map<String, dynamic>.from(item),
              ))
          .where((item) => item.title.isNotEmpty && item.quote.isNotEmpty)
          .take(3)
          .toList(growable: false);
      if (candidates.length < 3) throw StateError('候选称号不足');
      return LifeAtlasGeneratedTitles(
        analysis: serverAnalysis,
        candidates: candidates,
      );
    } catch (_) {
      return LifeAtlasGeneratedTitles(
        analysis: analysis,
        candidates: LifeAtlasNarrativeFallback.generate(
          input: eventText,
          analysis: analysis,
          meaning: meaning,
          report: report,
        ),
      );
    }
  }

  static Future<LifeAtlasRarityStat?> unlockEvent(String eventKey,
      {ApiSessionScope? session}) async {
    try {
      final response = await (session ?? ApiSessionScope()).post(
        '/api/fortune/life-atlas/unlock',
        data: {'eventKey': eventKey},
      );
      final body = response.data;
      if (body == null || body['code'] != 0 || body['data'] is! Map) {
        return null;
      }
      return LifeAtlasRarityStat.fromJson(
        Map<String, dynamic>.from(body['data'] as Map),
      );
    } catch (_) {
      return null;
    }
  }
}
