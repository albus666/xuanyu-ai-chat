import 'package:lunar/lunar.dart';

/// 日常个人择日支持的事项。
///
/// 每一种事项分别读取黄历宜忌，避免用同一个“吉日分数”覆盖所有用途。
enum PersonalDatePurpose {
  communication('重要沟通', ['会亲友', '纳采', '订盟'], ['词讼']),
  meeting('见面约会', ['会亲友', '纳采', '订盟', '嫁娶'], ['词讼']),
  interview('面试求职', ['赴任', '求名', '入学', '上官'], ['闭塞']),
  contract('签约合作', ['交易', '立券', '订盟', '纳财'], ['破券', '词讼']),
  travel('出行', ['出行', '移徙'], ['出行']),
  moving('搬家入宅', ['入宅', '移徙', '安床', '修造'], ['入宅', '移徙']),
  opening('开业经营', ['开市', '交易', '立券', '纳财'], ['开市', '交易']),
  wedding('登记婚礼', ['嫁娶', '纳采', '订盟'], ['嫁娶']);

  const PersonalDatePurpose(this.label, this.goodKeywords, this.badKeywords);

  final String label;
  final List<String> goodKeywords;
  final List<String> badKeywords;
}

class PersonalAlmanacProfile {
  const PersonalAlmanacProfile({
    required this.name,
    required this.gans,
    required this.zhis,
    this.supportiveElements = const <String>{},
  });

  final String name;
  final List<String> gans;
  final List<String> zhis;

  /// 只接受现有六十甲子用神条文能够稳定解析出的五行；解析不到时为空，
  /// 不使用默认值，也不猜测。
  final Set<String> supportiveElements;

  String get summary {
    final count = gans.length < zhis.length ? gans.length : zhis.length;
    return List.generate(count, (i) => '${gans[i]}${zhis[i]}').join(' ');
  }
}

enum PersonalDateLevel { suitable, steady, cautious }

class PersonalDateEvaluation {
  const PersonalDateEvaluation({
    required this.date,
    required this.purpose,
    required this.score,
    required this.level,
    required this.dayGanZhi,
    required this.suitableActions,
    required this.cautionActions,
    required this.reasons,
    required this.recommendedTimes,
  });

  final DateTime date;
  final PersonalDatePurpose purpose;

  /// 仅用于同一用户、同一事项下的候选日期排序，不向用户展示为命运分数。
  final int score;
  final PersonalDateLevel level;
  final String dayGanZhi;
  final List<String> suitableActions;
  final List<String> cautionActions;
  final List<String> reasons;
  final List<String> recommendedTimes;

  String get levelLabel => switch (level) {
        PersonalDateLevel.suitable => '适合你',
        PersonalDateLevel.steady => '较平稳',
        PersonalDateLevel.cautious => '宜谨慎',
      };
}

/// 确定性的个人择日排序层。
///
/// 公共历法和宜忌来自 lunar；个人部分只读取既有四柱与经过解析的喜用结果。
/// 本类不参与、不修改八字排盘。
class PersonalDateSelectionEngine {
  const PersonalDateSelectionEngine();

  static const _ganElement = {
    '甲': '木',
    '乙': '木',
    '丙': '火',
    '丁': '火',
    '戊': '土',
    '己': '土',
    '庚': '金',
    '辛': '金',
    '壬': '水',
    '癸': '水',
  };

  static const _zhiElement = {
    '寅': '木',
    '卯': '木',
    '巳': '火',
    '午': '火',
    '辰': '土',
    '戌': '土',
    '丑': '土',
    '未': '土',
    '申': '金',
    '酉': '金',
    '亥': '水',
    '子': '水',
  };

  static const _sixHarmony = {
    '子': '丑',
    '丑': '子',
    '寅': '亥',
    '亥': '寅',
    '卯': '戌',
    '戌': '卯',
    '辰': '酉',
    '酉': '辰',
    '巳': '申',
    '申': '巳',
    '午': '未',
    '未': '午',
  };

  static const _sixClash = {
    '子': '午',
    '午': '子',
    '丑': '未',
    '未': '丑',
    '寅': '申',
    '申': '寅',
    '卯': '酉',
    '酉': '卯',
    '辰': '戌',
    '戌': '辰',
    '巳': '亥',
    '亥': '巳',
  };

  static const _sixHarm = {
    '子': '未',
    '未': '子',
    '丑': '午',
    '午': '丑',
    '寅': '巳',
    '巳': '寅',
    '卯': '辰',
    '辰': '卯',
    '申': '亥',
    '亥': '申',
    '酉': '戌',
    '戌': '酉',
  };

  static const _sixBreak = {
    '子': '酉',
    '酉': '子',
    '丑': '辰',
    '辰': '丑',
    '寅': '亥',
    '亥': '寅',
    '卯': '午',
    '午': '卯',
    '巳': '申',
    '申': '巳',
    '未': '戌',
    '戌': '未',
  };

  static const _selfPunishment = {'辰', '午', '酉', '亥'};

  static const _goodOfficersByPurpose = {
    PersonalDatePurpose.communication: {'开', '成', '定'},
    PersonalDatePurpose.meeting: {'成', '定', '开'},
    PersonalDatePurpose.interview: {'开', '成', '定'},
    PersonalDatePurpose.contract: {'成', '定', '开'},
    PersonalDatePurpose.travel: {'成', '开', '除'},
    PersonalDatePurpose.moving: {'成', '定', '开'},
    PersonalDatePurpose.opening: {'开', '成', '满'},
    PersonalDatePurpose.wedding: {'成', '定', '开'},
  };

  static const _badOfficersByPurpose = {
    PersonalDatePurpose.communication: {'闭', '破'},
    PersonalDatePurpose.meeting: {'破', '闭'},
    PersonalDatePurpose.interview: {'闭', '破'},
    PersonalDatePurpose.contract: {'破', '闭'},
    PersonalDatePurpose.travel: {'闭', '破'},
    PersonalDatePurpose.moving: {'破', '闭'},
    PersonalDatePurpose.opening: {'闭', '破'},
    PersonalDatePurpose.wedding: {'破', '闭'},
  };

  static const _timeRanges = {
    '子': '23:00–00:59',
    '丑': '01:00–02:59',
    '寅': '03:00–04:59',
    '卯': '05:00–06:59',
    '辰': '07:00–08:59',
    '巳': '09:00–10:59',
    '午': '11:00–12:59',
    '未': '13:00–14:59',
    '申': '15:00–16:59',
    '酉': '17:00–18:59',
    '戌': '19:00–20:59',
    '亥': '21:00–22:59',
  };

  PersonalDateEvaluation evaluate({
    required DateTime date,
    required PersonalDatePurpose purpose,
    required PersonalAlmanacProfile profile,
    bool includeTimes = true,
  }) {
    final normalized = DateTime(date.year, date.month, date.day, 12);
    final lunar = Lunar.fromDate(normalized);
    final yi = lunar.getDayYi();
    final ji = lunar.getDayJi();
    final dayGanZhi = lunar.getDayInGanZhi();
    final dayGan = dayGanZhi.isEmpty ? '' : dayGanZhi[0];
    final dayZhi = dayGanZhi.length < 2 ? '' : dayGanZhi.substring(1, 2);
    final matchedYi = _matches(yi, purpose.goodKeywords);
    final matchedJi = _matches(ji, purpose.badKeywords);
    final reasons = <String>[];
    var score = 50;

    final tianShenLuck = lunar.getDayTianShenLuck();
    if (tianShenLuck.contains('吉')) {
      score += 6;
    } else if (tianShenLuck.contains('凶')) {
      score -= 6;
    }

    if (matchedYi.isNotEmpty) {
      score += 18;
      reasons.add(
          '公共黄历将${matchedYi.take(2).join('、')}列为今日宜项，与“${purpose.label}”相合');
    }
    if (matchedJi.isNotEmpty) {
      score -= 24;
      reasons.add('公共黄历将${matchedJi.take(2).join('、')}列为今日忌项，这件事更适合留出余地');
    }
    if (ji.any((item) => item.contains('诸事不宜'))) {
      score -= 18;
      reasons.add('今日公共黄历有“诸事不宜”提示，重要安排不宜只凭日期推进');
    }

    final officer = lunar.getZhiXing();
    if ((_goodOfficersByPurpose[purpose] ?? const {}).contains(officer)) {
      score += 8;
      reasons.add('今日为$officer日，传统择日中与“${purpose.label}”的事项性质较协调');
    }
    if ((_badOfficersByPurpose[purpose] ?? const {}).contains(officer)) {
      score -= 10;
      reasons.add('今日为$officer日，传统择日中不宜把这项安排得过于仓促');
    }

    final dayElement = _ganElement[dayGan];
    final branchElement = _zhiElement[dayZhi];
    if (dayElement != null && profile.supportiveElements.contains(dayElement)) {
      score += 9;
      reasons.add('今日天干属$dayElement，与命盘助力方向一致');
    }
    if (branchElement != null &&
        branchElement != dayElement &&
        profile.supportiveElements.contains(branchElement)) {
      score += 4;
      reasons.add('今日日支属$branchElement，可作为个人助力的辅助参考');
    }

    final relation = _personalRelation(dayZhi, profile, purpose);
    score += relation.score;
    if (relation.reason.isNotEmpty) reasons.add(relation.reason);

    final boundedScore = score.clamp(10, 95);
    final level = boundedScore >= 68
        ? PersonalDateLevel.suitable
        : boundedScore >= 48
            ? PersonalDateLevel.steady
            : PersonalDateLevel.cautious;
    final suitable = matchedYi.isNotEmpty
        ? matchedYi.take(4).toList()
        : yi.where((item) => item != '无').take(4).toList();
    final caution = matchedJi.isNotEmpty
        ? matchedJi.take(4).toList()
        : ji.where((item) => item != '无').take(3).toList();

    return PersonalDateEvaluation(
      date: normalized,
      purpose: purpose,
      score: boundedScore,
      level: level,
      dayGanZhi: dayGanZhi,
      suitableActions: suitable,
      cautionActions: caution,
      reasons: reasons.take(3).toList(),
      recommendedTimes:
          includeTimes ? _recommendedTimes(lunar, profile, purpose) : const [],
    );
  }

  /// 双方事项分别计算后取交集，不把其中一人的结果覆盖成另一人的结果。
  PersonalDateEvaluation evaluateForPair({
    required DateTime date,
    required PersonalDatePurpose purpose,
    required PersonalAlmanacProfile first,
    required PersonalAlmanacProfile second,
    bool includeTimes = true,
  }) {
    final a = evaluate(
      date: date,
      purpose: purpose,
      profile: first,
      includeTimes: includeTimes,
    );
    final b = evaluate(
      date: date,
      purpose: purpose,
      profile: second,
      includeTimes: includeTimes,
    );
    // 双方事项采用较谨慎一方的结果，避免平均分掩盖其中一人的明显冲突。
    final score = a.score < b.score ? a.score : b.score;
    final level = score >= 68
        ? PersonalDateLevel.suitable
        : score >= 48
            ? PersonalDateLevel.steady
            : PersonalDateLevel.cautious;
    final sharedTimes = a.recommendedTimes
        .where((time) => b.recommendedTimes.contains(time))
        .take(3)
        .toList();
    final reasons = <String>[
      if (a.reasons.isNotEmpty) '${first.name}：${a.reasons.first}',
      if (b.reasons.isNotEmpty) '${second.name}：${b.reasons.first}',
      if (a.level == PersonalDateLevel.cautious ||
          b.level == PersonalDateLevel.cautious)
        '双方事项以条件较谨慎的一方为重要参考，不因平均结果忽略个人冲突',
    ];
    return PersonalDateEvaluation(
      date: a.date,
      purpose: purpose,
      score: score,
      level: level,
      dayGanZhi: a.dayGanZhi,
      suitableActions: a.suitableActions,
      cautionActions:
          <String>{...a.cautionActions, ...b.cautionActions}.toList(),
      reasons: reasons.take(3).toList(),
      recommendedTimes: sharedTimes,
    );
  }

  List<PersonalDateEvaluation> recommend({
    required DateTime from,
    required int days,
    required PersonalDatePurpose purpose,
    required PersonalAlmanacProfile profile,
  }) {
    final results = List.generate(
      days,
      (index) => evaluate(
        date: DateTime(from.year, from.month, from.day)
            .add(Duration(days: index)),
        purpose: purpose,
        profile: profile,
      ),
    );
    results.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      return byScore != 0 ? byScore : a.date.compareTo(b.date);
    });
    return results;
  }

  List<PersonalDateEvaluation> recommendForPair({
    required DateTime from,
    required int days,
    required PersonalDatePurpose purpose,
    required PersonalAlmanacProfile first,
    required PersonalAlmanacProfile second,
  }) {
    final results = List.generate(
      days,
      (index) => evaluateForPair(
        date: DateTime(from.year, from.month, from.day)
            .add(Duration(days: index)),
        purpose: purpose,
        first: first,
        second: second,
      ),
    );
    results.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      return byScore != 0 ? byScore : a.date.compareTo(b.date);
    });
    return results;
  }

  _PersonalRelation _personalRelation(
    String dayZhi,
    PersonalAlmanacProfile profile,
    PersonalDatePurpose purpose,
  ) {
    if (dayZhi.isEmpty || profile.zhis.isEmpty) {
      return const _PersonalRelation(0, '');
    }
    final natalDay = profile.zhis.length > 2 ? profile.zhis[2] : '';
    final natalYear = profile.zhis.first;
    if (_sixClash[dayZhi] == natalDay) {
      final penalty = purpose == PersonalDatePurpose.meeting ||
              purpose == PersonalDatePurpose.wedding
          ? -16
          : -12;
      return _PersonalRelation(
        penalty,
        '今日日支与原局日支相冲，涉及关系或重要决定时宜多沟通、留备选',
      );
    }
    if (_sixHarmony[dayZhi] == natalDay) {
      final bonus = purpose == PersonalDatePurpose.meeting ||
              purpose == PersonalDatePurpose.wedding
          ? 12
          : 8;
      return _PersonalRelation(
        bonus,
        '今日日支与原局日支六合，互动与协商类事项可优先考虑',
      );
    }
    if (_sixClash[dayZhi] == natalYear) {
      return const _PersonalRelation(
        -6,
        '今日日支与原局年支相冲，外出与对外安排宜预留调整空间',
      );
    }
    if (_sixHarm[dayZhi] == natalDay) {
      return const _PersonalRelation(
        -6,
        '今日日支与原局日支有害，表达细节与临时变化需要多确认',
      );
    }
    if (_isPunishment(dayZhi, natalDay)) {
      return const _PersonalRelation(
        -6,
        '今日日支与原局日支有刑，重要安排宜减少急躁，并提前核对流程',
      );
    }
    if (_sixBreak[dayZhi] == natalDay ||
        (_selfPunishment.contains(dayZhi) && dayZhi == natalDay)) {
      return const _PersonalRelation(
        -4,
        '今日与原局日支存在破或自刑关系，执行时宜减少反复和急躁',
      );
    }
    return const _PersonalRelation(0, '今日与原局日支没有明显冲合，按事项本身稳妥推进即可');
  }

  List<String> _recommendedTimes(
    Lunar lunar,
    PersonalAlmanacProfile profile,
    PersonalDatePurpose purpose,
  ) {
    final natalDay = profile.zhis.length > 2 ? profile.zhis[2] : '';
    final candidates = <({String label, int rank})>[];
    for (final time in lunar.getTimes().take(12)) {
      final zhi = time.getZhi();
      if (_sixClash[zhi] == natalDay) continue;
      var rank = time.getTianShenLuck().contains('吉') ? 10 : 0;
      if (_sixHarmony[zhi] == natalDay) rank += 4;
      if (_matches(time.getYi(), purpose.goodKeywords).isNotEmpty) rank += 4;
      if (_matches(time.getJi(), purpose.badKeywords).isNotEmpty) rank -= 8;
      final element = _zhiElement[zhi];
      if (element != null && profile.supportiveElements.contains(element)) {
        rank += 3;
      }
      final range = _timeRanges[zhi] ?? '';
      candidates.add((label: '$zhi时 $range', rank: rank));
    }
    candidates.sort((a, b) => b.rank.compareTo(a.rank));
    return candidates.take(3).map((item) => item.label).toList();
  }

  bool _isPunishment(String first, String second) {
    if (first.isEmpty || second.isEmpty) return false;
    if (first == second && _selfPunishment.contains(first)) return true;
    if ((first == '子' && second == '卯') || (first == '卯' && second == '子')) {
      return true;
    }
    const groups = [
      {'寅', '巳', '申'},
      {'丑', '未', '戌'},
    ];
    return groups.any(
      (group) =>
          first != second && group.contains(first) && group.contains(second),
    );
  }

  List<String> _matches(List<String> source, List<String> keywords) {
    final result = <String>[];
    for (final item in source) {
      if (keywords.any((keyword) => item.contains(keyword))) result.add(item);
    }
    return result.toSet().toList();
  }
}

class _PersonalRelation {
  const _PersonalRelation(this.score, this.reason);

  final int score;
  final String reason;
}
