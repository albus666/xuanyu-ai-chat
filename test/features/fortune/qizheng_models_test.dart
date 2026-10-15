import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/features/fortune/qizheng/qizheng_archive_store.dart';
import 'package:xuanyu/features/fortune/qizheng/qizheng_chart_wheel.dart';
import 'package:xuanyu/features/fortune/qizheng/qizheng_models.dart';
import 'package:xuanyu/features/fortune/qizheng/qizheng_page.dart';
import 'package:xuanyu/features/fortune/qizheng/qizheng_personal_reading.dart';
import 'package:xuanyu/features/fortune/qizheng/qizheng_service.dart';

void main() {
  test('密集星曜文字会展开且保留真实落点顺序', () {
    final displayed = spreadQizhengBodyLabelLongitudes(
      const {'Venus': 10, 'Mercury': 11, 'Sun': 12, 'TrueNode': 13},
      minimumGap: 14,
    );
    final ordered = displayed.values.toList()..sort();
    final gaps = <double>[
      for (var index = 0; index < ordered.length; index++)
        (ordered[(index + 1) % ordered.length] - ordered[index] + 360) % 360,
    ];

    expect(displayed.keys, containsAll(<String>['Venus', 'Mercury', 'Sun']));
    expect(gaps.every((gap) => gap >= 14), isTrue);
  });

  test('七政响应必须完整解析十一曜、十二宫和二十八宿', () {
    final chart = QizhengChartData.fromJson(_chartJson());

    expect(chart.bodies, hasLength(11));
    expect(chart.palaces, hasLength(12));
    expect(chart.mansions, hasLength(28));
    expect(chart.birthMansion.name, '角');
    expect(chart.body('PurpleQi').name, '紫炁');
    expect(chart.calculation['doctrine'], contains('果老星宗'));
  });

  test('流月步进会安全处理月末', () {
    expect(
      QizhengTimeStep.month.shift(DateTime(2025, 1, 31, 8, 6), 1),
      DateTime(2025, 2, 28, 8, 6),
    );
    expect(
      QizhengTimeStep.year.shift(DateTime(2024, 2, 29, 8, 6), 1),
      DateTime(2025, 2, 28, 8, 6),
    );
  });

  test('立命法使用公开盘例口径并保留精确上升点选项', () {
    expect(
      QizhengLifeMode.fromCode('asc_sun_lock'),
      QizhengLifeMode.ascSunLock,
    );
    expect(
      QizhengLifeMode.fromCode('ascendant'),
      QizhengLifeMode.ascendant,
    );
    expect(QizhengLifeMode.fromCode(null), QizhengLifeMode.ascSunLock);
  });

  test('排盘请求明确发送立命法与罗计取法', () async {
    Map<String, dynamic>? sent;
    final interceptor = InterceptorsWrapper(
      onRequest: (options, handler) {
        sent = Map<String, dynamic>.from(options.data as Map);
        handler.resolve(Response<dynamic>(
          requestOptions: options,
          statusCode: 200,
          data: <String, dynamic>{'code': 0, 'data': _chartJson()},
        ));
      },
    );
    apiClient.interceptors.insert(0, interceptor);
    addTearDown(() => apiClient.interceptors.remove(interceptor));

    await QizhengService.calculate(
      QizhengProfile(
        name: '立命法请求测试',
        birthDateTime: DateTime(2001, 12, 1, 0, 42),
        birthPlace: '河南省 濮阳市 台前县',
        longitude: 115.871671,
        latitude: 35.970286,
      ),
      nodeMode: QizhengNodeMode.meanNode,
      lifeMode: QizhengLifeMode.ascendant,
    );

    expect(sent?['nodeMode'], 'mean');
    expect(sent?['lifeMode'], 'ascendant');
  });

  testWidgets('360宽度下个人解读和专业命盘均无布局异常', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final profile = QizhengProfile(
      name: '玄遇',
      birthDateTime: DateTime(2000, 3, 8, 9, 30),
      birthPlace: '河南省 郑州市',
      longitude: 113.62,
      latitude: 34.75,
    );
    final chart = QizhengChartData.fromJson(_chartJson());
    final record = QizhengArchiveRecord(
      id: 'test',
      createdAt: DateTime(2026, 1, 1),
      profile: profile,
      isSelf: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: QizhengChartPage(
          profile: profile,
          chart: chart,
          record: record,
          isSelf: true,
        ),
      ),
    );
    await tester.pump();

    expect(
        find.byKey(const ValueKey('qizheng-personal-reading')), findsOneWidget);
    expect(find.text('先看懂这三件事'), findsOneWidget);
    expect(find.text('七政落点'), findsOneWidget);
    expect(
      find.text(
        '月宿于${chart.body('Moon').mansion}\n${chart.birthMansion.ruler}曜为引',
      ),
      findsOneWidget,
    );
    expect(find.text('命度'), findsOneWidget);
    expect(find.text('月躔'), findsOneWidget);
    expect(find.text('四个关键坐标'), findsNothing);
    expect(
      tester
          .getTopRight(
            find.byKey(const ValueKey('qizheng-personal-orbit')),
          )
          .dx,
      closeTo(354, .1),
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('算法设置'));
    await tester.pumpAndSettle();
    expect(find.text('立命法'), findsOneWidget);
    expect(find.text('与日同络'), findsOneWidget);
    expect(find.text('地平上升点'), findsOneWidget);
    expect(find.text('真罗计'), findsOneWidget);
    expect(tester.takeException(), isNull);
    Navigator.of(tester.element(find.text('算法取法'))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('性格底色'));
    await tester.pumpAndSettle();
    expect(find.byType(DraggableScrollableSheet), findsOneWidget);
    expect(find.text('太阴躔角宿，体现情绪与关系习惯的底色。'), findsOneWidget);
    Navigator.of(tester.element(find.byType(DraggableScrollableSheet))).pop();
    await tester.pumpAndSettle();

    final personalScroll = find
        .descendant(
          of: find.byKey(const ValueKey('qizheng-personal-reading')),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('四余提醒'),
      260,
      scrollable: personalScroll,
    );
    expect(find.text('四余提醒'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('四余提醒'));
    await tester.pumpAndSettle();
    expect(find.text('罗睺'), findsOneWidget);
    expect(find.text('月孛'), findsOneWidget);
    expect(tester.takeException(), isNull);
    Navigator.of(tester.element(find.byType(DraggableScrollableSheet))).pop();
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('十二宫人生地图'),
      260,
      scrollable: personalScroll,
    );
    expect(find.text('十二宫人生地图'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(
      find.text('完整解读依据'),
      260,
      scrollable: personalScroll,
    );
    expect(find.text('完整解读依据'), findsOneWidget);
    expect(find.text('6项'), findsOneWidget);
    expect(find.text('本命星宿'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('专业命盘'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('qizheng-professional-chart')),
        findsOneWidget);
    expect(find.text('盘面参数'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      MaterialApp(
        home: QizhengChartPage(
          profile: profile,
          chart: chart,
          record: record,
          isSelf: true,
          professionalOnly: true,
        ),
      ),
    );
    await tester.pump();
    expect(find.text('个人解读'), findsNothing);
    expect(find.byKey(const ValueKey('qizheng-personal-reading')), findsNothing);
    expect(find.byKey(const ValueKey('qizheng-professional-chart')),
        findsOneWidget);
    expect(find.byTooltip('案例笔记'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('occupants缺失时会从星曜落宫回填十二宫', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final raw = _chartJson();
    for (final palace in raw['palaces']! as List<Map<String, dynamic>>) {
      palace['occupants'] = <String>[];
    }
    final chart = QizhengChartData.fromJson(raw);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: QizhengPersonalReading(chart: chart)),
      ),
    );
    await tester.pump();

    final personalScroll = find
        .descendant(
          of: find.byKey(const ValueKey('qizheng-personal-reading')),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('十二宫人生地图'),
      320,
      scrollable: personalScroll,
    );

    final firstPalace = find.byKey(const ValueKey('qizheng-palace-戌宫'));
    expect(firstPalace, findsOneWidget);
    expect(
      find.descendant(of: firstPalace, matching: find.text('太阳')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

Map<String, dynamic> _chartJson() {
  const bodyKeys = <String>[
    'Sun',
    'Moon',
    'Mercury',
    'Venus',
    'Mars',
    'Jupiter',
    'Saturn',
    'Rahu',
    'Ketu',
    'PurpleQi',
    'Yuebei',
  ];
  const bodyNames = <String>[
    '太阳',
    '太阴',
    '水星',
    '金星',
    '火星',
    '木星',
    '土星',
    '罗睺',
    '计都',
    '紫炁',
    '月孛',
  ];
  const mansions = <String>[
    '娄',
    '胃',
    '昴',
    '毕',
    '觜',
    '参',
    '井',
    '鬼',
    '柳',
    '星',
    '张',
    '翼',
    '轸',
    '角',
    '亢',
    '氐',
    '房',
    '心',
    '尾',
    '箕',
    '斗',
    '牛',
    '女',
    '虚',
    '危',
    '室',
    '壁',
    '奎',
  ];
  const branches = <String>[
    '戌',
    '酉',
    '申',
    '未',
    '午',
    '巳',
    '辰',
    '卯',
    '寅',
    '丑',
    '子',
    '亥'
  ];

  return <String, dynamic>{
    'chartType': 'natal',
    'chartTitle': '本命盘',
    'targetDateTime': '2000-03-08T09:30:00+08:00',
    'summary': '命宫戌宫 · 命度角 · 月躔角 · 昼生',
    'dayNight': '昼生',
    'birthMansion': <String, dynamic>{
      'name': '角',
      'ruler': '木',
      'quadrant': '东方青龙',
      'degree': 4.2,
      'tone': '有开创力，重原则，也愿意为长期目标先走一步',
    },
    'lifeDegree': <String, dynamic>{
      'longitude': 203.5,
      'palace': '辰宫',
      'mansion': '角',
      'mansionRuler': '木',
      'mansionDegree': 3.2,
    },
    'bodies': <Map<String, dynamic>>[
      for (var index = 0; index < bodyKeys.length; index++)
        <String, dynamic>{
          'key': bodyKeys[index],
          'name': bodyNames[index],
          'shortName': bodyNames[index].substring(bodyNames[index].length - 1),
          'element': index < 7 ? '木' : '余',
          'color': '#55AFA4',
          'longitude': (index * 31.7 + 8) % 360,
          'speed': index == 6 ? -0.1 : 1,
          'retrograde': index == 6,
          'palace': '${branches[index % 12]}宫',
          'palaceRole': index == 0 ? '命宫' : '官禄宫',
          'palaceDegree': 8.2,
          'mansion': mansions[index],
          'mansionRuler': '木',
          'mansionQuadrant': '东方青龙',
          'mansionDegree': 2.4,
          'dignities': index == 0 ? <String>['庙'] : <String>[],
        },
    ],
    'palaces': <Map<String, dynamic>>[
      for (var index = 0; index < 12; index++)
        <String, dynamic>{
          'index': index,
          'name': '${branches[index]}宫',
          'branch': branches[index],
          'element': '木',
          'role': index == 0 ? '命宫' : '第${index + 1}宫',
          'startLongitude': index * 30,
          'occupants': <String>[bodyKeys[index % bodyKeys.length]],
        },
    ],
    'mansions': <Map<String, dynamic>>[
      for (var index = 0; index < 28; index++)
        <String, dynamic>{
          'name': mansions[index],
          'ruler': '木',
          'quadrant': index < 7 ? '西方白虎' : '东方青龙',
          'determinativeStar': 'reference-$index',
          'longitude': index * (360 / 28),
          'width': 360 / 28,
        },
    ],
    'relationships': <Map<String, dynamic>>[
      <String, dynamic>{
        'body1': 'Sun',
        'body1Name': '太阳',
        'body2': 'Moon',
        'body2Name': '太阴',
        'type': '拱',
        'separation': 120,
      },
    ],
    'interpretations': <Map<String, dynamic>>[
      <String, dynamic>{
        'title': '本命星宿',
        'subtitle': '角宿 · 东方青龙',
        'content': '太阴躔角宿，体现情绪与关系习惯的底色。',
      },
      <String, dynamic>{
        'title': '命宫气质',
        'subtitle': '命度角宿',
        'content': '外在行动更愿意先观察全局，再稳步推进。',
      },
      <String, dynamic>{
        'title': '核心动力',
        'subtitle': '太阳在戌宫 · 娄宿',
        'content': '太阳进入命宫，人生中容易把注意力投向自我定位与主动选择。',
      },
      <String, dynamic>{
        'title': '情感与连接',
        'subtitle': '月官禄宫 · 金官禄宫',
        'content': '太阴体现安全感，金星体现亲近与审美，关系里需要照顾真实感受。',
      },
      <String, dynamic>{
        'title': '行动与事业',
        'subtitle': '火官禄宫 · 木官禄宫 · 土官禄宫',
        'content': '火星推动行动，木星扩展机会，土星要求长期建设。',
      },
      <String, dynamic>{
        'title': '四余课题',
        'subtitle': '罗鬼 · 孛柳',
        'content': '四余用来提示容易反复牵动的议题，不能脱离七政强弱单独下结论。',
      },
    ],
    'calculation': <String, dynamic>{
      'engine': 'XuanYu Qizheng / Moira Astronomy',
      'doctrine': '果老星宗-动态距星-v1',
      'ephemeris': 'JPL DE440',
    },
    'disclaimer': '传统文化研究与娱乐参考。',
  };
}
