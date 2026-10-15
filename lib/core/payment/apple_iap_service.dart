import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import '../network/api_client.dart';

bool get usesAppleIap => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

class AppleSyncResult {
  const AppleSyncResult({this.delivered = 0, this.failed = 0});
  final int delivered;
  final int failed;
  String get message => failed > 0
      ? '仍有购买未同步，请检查网络并登录购买时的账号后重试'
      : delivered > 0
          ? '已同步 $delivered 笔购买'
          : '没有待同步的购买';
}

class AppleIapService with WidgetsBindingObserver {
  AppleIapService._();
  static final instance = AppleIapService._();
  static const _channel = MethodChannel('xuanyu/apple_iap');
  final changes = ValueNotifier<int>(0);
  final Map<String, Future<Map<String, dynamic>>> _deliveries = {};
  bool _initialized = false;
  int _session = 0;

  void initialize() {
    if (!usesAppleIap || _initialized) return;
    _initialized = true;
    WidgetsBinding.instance.addObserver(this);
    apiSessionChanges.addListener(() {
      _session++;
      unawaited(sync());
    });
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'transaction') {
        try {
          await _deliver(Map<String, dynamic>.from(call.arguments as Map));
        } catch (_) {
          // Keep the StoreKit transaction unfinished for a later authenticated retry.
        }
      }
    });
    unawaited(sync());
  }

  bool get _loggedIn => apiClient.options.headers['Authorization'] != null;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(sync());
  }

  Future<AppleSyncResult> sync() async {
    if (!usesAppleIap) return const AppleSyncResult();
    if (!_loggedIn) return const AppleSyncResult(failed: 1);
    var delivered = 0;
    var failed = 0;
    try {
      final pending =
          await _channel.invokeListMethod<dynamic>('unfinished') ?? [];
      for (final item in pending) {
        try {
          await _deliver(Map<String, dynamic>.from(item as Map));
          delivered++;
        } catch (_) {
          failed++;
          // An account mismatch or temporary failure must not consume a purchase.
        }
      }
    } catch (_) {
      failed++;
      // Retry on foreground, login, or opening the recharge page.
    }
    return AppleSyncResult(delivered: delivered, failed: failed);
  }

  Future<Map<String, dynamic>> _config() async {
    final response = await apiClient.get('/api/apple-iap/products');
    return Map<String, dynamic>.from(response.data['data'] as Map);
  }

  Future<List<Map<String, dynamic>>> products() async {
    initialize();
    final config = await _config();
    final configured = List<Map<String, dynamic>>.from(
      (config['products'] as List)
          .map((p) => Map<String, dynamic>.from(p as Map)),
    );
    final native = await _channel.invokeListMethod<dynamic>('products', {
          'ids': configured.map((p) => p['id']).toList(),
        }) ??
        [];
    return configured
        .expand((p) => native
            .where((n) => n['id'] == p['id'])
            .map((n) => {...p, 'title': n['title'], 'price': n['price']}))
        .toList();
  }

  Future<Map<String, dynamic>> productDiagnostics() async {
    final config = await _config();
    final configured = List<Map<String, dynamic>>.from(
      (config['products'] as List)
          .map((p) => Map<String, dynamic>.from(p as Map)),
    );
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'productDiagnostics',
      {'ids': configured.map((p) => p['id']).toList()},
    );
    return Map<String, dynamic>.from(result ?? const {});
  }

  Future<Map<String, dynamic>> purchase(String productId) async {
    final session = _session;
    final config = await _config();
    if (session != _session) throw StateError('登录账号已变更，请重新购买');
    final result = await _channel.invokeMapMethod<String, dynamic>('purchase', {
      'id': productId,
      'appAccountToken': config['appAccountToken'],
    });
    if (result == null) throw StateError('苹果未返回购买结果');
    if (result['status'] != null) return result;
    return _deliver(Map<String, dynamic>.from(result));
  }

  Future<Map<String, dynamic>> _deliver(Map<String, dynamic> item) async {
    if (!_loggedIn) throw StateError('请先登录');
    final id = item['transactionId'] as String;
    final key = '$_session:$id';
    final existing = _deliveries[key];
    if (existing != null) return existing;
    final future = _verifyAndFinish(item);
    _deliveries[key] = future;
    try {
      return await future;
    } finally {
      _deliveries.remove(key);
    }
  }

  Future<Map<String, dynamic>> _verifyAndFinish(
      Map<String, dynamic> item) async {
    final session = _session;
    try {
      final response = await apiClient.post('/api/apple-iap/verify',
          data: {'signedTransaction': item['signedTransaction']},
          options: Options(receiveTimeout: const Duration(seconds: 60)));
      final body = response.data as Map;
      if (body['code'] != 0) {
        throw StateError(body['message']?.toString() ?? '购买验证失败');
      }
      final result = Map<String, dynamic>.from(body['data'] as Map);
      if (result['transactionId'] != item['transactionId']) {
        throw StateError('交易校验不一致');
      }
      if (session != _session) throw StateError('登录账号已变更，请重新同步购买');
      await _channel.invokeMethod<void>(
          'finish', {'transactionId': item['transactionId']});
      changes.value++;
      return result;
    } on DioException catch (e) {
      final data = e.response?.data;
      throw StateError(data is Map
          ? data['message']?.toString() ?? '验证失败'
          : '购买结果待同步，请稍后重新打开充值页');
    }
  }
}
