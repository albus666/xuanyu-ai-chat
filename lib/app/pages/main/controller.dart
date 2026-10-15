import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:xuanyu/app/bootstrap/auth_state.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/core/network/presence_heartbeat.dart';
import 'package:xuanyu/features/community/create_post_page.dart';

class MainController extends GetxController {
  MainController();

  final PresenceHeartbeat _presenceHeartbeat = PresenceHeartbeat();

  int currentIndex = 0;

  @override
  void onInit() {
    super.onInit();
    if (Get.isRegistered<AuthState>()) {
      final a = Get.find<AuthState>();
      if (a.isMinorMode && (currentIndex == 2 || currentIndex == 3)) {
        currentIndex = 0;
      }
    }
    _presenceHeartbeat.attach();
    _updateLocationOnOpen();
  }

  @override
  void onClose() {
    _presenceHeartbeat.detach();
    super.onClose();
  }

  Future<void> _updateLocationOnOpen() async {
    try {
      final res = await apiClient.get('/api/config/ipLocation');
      final data = (res.data as Map?)?['data'] as Map?;
      final loc = (data?['location'] as String?)?.trim();
      if (loc == null || loc.isEmpty) return;
      if (loc == '未知' || loc == '本地' || loc == '内网') return;
      await apiClient.post('/api/auth/location', data: {'locationCode': loc});
    } on DioException catch (e) {
      if (kDebugMode) {
        debugPrint('[ipLocation] 更新失败: ${e.message} code=${e.response?.statusCode}');
      }
    }
  }

  void onTap(int idx) {
    final auth = Get.find<AuthState>();
    if (auth.isMinorMode && (idx == 2 || idx == 3)) {
      Get.snackbar('提示', '未成年人模式下暂不可使用该功能', snackPosition: SnackPosition.BOTTOM);
      return;
    }
    if (idx == 2) {
      Get.to<dynamic>(() => const CreatePostPage());
      return;
    }
    if (idx == currentIndex) return;
    currentIndex = idx;
    update(['main']);
  }
}
