import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/features/community/map_location_picker_page.dart';

void main() {
  testWidgets('Android 选点页展示可交互地图而不是手输兜底', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: MapLocationPickerPage()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(MapLocationPickerPage), findsOneWidget);
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.text('当前设备不支持高德地图预览'), findsNothing);
    expect(find.text('搜索地点或区域'), findsOneWidget);
  });
}
