import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../core/network/api_session_scope.dart';
import '../ziwei/ziwei_models.dart';
import 'partner_portrait_models.dart';

class PartnerPortraitException implements Exception {
  const PartnerPortraitException(
    this.message, {
    this.reason = '',
    this.balance = 0,
    this.requiredAmount = 0,
  });

  final String message;
  final String reason;
  final double balance;
  final double requiredAmount;

  @override
  String toString() => message;
}

class PartnerPortraitService {
  PartnerPortraitService._();

  static final _previewRequests = <String, Future<PartnerPortraitState>>{};

  static Future<PartnerPortraitState> preview(
    ZiweiProfile profile, {
    ApiSessionScope? scope,
  }) {
    final bound = scope ?? ApiSessionScope();
    final payload = _chartPayload(profile);
    final key = '${bound.session}:${jsonEncode(payload)}';
    // 只合并同账号、同档案的在途读取；完成后仍重新查询购买状态和价格。
    return _previewRequests.putIfAbsent(key, () {
      return _preview(payload, bound).whenComplete(() {
        _previewRequests.remove(key);
      });
    });
  }

  static Future<PartnerPortraitState> _preview(
    Map<String, dynamic> payload,
    ApiSessionScope scope,
  ) async {
    try {
      final response = await scope.post(
        '/api/fortune/partner-portrait/preview',
        data: payload,
        receiveTimeout: const Duration(seconds: 30),
      );
      return _stateFromResponse(response.data);
    } on ApiSessionChangedException {
      rethrow;
    } on PartnerPortraitException {
      rethrow;
    } on DioException catch (error) {
      throw _dioError(error, '伴侣画像加载失败，请稍后重试');
    } catch (_) {
      throw const PartnerPortraitException('伴侣画像加载失败，请稍后重试');
    }
  }

  static Future<PartnerPortraitState> purchase(
    ZiweiProfile profile, {
    required String kind,
    String? testId,
    List<String> testIds = const <String>[],
    required String requestKey,
    ApiSessionScope? scope,
  }) async {
    try {
      final response = await (scope ?? ApiSessionScope()).post(
        '/api/fortune/partner-portrait/purchase',
        data: <String, dynamic>{
          ..._chartPayload(profile),
          'kind': kind,
          'requestKey': requestKey,
          if (testId != null) 'testId': testId,
          if (testIds.isNotEmpty) 'testIds': testIds,
        },
        receiveTimeout: const Duration(seconds: 95),
      );
      return _stateFromResponse(response.data);
    } on ApiSessionChangedException {
      rethrow;
    } on PartnerPortraitException {
      rethrow;
    } on DioException catch (error) {
      throw _dioError(error, '解锁失败，请稍后重试');
    } catch (_) {
      throw const PartnerPortraitException('解锁失败，请稍后重试');
    }
  }

  static PartnerPortraitState _stateFromResponse(dynamic payload) {
    if (payload is! Map) {
      throw const PartnerPortraitException('服务返回异常，请稍后重试');
    }
    final root = Map<String, dynamic>.from(payload);
    if (root['code'] != 0 || root['data'] is! Map) {
      throw PartnerPortraitException(root['message']?.toString() ?? '暂时无法完成操作');
    }
    return PartnerPortraitState.fromJson(
      Map<String, dynamic>.from(root['data'] as Map),
    );
  }

  static PartnerPortraitException _dioError(
    DioException error,
    String fallback,
  ) {
    final body = error.response?.data;
    final root = body is Map ? Map<String, dynamic>.from(body) : null;
    final data = root?['data'];
    final detail = data is Map ? Map<String, dynamic>.from(data) : null;
    return PartnerPortraitException(
      root?['message']?.toString().trim().isNotEmpty == true
          ? root!['message'].toString()
          : fallback,
      reason: detail?['reason']?.toString() ?? '',
      balance: _asDouble(detail?['walletBalance']),
      requiredAmount: _asDouble(detail?['required']),
    );
  }

  static Map<String, dynamic> _chartPayload(ZiweiProfile profile) {
    final now = DateTime.now();
    return <String, dynamic>{
      'birthDate': _date(profile.effectiveBirthDate),
      'birthTimeIndex': profile.birthTimeIndex,
      'gender': profile.gender,
      'targetDate': _date(now),
      'targetTimeIndex': ZiweiProfile.timeIndexFor(now.hour),
      'fixLeap': profile.settings.fixLeap,
      'astroType': profile.settings.astroType,
      'config': profile.settings.toRequestConfig(),
    };
  }

  static String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static double _asDouble(dynamic value) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
}
