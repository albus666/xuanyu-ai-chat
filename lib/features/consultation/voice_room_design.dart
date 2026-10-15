import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'voice_room_backgrounds.dart';

String voiceRoomRelationshipText(Map<String, dynamic> payload) {
  final actor = payload['actorNickname']?.toString().trim();
  final target = payload['targetNickname']?.toString().trim();
  final actorName = actor?.isNotEmpty == true ? actor! : '一位用户';
  final targetName = target?.isNotEmpty == true ? target! : '另一位用户';
  return payload['action'] == 'mutual'
      ? '$actorName 与 $targetName 已互相关注'
      : '$actorName 关注了 $targetName';
}

String voiceRoomAccessLabel(String? value) => switch (value) {
      'unlisted' => '仅邀请可进',
      'password' => '口令进入',
      _ => '公开房间',
    };

int voiceRoomLevelFromExp(int exp) {
  const thresholds = <int>[
    0,
    120,
    400,
    1000,
    2400,
    5200,
    10000,
    18000,
    30000,
    50000
  ];
  var level = 1;
  for (var i = 0; i < thresholds.length; i++) {
    if (exp >= thresholds[i]) level = i + 1;
  }
  return level;
}

String voiceRoomDiscoveryBadgeText(Map<String, dynamic> room) {
  final relation = room['roomRelationship']?.toString() ??
      room['ownerRelationship']?.toString() ??
      'none';
  return switch (relation) {
    'mutual' => '互相关注',
    'following' => '你关注的人在聊',
    'follows_me' => '关注你的人在聊',
    'self' => '我的房间',
    _ when room['roomType'] != 'master' && room['autonomousMic'] == true =>
      '可直接上麦',
    _ when room['roomType'] == 'master' => '名师正在播',
    _ => '正在聊天',
  };
}

class VoiceActivityBars extends StatefulWidget {
  const VoiceActivityBars({
    super.key,
    this.active = true,
    this.color = const Color(0xFF54E6D8),
    this.size = 22,
  });

  final bool active;
  final Color color;
  final double size;

  @override
  State<VoiceActivityBars> createState() => _VoiceActivityBarsState();
}

class _VoiceActivityBarsState extends State<VoiceActivityBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 860),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (_, __) => Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(3, (index) {
              final phase = (_controller.value + index * .24) % 1;
              final factor = widget.active
                  ? .35 + math.sin(phase * math.pi).abs() * .65
                  : .28;
              return Container(
                width: widget.size * .15,
                height: widget.size * factor,
                margin: EdgeInsets.symmetric(horizontal: widget.size * .045),
                decoration: BoxDecoration(
                  color: widget.active
                      ? widget.color
                      : widget.color.withValues(alpha: .38),
                  borderRadius: BorderRadius.circular(widget.size),
                ),
              );
            }),
          ),
        ),
      );
}

class VoiceRoomLevelBadge extends StatelessWidget {
  const VoiceRoomLevelBadge({
    super.key,
    required this.level,
    this.compact = false,
    this.dark = false,
  });

  final int level;
  final bool compact;
  final bool dark;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 7 : 9,
          vertical: compact ? 3 : 4,
        ),
        decoration: BoxDecoration(
          color: dark ? const Color(0xCC111827) : null,
          gradient: dark
              ? null
              : const LinearGradient(
                  colors: [Color(0xFFE2C37E), Color(0xFFB88B42)],
                ),
          borderRadius: BorderRadius.circular(20),
          border: dark ? Border.all(color: const Color(0x66E8C978)) : null,
          boxShadow: const [BoxShadow(color: Color(0x332C1F0C), blurRadius: 8)],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(
              dark
                  ? Icons.workspace_premium_rounded
                  : Icons.auto_awesome_rounded,
              size: compact ? 11 : 13,
              color: dark ? const Color(0xFFF3D17F) : Colors.white),
          const SizedBox(width: 3),
          Text(
            '房间 Lv.$level',
            style: TextStyle(
              color: Colors.white,
              fontSize: compact ? 9 : 10.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ]),
      );
}

class VoiceRoomDiscoveryCard extends StatelessWidget {
  const VoiceRoomDiscoveryCard({
    super.key,
    required this.room,
    required this.onTap,
  });

  final Map<String, dynamic> room;
  final VoidCallback onTap;

  int _number(String key) =>
      (room[key] as num?)?.toInt() ??
      int.tryParse(room[key]?.toString() ?? '') ??
      0;

  @override
  Widget build(BuildContext context) {
    final master = room['roomType'] == 'master';
    final owner = room['owner'] is Map
        ? Map<String, dynamic>.from(room['owner'])
        : <String, dynamic>{};
    final levelRaw = room['roomLevel'];
    final level = levelRaw is Map
        ? (levelRaw['level'] as num?)?.toInt() ?? 1
        : voiceRoomLevelFromExp(_number('roomExp'));
    final online = _number('onlineCount');
    final heat = _number('heatScore');
    final cover = room['coverUrl']?.toString() ?? '';
    final avatars = <String>{
      if ((owner['avatarUrl']?.toString() ?? '').isNotEmpty)
        owner['avatarUrl'].toString(),
      if (room['memberAvatars'] is List)
        ...(room['memberAvatars'] as List)
            .map((value) => value?.toString() ?? '')
            .where((value) => value.isNotEmpty),
    }.take(4).toList();
    final hiddenMembers = math.max(0, online - avatars.length);
    final relation = room['roomRelationship']?.toString() ??
        room['ownerRelationship']?.toString() ??
        'none';
    final badge = switch (relation) {
      'mutual' => ('互相关注', const Color(0xFF8463E6), Icons.people_alt_rounded),
      'following' => (
          '你关注的人在聊',
          const Color(0xFFE85A93),
          Icons.favorite_rounded
        ),
      'follows_me' => (
          '关注你的人在聊',
          const Color(0xFFE85A93),
          Icons.favorite_border_rounded
        ),
      'self' => ('我的房间', const Color(0xFF2ABDB6), Icons.home_rounded),
      _ when !master && room['autonomousMic'] == true => (
          '可直接上麦',
          const Color(0xFF26BDB7),
          Icons.mic_rounded
        ),
      _ when master => (
          '名师正在播',
          const Color(0xFFB58A42),
          Icons.verified_rounded
        ),
      _ => ('正在聊天', const Color(0xFF2A9FC4), Icons.forum_rounded),
    };
    final badgeText = voiceRoomDiscoveryBadgeText(room);
    final preview = (room['preview']?.toString().trim().isNotEmpty == true
            ? room['preview']
            : room['notice']?.toString().trim().isNotEmpty == true
                ? room['notice']
                : master
                    ? '免费旁听 · 付费连麦 · 安心交流'
                    : '真诚聊天 · 温暖陪伴 · 轻松交流')
        .toString();
    final price = (room['pricePerMin'] as num?)?.toDouble() ?? 0;

    return Material(
      color: const Color(0xFF172235),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          child: Stack(fit: StackFit.expand, children: [
            if (voiceRoomBackgroundImage(cover) != null)
              Image(
                image: voiceRoomBackgroundImage(cover)!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    _VoiceRoomCoverFallback(master: master),
              )
            else
              _VoiceRoomCoverFallback(master: master),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0, .38, 1],
                  colors: [
                    Color(0x1A08101F),
                    Color(0x7A101A2B),
                    Color(0xF20A1425),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(9, 9, 9, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 4),
                        decoration: BoxDecoration(
                          color: badge.$2.withValues(alpha: .92),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: const [
                            BoxShadow(color: Color(0x33000000), blurRadius: 8),
                          ],
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(badge.$3, size: 11, color: Colors.white),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              badgeText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 8.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ]),
                      ),
                    ),
                    const SizedBox(width: 6),
                    VoiceActivityBars(
                      active: room['status'] == 'live',
                      color: const Color(0xFF55E4DB),
                      size: 20,
                    ),
                  ]),
                  const Spacer(),
                  VoiceRoomLevelBadge(level: level, compact: true, dark: true),
                  const SizedBox(height: 4),
                  Text(
                    room['title']?.toString() ?? '语音交流房',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      height: 1.25,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    preview.replaceAll('\n', ' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFC6CFDC),
                      fontSize: 8.5,
                    ),
                  ),
                  const SizedBox(height: 5),
                  SizedBox(
                    height: 27,
                    child: Row(children: [
                      Expanded(
                        child: Stack(children: [
                          for (var index = 0; index < avatars.length; index++)
                            Positioned(
                              left: index * 20,
                              child: CircleAvatar(
                                radius: 13.5,
                                backgroundColor: Colors.white,
                                child: CircleAvatar(
                                  radius: 12,
                                  backgroundColor: const Color(0xFF334155),
                                  backgroundImage: NetworkImage(avatars[index]),
                                ),
                              ),
                            ),
                        ]),
                      ),
                      if (hiddenMembers > 0)
                        Container(
                          width: 27,
                          height: 27,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                            color: Color(0xB31B2840),
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '+$hiddenMembers',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ]),
                  ),
                  const SizedBox(height: 4),
                  Row(children: [
                    const Icon(Icons.person_rounded,
                        size: 12, color: Color(0xFFD6DDEA)),
                    const SizedBox(width: 3),
                    Text('$online人在线',
                        style: const TextStyle(
                            color: Color(0xFFD6DDEA), fontSize: 8.5)),
                    const Spacer(),
                    if (master) ...[
                      const Icon(Icons.paid_outlined,
                          size: 11, color: Color(0xFFF1CA7A)),
                      const SizedBox(width: 2),
                      Flexible(
                        child: Text(
                          '${price.toStringAsFixed(0)}币/分钟',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFF1CA7A),
                            fontSize: 8,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ] else ...[
                      const Icon(Icons.local_fire_department_rounded,
                          size: 12, color: Color(0xFFFF8B72)),
                      const SizedBox(width: 2),
                      Text('$heat',
                          style: const TextStyle(
                              color: Color(0xFFE5EAF1), fontSize: 8.5)),
                    ],
                    if (room['accessType'] == 'password') ...[
                      const SizedBox(width: 5),
                      const Icon(Icons.lock_rounded,
                          size: 11, color: Color(0xFFD6DDEA)),
                    ],
                  ]),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _VoiceRoomCoverFallback extends StatelessWidget {
  const _VoiceRoomCoverFallback({required this.master});

  final bool master;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: master
                ? const [Color(0xFF174B59), Color(0xFF15233F)]
                : const [Color(0xFF364A88), Color(0xFF271F53)],
          ),
        ),
        child: Stack(children: [
          Positioned(
            right: -18,
            top: -25,
            child: Icon(
              master ? Icons.auto_awesome_rounded : Icons.nightlight_round,
              size: 125,
              color: Colors.white.withValues(alpha: .13),
            ),
          ),
          Positioned(
            left: 18,
            top: 68,
            child: Icon(
              master ? Icons.spa_outlined : Icons.star_outline_rounded,
              size: 48,
              color: const Color(0x66F0D890),
            ),
          ),
        ]),
      );
}

class VoiceRoomSheetHandle extends StatelessWidget {
  const VoiceRoomSheetHandle({super.key});

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 42,
          height: 4,
          decoration: BoxDecoration(
            color: const Color(0xFFDDE5E4),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      );
}
