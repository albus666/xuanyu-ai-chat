import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';
import 'post_media_cache.dart';

/// 主页作品/收藏共用分页：刷新优先、失败保留、按作品 ID 去重、会话隔离。
class ProfilePostFeed extends ChangeNotifier {
  ProfilePostFeed(this.endpoint, {this.pageSize = 30}) {
    apiSessionChanges.addListener(reset);
  }

  final String? Function() endpoint;
  final int pageSize;
  final items = <Map<String, dynamic>>[];
  bool loading = false;
  bool loaded = false;
  bool hasMore = true;
  int? total;
  String? error;
  int _page = 1;
  int _generation = 0;
  bool _retryRefresh = false;
  bool _disposed = false;

  void reset() {
    _generation++;
    items.clear();
    total = null;
    _page = 1;
    loaded = false;
    loading = false;
    hasMore = true;
    error = null;
    _retryRefresh = false;
    if (!_disposed) notifyListeners();
  }

  Future<void> refresh() => load(refresh: true);
  Future<void> retry() => load(refresh: _retryRefresh, retry: true);

  Future<void> load({bool refresh = false, bool retry = false}) async {
    final path = endpoint();
    if (_disposed || path == null) return;
    if (!refresh && (loading || !hasMore || (error != null && !retry))) return;
    final generation = ++_generation;
    final session = apiSessionChanges.value;
    final page = refresh ? 1 : _page;
    bool current() =>
        !_disposed &&
        generation == _generation &&
        session == apiSessionChanges.value &&
        path == endpoint();
    loading = true;
    error = null;
    notifyListeners();
    try {
      final response = await apiClient.get(
        path,
        queryParameters: {'page': page, 'page_size': pageSize},
        options: Options(headers: {
          'Authorization': apiClient.options.headers['Authorization']
        }),
      );
      if (!current()) return;
      final body = response.data;
      if (body is! Map ||
          (body['code'] != null && body['code'] != 0) ||
          body['data'] is! Map ||
          body['data']['list'] is! List) {
        throw const FormatException('列表返回无效');
      }
      final data = body['data'] as Map;
      final rows = data['list'] as List;
      total = (data['total'] as num?)?.toInt();
      if (rows.any((row) => row is! Map || row['id'] is! num)) {
        throw const FormatException('作品数据不完整');
      }
      final previous = {for (final item in items) item['id']: item};
      final merged = <int, Map<String, dynamic>>{
        if (!refresh)
          for (final item in items) (item['id'] as num).toInt(): item,
        for (final row in rows)
          (row['id'] as num).toInt(): reuseLoadedPostMedia(
              previous[row['id']], Map<String, dynamic>.from(row as Map)),
      };
      items
        ..clear()
        ..addAll(merged.values);
      _page = page + 1;
      // 空页即使后端误报 hasMore 也不能形成自动加载死循环。
      hasMore = rows.isNotEmpty && data['hasMore'] == true;
      loaded = true;
      _retryRefresh = false;
    } catch (_) {
      if (!current()) return;
      error = '加载失败，请重试';
      _retryRefresh = refresh;
    } finally {
      if (current()) {
        loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    apiSessionChanges.removeListener(reset);
    super.dispose();
  }
}

/// 失败时始终有明确重试入口，短列表不能触底时仍可手动加载下一页。
class ProfileFeedStatus extends StatelessWidget {
  const ProfileFeedStatus({super.key, required this.feed});
  final ProfilePostFeed feed;

  @override
  Widget build(BuildContext context) {
    if (feed.loading || feed.endpoint() == null) return const SizedBox.shrink();
    if (feed.error == null && !feed.hasMore) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (feed.error != null) Text(feed.error!),
        TextButton(
          onPressed: feed.error != null ? feed.retry : feed.load,
          child: Text(feed.error != null ? '重试加载' : '加载更多'),
        ),
      ]),
    );
  }
}
