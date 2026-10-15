import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/features/community/map_location_picker_page.dart';
import 'package:xuanyu/features/emotion/models/emotion_type.dart';
import 'package:xuanyu/features/emotion/models/identity_type.dart';
import 'package:xuanyu/features/emotion/services/emotion_map_service.dart';
import 'package:xuanyu/features/emotion/widgets/china_emotion_map_widget.dart';

void main() {
  test('结构化位置只拼接有值的行政区层级', () {
    const selection = MapLocationSelection(
      address: '北京市朝阳区三里屯街道',
      province: '北京市',
      city: '',
      district: '朝阳区',
      township: '三里屯街道',
      latitude: 39.93,
      longitude: 116.45,
    );

    expect(selection.publicLabel, '北京市 朝阳区 三里屯街道');
  });

  test('情绪状态解析乡镇、模糊坐标和聊天意愿', () {
    final item = EmotionCheckin.fromJson({
      'id': 8,
      'nickname': '同频旅人',
      'identity': 'sleepless',
      'emotion': 'tired',
      'province': '广东省',
      'city': '深圳市',
      'district': '龙岗区',
      'township': '龙岗街道',
      'latitude': 22.72,
      'longitude': 114.25,
      'chatAllowed': true,
      'isMine': false,
      'content': '还没有睡',
      'likeCount': 2,
      'liked': false,
    });

    expect(item.identity, IdentityType.sleepless);
    expect(item.township, '龙岗街道');
    expect(item.latitude, 22.72);
    expect(item.chatAllowed, isTrue);
    expect(item.isMine, isFalse);
  });

  testWidgets('Flutter 情绪地图支持缩放并点击乡镇状态点', (tester) async {
    EmotionMapPoint? tapped;
    final scaleChanges = <double>[];
    const point = EmotionMapPoint(
      id: 8,
      latitude: 35.86,
      longitude: 104.19,
      emotion: EmotionType.tired,
      locationLabel: '中原街道',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 430,
            height: 700,
            child: ChinaEmotionMapWidget(
              expand: true,
              provinceEmotions: const {'广东': EmotionType.tired},
              provinceCounts: const {'广东': 1},
              points: const [point],
              onPointTap: (value) => tapped = value,
              onScaleChanged: scaleChanges.add,
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();

    expect(find.byType(InteractiveViewer), findsOneWidget);
    await tester.tap(find.byTooltip('放大'));
    await tester.pump();
    await tester.tap(find.byTooltip('放大'));
    await tester.pump();

    expect(scaleChanges, isNotEmpty);
    expect(find.text(EmotionType.tired.emoji), findsOneWidget);
    await tester.tap(find.text(EmotionType.tired.emoji));
    await tester.pump();
    expect(tapped?.id, point.id);

    await tester.tap(find.byTooltip('回到全国'));
    await tester.pump();
    expect(find.text(EmotionType.tired.emoji), findsNothing);
  });
}
