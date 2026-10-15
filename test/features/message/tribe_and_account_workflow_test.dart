import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xuanyu/core/auth/saved_account_store.dart';

void main() {
  test('切换账号保留登录态并支持返回已保存账号', () {
    final settings =
        File('lib/features/profile/settings_page.dart').readAsStringSync();
    final switcher = File('lib/features/profile/account_switcher_page.dart')
        .readAsStringSync();
    final auth = File('lib/app/bootstrap/auth_state.dart').readAsStringSync();
    final login =
        File('lib/app/pages/system/login/view.dart').readAsStringSync();

    expect(settings, contains('AccountSwitcherPage'));
    expect(settings, isNot(contains('_switchAccount')));
    expect(switcher, contains('activateSavedAccount'));
    expect(switcher, contains('登录其他账号'));
    expect(auth, contains('prepareAddAccount'));
    expect(login, contains('返回已保存账号'));
  });

  test('本机账号保存、排序与移除互不影响', () async {
    SharedPreferences.setMockInitialValues({});
    await SavedAccountStore.rememberLogin(
        token: 'session-a', userId: 10, account: '15600000001');
    await SavedAccountStore.rememberLogin(
        token: 'session-b', userId: 20, account: '15600000002');

    var accounts = await SavedAccountStore.load();
    expect(accounts.map((item) => item.userId), [20, 10]);
    expect(accounts.first.maskedAccount, '156****0002');

    await SavedAccountStore.remove(20);
    accounts = await SavedAccountStore.load();
    expect(accounts.map((item) => item.userId), [10]);
  });

  test('部落标识、成员与管理入口形成完整跳转', () {
    final chip =
        File('lib/features/community/team_title_chip.dart').readAsStringSync();
    final home =
        File('lib/features/community/team_home_page.dart').readAsStringSync();
    final groupInfo =
        File('lib/features/message/chat_info_page.dart').readAsStringSync();

    expect(chip, contains('/api/im/user/\$targetUserId/team'));
    expect(chip, contains('RouteNames.teamHome'));
    expect(home, contains('部落成员'));
    expect(home, contains("title: '部落求助'"));
    expect(home, contains('暂无面向该部落的求助'));
    expect(home, isNot(contains("title: '部落内容'")));
    expect(home, contains("Text(canManage ? '管理' : '详情')"));
    expect(groupInfo, contains("'退出\${_team != null ? '部落' : '群聊'}'"));
    expect(groupInfo, contains("'申请与邀请'"));
  });

  test('群聊申请支持理由、我的申请与处理记录', () {
    final applies =
        File('lib/features/message/chat_apply_page.dart').readAsStringSync();
    final discover = File('lib/features/message/joinable_groups_page.dart')
        .readAsStringSync();

    expect(applies, contains("Tab(text: '待我处理')"));
    expect(applies, contains("Tab(text: '我的申请')"));
    expect(applies, contains("Tab(text: '处理记录')"));
    expect(applies, contains('申请理由：\$note'));
    expect(applies, contains('/api/im/application-records/hide'));
    expect(applies, contains("PopupMenuItem(value: 'clear'"));
    expect(applies, contains('Dismissible('));
    expect(applies, contains('只会从你的列表中移除'));
    expect(discover, contains('搜索部落或群聊名称'));
    expect(discover, contains("data: {'note': note}"));
  });

  test('群聊与部落中心统一我的、创建、管理和申请入口', () {
    final messages =
        File('lib/features/message/message_page.dart').readAsStringSync();
    final center = File('lib/features/message/joinable_groups_page.dart')
        .readAsStringSync();

    expect(messages, contains("label: '群聊与部落'"));
    expect(messages, isNot(contains("label: '发现群聊与部落'")));
    expect(center, contains("title: const Text('群聊与部落')"));
    expect(center, contains("'我的群聊与部落'"));
    expect(center, contains("label: '创建群聊'"));
    expect(center, contains("label: '创建部落'"));
    expect(center, contains("label: '申请与邀请'"));
    expect(center, contains("label: '管理群聊与部落'"));
    expect(center, contains('/api/im/groups/mine'));
  });

  test('首次启动协议始终在应用内打开并保留确认弹窗', () {
    final agreement =
        File('lib/features/auth/agreement_dialog.dart').readAsStringSync();

    expect(agreement, contains('LegalDocumentPage'));
    expect(agreement, contains('Navigator.of(context).push'));
    expect(agreement, isNot(contains('launchUrl(')));
    expect(agreement, isNot(contains('LaunchMode.externalApplication')));
  });
}
