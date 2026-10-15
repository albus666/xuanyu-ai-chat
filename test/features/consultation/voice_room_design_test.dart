import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/features/consultation/voice_room_backgrounds.dart';
import 'package:xuanyu/features/consultation/voice_room_design.dart';

void main() {
  test('房间成长等级边界稳定', () {
    expect(voiceRoomLevelFromExp(0), 1);
    expect(voiceRoomLevelFromExp(119), 1);
    expect(voiceRoomLevelFromExp(120), 2);
    expect(voiceRoomLevelFromExp(50000), 10);
  });

  test('官方星海背景可持久化并解析为本地资源', () {
    expect(voiceRoomOfficialBackgrounds, hasLength(4));
    final first = voiceRoomOfficialBackgrounds.first;
    expect(first.coverValue, startsWith('official://voice-room/'));
    expect(voiceRoomOfficialBackground(first.coverValue), same(first));
    expect(voiceRoomBackgroundImage(first.coverValue), isA<AssetImage>());
    expect(voiceRoomBackgroundImage('https://example.test/cover.jpg'),
        isA<NetworkImage>());
  });

  test('关注事件只生成正向中文文案', () {
    expect(
      voiceRoomRelationshipText({
        'action': 'follow',
        'actorNickname': '向日葵',
        'targetNickname': '木头',
      }),
      '向日葵 关注了 木头',
    );
    expect(
      voiceRoomRelationshipText({
        'action': 'mutual',
        'actorNickname': '向日葵',
        'targetNickname': '木头',
      }),
      '向日葵 与 木头 已互相关注',
    );
  });

  test('可见范围使用中文标签', () {
    expect(voiceRoomAccessLabel('public'), '公开房间');
    expect(voiceRoomAccessLabel('unlisted'), '仅邀请可进');
    expect(voiceRoomAccessLabel('password'), '口令进入');
  });

  test('大厅卡片关系与上麦状态文案准确', () {
    expect(
      voiceRoomDiscoveryBadgeText({'roomRelationship': 'mutual'}),
      '互相关注',
    );
    expect(
      voiceRoomDiscoveryBadgeText({
        'roomType': 'free',
        'autonomousMic': true,
      }),
      '可直接上麦',
    );
    expect(
      voiceRoomDiscoveryBadgeText({'roomType': 'master'}),
      '名师正在播',
    );
  });

  testWidgets('房间卡片在手机双列正方形中完整布局', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox.square(
            dimension: 158,
            child: VoiceRoomDiscoveryCard(
              room: const {
                'id': 1,
                'roomType': 'free',
                'title': '轻松聊天交流房',
                'preview': '真诚聊天·温暖陪伴',
                'status': 'live',
                'onlineCount': 3,
                'heatScore': 8,
                'owner': <String, dynamic>{},
              },
              onTap: () {},
            ),
          ),
        ),
      ),
    ));

    expect(tester.takeException(), isNull);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox.square(
            dimension: 158,
            child: VoiceRoomDiscoveryCard(
              room: const {
                'id': 2,
                'roomType': 'master',
                'title': '名师公开连麦房',
                'preview': '旁听免费·接通计费',
                'status': 'live',
                'onlineCount': 12,
                'pricePerMin': 128.55,
                'owner': <String, dynamic>{},
              },
              onTap: () {},
            ),
          ),
        ),
      ),
    ));

    expect(tester.takeException(), isNull);
  });
}
