import 'package:xuanyu/core/network/api_session_scope.dart';
import 'package:xuanyu/features/role_diagnosis/models/role_diagnosis_models.dart';

class RoleDiagnosisApiResult {
  const RoleDiagnosisApiResult({
    required this.report,
    required this.cacheable,
  });

  final RoleDiagnosisReport report;
  final bool cacheable;
}

class RoleDiagnosisApiService {
  RoleDiagnosisApiService._();

  static Future<RoleDiagnosisApiResult> diagnose({
    ApiSessionScope? session,
    required DateTime birth,
    required int hour,
    required bool isMale,
    bool waitForLongReport = true,
  }) async {
    final bound = session ?? ApiSessionScope();
    RoleDiagnosisReport? latest;
    // qwen-plus 首次长报告实测约 60 秒；预留 90 秒窗口，缓存命中仍会首轮返回。
    for (var attempt = 0; attempt < 45; attempt++) {
      final response = await bound.post(
        '/api/fortune/role-diagnosis',
        data: {
          'birthDate':
              '${birth.year.toString().padLeft(4, '0')}-${birth.month.toString().padLeft(2, '0')}-${birth.day.toString().padLeft(2, '0')}',
          'birthTime': '${hour.toString().padLeft(2, '0')}:00',
          'gender': isMale ? 'male' : 'female',
        },
        sendTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
      );
      final body = response.data;
      if (body == null || body['code'] != 0 || body['data'] is! Map) {
        throw StateError(body?['message']?.toString() ?? '角色诊断服务暂不可用');
      }
      final data = Map<String, dynamic>.from(body['data'] as Map);
      latest = RoleDiagnosisReport.fromApiJson(data);
      final generationStatus = data['generationStatus']?.toString() ?? 'ready';
      if (generationStatus != 'pending' || !waitForLongReport) {
        return RoleDiagnosisApiResult(
          report: latest,
          cacheable: generationStatus == 'ready' || !waitForLongReport,
        );
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    if (latest == null) {
      throw StateError('角色诊断服务暂不可用');
    }
    return RoleDiagnosisApiResult(
      report: latest,
      cacheable: false,
    );
  }
}
