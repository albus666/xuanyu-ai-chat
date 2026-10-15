import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_constants.dart';
import 'im_workflow_request.dart';

class ChatAppearance {
  const ChatAppearance({
    this.background = 'plain',
    this.bubble = 'mint',
  });

  final String background;
  final String bubble;

  BoxDecoration get backgroundDecoration => switch (background) {
        'mist' => const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFEAF8F7), Color(0xFFF8F4FB)],
            ),
          ),
        'star' => const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFDDECF6), Color(0xFFF8EEF3)],
            ),
          ),
        _ => const BoxDecoration(color: Color(0xFFF7F9FA)),
      };

  Color get myBubbleColor => switch (bubble) {
        'teal' => const Color(0xFFBCEDE8),
        'blue' => const Color(0xFFD9E9FF),
        _ => const Color(0xFFD8F7E8),
      };

  Color get peerBubbleColor => Colors.white;
}

String _styleKey(int userId, int conversationId, String kind) =>
    'chat_style_account_${userId}_${conversationId}_$kind';

Future<ChatAppearance> loadChatAppearance(int conversationId) async {
  final scope = ImWorkflowRequest();
  final prefs = await SharedPreferences.getInstance();
  if (!scope.current) return const ChatAppearance();
  final userId = prefs.getInt(AppConstants.keyUserId);
  if (userId == null) return const ChatAppearance();
  // 旧全局样式没有账号归属，保留原键但不自动分配给当前账号。
  final background =
      prefs.getString(_styleKey(userId, conversationId, 'background'));
  final bubble = prefs.getString(_styleKey(userId, conversationId, 'bubble'));
  return ChatAppearance(
    background:
        chatBackgroundChoices.containsKey(background) ? background! : 'plain',
    bubble: chatBubbleChoices.containsKey(bubble) ? bubble! : 'mint',
  );
}

Future<void> _saveStyle(int conversationId, String kind, String value) async {
  final scope = ImWorkflowRequest();
  final prefs = await SharedPreferences.getInstance();
  if (!scope.current) throw const ImWorkflowFailure(imSessionChangedMessage);
  final userId = prefs.getInt(AppConstants.keyUserId);
  if (userId == null) throw const ImWorkflowFailure('请登录后设置');
  final choices =
      kind == 'background' ? chatBackgroundChoices : chatBubbleChoices;
  if (!choices.containsKey(value)) throw const ImWorkflowFailure('样式无效');
  if (!await prefs.setString(_styleKey(userId, conversationId, kind), value)) {
    throw const ImWorkflowFailure('样式保存失败，请重试');
  }
}

Future<void> saveChatBackground(int conversationId, String value) =>
    _saveStyle(conversationId, 'background', value);
Future<void> saveChatBubble(int conversationId, String value) =>
    _saveStyle(conversationId, 'bubble', value);

enum ChatAppearancePickerType { background, bubble }

const chatBackgroundChoices = <String, String>{
  'plain': '清爽浅灰',
  'mist': '青雾渐变',
  'star': '星海柔光',
};

const chatBubbleChoices = <String, String>{
  'mint': '薄荷绿',
  'teal': '玄青色',
  'blue': '柔和蓝',
};

/// 聊天背景和气泡共用的可视化选择器，选择前即可看到实际聊天效果。
Future<String?> showChatAppearancePicker(
  BuildContext context, {
  required String title,
  required String current,
  required ChatAppearancePickerType type,
}) {
  final choices = type == ChatAppearancePickerType.background
      ? chatBackgroundChoices
      : chatBubbleChoices;
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.white,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 14),
            ...choices.entries.map((entry) {
              final selected = entry.key == current;
              final appearance = type == ChatAppearancePickerType.background
                  ? ChatAppearance(background: entry.key)
                  : ChatAppearance(bubble: entry.key);
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: InkWell(
                  key: ValueKey('chat-appearance-${type.name}-${entry.key}'),
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => Navigator.pop(context, entry.key),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xFFF1FBFA)
                          : const Color(0xFFF8F9FA),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: selected
                            ? const Color(0xFF25BDB8)
                            : const Color(0xFFE9EBED),
                        width: selected ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 116,
                          height: 68,
                          padding: const EdgeInsets.fromLTRB(8, 9, 8, 8),
                          decoration: appearance.backgroundDecoration.copyWith(
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Container(
                                  height: 18,
                                  width: 60,
                                  decoration: BoxDecoration(
                                    color: appearance.peerBubbleColor,
                                    borderRadius: BorderRadius.circular(9),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Color(0x10000000),
                                        blurRadius: 3,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 7),
                              Align(
                                alignment: Alignment.centerRight,
                                child: Container(
                                  height: 18,
                                  width: 68,
                                  decoration: BoxDecoration(
                                    color: appearance.myBubbleColor,
                                    borderRadius: BorderRadius.circular(9),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            entry.value,
                            style: const TextStyle(
                              color: Color(0xFF25272B),
                              fontSize: 17,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Icon(
                          selected
                              ? Icons.radio_button_checked_rounded
                              : Icons.radio_button_off_rounded,
                          color: selected
                              ? const Color(0xFF25BDB8)
                              : const Color(0xFFB8B8BD),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    ),
  );
}
