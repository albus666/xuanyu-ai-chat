import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String source;
  late String ownerProfileSource;
  late String relationshipSource;
  late String shareSource;

  setUpAll(() {
    source = File('lib/features/community/user_profile_page.dart')
        .readAsStringSync();
    ownerProfileSource =
        File('lib/features/profile/profile_page.dart').readAsStringSync();
    relationshipSource = File(
      'lib/features/community/user_relationship_settings.dart',
    ).readAsStringSync();
    shareSource = File('lib/core/utils/profile_share.dart').readAsStringSync();
  });

  test('用户主页保留资料卡并支持下拉展开与上滑收起背景', () {
    expect(source, contains('onPointerMove: _handleRevealPointerMove'));
    expect(source, contains('_backgroundRevealController.animateTo'));
    expect(source, contains('_ProfileRevealScrollPhysics'));
    expect(source, contains('delta / 300'));
    expect(source, contains('_revealDragCanExpand'));
    expect(source, contains('position.minScrollExtent + 0.5'));
    expect(source, contains('_consumeRevealGesture = false'));
    expect(source, contains('_backgroundRevealController.value <= 0.001'));
    expect(source, contains('_revealCollapseHandoffDistance'));
    expect(source, contains('_limitRevealHandoffFling'));
    expect(source, contains('createBallisticSimulation'));
    expect(source, contains('velocity.clamp(-720.0, 720.0)'));
    expect(source, isNot(contains('_backgroundRevealController.animateBack')));
    expect(source, contains("label: '下拉展开主页背景，上滑收起'"));
    expect(source, contains('child: _buildProfileSummaryCard('));
    expect(source, contains('bottom: 12'));
  });

  test('自己和他人的背景大图预览都覆盖全屏', () {
    expect(source, isNot(contains('fit: BoxFit.contain')));
    expect(ownerProfileSource, isNot(contains('fit: BoxFit.contain')));
    expect(source, contains('fit: BoxFit.cover'));
    expect(ownerProfileSource, contains('fit: BoxFit.cover'));
  });

  test('背景本体不随手势做整体晃动或缩放', () {
    expect(source, contains('child: ProfileBackgroundArtwork('));
    expect(source, isNot(contains('Transform.scale')));
    expect(source, isNot(contains('Transform.translate')));
  });

  test('别人主页三点直接进入分享与五项关系设置', () {
    expect(source, contains('Icons.more_horiz_rounded'));
    expect(source, contains('showUserProfileShareSheet('));
    for (final label in ['备注', '对Ta隐身', '悄悄关注', '特别关心', '拉黑']) {
      expect(shareSource, contains(label));
    }
    expect(source, contains('/relationship-preferences'));
  });

  test('别人主页资料卡、字号和底栏按参考图紧凑化', () {
    expect(source, contains('radius: 34'));
    expect(source, contains('fontSize: 20'));
    expect(source, contains('height: 40'));
    expect(source, contains('height: 46'));
    expect(source, contains('height: 44'));
    expect(source, contains('compactLayout: true'));
    expect(source, contains("const tabs = ['瞬间', '收藏'];"));
    expect(source, isNot(contains("'收藏 🔒'")));
  });

  test('关系功能包含完整后续页面与真实保存字段', () {
    for (final text in [
      '备注和描述',
      '请填写备注',
      '请填写描述',
      '添加图片',
      '对TA隐身访问设置',
      '隐身查看TA的主页',
      '隐身查看TA的瞬间',
      '隐身查看与TA的私聊对话',
      '特别关心设置',
      '消息提示音',
    ]) {
      expect(relationshipSource, contains(text));
    }
    expect(source, contains('确定将对方加入黑名单？'));
    expect(source, contains('黑名单在“我的-设置-隐私设置”中'));
  });
}
