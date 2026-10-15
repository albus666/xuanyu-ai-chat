import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('播间不强制开启会产生收音伪影的激进 AI 降噪', () {
    final source = File(
      'lib/features/consultation/voice_plaza_room_page.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('ainsModeAggressive')));
    expect(source, isNot(contains('setAINSMode(')));
    expect(source, contains('audioScenarioChatroom'));
    expect(source, contains('setDefaultAudioRouteToSpeakerphone'));
  });
}
