import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xuanyu/core/constants/app_constants.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/features/message/chat_appearance.dart';
import 'package:xuanyu/features/message/im_workflow_request.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() =>
      SharedPreferences.setMockInitialValues({AppConstants.keyUserId: 7}));
  test('同群聊不同账号的样式互不覆盖，切回账号可恢复', () async {
    final prefs = await SharedPreferences.getInstance();
    await saveChatBackground(12, 'star');
    await saveChatBubble(12, 'blue');
    await prefs.setInt(AppConstants.keyUserId, 8);
    apiSessionChanges.value++;
    expect((await loadChatAppearance(12)).background, 'plain');
    expect((await loadChatAppearance(12)).bubble, 'mint');
    await saveChatBackground(12, 'mist');
    await prefs.setInt(AppConstants.keyUserId, 7);
    apiSessionChanges.value++;
    expect((await loadChatAppearance(12)).background, 'star');
    expect((await loadChatAppearance(12)).bubble, 'blue');
  });
  test('不同会话的样式各自保存', () async {
    await saveChatBackground(12, 'mist');
    expect((await loadChatAppearance(13)).background, 'plain');
  });
  test('无归属旧值保留但不分配给当前账号', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('chat_background_12', 'star');
    expect((await loadChatAppearance(12)).background, 'plain');
    expect(prefs.getString('chat_background_12'), 'star');
  });
  test('异常样式不会写入，不登录不能写账号设置', () async {
    await expectLater(
        saveChatBubble(12, 'invalid'), throwsA(isA<ImWorkflowFailure>()));
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppConstants.keyUserId);
    await expectLater(
        saveChatBackground(12, 'star'), throwsA(isA<ImWorkflowFailure>()));
    expect(prefs.getKeys().where((k) => k.startsWith('chat_style_account_')),
        isEmpty);
  });
}
