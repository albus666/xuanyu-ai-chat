import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/app/common/routers/names.dart';
import 'package:xuanyu/app/common/routers/pages.dart';
import 'package:xuanyu/app/pages/home/home_index/controller.dart';

void main() {
  test('首页和全局路由不再暴露情绪地图', () {
    final labels = HomeIndexController().gridEntries.map((item) => item.label);
    final routes = RoutePages.list.map((item) => item.name);

    expect(labels, isNot(contains('情绪地图')));
    expect(routes, isNot(contains('/emotion_map')));
    expect(routes, isNot(contains('/home_no_kind_words')));
    expect(routes, isNot(contains('/home_ai_square')));
    expect(routes, isNot(contains('/pet_insight')));
    expect(RouteNames.roleDiagnosis, '/role_diagnosis');
  });

  test('首页快捷入口按确认顺序展示', () {
    final entries = HomeIndexController().gridEntries;

    expect(entries.map((item) => item.label), <String>[
      '八字排盘',
      '紫微斗数',
      '星座星盘',
      '七政四余',
      '生肖印记',
      '住宅分析',
      '体质测试',
      '伴侣画像',
      '使用建议',
    ]);
    expect(entries[2].routeName, RouteNames.homeAstrology);
    expect(entries[3].routeName, RouteNames.homeQizheng);
    expect(entries[4].routeName, RouteNames.zodiac);
    expect(entries[7].routeName, RouteNames.partnerPortrait);
    expect(entries[8].routeName, RouteNames.suggestions);
    expect(
      RoutePages.list.map((item) => item.name),
      contains(RouteNames.suggestions),
    );
  });

  test('首页快捷入口每页两行五列', () {
    expect(HomeIndexController.gridColumns, 5);
    expect(HomeIndexController.gridRows, 2);
    expect(HomeIndexController.gridItemsPerPage, 10);

    final entries = HomeIndexController().gridEntries;
    expect(entries, hasLength(9));
  });

  test('首页伴侣画像替换 AI 八字，隐藏四个暂停功能入口', () {
    final entries = HomeIndexController().gridEntries;
    final labels = entries.map((item) => item.label);

    expect(entries[7], HomeIndexController.partnerPortraitEntry);
    expect(HomeIndexController.partnerPortraitEntry.label, '伴侣画像');
    expect(
      HomeIndexController.partnerPortraitEntry.routeName,
      RouteNames.partnerPortrait,
    );
    expect(labels, isNot(contains('AI八字')));
    expect(labels, isNot(contains('没一句好话')));
    expect(labels, isNot(contains('人生图鉴')));
    expect(labels, isNot(contains('灵宠心语')));
  });

  test('生肖印记在功能入口中位于伴侣画像之前', () {
    final routes = RoutePages.list.map((item) => item.name);
    final entries = HomeIndexController().gridEntries;

    expect(routes, contains(RouteNames.zodiac));
    expect(entries[4].label, '生肖印记');
    expect(entries[4].routeName, RouteNames.zodiac);
    expect(entries[7].label, '伴侣画像');
  });

  test('七政四余保留独立入口且星宿印记不再暴露', () {
    final routes = RoutePages.list.map((item) => item.name);
    final labels = HomeIndexController().gridEntries.map((item) => item.label);
    expect(routes, contains(RouteNames.homeQizheng));
    expect(RouteNames.homeQizheng, isNot(RouteNames.homeAstrology));
    expect(labels, isNot(contains('星宿印记')));
    expect(routes, isNot(contains('/home_xingxiu')));
  });
}
