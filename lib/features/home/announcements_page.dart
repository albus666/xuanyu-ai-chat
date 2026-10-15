import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/app_toast.dart';
import '../../core/theme/app_text_styles.dart';

/// 后台公告列表页（首页右上角入口）
class AnnouncementsPage extends StatefulWidget {
  const AnnouncementsPage({super.key});

  @override
  State<AnnouncementsPage> createState() => _AnnouncementsPageState();
}

class _AnnouncementsPageState extends State<AnnouncementsPage> {
  final _list = <Map<String, dynamic>>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await apiClient.get('/api/config/announcements');
      final data = (res.data as Map?)?['data'];
      if (data is List && mounted) {
        setState(() {
          _list.clear();
          for (final e in data) {
            if (e is Map<String, dynamic>) _list.add(Map<String, dynamic>.from(e));
          }
        });
      }
    } on DioException catch (e) {
      if (mounted) {
        setState(() => _error = e.response?.data is Map && (e.response!.data as Map).containsKey('message')
            ? (e.response!.data as Map)['message']?.toString()
            : '加载失败');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        centerTitle: true,
        title: Text('平台公告', style: AppTextStyles.titleMedium),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textHint)),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: _load,
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                )
              : _list.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.campaign_outlined, size: 64, color: AppColors.textHint.withOpacity(0.5)),
                          const SizedBox(height: 16),
                          Text('暂无公告', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textHint)),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      color: AppColors.primary,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                        itemCount: _list.length,
                        itemBuilder: (context, index) {
                          final item = _list[index];
                          return _buildItem(item);
                        },
                      ),
                    ),
    );
  }

  Widget _buildItem(Map<String, dynamic> item) {
    final title = item['title'] as String? ?? '公告';
    final content = item['content'] as String? ?? '';
    final linkUrl = item['linkUrl'] as String?;
    final createdAt = item['createdAt'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: InkWell(
        onTap: linkUrl != null && linkUrl.trim().isNotEmpty
            ? () {
                try {
                  final uri = Uri.tryParse(linkUrl);
                  if (uri != null) {
                    // 可在此用 url_launcher 打开
                    showAppToast(context, '链接: $linkUrl');
                  }
                } catch (_) {}
              }
            : null,
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.campaign_rounded, size: 20, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: AppTextStyles.titleSmall.copyWith(fontSize: 16),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (createdAt != null && createdAt.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(createdAt, style: AppTextStyles.bodySmall.copyWith(color: AppColors.textHint, fontSize: 12)),
            ],
            if (content.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                content,
                style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary, height: 1.5),
                maxLines: 10,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (linkUrl != null && linkUrl.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Text('查看详情', style: AppTextStyles.bodySmall.copyWith(color: AppColors.primary, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_forward_ios_rounded, size: 12, color: AppColors.primary),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
