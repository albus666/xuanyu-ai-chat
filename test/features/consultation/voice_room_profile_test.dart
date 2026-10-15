import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/features/consultation/voice_room_profile_page.dart';

void main() {
  testWidgets('房间资料兼容旧分类且不再展示派对预告', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: VoiceRoomProfilePage(
          isOwner: true,
          room: {
            'id': 1,
            'roomNo': '10001',
            'roomType': 'party',
            'title': '测试房间',
            'notice': '',
            'preview': '旧预告',
            'category': '情感交流',
            'owner': <String, dynamic>{},
          },
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('情感倾听'), findsOneWidget);
    expect(find.text('派对预告'), findsNothing);
    expect(find.text('旧预告'), findsNothing);
  });
}
