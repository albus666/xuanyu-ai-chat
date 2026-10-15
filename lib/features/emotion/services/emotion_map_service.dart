import 'package:dio/dio.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/features/emotion/models/emotion_type.dart';
import 'package:xuanyu/features/emotion/models/identity_type.dart';

class EmotionMapService {
  EmotionMapService._();

  static Future<EmotionMapOverview> overview({IdentityType? identity}) async {
    final response =
        await apiClient.get('/api/emotion/overview', queryParameters: {
      if (identity != null) 'identity': identity.name,
    });
    final data = (response.data as Map?)?['data'] as Map? ?? const {};
    return EmotionMapOverview.fromJson(Map<String, dynamic>.from(data));
  }

  static Future<EmotionFeedPage> feed(
      {String? province,
      String? city,
      String? district,
      String? township}) async {
    final response = await apiClient.get('/api/emotion/feed', queryParameters: {
      if (province?.isNotEmpty == true) 'province': province,
      if (city?.isNotEmpty == true) 'city': city,
      if (district?.isNotEmpty == true) 'district': district,
      if (township?.isNotEmpty == true) 'township': township,
      'page_size': 100,
    });
    final data = (response.data as Map?)?['data'] as Map? ?? const {};
    return EmotionFeedPage.fromJson(Map<String, dynamic>.from(data));
  }

  static Future<void> publish({
    required IdentityType identity,
    required EmotionType emotion,
    required String province,
    String? city,
    String? district,
    String? township,
    double? latitude,
    double? longitude,
    bool chatAllowed = false,
    String? content,
  }) async {
    await apiClient.post('/api/emotion/checkins', data: {
      'identity': identity.name,
      'emotion': emotion.name,
      'province': province,
      'city': city,
      'district': district,
      'township': township,
      'latitude': latitude,
      'longitude': longitude,
      'chatAllowed': chatAllowed,
      'content': content,
    });
  }

  static Future<EmotionChatTarget> startChat(int checkinId) async {
    final response =
        await apiClient.post('/api/emotion/checkins/$checkinId/chat');
    final data = (response.data as Map?)?['data'] as Map? ?? const {};
    return EmotionChatTarget.fromJson(Map<String, dynamic>.from(data));
  }

  static Future<({bool liked, int likeCount})> toggleLike(int id) async {
    final response = await apiClient.post('/api/emotion/checkins/$id/like');
    final data = (response.data as Map?)?['data'] as Map? ?? const {};
    return (
      liked: data['liked'] == true,
      likeCount: (data['likeCount'] as num?)?.toInt() ?? 0
    );
  }

  static String message(Object error) {
    if (error is DioException) {
      return ((error.response?.data as Map?)?['message']?.toString()) ??
          '情绪地图暂时无法连接';
    }
    return '情绪地图暂时无法连接';
  }
}

class EmotionMapOverview {
  const EmotionMapOverview({required this.total, required this.regions});
  final int total;
  final List<EmotionRegion> regions;
  factory EmotionMapOverview.fromJson(Map<String, dynamic> json) =>
      EmotionMapOverview(
        total: (json['total'] as num?)?.toInt() ?? 0,
        regions: ((json['regions'] as List?) ?? const [])
            .whereType<Map>()
            .map((item) =>
                EmotionRegion.fromJson(Map<String, dynamic>.from(item)))
            .toList(),
      );
}

class EmotionRegion {
  const EmotionRegion(
      {required this.province, required this.count, required this.emotion});
  final String province;
  final int count;
  final EmotionType emotion;
  factory EmotionRegion.fromJson(Map<String, dynamic> json) => EmotionRegion(
        province: json['province']?.toString() ?? '',
        count: (json['count'] as num?)?.toInt() ?? 0,
        emotion: EmotionType.values.firstWhere(
            (item) => item.name == json['emotion'],
            orElse: () => EmotionType.zen),
      );
}

class EmotionFeedPage {
  const EmotionFeedPage({required this.items});
  final List<EmotionCheckin> items;
  factory EmotionFeedPage.fromJson(Map<String, dynamic> json) =>
      EmotionFeedPage(
        items: ((json['list'] as List?) ?? const [])
            .whereType<Map>()
            .map((item) =>
                EmotionCheckin.fromJson(Map<String, dynamic>.from(item)))
            .toList(),
      );
}

class EmotionCheckin {
  EmotionCheckin(
      {required this.id,
      required this.nickname,
      required this.identity,
      required this.emotion,
      required this.province,
      required this.city,
      required this.district,
      required this.township,
      required this.latitude,
      required this.longitude,
      required this.chatAllowed,
      required this.isMine,
      required this.content,
      required this.likeCount,
      required this.liked,
      required this.createdAt});
  final int id;
  final String nickname;
  final IdentityType identity;
  final EmotionType emotion;
  final String province;
  final String city;
  final String district;
  final String township;
  final double? latitude;
  final double? longitude;
  final bool chatAllowed;
  final bool isMine;
  final String content;
  int likeCount;
  bool liked;
  final String? createdAt;
  factory EmotionCheckin.fromJson(Map<String, dynamic> json) => EmotionCheckin(
        id: (json['id'] as num?)?.toInt() ?? 0,
        nickname: json['nickname']?.toString() ?? '匿名用户',
        identity: IdentityType.values.firstWhere(
            (item) => item.name == json['identity'],
            orElse: () => IdentityType.worker),
        emotion: EmotionType.values.firstWhere(
            (item) => item.name == json['emotion'],
            orElse: () => EmotionType.zen),
        province: json['province']?.toString() ?? '',
        city: json['city']?.toString() ?? '',
        district: json['district']?.toString() ?? '',
        township: json['township']?.toString() ?? '',
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        chatAllowed: json['chatAllowed'] == true,
        isMine: json['isMine'] == true,
        content: json['content']?.toString() ?? '',
        likeCount: (json['likeCount'] as num?)?.toInt() ?? 0,
        liked: json['liked'] == true,
        createdAt: json['createdAt']?.toString(),
      );
}

class EmotionChatTarget {
  const EmotionChatTarget({
    required this.conversationId,
    required this.title,
    required this.peerUserId,
  });

  final int conversationId;
  final String title;
  final int peerUserId;

  factory EmotionChatTarget.fromJson(Map<String, dynamic> json) =>
      EmotionChatTarget(
        conversationId: (json['conversationId'] as num?)?.toInt() ?? 0,
        title: json['title']?.toString() ?? '同频旅人',
        peerUserId: (json['peerUserId'] as num?)?.toInt() ?? 0,
      );
}
