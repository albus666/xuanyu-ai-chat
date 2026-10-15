import 'conversation_preview.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../core/network/api_client.dart';
import '../../core/utils/date_utils.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import 'chat_page.dart';

/// 名师咨询：与名师对话的会话列表
class MasterConsultPage extends StatefulWidget {
  const MasterConsultPage({super.key, this.onChatTapped});

  final VoidCallback? onChatTapped;

  @override
  State<MasterConsultPage> createState() => _MasterConsultPageState();
}

class _MasterConsultPageState extends State<MasterConsultPage> {
  final _list = <Map<String, dynamic>>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  static String _lastMessageLabel(String raw) => conversationPreview(raw);

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await apiClient.get('/api/im/conversations/master-consult');
      final data = (res.data as Map?)?['data'] as Map?;
      final list = data?['list'] as List<dynamic>?;
      if (mounted) {
        setState(() {
          _list.clear();
          if (list != null) {
            for (final e in list) {
              if (e is Map<String, dynamic>) {
                _list.add(Map<String, dynamic>.from(e));
              }
            }
          }
          _loading = false;
        });
      }
    } on DioException catch (_) {
      if (mounted) setState(() => _list.clear());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('名师咨询'),
      ),
      body: _loading && _list.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _list.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        const SizedBox(height: 80),
                        const Icon(Icons.person_search,
                            size: 64, color: AppColors.textHint),
                        const SizedBox(height: 16),
                        Center(
                          child: Text(
                            '暂无名师咨询对话',
                            style: AppTextStyles.bodyMedium
                                .copyWith(color: AppColors.textHint),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Center(
                          child: Text(
                            '从首页进入「名师咨询」与名师沟通后，对话将显示在此',
                            style: AppTextStyles.bodySmall
                                .copyWith(color: AppColors.textHint),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      itemCount: _list.length,
                      itemBuilder: (context, index) {
                        final c = _list[index];
                        final id = (c['conversationId'] as num?)?.toInt();
                        final title = c['title'] as String? ?? '名师';
                        final last = c['lastMessage'] as String? ?? '';
                        final time = c['lastMessageAt'] as String? ?? '';
                        final unread = (c['unreadCount'] as num?)?.toInt() ?? 0;
                        if (id == null) return const SizedBox.shrink();
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: AppColors.primaryLight,
                            child: Text(title.isNotEmpty ? title[0] : '师',
                                style: AppTextStyles.titleSmall),
                          ),
                          title: Row(
                            children: [
                              Text(title),
                              if (unread > 0) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.red,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '${unread > 99 ? "99+" : unread}',
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 12),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          subtitle: last.isNotEmpty
                              ? Text(_lastMessageLabel(last),
                                  maxLines: 1, overflow: TextOverflow.ellipsis)
                              : null,
                          trailing: time.isNotEmpty
                              ? Text(
                                  AppDateUtils.formatRelative(time),
                                  style: AppTextStyles.bodySmall
                                      .copyWith(color: AppColors.textHint),
                                )
                              : null,
                          onTap: () {
                            Navigator.of(context)
                                .push(
                                  MaterialPageRoute(
                                    builder: (_) => ChatPage(
                                      conversationId: id,
                                      title: title,
                                      conversationType: 'single',
                                    ),
                                  ),
                                )
                                .then((_) => _load());
                            widget.onChatTapped?.call();
                          },
                        );
                      },
                    ),
            ),
    );
  }
}
