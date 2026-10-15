import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/core/profile/account_birth_profile.dart';
import 'package:xuanyu/features/fortune/astrology/astrology_archive_store.dart';
import 'package:xuanyu/features/fortune/astrology/astrology_chart_wheel.dart';
import 'package:xuanyu/features/fortune/astrology/astrology_models.dart';
import 'package:xuanyu/features/fortune/astrology/astrology_page.dart';

void main() {
  test('本人出生地和坐标完整时可直接用于星盘', () {
    final profile = AccountBirthProfile.fromMap({
      'nickname': '玄遇',
      'birthDate': '2000-03-08',
      'birthTime': '09:30',
      'gender': 1,
      'birthPlace': '河南省 郑州市 金水区',
      'birthLongitude': 113.6254,
      'birthLatitude': 34.7466,
      'birthTimezone': 'Asia/Shanghai',
    });

    expect(profile.isAstrologyComplete, isTrue);
    final request = AstrologyProfile.fromAccount(profile).toRequest();
    expect(request['birthDate'], '2000-03-08');
    expect(request['birthTime'], '09:30');
    expect(request['longitude'], 113.6254);
    expect(request['houseSystem'], 'P');
  });

  test('缺少出生地时不会伪造可计算状态', () {
    final profile = AccountBirthProfile.fromMap({
      'birthDate': '2000-03-08',
      'birthTime': '09:30',
      'gender': 2,
    });
    expect(profile.isComplete, isTrue);
    expect(profile.isAstrologyComplete, isFalse);
  });

  test('时间盘默认使用合适步长并能安全跨月跨年', () {
    expect(AstrologyChartType.natal.supportsTimeNavigation, isFalse);
    expect(AstrologyChartType.relocated.supportsTimeNavigation, isFalse);
    expect(AstrologyChartType.transit.supportsTimeNavigation, isTrue);
    expect(AstrologyChartType.firdaria.supportsTimeNavigation, isTrue);
    expect(AstrologyChartType.transit.defaultTimeStep, AstrologyTimeStep.day);
    expect(
      AstrologyChartType.lunarReturn.defaultTimeStep,
      AstrologyTimeStep.month,
    );
    expect(
      AstrologyChartType.firdaria.defaultTimeStep,
      AstrologyTimeStep.year,
    );

    final leapDay = DateTime(2024, 2, 29, 9, 30);
    expect(
      AstrologyTimeStep.year.shift(leapDay, 1),
      DateTime(2025, 2, 28, 9, 30),
    );
    expect(
      AstrologyTimeStep.month.shift(DateTime(2026, 3, 31, 9, 30), 1),
      DateTime(2026, 4, 30, 9, 30),
    );
  });

  test('动态盘能区分本命层、跨盘相位与未判定运动状态', () {
    final chart = AstrologyChartData.fromJson({
      'chartType': 'secondary',
      'activeLabel': '次限',
      'comparisonLabel': '本命',
      'planets': [
        {
          'key': 'Sun',
          'name': '太阳',
          'symbol': '☉',
          'longitude': 10,
          'sign': '白羊座',
          'signSymbol': '♈',
          'signIndex': 0,
          'degree': 10,
        }
      ],
      'comparisonPlanets': [
        {
          'key': 'Sun',
          'name': '太阳',
          'symbol': '☉',
          'longitude': 8,
          'sign': '白羊座',
          'signSymbol': '♈',
          'signIndex': 0,
          'degree': 8,
        }
      ],
      'crossAspects': [
        {
          'body1': 'Sun',
          'body1Name': '太阳',
          'body2': 'Sun',
          'body2Name': '太阳',
          'type': 'Conjunction',
          'typeName': '合相',
          'symbol': '☌',
          'orb': 2,
          'applying': null,
        }
      ],
      'angles': const {
        'ascendant': {'longitude': 0},
        'midheaven': {'longitude': 270},
      },
    });

    expect(chart.hasComparison, isTrue);
    expect(chart.activeLabel, '次限');
    expect(chart.crossAspects.single.applying, isNull);
    expect(AstrologyChartType.solarReturn.usesEventPlace, isTrue);
    expect(AstrologyChartType.transit.usesEventPlace, isFalse);
  });

  testWidgets('法达盘完整主副限外环可在小屏正常绘制', (tester) async {
    const angle = AstrologyPosition(
      key: 'Ascendant',
      name: '上升',
      symbol: 'ASC',
      longitude: 0,
      sign: '白羊座',
      signSymbol: '♈',
      signIndex: 0,
      degree: 0,
    );
    final chart = AstrologyChartData(
      summary: '太阳白羊座 · 月亮金牛座 · 上升白羊座',
      planets: const [],
      houses: const [],
      ascendant: angle,
      midheaven: angle,
      aspects: const [],
      interpretations: const [],
      elements: const {},
      modes: const {},
      calculation: const {},
      disclaimer: '',
      chartType: AstrologyChartType.firdaria,
      chartTitle: '法达盘',
      firdaria: [
        AstrologyTimePeriod(
          level: 1,
          planet: 'Jupiter',
          planetName: '木星',
          majorPlanetName: '木星',
          startDate: DateTime(2000),
          endDate: DateTime(2012),
          active: true,
        ),
        AstrologyTimePeriod(
          level: 2,
          planet: 'Venus',
          planetName: '金星',
          majorPlanetName: '木星',
          startDate: DateTime(2000),
          endDate: DateTime(2002),
          active: true,
        ),
        AstrologyTimePeriod(
          level: 1,
          planet: 'Mars',
          planetName: '火星',
          majorPlanetName: '火星',
          startDate: DateTime(2012),
          endDate: DateTime(2025),
          active: false,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox.square(
            dimension: 360,
            child: AstrologyChartWheel(chart: chart),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('星盘结果在360像素手机宽度可完整切换专业盘', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final profile = AstrologyProfile(
      name: '测试档案',
      birthDateTime: DateTime(2000, 3, 8, 9, 30),
      birthPlace: '河南省 郑州市 金水区',
      longitude: 113.6254,
      latitude: 34.7466,
    );
    final planets = <String>[
      'Sun',
      'Moon',
      'Mercury',
      'Venus',
      'Mars',
      'Jupiter',
      'Saturn',
      'Uranus',
      'Neptune',
      'Pluto'
    ];
    final chart = AstrologyChartData.fromJson({
      'summary': '太阳双鱼座 · 月亮白羊座 · 上升金牛座',
      'planets': [
        for (var i = 0; i < planets.length; i++)
          {
            'key': planets[i],
            'name': '行星$i',
            'symbol': '●',
            'longitude': i * 31.0,
            'sign': '双鱼座',
            'signSymbol': '♓',
            'signIndex': 11,
            'degree': 17.5,
            'house': i % 12 + 1,
          },
      ],
      'houses': [
        for (var i = 0; i < 12; i++)
          {
            'house': i + 1,
            'longitude': i * 30.0,
            'sign': '白羊座',
            'signSymbol': '♈',
            'signIndex': 0,
            'degree': 0,
          },
      ],
      'angles': {
        'ascendant': {
          'key': 'Ascendant',
          'name': '上升',
          'symbol': 'ASC',
          'longitude': 46.78,
          'sign': '金牛座',
          'signSymbol': '♉',
          'signIndex': 1,
          'degree': 16.78,
        },
        'midheaven': {
          'key': 'Midheaven',
          'name': '天顶',
          'symbol': 'MC',
          'longitude': 300.0,
          'sign': '水瓶座',
          'signSymbol': '♒',
          'signIndex': 10,
          'degree': 0,
        },
      },
      'aspects': const [],
      'interpretations': const [
        {'title': '性格底色', 'subtitle': '太阳双鱼', 'content': '基于太阳、月亮与上升的组合解读。'},
      ],
      'distribution': {
        'elements': {'火': 2, '土': 4, '风': 2, '水': 3},
        'modes': {'开创': 3, '固定': 3, '变动': 4},
      },
      'calculation': const {'engine': 'Moira', 'ephemeris': 'JPL DE440'},
      'disclaimer': '仅供文化娱乐参考',
    });
    final record = AstrologyArchiveRecord(
      id: 'test',
      createdAt: DateTime(2026),
      profile: profile,
      isSelf: true,
    );
    await tester.pumpWidget(MaterialApp(
      home: AstrologyChartPage(
        profile: profile,
        chart: chart,
        record: record,
        isSelf: true,
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(find.text('你的本命星灵'), findsOneWidget);
    expect(find.text('星岩灵鹿'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('astrology-star-spirit-image')),
      findsOneWidget,
    );
    final spiritImage = tester.widget<Image>(
      find.byKey(const ValueKey('astrology-star-spirit-image')),
    );
    expect(
      (spiritImage.image as AssetImage).assetName,
      'assets/astrology/star_spirit_earth_v2.png',
    );
    expect(find.byTooltip('档案笔记'), findsOneWidget);
    expect(find.byTooltip('宫制设置'), findsOneWidget);
    expect(find.text('测试档案 · 本人'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('测试档案 · 本人')).dx,
      lessThan(tester.getTopLeft(find.byTooltip('档案笔记')).dx),
    );
    expect(
      tester.getTopLeft(find.byTooltip('档案笔记')).dx,
      lessThan(tester.getTopLeft(find.byTooltip('宫制设置')).dx),
    );
    await tester.tap(find.text('专业星盘'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('astrology-chart-stage')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('astrology-chart-stage'))).width,
      greaterThanOrEqualTo(350),
    );
    expect(find.text('本命盘'), findsOneWidget);
    expect(find.text('参数'), findsOneWidget);
    expect(find.text('热带黄道'), findsOneWidget);
    expect(find.text('地心视黄经'), findsOneWidget);
    expect(find.text('普拉西德宫制'), findsOneWidget);
    expect(find.text('合相'), findsOneWidget);
    expect(find.text('对冲'), findsOneWidget);
    expect(find.text('刑相'), findsOneWidget);
    expect(find.text('拱相'), findsOneWidget);
    expect(find.text('六合'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('astrology-chart-summary')), findsOneWidget);
    expect(find.text('本命盘概览'), findsOneWidget);
    expect(find.text('太阳'), findsOneWidget);
    expect(find.text('月亮'), findsOneWidget);
    expect(find.text('上升'), findsOneWidget);
    expect(find.text('天顶'), findsOneWidget);
    expect(find.text('水瓶座0°00′'), findsOneWidget);
    expect(find.text('选择盘型'), findsNothing);
    expect(find.text('此刻天象'), findsNothing);
    expect(find.textContaining('2000.03.08'), findsNothing);
    expect(find.textContaining('河南省'), findsNothing);

    await tester.tap(find.text('本命盘'));
    await tester.pumpAndSettle();
    expect(find.text('选择盘型'), findsOneWidget);
    expect(find.text('此刻天象'), findsOneWidget);
    expect(find.text('太阳返照'), findsOneWidget);
    expect(find.text('重置盘'), findsOneWidget);
    await tester.tap(find.text('本命盘').last);
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('astrology-parameter-button')),
    );
    await tester.pumpAndSettle();
    expect(find.text('星盘参数'), findsOneWidget);
    expect(find.text('行星落宫'), findsOneWidget);
    expect(find.text('宫位'), findsOneWidget);
    expect(find.text('相位'), findsOneWidget);
    await tester.tap(find.text('宫位'));
    await tester.pumpAndSettle();
    expect(find.text('升'), findsOneWidget);
    expect(find.text('顶'), findsOneWidget);
    expect(find.text('ASC'), findsNothing);
    expect(find.text('MC'), findsNothing);
    expect(find.textContaining('由开源 Moira'), findsNothing);
    expect(tester.takeException(), isNull);

    Navigator.of(tester.element(find.text('星盘参数'))).pop();
    await tester.pumpAndSettle();
    await tester.pumpWidget(MaterialApp(
      home: AstrologyChartPage(
        profile: profile,
        chart: chart,
        record: record,
        isSelf: true,
        professionalOnly: true,
      ),
    ));
    await tester.pump();
    expect(find.text('个人解读'), findsNothing);
    expect(find.text('专业星盘'), findsNothing);
    expect(find.byKey(const ValueKey('astrology-chart-stage')), findsOneWidget);
    expect(find.byTooltip('档案笔记'), findsNothing);
    expect(find.byTooltip('宫制设置'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
