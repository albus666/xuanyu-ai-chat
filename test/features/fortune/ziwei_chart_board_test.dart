import 'package:flutter/material.dart';
import 'package:xuanyu/shared/widgets/cultural_reference_notice.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:xuanyu/features/fortune/ziwei/widgets/ziwei_chart_board.dart';
import 'package:xuanyu/features/fortune/ziwei/widgets/ziwei_personal_info_tab.dart';
import 'package:xuanyu/features/fortune/ziwei/ziwei_chart_page.dart';
import 'package:xuanyu/features/fortune/ziwei/ziwei_input_page.dart';
import 'package:xuanyu/features/fortune/ziwei/ziwei_models.dart';
import 'package:xuanyu/features/fortune/ziwei/ziwei_pattern.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() => initializeDateFormatting('zh_CN'));

  testWidgets('排盘输入页与平台表单一致且不提供AI解读', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, child) => const MaterialApp(
          home: ZiweiInputPage(loadAccountProfile: false, forOther: true),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('输入对方生辰信息'), findsOneWidget);
    expect(find.text('开始排盘'), findsOneWidget);
    expect(find.textContaining('AI解读'), findsNothing);
  });

  testWidgets('斗数输入页提示在表单末尾随内容滚动，不占用固定底栏', (tester) async {
    tester.view.physicalSize = const Size(320, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, child) => const MaterialApp(
          home: ZiweiInputPage(loadAccountProfile: false, forOther: true),
        ),
      ),
    );
    await tester.pump();

    final notice = find.text(CulturalReferenceNotice.text);
    final scroll = find.byType(CustomScrollView);
    expect(tester.widget<Scaffold>(find.byType(Scaffold)).bottomNavigationBar,
        isNull);
    expect(notice, findsOneWidget);
    expect(tester.getRect(notice).top, greaterThanOrEqualTo(360));
    await tester.drag(scroll, const Offset(0, -1000));
    await tester.pumpAndSettle();
    final noticeBounds = tester.getRect(notice);
    final buttonBounds = tester.getRect(find.text('开始排盘'));
    expect(noticeBounds.top, greaterThan(buttonBounds.bottom));
    expect(noticeBounds.bottom, lessThanOrEqualTo(360));
    expect(noticeBounds.left, greaterThan(0));
    expect(noticeBounds.right, lessThan(320));
    await tester.drag(scroll, const Offset(0, 1000));
    await tester.pumpAndSettle();
    expect(tester.getRect(notice).top, greaterThanOrEqualTo(360));
    expect(tester.takeException(), isNull);
  });

  testWidgets('命盘在手机宽度完整绘制并可点击宫位', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var selected = -1;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 366,
              child: ZiweiChartBoard(
                data: _chartData(),
                profile: _profile(),
                activeLayer: ZiweiLayer.yearly,
                selectedPalaceIndex: 0,
                onPalaceTap: (index) => selected = index,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('命宫'), findsWidgets);
    expect(find.text('本禄'), findsWidgets);
    expect(find.text('年禄'), findsWidgets);
    expect(find.textContaining('节气四柱'), findsOneWidget);
    expect(find.textContaining('斗数四柱'), findsOneWidget);
    expect(find.text('流年：1,13,25,37,49'), findsWidgets);
    expect(find.text('小限：1,13,25,37,49'), findsWidgets);
    expect(find.text('博士\n将星\n岁驿'), findsWidgets);
    expect(find.text('长生'), findsWidgets);
    expect(find.text('大限 3～12'), findsOneWidget);
    expect(find.text('大命'), findsOneWidget);
    expect(find.text('年命'), findsOneWidget);
    final boardSize = tester.getSize(find.byType(ZiweiChartBoard));
    expect(boardSize.height, closeTo(boardSize.width * 1.34, .1));
    expect(
      find.byKey(const ValueKey('ziwei-surrounded-lines-yearly-0')),
      findsOneWidget,
    );
    await tester.tap(find.text('命宫').first);
    expect(selected, 0);
  });

  testWidgets('空宫盘面显示对宫主星而不显示空宫占位文字', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 366,
            child: ZiweiChartBoard(
              data: _chartData(emptyPalaceIndex: 0),
              profile: _profile(),
              activeLayer: ZiweiLayer.natal,
              selectedPalaceIndex: 0,
              onPalaceTap: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('借对宫'), findsOneWidget);
    expect(find.text('空宫'), findsNothing);
  });

  testWidgets('命盘保留设置与分享入口且点击宫位只更新三方四正', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: ZiweiChartPage(
          profile: _profile(),
          initialData: _chartData(),
          initialTargetDate: DateTime(2026, 8, 10),
          initialTargetTimeIndex: 7,
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('本命'), findsOneWidget);
    expect(find.textContaining('当前：'), findsNothing);
    expect(find.textContaining('路径：'), findsNothing);
    expect(find.text('运限选择'), findsNothing);
    expect(find.byTooltip('设置'), findsOneWidget);
    expect(find.text('个人信息'), findsOneWidget);
    expect(find.text('专业命盘'), findsOneWidget);
    expect(find.text('本命主轴'), findsOneWidget);
    expect(find.text('当前人生阶段'), findsOneWidget);
    expect(find.text('十二宫人生地图'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('ziwei-case-notebook-action')),
      findsOneWidget,
    );
    await tester.dragUntilVisible(
      find.text('认识自己'),
      find.byType(Scrollable).first,
      const Offset(0, -420),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('更多'), findsOneWidget);
    expect(find.byTooltip('命盘资料'), findsNothing);
    expect(find.byTooltip('全屏命盘'), findsNothing);
    expect(find.text('宫位详情'), findsNothing);
    expect(find.text('排盘信息'), findsNothing);

    await tester.tap(find.text('专业命盘'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('ziwei-professional-bottom-safe-area')),
      findsOneWidget,
    );
    expect(find.text('流时'), findsWidgets);
    await tester.tap(find.text('流年').first);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('大命'), findsOneWidget);
    expect(find.text('年命'), findsOneWidget);

    await tester.tap(find.text('宫2').first);
    await tester.pump();
    expect(find.textContaining('详情'), findsNothing);
    expect(
      find.byKey(const ValueKey('ziwei-surrounded-lines-yearly-2')),
      findsOneWidget,
    );
  });

  testWidgets('隐藏出生资料的共享专业盘保留运限并通过授权加载器切换', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final requested = <DateTime>[];
    await tester.pumpWidget(MaterialApp(home: ZiweiChartPage(
      profile: _profile(), initialData: _chartData(),
      initialTargetDate: DateTime(2026, 8, 10), initialTargetTimeIndex: 7,
      professionalOnly: true, embedded: true, showBirthData: false,
      sharedChartLoader: (date, timeIndex) async {
        requested.add(date);
        return _chartData();
      },
    )));
    await tester.pumpAndSettle();
    expect(find.byType(AppBar), findsNothing);
    expect(find.textContaining('1990-05-08'), findsNothing);
    expect(find.text('大限'), findsWidgets);
    final label = find.text('3～12岁');
    await tester.ensureVisible(label);
    await tester.pumpAndSettle();
    await tester.tap(label);
    await tester.pumpAndSettle();
    expect(requested, hasLength(1));
    expect(requested.single.year, 1992);
    expect(find.text('流月'), findsWidgets);
    expect(find.text('流日'), findsWidgets);
    expect(find.text('流时'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('房间模式只显示斗数专业盘面', (tester) async {
    tester.view.physicalSize = const Size(360, 520);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: ZiweiChartPage(
          profile: _profile(),
          initialData: _chartData(),
          initialTargetDate: DateTime(2026, 8, 10),
          initialTargetTimeIndex: 7,
          professionalOnly: true,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('个人信息'), findsNothing);
    expect(find.text('专业命盘'), findsNothing);
    expect(
      find.byKey(const ValueKey('ziwei-professional-bottom-safe-area')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('ziwei-case-notebook-action')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('ziwei-archive-switch-action')),
        findsNothing);
    expect(tester.widget<Scaffold>(find.byType(Scaffold)).bottomNavigationBar,
        isNull);
    final notice = find.text(CulturalReferenceNotice.text);
    final chartScroll = find.byKey(
      const PageStorageKey('ziwei-professional-chart-scroll'),
    );
    expect(notice.hitTestable(), findsNothing);
    await tester.dragUntilVisible(notice, chartScroll, const Offset(0, -400));
    await tester.drag(chartScroll, const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(notice, findsOneWidget);
    expect(tester.getRect(notice).bottom, lessThanOrEqualTo(520));
    await tester.drag(chartScroll, const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(notice.hitTestable(), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('未满足严格格局条件时回落到可核对的坐命主轴', () {
    final pattern = ZiweiPatternRecognizer.recognize(_chartData());

    expect(pattern.classic, isFalse);
    expect(pattern.name, contains('坐命'));
    expect(pattern.summary, contains('三方四正'));
  });

  testWidgets('斗数人生阶段显示当前运限动态文案', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: ZiweiChartPage(
          profile: _profile(),
          initialData: _chartData(),
          initialTargetDate: DateTime(2026, 8, 10),
          initialTargetTimeIndex: 7,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('当前人生阶段'), findsOneWidget);
    for (final value in ziweiStageSignalValues(_chartData())) {
      expect(find.text(value), findsOneWidget);
    }
  });

  test('斗数人生阶段更换流年干支与落宫后文案变化', () {
    final original = ziweiStageSignalValues(_chartData());
    final changed = ziweiStageSignalValues(
      _chartData(
        yearly: _scope(
          index: 1,
          heavenlyStem: '丁',
          earthlyBranch: '未',
          nominalAge: 38,
        ),
      ),
    );

    expect(changed, isNot(equals(original)));
  });
}

ZiweiProfile _profile() => ZiweiProfile(
      name: '测试命盘',
      gender: '男',
      clockBirthDate: DateTime(1990, 5, 8, 13),
      effectiveBirthDate: DateTime(1990, 5, 8, 13),
      calendarTypeIndex: 0,
      settings: const ZiweiSettings(),
    );

ZiweiChartData _chartData({ZiweiScope? yearly, int? emptyPalaceIndex}) {
  final stars = [
    const ZiweiStar(
      name: '紫微',
      type: 'major',
      scope: 'origin',
      brightness: '庙',
      mutagen: '禄',
    ),
    const ZiweiStar(
      name: '天机',
      type: 'minor',
      scope: 'origin',
      brightness: '旺',
      mutagen: '',
    ),
    const ZiweiStar(
      name: '太阴',
      type: 'minor',
      scope: 'origin',
      brightness: '得',
      mutagen: '',
    ),
  ];
  final palaces = [
    for (var index = 0; index < 12; index++)
      ZiweiPalace(
        index: index,
        name: index == 0 ? '命宫' : '宫$index',
        isBodyPalace: index == 1,
        isOriginalPalace: index == 2,
        heavenlyStem: '甲',
        earthlyBranch: '子',
        majorStars: index == emptyPalaceIndex ? const [] : stars,
        minorStars: stars,
        adjectiveStars: stars,
        changsheng12: '长生',
        boshi12: '博士',
        jiangqian12: '将星',
        suiqian12: '岁驿',
        decadal: ZiweiDecadal(
          startAge: index * 10 + 3,
          endAge: index * 10 + 12,
          heavenlyStem: '甲',
          earthlyBranch: '子',
        ),
        ages: const [1, 13, 25, 37, 49],
      ),
  ];
  final scope = _scope(stars: stars);
  return ZiweiChartData(
    engineName: 'iztro',
    engineVersion: '2.5.8',
    ruleCode: 'test',
    astrolabe: ZiweiAstrolabe(
      gender: '男',
      solarDate: '1990-05-08',
      lunarDate: '一九九○年四月十四',
      chineseDate: '庚午 辛巳 癸酉 己未',
      time: '未时',
      timeRange: '13:00~15:00',
      sign: '金牛座',
      zodiac: '马',
      bodyPalaceBranch: '丑',
      soulPalaceBranch: '子',
      soul: '破军',
      body: '火星',
      fiveElementsClass: '金四局',
      palaces: palaces,
    ),
    horoscope: ZiweiHoroscope(
      solarDate: '2026-08-10',
      lunarDate: '二○二六年六月廿八',
      decadal: scope,
      age: scope,
      yearly: yearly ?? scope,
      monthly: scope,
      daily: scope,
      hourly: scope,
    ),
  );
}

ZiweiScope _scope({
  int index = 0,
  String heavenlyStem = '丙',
  String earthlyBranch = '午',
  int nominalAge = 37,
  List<ZiweiStar>? stars,
}) {
  final activeStars = stars ??
      const [
        ZiweiStar(
          name: '紫微',
          type: 'major',
          scope: 'origin',
          brightness: '庙',
          mutagen: '禄',
        ),
      ];
  return ZiweiScope(
    index: index,
    name: '流年',
    heavenlyStem: heavenlyStem,
    earthlyBranch: earthlyBranch,
    palaceNames: const [
      '命宫',
      '兄弟',
      '夫妻',
      '子女',
      '财帛',
      '疾厄',
      '迁移',
      '交友',
      '官禄',
      '田宅',
      '福德',
      '父母',
    ],
    mutagen: const ['紫微', '天机', '太阳', '武曲'],
    stars: [for (var group = 0; group < 12; group++) activeStars],
    nominalAge: nominalAge,
  );
}
