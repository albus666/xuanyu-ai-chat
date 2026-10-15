import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xuanyu/core/constants/app_constants.dart';
import 'package:xuanyu/core/local/paipan_record_store.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/core/network/api_session_scope.dart';
import 'package:xuanyu/core/utils/app_toast.dart';
import 'package:xuanyu/features/consultation/room_chart_sheet.dart';
import 'package:xuanyu/features/fortune/archive_relationship.dart';
import 'package:xuanyu/features/fortune/paipan/models/paipan_record.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.directory);

  final Directory directory;

  @override
  Future<String?> getApplicationDocumentsPath() async => directory.path;
}

Response<dynamic> _response(RequestOptions request, Object? data) =>
    Response<dynamic>(requestOptions: request, statusCode: 200, data: data);

PaipanRecord _sourceRecord() => PaipanRecord(
      id: 'room-case-1',
      createdAt: DateTime(2026, 9, 28),
      displayName: '测试案例',
      relationship: ArchiveRelationship.friend,
      birthDateTime: DateTime(2000, 1, 1, 12),
      isFemale: false,
      calendarTypeIndex: 0,
      summary: '庚辰 戊子 戊午 戊午',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late PathProviderPlatform previousPaths;
  late InterceptorsWrapper interceptor;
  late void Function(RequestOptions, RequestInterceptorHandler) respond;
  final calls = <RequestOptions>[];

  setUp(() async {
    calls.clear();
    SharedPreferences.setMockInitialValues({AppConstants.keyUserId: 77});
    directory = await Directory.systemTemp.createTemp('room-chart-workflow-');
    previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(directory);
    setupApiClientToken('room-chart-old');
    await PaipanRecordStore.save(_sourceRecord());
    respond = (request, handler) {
      handler.resolve(
        _response(request, {
          'code': 0,
          'data': {'list': <Object>[]},
        }),
      );
    };
    interceptor = InterceptorsWrapper(onRequest: (request, handler) {
      calls.add(request);
      respond(request, handler);
    });
    apiClient.interceptors.insert(0, interceptor);
  });

  tearDown(() async {
    dismissAllAppToasts();
    apiClient.interceptors.remove(interceptor);
    setupApiClientToken(null);
    PathProviderPlatform.instance = previousPaths;
    await directory.delete(recursive: true);
  });

  Future<void> openRoomCharts(WidgetTester tester) async {
    final source = _sourceRecord();
    final roomCase = RoomChartCase(
      id: source.id,
      createdAt: source.createdAt,
      name: source.displayName,
      isSelf: source.isSelf,
      relationship: source.relationship,
      birthDateTime: source.birthDateTime,
      isFemale: source.isFemale,
      calendarTypeIndex: source.calendarTypeIndex,
      snapshots: {RoomChartKind.bazi: source.toJson()},
    );
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showRoomChartSheet(
                context,
                roomId: 9,
                members: const [
                  {'userId': 77, 'nickname': '我', 'isMe': true},
                  {'userId': 88, 'nickname': '成员甲'},
                  {'userId': 99, 'nickname': '成员乙'},
                ],
                caseLoader: () async => [roomCase],
              ),
              child: const Text('打开命盘'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开命盘'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text('测试案例'), findsWidgets);
  }

  Future<void> openPublishSettings(WidgetTester tester) async {
    final publish = find.text('发布「测试案例」到本房间');
    await tester.ensureVisible(publish);
    await tester.tap(publish);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('发布到本房间'), findsOneWidget);
  }

  testWidgets('私人命盘选择提供四分类和新增案例且不访问派对发布接口', (tester) async {
    final source = _sourceRecord();
    RoomChartArchive? selected;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: RoomChartSheet(
      roomId: 0,
      members: const [],
      caseLoader: () async => [
        RoomChartCase(
          id: source.id,
          createdAt: source.createdAt,
          name: source.displayName,
          isSelf: source.isSelf,
          relationship: source.relationship,
          birthDateTime: source.birthDateTime,
          isFemale: source.isFemale,
          calendarTypeIndex: source.calendarTypeIndex,
          snapshots: {RoomChartKind.bazi: source.toJson()},
        )
      ],
      onChooseArchive: (archive) => selected = archive,
    ))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    for (final kind in RoomChartKind.values) {
      expect(find.widgetWithText(ChoiceChip, kind.label), findsOneWidget);
    }
    expect(find.text('新增案例'), findsOneWidget);
    final authorize = find.text('授权「测试案例」给老师');
    await tester.ensureVisible(authorize);
    await tester.tap(authorize);
    await tester.pump();
    expect(selected?.kind, RoomChartKind.bazi);
    expect(selected?.name, '测试案例');
    expect(calls.where((r) => r.path.contains('/rooms/')), isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('指定成员发布只上传已选用户', (tester) async {
    Map<String, dynamic>? submitted;
    respond = (request, handler) {
      if (request.method == 'POST') {
        submitted = Map<String, dynamic>.from(request.data as Map);
        handler.resolve(_response(request, {'code': 0, 'data': {}}));
        return;
      }
      handler.resolve(
        _response(request, {
          'code': 0,
          'data': {'list': <Object>[]},
        }),
      );
    };

    await openRoomCharts(tester);
    await openPublishSettings(tester);
    await tester.tap(find.text('指定成员'));
    await tester.pump();
    await tester.tap(find.text('成员甲'));
    await tester.pump();
    await tester.tap(find.text('确认发布'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(submitted?['scope'], 'selected');
    expect(submitted?['recipientUserIds'], <int>[88]);
    expect(calls.where((request) => request.method == 'POST'), hasLength(1));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('HTTP 200 业务拒绝不再误报命盘发布成功', (tester) async {
    respond = (request, handler) {
      if (request.method == 'POST') {
        handler.resolve(
          _response(request, {'code': 403, 'message': '无权发布命盘'}),
        );
        return;
      }
      handler.resolve(
        _response(request, {
          'code': 0,
          'data': {'list': <Object>[]},
        }),
      );
    };

    await openRoomCharts(tester);
    await openPublishSettings(tester);
    await tester.tap(find.text('确认发布'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('无权发布命盘'), findsOneWidget);
    expect(find.text('命盘仅自己可见'), findsNothing);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('发布设置打开后切号会立即失效且不发送旧房间请求', (tester) async {
    await openRoomCharts(tester);
    await openPublishSettings(tester);
    calls.clear();

    setupApiClientToken('room-chart-new');
    await tester.pump();

    expect(find.text(apiSessionChangedMessage), findsWidgets);
    expect(find.text('确认发布'), findsNothing);
    expect(calls.where((request) => request.method == 'POST'), isEmpty);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('HTTP 200 撤回失败保留命盘并展示真实原因', (tester) async {
    final source = _sourceRecord();
    respond = (request, handler) {
      if (request.method == 'DELETE') {
        handler.resolve(
          _response(request, {'code': 403, 'message': '仅发布者可撤回'}),
        );
        return;
      }
      handler.resolve(
        _response(request, {
          'code': 0,
          'data': {
            'list': [
              {
                'id': 31,
                'chartType': 'bazi',
                'ownerNickname': '发布者',
                'displayName': '共享命盘',
                'scope': 'all',
                'recipientUserIds': <int>[],
                'allowSaveCopy': false,
                'canManage': true,
                'snapshot': source.toJson(),
              },
            ],
          },
        }),
      );
    };

    await openRoomCharts(tester);
    await tester.ensureVisible(find.text('共享命盘'));
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('撤回命盘'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('确认撤回'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('仅发布者可撤回'), findsOneWidget);
    expect(find.text('命盘已撤回'), findsNothing);
    expect(find.text('共享命盘'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('八字副本写入前校验目标账号', () async {
    final record = (await PaipanRecordStore.loadAll()).single;
    await expectLater(
      PaipanRecordStore.save(record, expectedUserId: 88),
      throwsStateError,
    );
    expect(await PaipanRecordStore.loadAll(), hasLength(1));
  });

  testWidgets('命盘加载失败显示重试而非暂无命盘', (tester) async {
    respond =
        (r, h) => h.resolve(_response(r, {'code': 503, 'message': '命盘服务暂不可用'}));
    await openRoomCharts(tester);
    expect(find.text('重试加载命盘'), findsOneWidget);
    expect(find.text('命盘服务暂不可用'), findsOneWidget);
    respond = (r, h) => h.resolve(_response(r, {
          'code': 0,
          'data': {'list': []}
        }));
    await tester.tap(find.text('重试加载命盘'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('重试加载命盘'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('撤回确认中切号移除旧信息与确认按钮', (tester) async {
    respond = (r, h) => h.resolve(_response(r, {
          'code': 0,
          'data': {
            'list': [
              {
                'id': 31,
                'displayName': '旧账号命盘',
                'canManage': true,
                'allowSaveCopy': false
              }
            ]
          }
        }));
    await openRoomCharts(tester);
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('撤回命盘'));
    await tester.pumpAndSettle();
    expect(find.text('确认撤回'), findsOneWidget);
    setupApiClientToken('room-chart-new');
    await tester.pump();
    expect(find.text('确认撤回'), findsNothing);
    expect(find.textContaining('旧账号命盘'), findsNothing);
    expect(calls.where((r) => r.method == 'DELETE'), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('未明确授予另存权限时不可另存', () {
    for (final value in [null, false, 'true', 1]) {
      expect(RoomChartShare.fromJson({'allowSaveCopy': value}).allowSaveCopy,
          isFalse);
    }
    expect(
        RoomChartShare.fromJson({'allowSaveCopy': true}).allowSaveCopy, isTrue);
  });
}
