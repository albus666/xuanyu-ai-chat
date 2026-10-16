import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/features/consultation/consultation_center_page.dart';

void main() {
  for (final width in [360.0, 411.4]) {
    testWidgets('咨询吸顶栏首屏、滚动及切换标签布局正常：$width', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fake = InterceptorsWrapper(onRequest: (options, handler) {
        handler.resolve(Response(
          requestOptions: options,
          data: {
            'code': options.path.endsWith('/workbench') ? 403 : 0,
            'data': {'list': []},
          },
        ));
      });
      apiClient.interceptors.insert(0, fake);
      addTearDown(() => apiClient.interceptors.remove(fake));

      await tester.pumpWidget(
        const MaterialApp(home: ConsultationCenterPage()),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final header = find.byType(SliverPersistentHeader);
      expect(header, findsOneWidget);
      expect(tester.getSize(find.byType(TabBar)).height, 50);

      await tester.drag(find.byType(NestedScrollView), const Offset(0, -150));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final label in ['在线名师', '免费派对', '私人专线']) {
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
}
