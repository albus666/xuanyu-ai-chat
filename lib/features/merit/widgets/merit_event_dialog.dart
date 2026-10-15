import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:xuanyu/features/merit/engine/merit_engine.dart';
import 'package:xuanyu/features/merit/models/merit_models.dart';

/// 用户主动点待领图标后打开（不在敲击时拦截）
Future<String?> claimMeritEvent(BuildContext context, MeritEngine engine, MeritEventType type) async {
  switch (type) {
    case MeritEventType.buddhaPass:
      return _choiceDialog(
        context,
        title: '佛祖路过',
        body: '佛祖路过，赐你 30 秒双倍负功德 buff',
        choices: const [
          _Choice('accept', '谢主隆恩'),
          _Choice('reject', '我命由我不由佛'),
        ],
        onPick: (c) => engine.resolveEvent(type, c),
      );
    case MeritEventType.bossCheck:
      return _bossCheckDialog(context, engine);
    case MeritEventType.fishMood:
      return _choiceDialog(
        context,
        title: '木鱼闹脾气',
        body: '木鱼敲累了（已开始 15 下无文案）。可花 80 币提前哄好。',
        choices: const [
          _Choice('pay', '花 80 币哄好'),
          _Choice('hard', '继续硬敲'),
        ],
        onPick: (c) => engine.resolveEvent(type, c),
      );
    case MeritEventType.karmaBacklash:
      // 已即时生效，一般不会入队
      final msg = await engine.resolveEvent(type, 'ok');
      return msg;
    case MeritEventType.fortuneGod:
      return _choiceDialog(
        context,
        title: '财神串门',
        body: '财神路过，丢下一个红包，点开领取',
        choices: const [_Choice('open', '领取红包')],
        onPick: (c) => engine.resolveEvent(type, c),
      );
  }
}

class _Choice {
  const _Choice(this.id, this.label);
  final String id;
  final String label;
}

Future<String?> _choiceDialog(
  BuildContext context, {
  required String title,
  required String body,
  required List<_Choice> choices,
  required Future<String> Function(String) onPick,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => AlertDialog(
      backgroundColor: MeritColors.card,
      title: Text(title, style: const TextStyle(color: MeritColors.gold)),
      content: Text(body, style: const TextStyle(color: MeritColors.textPrimary)),
      actions: choices
          .map(
            (c) => TextButton(
              onPressed: () async {
                final msg = await onPick(c.id);
                if (ctx.mounted) Navigator.pop(ctx, msg);
              },
              child: Text(c.label),
            ),
          )
          .toList(),
    ),
  );
}

Future<String?> _bossCheckDialog(BuildContext context, MeritEngine engine) async {
  var success = false;
  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _BossCheckDialog(
      onSuccess: () {
        success = true;
        Navigator.pop(ctx);
      },
      onFail: () => Navigator.pop(ctx),
    ),
  );
  return engine.resolveEvent(MeritEventType.bossCheck, success ? 'success' : 'fail');
}

class _BossCheckDialog extends StatefulWidget {
  const _BossCheckDialog({required this.onSuccess, required this.onFail});

  final VoidCallback onSuccess;
  final VoidCallback onFail;

  @override
  State<_BossCheckDialog> createState() => _BossCheckDialogState();
}

class _BossCheckDialogState extends State<_BossCheckDialog> {
  int _sec = 10;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _sec -= 1);
      if (_sec <= 0) {
        t.cancel();
        widget.onFail();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: MeritColors.card,
      title: const Text('老板查岗', style: TextStyle(color: MeritColors.gold)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '老板正在靠近！$_sec 秒内点击「切屏」躲避',
            style: const TextStyle(color: MeritColors.textPrimary),
          ),
          SizedBox(height: 16.h),
          FilledButton(
            onPressed: widget.onSuccess,
            child: const Text('切屏'),
          ),
        ],
      ),
    );
  }
}

Future<bool?> showReincarnationConfirm(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: MeritColors.card,
      title: const Text('功德圆满，立即轮回？', style: TextStyle(color: MeritColors.gold)),
      content: const Text(
        '✅ 永久保留：已收集文案、永久成就、业力加成、皮肤\n'
        '❌ 重置清空：本世敲击数、负功德币、木鱼等级、本世称号、本世成就',
        style: TextStyle(color: MeritColors.textPrimary, height: 1.6),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('再敲敲')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确认轮回')),
      ],
    ),
  );
}

Future<void> showReincarnationSummary(BuildContext context, MeritEngine engine, MeritReincarnationSummary s) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      backgroundColor: MeritColors.card,
      title: Text('${engine.reincarnationBadge} 转生成功', style: const TextStyle(color: MeritColors.gold)),
      content: Text(
        '上一世敲击 ${s.lifeTaps} 次\n'
        '获得 ${s.coinsEarned} 负功德币\n'
        '解锁称号 ${s.titlesUnlocked} 个\n'
        '收集文案 ${s.textsCollected} 条\n\n'
        '业力加成已永久提升！',
        style: const TextStyle(color: MeritColors.textPrimary, height: 1.6),
      ),
      actions: [
        FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('开启新一世')),
      ],
    ),
  );
}
