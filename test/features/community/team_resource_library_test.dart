import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('team resource library keeps complete management actions wired', () {
    final source =
        File('lib/features/community/team_home_page.dart').readAsStringSync();

    expect(source, contains("_scope.patch("));
    expect(source, contains("_scope.delete("));
    expect(source, contains('选择并上传附件（选填）'));
    expect(source, contains('查看全部（\${_resources.length}）'));
    expect(source, contains("'admins' => '仅管理者可见'"));
    expect(source, contains('资料库加载失败'));
  });
}
