import 'dart:math' as math;

import '../../../core/network/api_client.dart';
import '../models/wish_feed_state.dart';

class WishFeedService {
  const WishFeedService();

  static final math.Random _random = math.Random.secure();

  Future<WishFeedState> loadStatus() async {
    final response = await apiClient.get('/api/merit/wish-feeding/status');
    return WishFeedState.fromJson(_responseData(response.data));
  }

  Future<Map<String, dynamic>> purchase(String packageId) async {
    final response = await apiClient.post(
      '/api/merit/wish-feeding/purchase',
      data: <String, dynamic>{
        'packageId': packageId,
        'requestId': _requestId(),
      },
    );
    return _responseData(response.data);
  }

  Future<Map<String, dynamic>> feed(int quantity) async {
    final response = await apiClient.post(
      '/api/merit/wish-feeding/feed',
      data: <String, dynamic>{
        'requestId': _requestId(),
        'quantity': quantity,
      },
    );
    return _responseData(response.data);
  }

  static String _requestId() {
    final timestamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final first = _random.nextInt(1 << 32).toRadixString(36);
    final second = _random.nextInt(1 << 32).toRadixString(36);
    return '${timestamp}_$first$second';
  }

  static Map<String, dynamic> _responseData(Object? raw) {
    if (raw is! Map) return <String, dynamic>{};
    final data = raw['data'];
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }
}
