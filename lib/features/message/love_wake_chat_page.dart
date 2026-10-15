import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/ai_generated_mark.dart';
import '../../core/widgets/app_gpt_markdown.dart';

class LoveWakeChatPage extends StatefulWidget {
  const LoveWakeChatPage({super.key});

  @override
  State<LoveWakeChatPage> createState() => _LoveWakeChatPageState();
}

class _LoveWakeChatPageState extends State<LoveWakeChatPage> {
  final _messages = <Map<String, String>>[
    {
      'role': 'assistant',
      'content': AiGeneratedMark.ensureTextMark(
          '把你的情况说清楚，我来直接点：该清醒的地方我不会绕弯子。'),
    },
  ];
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() {
      _messages.add({'role': 'user', 'content': text});
      _sending = true;
      _controller.clear();
    });
    _jumpToBottom();
    try {
      final res = await apiClient.post('/api/fortune/ai-love-wake-chat', data: {'message': text});
      final data = (res.data as Map?)?['data'] as Map?;
      final reply = (data?['content'] as String?)?.trim();
      setState(() {
        _messages.add({
          'role': 'assistant',
          'content': AiGeneratedMark.ensureTextMark(
              (reply == null || reply.isEmpty)
                  ? '先暂停联系 24 小时，先把自己睡饱。'
                  : reply),
        });
      });
    } on DioException catch (e) {
      String msg = '网络异常，请稍后重试';
      final data = e.response?.data;
      if (data is Map && data['message'] != null) {
        final m = data['message'].toString().trim();
        if (m.isNotEmpty) msg = m;
      }
      setState(() {
        _messages.add({'role': 'assistant', 'content': '出错了：$msg'});
      });
    } finally {
      setState(() => _sending = false);
      _jumpToBottom();
    }
  }

  void _jumpToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent + 120,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text('骂醒恋爱脑', style: AppTextStyles.titleMedium),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: const Color(0xFFFDECEC),
            child: const Text(
              'AI生成内容 · 仅供情感交流参考，不替代专业咨询',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Color(0xFFB91C1C)),
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              itemCount: _messages.length,
              itemBuilder: (_, i) {
                final m = _messages[i];
                final isUser = m['role'] == 'user';
                return Align(
                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    padding: const EdgeInsets.all(12),
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
                    decoration: BoxDecoration(
                      color: isUser ? const Color(0xFFFFE5E5) : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFF2D0D0)),
                    ),
                    child: isUser
                        ? Text(m['content'] ?? '', style: AppTextStyles.bodyMedium)
                        : AppGptMarkdown(data: m['content'] ?? '', bodyStyle: AppTextStyles.bodyMedium),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: '把让你上头的事说出来…',
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.withOpacity(0.2)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _sending ? null : _send,
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626), foregroundColor: Colors.white),
                    child: Text(_sending ? '发送中' : '发送'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
