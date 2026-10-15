import 'package:dio/dio.dart';
import '../../core/network/api_client.dart';
import 'im_workflow_request.dart';

/// 按消息 ID 翻页，避免新消息插入后使用页码发生重复或遗漏。
class ChatMessageSync {
  ChatMessageSync(this.client, this.conversationId)
      : _session = apiSessionChanges.value,
        _options = Options(headers: {
          'Authorization': client.options.headers['Authorization']
        });
  final Dio client;
  final int conversationId;
  final int _session;
  final Options _options;

  Future<Map<String, dynamic>> page(
      {int? beforeId,
      Iterable<int> reconciliationIds = const [],
      int pageSize = 50}) async {
    if (_session != apiSessionChanges.value) {
      throw const ImWorkflowFailure(imSessionChangedMessage);
    }
    final response = await client.get(
      '/api/im/conversation/$conversationId/messages',
      queryParameters: {
        'page_size': pageSize,
        if (beforeId != null) 'before_id': beforeId,
        if (reconciliationIds.isNotEmpty)
          'reconciliation_ids': reconciliationIds.join(','),
      },
      options: _options,
    );
    if (_session != apiSessionChanges.value) {
      throw const ImWorkflowFailure(imSessionChangedMessage);
    }
    final data = imResponseData(response.data);
    imResponseList(data);
    return data;
  }

  /// 断线期间可能超过一页；一直补到已知最新消息，不能只取最近 50 条。
  Future<Map<String, dynamic>> refresh(
      {int? latestKnownId, Iterable<int> knownIds = const []}) async {
    final reconcile = knownIds.where((id) => id > 0).toSet().toList();
    final newest = await page(reconciliationIds: reconcile.take(100));
    final recalled = <int>{};
    void collect(Map data) {
      final ids = data['recalledIds'];
      if (ids is List) {
        recalled.addAll(ids.whereType<num>().map((id) => id.toInt()));
      }
      for (final row in imResponseList(data)) {
        if ((row['recalled'] == true || row['type'] == 'recalled') &&
            row['id'] is num) {
          recalled.add((row['id'] as num).toInt());
        }
      }
    }

    collect(newest);
    // Include loaded history and quoted originals, not only the latest page.
    for (var start = 100; start < reconcile.length; start += 100) {
      collect(await page(
          reconciliationIds: reconcile.skip(start).take(100), pageSize: 1));
    }
    final rows = List<dynamic>.from(newest['list'] as List? ?? const []);
    var pageData = newest;
    while (latestKnownId != null &&
        rows.isNotEmpty &&
        pageData['hasMore'] == true) {
      final ids = (pageData['list'] as List)
          .whereType<Map>()
          .map((item) => (item['id'] as num?)?.toInt())
          .whereType<int>();
      if (ids.isEmpty) break;
      final oldest = ids.reduce((a, b) => a < b ? a : b);
      if (oldest <= latestKnownId) break;
      pageData = await page(beforeId: oldest);
      collect(pageData);
      final older = pageData['list'] as List? ?? const [];
      if (older.isEmpty) break;
      final olderIds = older
          .whereType<Map>()
          .map((e) => (e['id'] as num?)?.toInt())
          .whereType<int>();
      if (olderIds.isEmpty || olderIds.every((id) => id >= oldest)) break;
      rows.insertAll(0, older);
    }
    return {...newest, 'list': rows, 'recalledIds': recalled.toList()};
  }
}
