import 'consultation_call_overlay.dart';
import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_session_scope.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/app_toast.dart';
import 'teacher_settlement_amount.dart';
import 'teacher_profile_editor_page.dart';
import 'teacher_profile_updates.dart';
import '../../core/local/archive_cloud_sync.dart';
import '../fortune/paipan_record_archive_page.dart';
import '../fortune/ziwei/ziwei_archive_page.dart';
import 'consultation_after_sales_page.dart';
import 'create_voice_room_page.dart';
import 'teacher_income_page.dart';
import 'teacher_schedule_page.dart';

class TeacherWorkbenchPage extends StatefulWidget {
  const TeacherWorkbenchPage({super.key});

  @override
  State<TeacherWorkbenchPage> createState() => _TeacherWorkbenchPageState();
}

class _TeacherWorkbenchPageState extends State<TeacherWorkbenchPage> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;
  int _tab = 0;
  bool _updatingService = false;
  final _pendingActions = <String>{};
  int _loadGeneration = 0;

  Map<String, dynamic> _map(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  List<Map<String, dynamic>> _list(Object? value) => value is List
      ? value
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList()
      : <Map<String, dynamic>>[];

  double _number(Object? value) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

  final _scope = ApiSessionScope();

  void _accountChanged() {
    if (mounted && !_scope.current) setState(() {});
  }

  void _profileChanged() {
    final update = teacherProfileUpdates.value;
    if (!mounted ||
        !_scope.current ||
        update == null ||
        !update.current ||
        _map(_data?['profile'])['userId'] != update.profile['userId']) {
      return;
    }
    ++_loadGeneration;
    setState(() {
      _data = {...?_data, 'profile': update.profile};
      _loading = false;
      _error = null;
    });
  }

  @override
  void initState() {
    super.initState();
    apiSessionChanges.addListener(_accountChanged);
    teacherProfileUpdates.addListener(_profileChanged);
    _load();
  }

  @override
  void dispose() {
    apiSessionChanges.removeListener(_accountChanged);
    teacherProfileUpdates.removeListener(_profileChanged);
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted || !_scope.current) return;
    final generation = ++_loadGeneration;
    if (mounted && _scope.current) setState(() => _error = null);
    try {
      final response = await _scope.get('/api/consultation/teacher/workbench');
      final raw = (response.data as Map?)?['data'];
      if (raw is! Map) throw const FormatException('工作台返回异常');
      if (mounted && _scope.current && generation == _loadGeneration) {
        setState(() => _data = Map<String, dynamic>.from(raw));
      }
    } catch (error) {
      if (mounted && _scope.current && generation == _loadGeneration) {
        setState(() {
          _error = apiSessionFailureMessage(error, '工作台加载失败');
        });
      }
    } finally {
      if (mounted && _scope.current && generation == _loadGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _updateService(Map<String, dynamic> overrides) async {
    if (!mounted || !_scope.current || _updatingService) return;
    setState(() => _updatingService = true);
    final profile = _map(_data?['profile']);
    try {
      await _scope.put('/api/consultation/teacher/service', data: {
        'displayTitle': profile['displayTitle'],
        'specialties': profile['specialties'],
        'voiceIntroUrl': profile['voiceIntroUrl'],
        'serviceNotice': profile['serviceNotice'],
        'privatePricePerMin': profile['privatePricePerMin'],
        'publicPricePerMin': profile['publicPricePerMin'],
        'canPrivate': profile['canPrivate'],
        'canLive': profile['canLive'],
        'serviceStatus': profile['serviceStatus'],
        ...overrides,
      });
      await _load();
    } catch (error) {
      if (mounted && _scope.current) {
        showAppToast(context, apiSessionFailureMessage(error, '保存失败'));
      }
    } finally {
      if (mounted && _scope.current) setState(() => _updatingService = false);
    }
  }

  Future<void> _editPrices() async {
    if (!mounted || !_scope.current || _updatingService) return;
    final profile = _map(_data?['profile']);
    final privateController = TextEditingController(
      text: '${profile['privatePricePerMin'] ?? 10}',
    );
    final publicController = TextEditingController(
      text: '${profile['publicPricePerMin'] ?? 6}',
    );
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('设置服务价格'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: privateController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: '私人专线（玄遇币/分钟）',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: publicController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: '公开连线（玄遇币/分钟）',
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '用户以玄遇币支付；老师收益按平台服务费规则折算为人民币结算。修改后仅影响新订单。',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (save == true && mounted && _scope.current) {
      final privatePrice = double.tryParse(privateController.text.trim());
      final publicPrice = double.tryParse(publicController.text.trim());
      if (privatePrice == null ||
          publicPrice == null ||
          !privatePrice.isFinite ||
          !publicPrice.isFinite ||
          privatePrice < 0 ||
          publicPrice < 0) {
        if (mounted && _scope.current) showAppToast(context, '请输入正确价格');
      } else if (privatePrice <= publicPrice) {
        if (mounted && _scope.current) showAppToast(context, '私人专线价格需高于公开连线');
      } else {
        await _updateService({
          'privatePricePerMin': privatePrice,
          'publicPricePerMin': publicPrice,
        });
      }
    }
    privateController.dispose();
    publicController.dispose();
  }

  Future<void> _answer(Map<String, dynamic> session, bool accept) async {
    final id = (session['id'] as num?)?.toInt();
    if (id == null ||
        !mounted ||
        !_scope.current ||
        !_pendingActions.add('session:$id')) {
      return;
    }
    try {
      await _scope.post(
        '/api/consultation/sessions/$id/${accept ? 'accept' : 'reject'}',
      );
      if (accept && mounted && _scope.current) {
        await ConsultationCallOverlay.instance.open(id);
      }
      await _load();
    } catch (error) {
      if (mounted && _scope.current) {
        showAppToast(context, apiSessionFailureMessage(error, '操作失败'));
      }
    } finally {
      _pendingActions.remove('session:$id');
    }
  }

  Future<void> _appointmentAction(
    Map<String, dynamic> appointment,
    String action,
  ) async {
    final id = (appointment['id'] as num?)?.toInt();
    if (id == null ||
        !mounted ||
        !_scope.current ||
        !_pendingActions.add('appointment:$id')) {
      return;
    }
    try {
      final response = await _scope.post(
          '/api/consultation/appointments/$id/$action',
          data: action == 'start'
              ? {'paymentMethod': 'coin', 'agreementAccepted': true}
              : null);
      if (!mounted || !_scope.current) return;
      if (action == 'start') {
        final data = (response.data as Map?)?['data'];
        final session = data is Map ? data['session'] : null;
        final sessionId =
            session is Map ? (session['id'] as num?)?.toInt() : null;
        if (sessionId != null) {
          await ConsultationCallOverlay.instance.open(sessionId);
        }
      }
      if (action != 'start' && mounted && _scope.current) {
        showAppToast(context, action == 'accept' ? '已接受预约' : '已更新预约');
      }
      await _load();
    } catch (error) {
      if (mounted && _scope.current) {
        showAppToast(context, apiSessionFailureMessage(error, '处理失败'));
      }
    } finally {
      _pendingActions.remove('appointment:$id');
    }
  }

  Future<void> _replyReview(Map<String, dynamic> review) async {
    final key = 'review:${review['id']}';
    if (!mounted || !_scope.current || !_pendingActions.add(key)) return;
    try {
      await _performReplyReview(review);
    } finally {
      _pendingActions.remove(key);
    }
  }

  Future<void> _performReplyReview(Map<String, dynamic> review) async {
    final id = (review['id'] as num?)?.toInt();
    if (id == null) return;
    final controller = TextEditingController(
      text: review['teacherReply']?.toString() ?? '',
    );
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('回复评价'),
        content: TextField(
          controller: controller,
          minLines: 3,
          maxLines: 6,
          maxLength: 500,
          decoration: const InputDecoration(
            hintText: '感谢反馈，说明你的服务态度或后续改进。',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('保存')),
        ],
      ),
    );
    if (mounted &&
        _scope.current &&
        save == true &&
        controller.text.trim().isNotEmpty) {
      try {
        await _scope.post(
          '/api/consultation/teacher/reviews/$id/reply',
          data: {'reply': controller.text.trim()},
        );
        if (mounted && _scope.current) showAppToast(context, '评价回复已保存');
        await _load();
      } catch (error) {
        if (mounted && _scope.current) {
          showAppToast(context, apiSessionFailureMessage(error, '回复失败'));
        }
      }
    }
    controller.dispose();
  }

  String _time(Object? value) {
    final time = DateTime.tryParse('$value')?.toLocal();
    if (time == null) return '时间待确认';
    return '${time.month}月${time.day}日 ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  String _sessionStatus(Object? value) => switch ('$value') {
        'ended' => '已完成',
        'refunded' => '已退款',
        'cancelled' => '已取消',
        'rejected' => '未接听',
        'active' => '进行中',
        'waiting' => '待接听',
        _ => '$value',
      };

  @override
  Widget build(BuildContext context) {
    if (!_scope.current) {
      return Scaffold(
        appBar: AppBar(title: const Text('账号已切换')),
        body: const Center(child: Text(apiSessionChangedMessage)),
      );
    }

    if (_loading && _data == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null && _data == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('老师工作台')),
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _load, child: const Text('重新加载')),
          ]),
        ),
      );
    }
    final profile = _map(_data?['profile']);
    final tabs = <Widget>[
      _todayView(profile),
      _ordersView(),
      _serviceView(profile),
      _incomeView(),
      _caseView(),
    ];
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text('老师工作台'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: tabs[_tab],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) => setState(() => _tab = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.today_outlined), label: '今日'),
          NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined), label: '订单'),
          NavigationDestination(icon: Icon(Icons.tune_rounded), label: '服务'),
          NavigationDestination(
              icon: Icon(Icons.account_balance_wallet_outlined), label: '收益'),
          NavigationDestination(
              icon: Icon(Icons.menu_book_outlined), label: '案例'),
        ],
      ),
    );
  }

  Widget _todayView(Map<String, dynamic> profile) {
    final incoming = _list(_data?['incoming']);
    final appointments = _list(_data?['appointments']);
    final today = _map(_data?['today']);
    final online = profile['serviceStatus'] == 'online' ||
        profile['serviceStatus'] == 'busy';
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF103F43), Color(0xFF1D6B68)],
            ),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(children: [
            Row(children: [
              const CircleAvatar(
                radius: 25,
                backgroundColor: Color(0xFFF2DDAE),
                child: Icon(Icons.workspace_premium_rounded,
                    color: Color(0xFF8C611D)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(profile['displayTitle']?.toString() ?? '认证老师',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w700)),
                    Text(online ? '可接私人专线' : '当前休息',
                        style: const TextStyle(color: Colors.white60)),
                  ],
                ),
              ),
              Switch(
                value: online,
                activeThumbColor: const Color(0xFFF2DDAE),
                onChanged: _updatingService
                    ? null
                    : (value) => _updateService({
                          'serviceStatus': value ? 'online' : 'offline',
                        }),
              ),
            ]),
            const SizedBox(height: 18),
            Row(children: [
              _heroStat('${today['sessionCount'] ?? 0}', '完成单'),
              _heroStat('${today['serviceMinutes'] ?? 0}', '服务分钟'),
              _heroStat(
                '¥${_number(today['incomeAmount']).toStringAsFixed(2)}',
                '预计收益',
              ),
            ]),
          ]),
        ),
        const SizedBox(height: 22),
        _sectionTitle('待处理咨询', incoming.length),
        const SizedBox(height: 9),
        if (incoming.isEmpty)
          _empty('暂时没有等待接听的咨询')
        else
          ...incoming.map(_incomingTile),
        const SizedBox(height: 22),
        _sectionTitle('预约待办', appointments.length),
        const SizedBox(height: 9),
        if (appointments.isEmpty)
          _empty('今天没有待处理预约')
        else
          ...appointments.map(_appointmentTile),
      ],
    );
  }

  Future<void> _deleteOrder(Map<String, dynamic> order) async {
    final id = (order['id'] as num?)?.toInt();
    if (id == null || !_scope.current) return;
    final key = 'delete-order:$id';
    if (_pendingActions.contains(key)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除订单记录？'),
        content: const Text('仅从你的列表移除，结算和售后记录仍会保留。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (confirmed != true || !mounted || !_scope.current) return;
    setState(() => _pendingActions.add(key));
    try {
      await _scope.post('/api/consultation/sessions/$id/delete-record');
      if (!mounted || !_scope.current) return;
      ++_loadGeneration;
      setState(() => _data = {
            ...?_data,
            'recentOrders': _list(_data?['recentOrders'])
                .where((r) => r['id'] != id)
                .toList(),
          });
    } catch (error) {
      if (mounted && _scope.current) {
        showAppToast(context, apiSessionFailureMessage(error, '删除失败，请重试'));
      }
    } finally {
      if (mounted) setState(() => _pendingActions.remove(key));
    }
  }

  Widget _ordersView() {
    final orders = _list(_data?['recentOrders']);
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
      children: [
        Text('最近服务订单', style: AppTextStyles.titleMedium),
        const SizedBox(height: 16),
        if (orders.isEmpty)
          _empty('暂无已结束订单')
        else
          ...orders.map((order) {
            final peer = _map(order['peer']);
            final seconds = (order['billedSeconds'] as num?)?.toInt() ?? 0;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.divider),
              ),
              child: Column(children: [
                Row(children: [
                  Expanded(
                    child: Text(peer['nickname']?.toString() ?? '咨询用户',
                        style: AppTextStyles.titleSmall),
                  ),
                  Text(_sessionStatus(order['status']),
                      style: AppTextStyles.bodySmall
                          .copyWith(color: AppColors.primaryDark)),
                ]),
                const SizedBox(height: 7),
                Row(children: [
                  Expanded(
                    child: Text(
                      '${order['mode'] == 'public_mic' ? '公开连线' : order['mode'] == 'private_mic' ? '私密连麦' : '私人专线'} · $seconds秒 · ${order['paymentMethod'] == 'alipay' ? '支付宝实付' : '扣费'}${_number(order['chargedAmount']).toStringAsFixed(2)}${order['paymentMethod'] == 'alipay' ? '元' : '玄遇币'}',
                      style: AppTextStyles.bodySmall
                          .copyWith(color: AppColors.textSecondary),
                    ),
                  ),
                  Text(
                    '收益 ¥${_number(order['teacherIncome']).toStringAsFixed(2)}',
                    style: const TextStyle(
                        color: AppColors.success, fontWeight: FontWeight.w700),
                  ),
                ]),
                const SizedBox(height: 5),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Row(children: [
                    Expanded(
                      child: Text(
                        '${_time(order['createdAt'])} · 平台服务费 ¥${_number(order['platformFee']).toStringAsFixed(2)}',
                        style: AppTextStyles.bodySmall
                            .copyWith(color: AppColors.textHint),
                      ),
                    ),
                    IconButton(
                      tooltip: '删除订单记录',
                      onPressed: _pendingActions
                              .contains('delete-order:${order['id']}')
                          ? null
                          : () => _deleteOrder(order),
                      icon: const Icon(Icons.delete_outline, size: 20),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ConsultationAfterSalesPage(
                            initialSession: order,
                          ),
                        ),
                      ),
                      child: const Text('售后记录'),
                    ),
                  ]),
                ),
              ]),
            );
          }),
      ],
    );
  }

  Widget _serviceView(Map<String, dynamic> profile) {
    final availability = _map(_data?['availability']);
    final reviews = _list(_data?['reviews']);
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
      children: [
        _serviceTile(
          Icons.account_circle_outlined,
          '名师资料',
          '名称、头像、个人介绍、擅长领域与服务经验',
          () => Navigator.of(context).push<Map<String, dynamic>>(
              MaterialPageRoute(
                  builder: (_) => TeacherProfileEditorPage(profile: profile))),
        ),
        _serviceTile(
          Icons.price_change_outlined,
          '服务与价格',
          '私人专线 ${_number(profile['privatePricePerMin']).toStringAsFixed(0)}币/分 · 公开连线 ${_number(profile['publicPricePerMin']).toStringAsFixed(0)}币/分',
          _editPrices,
        ),
        _serviceTile(
          Icons.event_available_outlined,
          '可预约时间',
          availability['enabled'] == true ? '已开放预约 · 可随时调整时段' : '未开放预约',
          () => Navigator.of(context)
              .push<bool>(MaterialPageRoute(
                  builder: (_) => const TeacherSchedulePage()))
              .then((changed) {
            if (changed == true) _load();
          }),
        ),
        _serviceTile(
          Icons.mic_none_rounded,
          '创建名师房间',
          '旁听免费，用户公开连线按你设置的价格计费',
          () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const CreateVoiceRoomPage(roomType: 'master'),
          )),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFEAF8F6),
            borderRadius: BorderRadius.circular(16),
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('服务质量', style: AppTextStyles.titleSmall),
            const SizedBox(height: 12),
            Row(children: [
              _quality(_number(profile['rating']).toStringAsFixed(1), '综合评分'),
              _quality('${profile['reviewCount'] ?? 0}', '有效评价'),
              _quality('${profile['completedSessions'] ?? 0}', '完成服务'),
            ]),
          ]),
        ),
        const SizedBox(height: 22),
        _sectionTitle('最近评价', reviews.length),
        const SizedBox(height: 9),
        if (reviews.isEmpty)
          _empty('暂无用户评价')
        else
          ...reviews.map((review) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: _boxDecoration(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text('★ ${review['rating'] ?? 5}',
                          style: const TextStyle(
                              color: AppColors.warning,
                              fontWeight: FontWeight.w700)),
                      const Spacer(),
                      Text(review['anonymous'] == true ? '匿名用户' : '服务用户',
                          style: AppTextStyles.bodySmall
                              .copyWith(color: AppColors.textHint)),
                    ]),
                    if ((review['content']?.toString() ?? '').isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(review['content'].toString()),
                    ],
                    if ((review['teacherReply']?.toString() ?? '')
                        .isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('老师回复：${review['teacherReply']}',
                          style: AppTextStyles.bodySmall
                              .copyWith(color: AppColors.textSecondary)),
                    ],
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => _replyReview(review),
                        child: Text(
                            (review['teacherReply']?.toString() ?? '').isEmpty
                                ? '回复'
                                : '修改回复'),
                      ),
                    ),
                  ],
                ),
              )),
      ],
    );
  }

  Widget _incomeView() {
    final settlement = _map(_data?['settlement']);
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF103F43), Color(0xFF1D6B68)],
            ),
            borderRadius: BorderRadius.circular(22),
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('可提现人民币收益', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 8),
            Text(
              '¥${withdrawableAmountText(settlement['availableAmount'])}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 30,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 15),
            Row(children: [
              _heroStat(
                  '¥${_number(settlement['pendingAmount']).toStringAsFixed(2)}',
                  '待结算'),
              _heroStat(
                  '¥${_number(settlement['withdrawingAmount']).toStringAsFixed(2)}',
                  '提现中'),
              _heroStat(
                  '¥${_number(settlement['withdrawnAmount']).toStringAsFixed(2)}',
                  '累计提现'),
            ]),
            if (_number(settlement['debtAmount']) > 0 ||
                _number(settlement['availableAmount']) < 0) ...[
              const SizedBox(height: 12),
              Text(
                '待抵扣金额 ¥${(_number(settlement['debtAmount']) > 0 ? _number(settlement['debtAmount']) : -_number(settlement['availableAmount'])).toStringAsFixed(2)}',
                style: const TextStyle(color: Colors.white),
              ),
            ],
            if (_number(settlement['disputedAmount']) > 0) ...[
              const SizedBox(height: 12),
              Text(
                '售后争议冻结 ¥${_number(settlement['disputedAmount']).toStringAsFixed(2)}',
                style: const TextStyle(color: Color(0xFFF2DDAE), fontSize: 12),
              ),
            ],
          ]),
        ),
        const SizedBox(height: 22),
        FilledButton.icon(
          onPressed: () => Navigator.of(context)
              .push(
                  MaterialPageRoute(builder: (_) => const TeacherIncomePage()))
              .then((_) => _load()),
          icon: const Icon(Icons.receipt_long_outlined),
          label: const Text('查看收益明细与申请提现'),
        ),
      ],
    );
  }

  Widget _caseView() => ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
        children: [
          Text('档案笔记', style: AppTextStyles.titleMedium),
          const ArchiveSyncNotice(),
          const SizedBox(height: 18),
          _caseEntry(
            const Color(0xFFEAF8F6),
            Icons.auto_awesome_outlined,
            '八字档案笔记',
            '查看八字档案、看盘判断与现实反馈',
            () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => const PaipanRecordArchivePage()),
            ),
          ),
          const SizedBox(height: 12),
          _caseEntry(
            const Color(0xFFF3EEFC),
            Icons.blur_circular_outlined,
            '斗数档案笔记',
            '查看斗数档案、运限判断与现实反馈',
            () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ZiweiArchivePage()),
            ),
          ),
        ],
      );

  Widget _incomingTile(Map<String, dynamic> session) {
    final peer = _map(session['peer']);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: _boxDecoration(),
      child: Row(children: [
        const CircleAvatar(
          backgroundColor: Color(0xFFEAF8F6),
          child: Icon(Icons.person_outline, color: AppColors.primaryDark),
        ),
        const SizedBox(width: 11),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(peer['nickname']?.toString() ?? '咨询用户',
                style: AppTextStyles.titleSmall),
            Text(
              '${session['mode'] == 'public_mic' ? '公开连线' : session['mode'] == 'private_mic' ? '私密连麦' : '私人专线'} · ${_number(session['ratePerMin']).toStringAsFixed(2)}${session['paymentMethod'] == 'alipay' ? '元' : '玄遇币'}/分钟',
              style:
                  AppTextStyles.bodySmall.copyWith(color: AppColors.textHint),
            ),
          ]),
        ),
        if (session['status'] == 'waiting') ...[
          IconButton(
            onPressed: () => _answer(session, false),
            icon: const Icon(Icons.close_rounded, color: AppColors.error),
          ),
          FilledButton(
            onPressed: () => _answer(session, true),
            child: const Text('接听'),
          ),
        ] else
          FilledButton(
            onPressed: () => ConsultationCallOverlay.instance
                .open((session['id'] as num).toInt()),
            child: const Text('进入'),
          ),
      ]),
    );
  }

  Widget _appointmentTile(Map<String, dynamic> appointment) {
    final peer = _map(appointment['peer']);
    final pending = appointment['status'] == 'pending';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: _boxDecoration(),
      child: Column(children: [
        Row(children: [
          const Icon(Icons.event_available_outlined,
              color: AppColors.primaryDark),
          const SizedBox(width: 10),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(peer['nickname']?.toString() ?? '预约用户',
                  style: AppTextStyles.titleSmall),
              Text(
                '${_time(appointment['scheduledAt'])} · ${appointment['expectedMinutes']}分钟 · ${appointment['ratePerMin']}玄遇币/分',
                style:
                    AppTextStyles.bodySmall.copyWith(color: AppColors.textHint),
              ),
            ]),
          ),
          _badge(pending ? '待确认' : '已接受'),
        ]),
        if ((appointment['note']?.toString() ?? '').isNotEmpty) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(appointment['note'].toString(),
                style: AppTextStyles.bodySmall),
          ),
        ],
        if (!pending) ...[
          const SizedBox(height: 7),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${appointment['checkedIn'] == true ? '你已到场' : '你尚未签到'} · ${appointment['peerCheckedIn'] == true ? '用户已到场' : '用户尚未签到'}',
              style: AppTextStyles.bodySmall.copyWith(
                color: appointment['peerCheckedIn'] == true
                    ? AppColors.success
                    : AppColors.textHint,
              ),
            ),
          ),
        ],
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 6, children: [
          OutlinedButton(
            onPressed: () =>
                _appointmentAction(appointment, pending ? 'reject' : 'cancel'),
            child: Text(pending ? '暂不接受' : '取消预约'),
          ),
          if (appointment['canCancelCheckIn'] == true)
            TextButton(
                onPressed: _pendingActions
                        .contains('appointment:${appointment['id']}')
                    ? null
                    : () => _appointmentAction(appointment, 'cancel-check-in'),
                child: const Text('取消签到')),
          if (pending) ...[
            FilledButton(
              onPressed: () => _appointmentAction(appointment, 'accept'),
              child: const Text('接受预约'),
            ),
          ] else
            OutlinedButton(
              onPressed: appointment['checkedIn'] != true
                  ? () {
                      if (appointment['canCheckIn'] != true) {
                        final scheduled =
                            DateTime.tryParse('${appointment['scheduledAt']}');
                        showAppToast(
                            context,
                            scheduled != null &&
                                    DateTime.now().isAfter(scheduled
                                        .add(const Duration(minutes: 30)))
                                ? '本次预约签到已结束'
                                : '预约前30分钟内签到');
                        return;
                      }
                      _appointmentAction(appointment, 'check-in');
                    }
                  : null,
              child: Text(appointment['checkedIn'] == true ? '已签到' : '到场签到'),
            ),
          if (!pending)
            FilledButton(
              onPressed: appointment['canStart'] == true &&
                      !_pendingActions
                          .contains('appointment:${appointment['id']}')
                  ? () => _appointmentAction(appointment, 'start')
                  : null,
              child: const Text('发起专线'),
            ),
        ]),
      ]),
    );
  }

  Widget _serviceTile(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback? onTap,
  ) =>
      Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: _boxDecoration(),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            onTap: onTap,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
            leading: Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF8F6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppColors.primaryDark),
            ),
            title: Text(title, style: AppTextStyles.titleSmall),
            subtitle: Text(subtitle),
            trailing: const Icon(Icons.chevron_right_rounded),
          ),
        ),
      );

  Widget _caseEntry(
    Color color,
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) =>
      Material(
        color: color,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(children: [
              Icon(icon, size: 34, color: AppColors.primaryDark),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: AppTextStyles.titleSmall),
                      const SizedBox(height: 4),
                      Text(subtitle,
                          style: AppTextStyles.bodySmall
                              .copyWith(color: AppColors.textSecondary)),
                    ]),
              ),
              const Icon(Icons.chevron_right_rounded),
            ]),
          ),
        ),
      );

  Widget _heroStat(String value, String label) => Expanded(
        child: Column(children: [
          Text(value,
              style: const TextStyle(
                  color: Color(0xFFF2DDAE), fontWeight: FontWeight.w800)),
          const SizedBox(height: 3),
          Text(label,
              style: const TextStyle(color: Colors.white60, fontSize: 11)),
        ]),
      );

  Widget _quality(String value, String label) => Expanded(
        child: Column(children: [
          Text(value,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          Text(label,
              style:
                  AppTextStyles.bodySmall.copyWith(color: AppColors.textHint)),
        ]),
      );

  Widget _sectionTitle(String title, int count) => Row(children: [
        Text(title, style: AppTextStyles.titleMedium),
        const Spacer(),
        if (count > 0)
          Text('$count条',
              style:
                  AppTextStyles.bodySmall.copyWith(color: AppColors.textHint)),
      ]);

  Widget _empty(String text) => Container(
        padding: const EdgeInsets.all(24),
        decoration: _boxDecoration(),
        child: Text(text,
            textAlign: TextAlign.center,
            style:
                AppTextStyles.bodyMedium.copyWith(color: AppColors.textHint)),
      );

  Widget _badge(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFFEAF8F6),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text,
            style: const TextStyle(
                color: AppColors.primaryDark,
                fontSize: 11,
                fontWeight: FontWeight.w700)),
      );

  BoxDecoration _boxDecoration() => BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      );
}
