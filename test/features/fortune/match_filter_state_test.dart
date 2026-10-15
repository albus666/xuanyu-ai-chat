import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/app/pages/home/destiny_match/controller.dart';

void main() {
  test('缘分匹配支持多选十天干十二地支与最多两个五行', () {
    expect(DestinyMatchController.stemOptions, hasLength(10));
    expect(DestinyMatchController.branchOptions, hasLength(12));

    final controller = DestinyMatchController();
    controller.toggleFilterStem('乙');
    controller.toggleFilterStem('庚');
    controller.toggleFilterBranch('卯');
    controller.toggleFilterBranch('子');
    controller.toggleFilterElement('木');
    controller.toggleFilterElement('火');

    expect(controller.filterStems, ['乙', '庚']);
    expect(controller.filterBranches, ['卯', '子']);
    expect(controller.filterElements, ['木', '火']);

    controller.toggleFilterStem('乙');
    controller.toggleFilterBranch('卯');
    expect(controller.filterStems, ['庚']);
    expect(controller.filterBranches, ['子']);
    controller.onClose();
  });

  test('缘分匹配提供四种免费交友意向并解析多维结果', () {
    expect(MatchIntent.values.map((item) => item.label),
        ['交朋友', '认真恋爱', '长期关系', '文化同好']);

    final user = FateUser.fromJson({
      'userId': 8,
      'nickname': '同频用户',
      'matchScore': 82,
      'dimensions': {'命理同频': 80, '关系互补': 76, '相处节奏': 84},
      'highlights': ['表达节奏自然'],
      'watchouts': ['先了解彼此边界'],
      'topics': ['最近喜欢的事'],
    });

    expect(user.userId, 8);
    expect(user.dimensions['相处节奏'], 84);
    expect(user.highlights, isNotEmpty);
    expect(user.age, '年龄未公开');
  });
}
