import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('收藏和赞过在个人主页内切换并共用瞬间网格', () {
    final source =
        File('lib/features/profile/profile_page.dart').readAsStringSync();

    expect(source, contains('_switchProfileContent(1)'));
    expect(source, contains('_switchProfileContent(2)'));
    expect(source, contains("'/api/community/favorites'"));
    expect(source, contains("'/api/community/likes'"));
    expect(source, contains('_buildPostThumbnail(visiblePosts[index])'));
    expect(source, isNot(contains('const LikedPostsPage()')));
  });
}
