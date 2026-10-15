import 'bazi_result.dart';
import 'decline_yongshen_parse.dart';

/// 个人信息页使用的传统子平解读。
///
/// 这里仅组合专业细盘已经算出的四柱、藏干、司令，以及既有旺衰和
/// 用神条文；不重新排盘，也不反向修改任何命盘数据。
class ZipingSelfInsight {
  const ZipingSelfInsight({
    required this.title,
    required this.summary,
    required this.sections,
  });

  final String title;
  final String summary;
  final List<ZipingInsightSection> sections;

  String get detail => sections
      .map((section) => '${section.title}\n${section.content}')
      .join('\n\n');
}

class ZipingInsightSection {
  const ZipingInsightSection({
    required this.title,
    required this.content,
  });

  final String title;
  final String content;
}

List<ZipingSelfInsight> buildZipingSelfInsights({
  required BaziResult result,
  required String wangShuai,
  required String yongShen,
}) {
  final dayElement = _elementOfGan(result.dayGan);
  final monthCommandStem = result.siLing.trim().isNotEmpty
      ? result.siLing.trim()[0]
      : result.zhiCangGan[1].isEmpty
          ? ''
          : result.zhiCangGan[1][0];
  final monthCommandGod = monthCommandStem.isEmpty
      ? ''
      : shiShenJianForDayGanVsStem(result.dayGan, monthCommandStem);
  final monthCommandName = _tenGodFull(monthCommandGod);
  final monthCommandRevealed = monthCommandStem.isNotEmpty &&
      <String>[
        result.yearGan,
        result.monthGan,
        result.timeGan,
      ].contains(monthCommandStem);
  final strength = _strengthLabel(wangShuai);
  final rootPillars = _rootPillars(result, dayElement);
  final rootText =
      rootPillars.isEmpty ? '四支同类根气不显' : '在${rootPillars.join('、')}见根';
  final revealedPeers = <String>[];
  for (final entry in <(String, String)>[
    ('年干', result.yearGan),
    ('月干', result.monthGan),
    ('时干', result.timeGan),
  ]) {
    if (_elementOfGan(entry.$2) == dayElement) revealedPeers.add(entry.$1);
  }
  final revealedPeerText =
      revealedPeers.isEmpty ? '天干不见同类透出' : '${revealedPeers.join('、')}见同类透出';
  final groupCounts = _tenGodGroupCounts(result, monthCommandGod);
  final orderedGroups = groupCounts.entries.toList()
    ..sort((a, b) {
      final count = b.value.compareTo(a.value);
      return count != 0
          ? count
          : _groupOrder(a.key).compareTo(_groupOrder(b.key));
    });
  final dominantGroups = orderedGroups
      .where((entry) => entry.value > 0)
      .take(2)
      .map((entry) => entry.key)
      .toList();
  final dominantText =
      dominantGroups.isEmpty ? '十神气势较为分散' : '${dominantGroups.join('、')}较为显眼';
  final primaryGroup = dominantGroups.isEmpty ? '比劫' : dominantGroups.first;
  final secondaryGroup =
      dominantGroups.length < 2 ? primaryGroup : dominantGroups[1];
  final dayBranchMainStem =
      result.zhiCangGan[2].isEmpty ? '' : result.zhiCangGan[2][0];
  final dayBranchGod = dayBranchMainStem.isEmpty
      ? ''
      : shiShenJianForDayGanVsStem(result.dayGan, dayBranchMainStem);
  final dayBranchHidden = result.zhiCangGan[2]
      .split('')
      .where((stem) => stem.isNotEmpty)
      .map((stem) =>
          _tenGodFull(shiShenJianForDayGanVsStem(result.dayGan, stem)))
      .toSet()
      .join('、');
  final wealth = _godPresence(result, const {'才', '财'});
  final relationshipSignal = _dayBranchRelationship(result);
  final parsed = yongShen.isEmpty ? null : parseYongshenYsToXiYong(yongShen);
  final yong = parsed?['用神'];
  final xi = parsed?['喜神'];
  final supportText = yong == null || xi == null
      ? '喜用方向需结合全盘判断'
      : yong == xi
          ? '喜用同取$yong'
          : '用神取$yong，喜神取$xi';
  final yongShenText = yongShen.trim();
  final supportDetail =
      yongShenText.isEmpty ? '喜用方向需结合完整命局再定' : '喜用重点：$yongShenText';
  final seed =
      result.fourPillarsStr.codeUnits.fold<int>(0, (sum, code) => sum + code);
  final mainHeadline = _mainHeadline(
    strength: strength,
    primaryGroup: primaryGroup,
    yong: yong,
    seed: seed,
  );
  final temperamentHeadline = _temperamentHeadline(
    dayGan: result.dayGan,
    groups: dominantGroups,
    strength: strength,
    seed: seed,
  );
  final relationshipHeadline = _relationshipHeadline(
    dayBranchGod: dayBranchGod,
    relationshipSignal: relationshipSignal,
    seed: seed,
  );
  final careerHeadline = _careerHeadline(
    monthCommandGod: monthCommandGod,
    strength: strength,
    primaryGroup: primaryGroup,
    seed: seed,
  );
  final wealthHeadline = _wealthHeadline(
    wealth: wealth,
    strength: strength,
    seed: seed,
  );
  final choiceHeadline = _choiceHeadline(yong: yong, xi: xi, seed: seed);

  return [
    ZipingSelfInsight(
      title: '命局主线',
      summary: mainHeadline,
      sections: [
        ZipingInsightSection(
          title: '核心判断',
          content: '$mainHeadline。${_mainJudgment(strength, primaryGroup)}',
        ),
        ZipingInsightSection(
          title: '现实中的你',
          content:
              '${_groupEveryday(primaryGroup)}${_strengthEveryday(strength)}',
        ),
        ZipingInsightSection(
          title: '你的长处',
          content:
              '${_dayMasterNature(result.dayGan)}。${_groupAdvantage(primaryGroup)}',
        ),
        ZipingInsightSection(
          title: '容易卡住',
          content:
              '${_groupBlindSpot(primaryGroup)}${_groupTension(primaryGroup, secondaryGroup)}',
        ),
        ZipingInsightSection(
          title: '状态变化',
          content: _stateShift(strength: strength, yong: yong),
        ),
        ZipingInsightSection(
          title: '更适合你的做法',
          content: _mainAdvice(strength: strength, primaryGroup: primaryGroup),
        ),
        ZipingInsightSection(
          title: '命局依据',
          content:
              '${result.fourPillarsStr}。${result.dayGan}$dayElement日主生于${result.monthZhi}月，'
              '${monthCommandStem.isEmpty ? '以月令为提纲' : '月令主气$monthCommandStem，对日主为$monthCommandName${monthCommandRevealed ? '，并透于天干' : '，未透于天干'}'}；'
              '${strength.isEmpty ? '整体旺衰仍需合看全盘' : '整体呈$strength'}，$rootText，$revealedPeerText。',
        ),
      ],
    ),
    ZipingSelfInsight(
      title: '性情底色',
      summary: temperamentHeadline,
      sections: [
        ZipingInsightSection(
          title: '给人的第一感觉',
          content: '$temperamentHeadline。${_temperamentOuter(primaryGroup)}',
        ),
        ZipingInsightSection(
          title: '真正驱动你的东西',
          content:
              '${_groupTemperament(dominantGroups)}。${_temperamentDrive(primaryGroup)}',
        ),
        ZipingInsightSection(
          title: '你很能打的地方',
          content: _groupAdvantage(primaryGroup),
        ),
        ZipingInsightSection(
          title: '别人不一定看见的消耗',
          content:
              '${_groupBlindSpot(primaryGroup)}${_strengthPressure(strength)}',
        ),
        ZipingInsightSection(
          title: '舒服与失衡时',
          content: _temperamentState(primaryGroup, strength),
        ),
        ZipingInsightSection(
          title: '对你有用的提醒',
          content: _temperamentAdvice(primaryGroup, strength),
        ),
        ZipingInsightSection(
          title: '命局依据',
          content:
              '${result.dayGan}日主取象为${_dayMasterImage(result.dayGan)}；原局$dominantText，主次落在$primaryGroup与$secondaryGroup，日主${strength.isEmpty ? '旺衰待综合判断' : strength}。',
        ),
      ],
    ),
    ZipingSelfInsight(
      title: '关系模式',
      summary: relationshipHeadline,
      sections: [
        ZipingInsightSection(
          title: '你真正要的关系',
          content:
              '$relationshipHeadline。你在稳定关系里尤其看重${_relationshipKeyword(dayBranchGod)}。',
        ),
        ZipingInsightSection(
          title: '你会怎样表达在意',
          content: _relationshipCare(dayBranchGod),
        ),
        ZipingInsightSection(
          title: '你容易被什么打动',
          content: _relationshipAttraction(dayBranchGod),
        ),
        ZipingInsightSection(
          title: '关系里的盲点',
          content:
              '${_relationshipRisk(dayBranchGod)}${relationshipSignal.advice}',
        ),
        ZipingInsightSection(
          title: '关系变好的关键',
          content: _relationshipAdvice(dayBranchGod, relationshipSignal.kind),
        ),
        ZipingInsightSection(
          title: '命局依据',
          content:
              '日支${result.dayZhi}为夫妻宫，主气$dayBranchMainStem对日主为${_tenGodFull(dayBranchGod)}${dayBranchHidden.isEmpty ? '' : '，宫内兼见$dayBranchHidden'}。${relationshipSignal.evidence}',
        ),
      ],
    ),
    ZipingSelfInsight(
      title: '事业路径',
      summary: careerHeadline,
      sections: [
        ZipingInsightSection(
          title: '更顺手的赛道',
          content:
              '$careerHeadline。比起追某个固定职业名，你更适合${_careerReading(monthCommandGod)}。',
        ),
        ZipingInsightSection(
          title: '你的工作方式',
          content: _careerWorkStyle(monthCommandGod, primaryGroup),
        ),
        ZipingInsightSection(
          title: '你的职场优势',
          content: _careerAdvantage(monthCommandGod),
        ),
        ZipingInsightSection(
          title: '不适合长期待的环境',
          content: _careerMismatch(monthCommandGod, strength),
        ),
        ZipingInsightSection(
          title: '成长顺序',
          content:
              '${_strengthCareerReminder(strength)}。${_careerNextStep(monthCommandGod)}',
        ),
        ZipingInsightSection(
          title: '命局依据',
          content:
              '${result.monthZhi}月以主气$monthCommandStem为提纲，对日主为$monthCommandName${monthCommandRevealed ? '，并透于天干' : '，未透于天干'}；原局$dominantText，整体${strength.isEmpty ? '旺衰需合看全盘' : strength}。',
        ),
      ],
    ),
    ZipingSelfInsight(
      title: '财富方式',
      summary: wealthHeadline,
      sections: [
        ZipingInsightSection(
          title: '你的财富逻辑',
          content: '$wealthHeadline。${_wealthMode(wealth)}',
        ),
        ZipingInsightSection(
          title: '钱更容易从哪里来',
          content: _wealthSource(primaryGroup, monthCommandGod, wealth),
        ),
        ZipingInsightSection(
          title: '你对钱的真实态度',
          content: _wealthAttitude(wealth, strength),
        ),
        ZipingInsightSection(
          title: '容易漏财或错失的地方',
          content: _wealthRisk(wealth, strength),
        ),
        ZipingInsightSection(
          title: '更稳的积累方式',
          content:
              '${_wealthStrengthReading(strength)}。${_wealthAdvice(wealth)}',
        ),
        ZipingInsightSection(
          title: '命局依据',
          content: wealth.visible > 0
              ? '原局天干财星透见${wealth.visible}处，地支另藏${wealth.hidden}处；日主${strength.isEmpty ? '旺衰需综合判断' : strength}。'
              : wealth.hidden > 0
                  ? '原局财星藏于地支${wealth.hidden}处而未透干；日主${strength.isEmpty ? '旺衰需综合判断' : strength}。'
                  : '原局明暗处财星均不突出；这表示财富不是命局最先被看见的主题，并不等于没有财富机会。',
        ),
      ],
    ),
    ZipingSelfInsight(
      title: '喜忌取舍',
      summary: choiceHeadline,
      sections: [
        ZipingInsightSection(
          title: '对你最重要的取舍',
          content: '$choiceHeadline。${_supportMeaning(yong)}',
        ),
        ZipingInsightSection(
          title: '什么状态更养你',
          content: _supportState(yong),
        ),
        ZipingInsightSection(
          title: '什么状态更耗你',
          content: _drainState(yong, strength),
        ),
        ZipingInsightSection(
          title: '落到日常怎么选',
          content: _supportDaily(yong),
        ),
        ZipingInsightSection(
          title: '遇到重要决定时',
          content: _decisionAdvice(yong, strength),
        ),
        ZipingInsightSection(
          title: '命局依据',
          content:
              '${strength.isEmpty ? '整体力量仍需结合全盘观察' : '日主整体呈$strength'}，$supportText。$supportDetail。喜用用于判断取舍方向，不等同于只选某种颜色、行业或物品。',
        ),
      ],
    ),
  ];
}

bool _isWeak(String strength) => const {'身弱', '身衰', '偏弱'}.contains(strength);

bool _isStrong(String strength) => const {'身强', '身旺', '偏强'}.contains(strength);

String _pick(List<String> values, int seed) =>
    values[seed.abs() % values.length];

String _mainHeadline({
  required String strength,
  required String primaryGroup,
  required String? yong,
  required int seed,
}) {
  if (_isWeak(strength) && yong == '火') {
    return '先把自己点亮，才接得住外面的机会';
  }
  if (_isWeak(strength)) {
    return switch (primaryGroup) {
      '财星' || '官杀' => _pick([
          '机会和责任来得不慢，你真正要练的是接得稳',
          '你不是缺机会，而是不能让每个机会都来消耗你',
        ], seed),
      '食伤' => '想法并不少，先稳住底盘，表达才更有分量',
      '印星' => '你靠理解建立底气，再把底气变成行动',
      _ => '先把自己的节奏站稳，再去承接更大的局面',
    };
  }
  if (_isStrong(strength)) {
    return switch (primaryGroup) {
      '比劫' => '你不缺往前走的力气，真正重要的是把力气用对地方',
      '食伤' => '你的人生不是等答案，而是把想法做成答案',
      '财星' => '你有把事情推向结果的能力，也要学会给自己留余地',
      '官杀' => '越是有难度的局面，越容易逼出你的本事',
      _ => '底气已经在身上，下一步是让能力接受现实检验',
    };
  }
  return switch (primaryGroup) {
    '食伤' => '你最好的状态，是既能表达自己，也能把事情做成',
    '财星' => '你会在现实里找答案，也要给内心留一个位置',
    '官杀' => '责任能成就你，但不必把所有责任都背在身上',
    '印星' => '想明白是你的起点，真正落地才是你的转折',
    _ => '你的人生主线，是在坚持自己和回应现实之间找到尺度',
  };
}

String _mainJudgment(String strength, String primaryGroup) {
  final group = switch (primaryGroup) {
    '比劫' => '自主、边界与同伴关系会反复成为重要课题',
    '食伤' => '表达、创造和把复杂事说清楚，是你打开局面的方式',
    '财星' => '资源、结果与现实兑现，是你很难绕开的主线',
    '官杀' => '责任、标准与压力，会不断推动你完成升级',
    '印星' => '学习、理解与建立自己的方法，是你获得安全感的入口',
    _ => '你需要在自身节奏与外界要求之间建立稳定秩序',
  };
  if (_isWeak(strength)) return '$group；先增强承载，再扩大目标，会比一开始铺得很大更顺。';
  if (_isStrong(strength)) return '$group；你有主动开局的力量，关键是让力量流向具体结果。';
  return '$group；既不必过度收缩，也不宜只凭一时冲劲。';
}

String _groupEveryday(String group) => switch (group) {
      '比劫' => '遇到事情时，你通常先形成自己的判断，再决定要不要听别人；不喜欢被安排，却愿意为认可的人并肩出力。',
      '食伤' => '你会本能地观察哪里不合理、怎样能更好，也很难长期压住真实意见；只要有表达和创造空间，状态就会明显打开。',
      '财星' => '你习惯先看事情能否落地、投入是否值得、结果能否兑现；嘴上未必谈利益，心里却会自然计算成本和后果。',
      '官杀' => '你对要求、评价和责任很敏感，往往别人还没催，你已经开始给自己加标准；面对难题时反而容易进入战斗状态。',
      '印星' => '你做决定前需要先理解来龙去脉，习惯把经验整理成自己的方法；环境越混乱，你越想先找到一套可靠逻辑。',
      _ => '你会先观察局势，再决定以哪一种方式回应。',
    };

String _strengthEveryday(String strength) {
  if (_isWeak(strength)) return '但当任务、关系和期待同时涌来时，你容易先答应、后透支，恢复时间也会比旁人想象得更久。';
  if (_isStrong(strength)) return '当方向明确时，你推进很快；方向不清时，也可能把坚持变成无效用力。';
  return '你通常能在主动与配合之间切换，但长期缺少明确反馈时仍会内耗。';
}

String _groupAdvantage(String group) => switch (group) {
      '比劫' => '你的优势是有主见、能扛事，也能在局面不明时先迈出第一步。真正认定一件事后，持续性比别人看到的更强。',
      '食伤' => '你的优势是看得出差异、讲得出重点，并能把经验变成内容、方案或作品。越允许你改进旧方法，越容易出成绩。',
      '财星' => '你的优势是现实感强，能同时关注资源、关系和结果。别人只看到机会时，你通常已经在估算怎样把机会接住。',
      '官杀' => '你的优势是面对标准和压力时能迅速进入角色，关键时刻有担当，也愿意为了长期信用约束自己。',
      '印星' => '你的优势是学习快、理解深，能在混乱信息里提炼规律。积累到一定程度后，你往往能形成一套别人拿不走的方法。',
      _ => '你的优势在于能根据环境调整策略，并把经验慢慢沉淀成判断力。',
    };

String _groupBlindSpot(String group) => switch (group) {
      '比劫' => '你容易把“我能处理”用得太久，等到真正疲惫时，别人还以为你不需要帮助。',
      '食伤' => '看见问题太快时，你可能先指出不合理，却忘了别人还没跟上你的思路；表达越急，越容易被误解成挑剔。',
      '财星' => '你容易同时看见太多可能性，也会不自觉替结果负责；一旦回报不明，心里就开始反复衡量。',
      '官杀' => '你容易把外界标准搬进心里，事情还没失败，先担心自己做得不够；久而久之会把责任感活成紧绷感。',
      '印星' => '你容易用继续准备换取安全感，明明已经懂得不少，却因为还想更确定而推迟真正出手。',
      _ => '你容易在想清楚和马上行动之间来回切换，消耗在尚未发生的情境里。',
    };

String _groupTension(String first, String second) {
  if (first == second) return '';
  final pair = {first, second};
  if (pair.contains('财星') && pair.contains('官杀')) {
    return '你会同时计算结果与规则：既想把事做成，又怕哪一步失去控制。';
  }
  if (pair.contains('财星') && pair.contains('食伤')) {
    return '你既想把想法做得漂亮，也希望它尽快得到现实反馈，慢下来时容易怀疑方向。';
  }
  if (pair.contains('官杀') && pair.contains('印星')) {
    return '你一面回应要求，一面需要先理解和确认；压力大时会在硬扛与退回准备之间摆动。';
  }
  if (pair.contains('比劫') && pair.contains('财星')) {
    return '你既重自主，也很在意现实得失；资源边界不清时，最容易伤到关系。';
  }
  if (pair.contains('比劫') && pair.contains('官杀')) {
    return '你既不愿失去主导，又会认真回应责任，越重要的事越容易对自己用力过猛。';
  }
  if (pair.contains('食伤') && pair.contains('印星')) {
    return '你既想表达，又会反复检查表达是否准确，常常在出口前先在心里改了很多遍。';
  }
  return '两种驱动力同时出现时，你偶尔会在“按自己的方式”与“回应现实需要”之间拉扯。';
}

String _stateShift({required String strength, required String? yong}) {
  final support =
      yong == null ? '得到稳定支持、明确边界和及时反馈' : '处在${_supportScene(yong)}的环境';
  if (_isWeak(strength)) {
    return '$support时，你会从谨慎观望变得愿意承担，原本的细腻会转成判断力。相反，任务同时铺开、长期没有恢复空间时，你容易看起来还在坚持，内里已经明显掉电。';
  }
  if (_isStrong(strength)) {
    return '$support时，你的行动力更容易变成持续成果。若长期缺少边界、反馈或现实校验，优势会过量，变成固执、抢跑或什么都想自己处理。';
  }
  return '$support时，你既能保持自己的判断，也能听进外界反馈。失衡时则容易在过度承担和突然抽离之间切换。';
}

String _mainAdvice({required String strength, required String primaryGroup}) {
  final action = switch (primaryGroup) {
    '比劫' => '把“我要什么、我能给什么、哪里需要别人”说清楚',
    '食伤' => '先完成一个可交付版本，再通过反馈继续优化',
    '财星' => '先核对时间、精力与回报，再决定是否接住机会',
    '官杀' => '把大责任拆成阶段标准，不要每天都用终局要求自己',
    '印星' => '给准备设置截止时间，让理解最终落到一次行动',
    _ => '把选择缩小到眼前最重要的一步',
  };
  if (_isWeak(strength)) {
    return '$action。你的顺序应是先稳住能量和支持系统，再扩大承诺；拒绝一部分，并不等于错过全部。';
  }
  if (_isStrong(strength)) {
    return '$action。你不需要再证明自己能扛，而要练习把力量配置给真正值得的事情。';
  }
  return '$action。保持七分主动、三分校准，通常比全进或全退更适合你。';
}

String _temperamentHeadline({
  required String dayGan,
  required List<String> groups,
  required String strength,
  required int seed,
}) {
  final set = groups.toSet();
  if ((dayGan == '戊' && _isWeak(strength)) ||
      (_elementOfGan(dayGan) == '土' &&
          (set.contains('财星') || set.contains('官杀')))) {
    return '表面很稳，心里一直在计算代价';
  }
  if (set.contains('食伤') && set.contains('印星')) {
    return _pick(['看起来话不多，脑子里已经推演了好几轮', '既想表达得痛快，又想确保自己没有说错'], seed);
  }
  if (set.contains('官杀') && set.contains('印星')) {
    return '外表能扛事，内里其实很需要确定感';
  }
  if (set.contains('财星') && set.contains('食伤')) {
    return '看起来随和，心里对值不值得很有数';
  }
  if (set.contains('比劫') && set.contains('官杀')) {
    return '骨子里不服输，表面却会先顾全局';
  }
  if (_isWeak(strength)) return '比看起来更敏感，也比自己以为的更能撑';
  if (_isStrong(strength)) return '主意来得快，认定以后很难被轻易带走';
  return '看着有分寸，心里其实有一套自己的秩序';
}

String _temperamentOuter(String group) => switch (group) {
      '比劫' => '别人容易觉得你直接、有主见，不太会为了合群改变核心立场。',
      '食伤' => '别人容易觉得你有想法、反应快，也能很快察觉气氛里的不自然。',
      '财星' => '别人容易觉得你会来事、懂轻重，处理现实问题时比较有章法。',
      '官杀' => '别人容易先看到你的可靠、克制和责任感，不一定知道你对自己要求有多高。',
      '印星' => '别人容易觉得你沉稳、好沟通，但你真正认可一个结论前会在心里验证很久。',
      _ => '你给人的感觉通常比内在更稳定，也更少暴露自己的反复思量。',
    };

String _temperamentDrive(String group) => switch (group) {
      '比劫' => '你真正需要的是自主权，以及“这件事由我决定”的确认感。',
      '食伤' => '你真正需要的是表达、创造，以及亲眼看到事情因你而变得更好。',
      '财星' => '你真正需要的是价值被兑现，投入能够换来清晰、可靠的结果。',
      '官杀' => '你真正需要的是胜任感：越重要的事，越想证明自己可以做好。',
      '印星' => '你真正需要的是理解和确定，只有内在逻辑成立，行动才会安心。',
      _ => '你真正需要的是自己的判断被尊重，同时不失去与现实的连接。',
    };

String _strengthPressure(String strength) {
  if (_isWeak(strength)) return '你对环境变化的感受较直接，压力常不是某一件大事，而是许多小事长期叠加。';
  if (_isStrong(strength)) return '你最隐蔽的消耗来自不肯放手：明知可以交给别人，仍担心结果不如自己。';
  return '你平时能自我调节，但连续缺少反馈时，也会陷入“是不是我哪里还没做好”的循环。';
}

String _temperamentState(String group, String strength) {
  final balanced = switch (group) {
    '比劫' => '有选择权和清晰边界时，你果断、仗义，也能带动别人',
    '食伤' => '有表达空间和真实反馈时，你灵活、有趣，解决问题很有创造性',
    '财星' => '目标与回报清楚时，你务实、周到，能把资源安排得井井有条',
    '官杀' => '标准明确且责任匹配时，你可靠、专注，越做越有分量',
    '印星' => '有学习空间和稳定支持时，你理解深、判断准，能持续沉淀',
    _ => '边界和目标清楚时，你能保持稳定输出',
  };
  final unbalanced = _isWeak(strength)
      ? '；透支时则会先迁就、后疲惫，最后突然不想回应任何人。'
      : '；失衡时则会把优势用过头，变得过度坚持或难以放松。';
  return '$balanced$unbalanced';
}

String _temperamentAdvice(String group, String strength) {
  final advice = switch (group) {
    '比劫' => '练习在坚持之前先说目标，在拒绝之前先说边界',
    '食伤' => '把“我看见了问题”和“我怎样让对方听进去”分成两件事',
    '财星' => '别只算事情值不值得，也要计算自己是否真的有余量',
    '官杀' => '把外界要求分成“必须做到”和“可以更好”，不要混成同一个标准',
    '印星' => '允许自己带着七成确定开始，剩下三成在行动中补齐',
    _ => '为重要选择留出一次停顿，确认这是你真正想承担的',
  };
  return '$advice。${_isWeak(strength) ? '先照顾承载，再谈表现，反而更能稳定发挥。' : '给反馈和协作留位置，会让你的长处更耐用。'}';
}

String _dayMasterImage(String gan) => switch (gan) {
      '甲' => '乔木',
      '乙' => '花藤',
      '丙' => '太阳',
      '丁' => '灯火',
      '戊' => '高地',
      '己' => '田园',
      '庚' => '刚铁',
      '辛' => '珠玉',
      '壬' => '江海',
      '癸' => '雨露',
      _ => '自身',
    };

({String kind, String evidence, String advice}) _dayBranchRelationship(
  BaziResult result,
) {
  final day = result.dayZhi;
  final others = <(String, String)>[
    ('年支', result.yearZhi),
    ('月支', result.monthZhi),
    ('时支', result.timeZhi),
  ];
  const clashes = {'子午', '丑未', '寅申', '卯酉', '辰戌', '巳亥'};
  const combines = {'子丑', '寅亥', '卯戌', '辰酉', '巳申', '午未'};
  const harms = {'子未', '丑午', '寅巳', '卯辰', '申亥', '酉戌'};
  bool matches(Set<String> pairs, String other) =>
      pairs.contains('$day$other') || pairs.contains('$other$day');
  for (final entry in others) {
    if (matches(clashes, entry.$2)) {
      return (
        kind: '冲',
        evidence: '夫妻宫与${entry.$1}${entry.$2}相冲，关系节奏带有动象。',
        advice: '有冲时，你对靠近与空间的切换会更敏感，情绪上来时容易用推开代替说明。',
      );
    }
  }
  for (final entry in others) {
    if (matches(harms, entry.$2)) {
      return (
        kind: '害',
        evidence: '夫妻宫与${entry.$1}${entry.$2}相害，细小感受较容易累积。',
        advice: '有害时，真正影响关系的常不是大冲突，而是没有说出口的小失望。',
      );
    }
  }
  for (final entry in others) {
    if (matches(combines, entry.$2)) {
      return (
        kind: '合',
        evidence: '夫妻宫与${entry.$1}${entry.$2}相合，关系对整体选择的牵动较明显。',
        advice: '有合时，你容易为了维持连接多做一步，也要避免把体谅变成长期代替对方承担。',
      );
    }
  }
  return (
    kind: '平',
    evidence: '夫妻宫与其余三支无直接六冲、六合或六害，关系模式更多由宫内十神呈现。',
    advice: '你不一定喜欢关系大起大落，但没有冲突不等于需求已经被看见。',
  );
}

String _relationshipHeadline({
  required String dayBranchGod,
  required ({String kind, String evidence, String advice}) relationshipSignal,
  required int seed,
}) {
  if (relationshipSignal.kind == '冲') return '你既想靠近，也很怕关系打乱自己的节奏';
  return switch (_tenGodGroup(dayBranchGod)) {
    '比劫' => '你要的不是热闹，是有人愿意和你一起扛事',
    '食伤' => _pick(['你要的不是句句回应，是彼此真的听得懂', '能聊到一起，比表面般配更重要'], seed),
    '财星' => '真正让你安心的，不是承诺好听，而是一直有行动',
    '官杀' => '你对关系很认真，所以也很怕认真被辜负',
    '印星' => '你不是慢热，只是不愿把真心交给不确定',
    _ => '你要的不是形式完整，而是相处时真的能放下防备',
  };
}

String _relationshipCare(String god) => switch (_tenGodGroup(god)) {
      '比劫' => '你更常用陪伴、站队和共同承担表达在意。嘴上未必柔软，但对方真遇到事时，你通常不会袖手旁观。',
      '食伤' => '你会分享日常、制造体验、主动沟通，也希望对方对你的表达有真实回应。愿意一直聊，往往就是你的认真。',
      '财星' => '你习惯把在意落到具体事情上：记住需求、安排现实、兑现承诺。你相信长期稳定的行动胜过一时热烈。',
      '官杀' => '你会用负责、守约和规划未来表达认真。关系一旦被你纳入长期考虑，你往往比自己表现出来的更有责任感。',
      '印星' => '你会倾听、理解、照顾情绪，也愿意给对方恢复空间。确认安全以后，你的包容度会明显增加。',
      _ => '你更愿意通过持续回应和具体行动表达在意，而不是只停留在语言上。',
    };

String _relationshipAttraction(String god) => switch (_tenGodGroup(god)) {
      '比劫' => '有立场、讲义气、遇事不躲的人，会让你产生“可以并肩”的感觉。',
      '食伤' => '有趣、坦诚、能接住你的话，也允许彼此做自己的人更容易打动你。',
      '财星' => '靠谱、有生活能力、说到做到的人，比只会制造浪漫的人更容易让你长期心动。',
      '官杀' => '有担当、有分寸、做事让人放心的人，更容易让你认真看待这段关系。',
      '印星' => '温和、理解力强、不催你立刻表态的人，更容易让你慢慢卸下防备。',
      _ => '稳定回应、尊重边界且愿意共同处理现实的人，更容易让你真正投入。',
    };

String _relationshipRisk(String god) => switch (_tenGodGroup(god)) {
      '比劫' => '你重平等，却可能在受伤时迅速进入对抗或独自扛住，让对方不知道怎样靠近。',
      '食伤' => '你需要沟通，但失望时容易把“想被理解”说成“指出对方哪里不对”。',
      '财星' => '你会用投入衡量认真，也可能默默记下双方付出的差额，直到某次突然觉得不值。',
      '官杀' => '你容易把关系经营成责任清单，对自己和对方都要求正确，却少了轻松和示弱。',
      '印星' => '你会先观察和理解，却可能把真实需求藏得太深，期待对方自己发现。',
      _ => '你往往先维持表面稳定，真实需求说得偏晚。',
    };

String _relationshipAdvice(String god, String relationKind) {
  final base = switch (_tenGodGroup(god)) {
    '比劫' => '把边界说在情绪前，也把“我需要你”说出来',
    '食伤' => '先说感受和期待，再讨论谁对谁错',
    '财星' => '别用猜测记账，把投入方式和现实安排提前谈清',
    '官杀' => '允许关系里有不完美，也允许自己偶尔不负责解决全部问题',
    '印星' => '不要只等对方理解，给需求一个明确、可回应的表达',
    _ => '把真实需要说清楚，并给对方一次实际回应的机会',
  };
  final extra = relationKind == '冲'
      ? '；尤其在想推开对方时，先约定冷静多久、何时回来继续谈。'
      : relationKind == '合'
          ? '；亲密不等于替对方承担，保留各自负责的部分。'
          : '。';
  return '$base$extra';
}

String _careerHeadline({
  required String monthCommandGod,
  required String strength,
  required String primaryGroup,
  required int seed,
}) {
  final monthGroup = _tenGodGroup(monthCommandGod);
  if (_isWeak(strength) && monthGroup == '财星') {
    return '适合在复杂里建立秩序，不适合长期靠蛮劲硬撑';
  }
  if (_isWeak(strength) && monthGroup == '官杀') {
    return '你能接难题，但要先借平台和方法，不必单枪匹马';
  }
  return switch (monthGroup ?? primaryGroup) {
    '比劫' => '你适合拥有一块自己能真正负责的阵地',
    '食伤' => _pick(['你的价值，在于把旧问题做出新解法', '越能输出观点和作品，越容易被市场看见'], seed),
    '财星' => '你适合离真实需求近一点，价值会在那里兑现',
    '官杀' => '有标准、有难度、有成长台阶的地方，更容易成就你',
    '印星' => '先把专业做深，你的位置会随着不可替代性出现',
    _ => '比起追风口，你更适合建立一条可持续积累的路径',
  };
}

String _careerWorkStyle(String monthGod, String primaryGroup) {
  final group = _tenGodGroup(monthGod) ?? primaryGroup;
  return switch (group) {
    '比劫' => '你需要明确的负责边界和一定自主权。适合从目标出发自己拆路径，不适合每一步都被微观管理。',
    '食伤' => '你擅长从问题出发改方法，在边做边迭代中找到答案。重复执行但不允许优化，会快速消耗你的热情。',
    '财星' => '你习惯围绕真实需求安排资源，适合目标、客户或结果较清楚的工作。看得见价值闭环时，执行力更稳定。',
    '官杀' => '你在规则明确、职责清晰的体系里容易成长，也能处理高要求任务。前提是标准一致，而不是反复变化。',
    '印星' => '你适合先掌握原理，再形成方法和专业壁垒。给你时间研究清楚，后续判断往往更稳。',
    _ => '你需要目标清楚、反馈真实，并能逐步形成自己方法的工作方式。',
  };
}

String _careerAdvantage(String god) => switch (_tenGodGroup(god)) {
      '比劫' => '开局、承担和临场推动是优势，尤其适合需要主人翁意识的岗位或项目。',
      '食伤' => '洞察问题、表达方案和持续优化是优势，能把经验转为可复制的成果。',
      '财星' => '需求判断、资源配置和结果意识是优势，能在多人多事之间抓住现实重点。',
      '官杀' => '责任感、执行标准和抗压推进是优势，关键任务更容易建立你的信用。',
      '印星' => '学习、研究、归纳和专业判断是优势，越做越深的领域更能形成护城河。',
      _ => '整合信息、判断轻重和持续交付，是你更容易建立口碑的地方。',
    };

String _careerMismatch(String god, String strength) {
  final mismatch = switch (_tenGodGroup(god)) {
    '比劫' => '权责模糊、只让执行却不给判断空间的环境',
    '食伤' => '长期机械重复、否定表达且没有优化空间的环境',
    '财星' => '投入产出长期不清、目标经常变化却无人负责的环境',
    '官杀' => '规则双标、责任无限扩大、努力也没有清晰评价的环境',
    '印星' => '只求速度、不允许理解背景、知识无法沉淀的环境',
    _ => '目标模糊、边界混乱且长期没有真实反馈的环境',
  };
  return '你不适合长期处在$mismatch。${_isWeak(strength) ? '这类环境不只影响效率，还会持续透支你的判断力。' : '你可能暂时能扛，但久了会把精力耗在无效对抗上。'}';
}

String _careerNextStep(String god) => switch (_tenGodGroup(god)) {
      '比劫' => '先拿下一块完整责任，再扩大团队或资源。',
      '食伤' => '先做出可展示的作品或方案，再让影响力带来位置。',
      '财星' => '先验证一个稳定价值闭环，再复制和放大。',
      '官杀' => '先建立可信的履历与标准，再争取更高权限。',
      '印星' => '先形成一项能被验证的深度专长，再拓展边界。',
      _ => '先把一项能力做成稳定结果，再向外扩张。',
    };

String _wealthHeadline({
  required ({int visible, int hidden}) wealth,
  required String strength,
  required int seed,
}) {
  if (_isWeak(strength) && wealth.visible + wealth.hidden > 0) {
    return '不是没有财，而是机会有时来得比承载能力更快';
  }
  if (wealth.visible > 0) {
    return _pick(['你对机会不迟钝，更要学会筛选值得的机会', '钱要看得见路径，你才愿意真正投入'], seed);
  }
  if (wealth.hidden > 0) return '你的财更像慢慢长出来的结果，不适合只追眼前热度';
  return '先把能力做成稀缺性，财富会在后面找到入口';
}

String _wealthMode(({int visible, int hidden}) wealth) {
  if (wealth.visible > 0) return '财星在明处，说明你更容易直接感知市场、回报和资源变化，也更早面对“值不值得”的现实选择。';
  if (wealth.hidden > 0) return '财星藏而不透，财富往往先以能力、资源关系或长期积累存在，遇到合适平台和时机后才更明显。';
  return '财星不显时，财富通常不是最先发力的主题。先站稳专业位置，比过早追逐每个赚钱机会更有效。';
}

String _wealthSource(
  String primaryGroup,
  String monthGod,
  ({int visible, int hidden}) wealth,
) {
  final sourceGroup = _tenGodGroup(monthGod) ?? primaryGroup;
  final source = switch (sourceGroup) {
    '比劫' => '自主项目、团队协作、渠道开拓与把人组织起来',
    '食伤' => '技能输出、内容产品、创意方案与解决具体问题',
    '财星' => '贴近需求、经营项目、配置资源与持续成交',
    '官杀' => '专业责任、组织位置、难题处理与长期信用',
    '印星' => '知识、资质、研究判断与不可替代的专业方法',
    _ => '可重复的专业能力和稳定交付',
  };
  return '更适合你的入口是$source。${wealth.visible == 0 ? '先积累可验证的价值，再谈放大收益。' : '机会出现时，用清晰边界筛掉只占精力、不形成结果的项目。'}';
}

String _wealthAttitude(({int visible, int hidden}) wealth, String strength) {
  if (wealth.visible > 0 && _isWeak(strength)) {
    return '你并不排斥赚钱，甚至很早就能看到机会；真正让你犹豫的，是接下以后要付出的时间、精力和责任。';
  }
  if (wealth.visible > 0) {
    return '你愿意为清晰结果投入，也容易把收入当成能力是否被认可的反馈。只要路径成立，你的执行会很务实。';
  }
  if (wealth.hidden > 0) return '你对钱未必高调，却很在意长期安全感。比起一次赚得漂亮，你更希望它可持续、可复用。';
  return '你可能更先关心事情有没有意义、自己是否擅长，钱通常在价值确定后才进入核心考虑。';
}

String _wealthRisk(({int visible, int hidden}) wealth, String strength) {
  if (_isWeak(strength) && wealth.visible + wealth.hidden > 0) {
    return '风险不是看不到机会，而是同时接太多：收入尚未稳定，精力和责任已经先被占满。也要留意因为不好拒绝而承担不属于自己的成本。';
  }
  if (_isStrong(strength) && wealth.visible > 0) {
    return '你容易相信自己能把局面推起来，因而高估可控性。扩张之前要看现金流、退出条件和最坏结果。';
  }
  if (wealth.hidden > 0) return '容易长期准备却迟迟没有报价、成交或放大动作，让价值停留在“别人都说不错”而不是实际回报。';
  return '容易只顾把能力做好，却没有同步建立被看见、被购买和持续复购的路径。';
}

String _wealthAdvice(({int visible, int hidden}) wealth) {
  if (wealth.visible > 0) return '每次只扩大一个变量：要么客单、要么客户量、要么项目规模，不要三项同时增加。';
  if (wealth.hidden > 0) return '把隐性的能力做成作品、标准服务或清晰报价，让积累有一个可以兑现的出口。';
  return '先建立一项稳定交付，再补上展示、定价和复购机制；财富路径需要被设计，而不是只等机会出现。';
}

String _choiceHeadline(
    {required String? yong, required String? xi, required int seed}) {
  if (yong == null) return '先回到自己的承载力，再决定什么值得继续';
  return switch (yong) {
    '火' => '对你来说，先增温，比先增量更重要',
    '木' => '先长出方向，比盲目加速更重要',
    '土' => '先稳住结构，比继续增加目标更重要',
    '金' => '先立标准、做减法，比继续堆叠更重要',
    '水' => '先让信息和资源流动，比固守一种答案更重要',
    _ => xi == null
        ? '先选择真正能补足你的环境，再谈更多机会'
        : _pick(['靠近让你更稳定的力量，选择会自然变清楚', '真正适合你的，不只是一条路，更是一种状态'], seed),
  };
}

String _supportMeaning(String? element) => switch (element) {
      '火' => '这里的“火”不是只穿红色，而是清晰、行动、被看见和人与人之间真实的温度。',
      '木' => '这里的“木”不是只接触植物，而是方向、成长、长期规划和不断向上的空间。',
      '土' => '这里的“土”不是只选某种物品，而是秩序、稳定、可持续的日常和能够落地的结构。',
      '金' => '这里的“金”不是简单等于饰品，而是标准、边界、专业度和必要的取舍。',
      '水' => '这里的“水”不是简单等于颜色，而是信息、连接、弹性和让资源流通起来。',
      _ => '喜用的意义是帮助命局恢复平衡，它更像选择环境和行动方式的参考，而不是单一标签。',
    };

String _supportScene(String? element) => switch (element) {
      '火' => '目标清楚、有正向回应、行动能够被看见',
      '木' => '方向明确、允许成长、能够持续学习',
      '土' => '节奏稳定、规则清楚、生活有序',
      '金' => '边界明确、标准一致、能够专注取舍',
      '水' => '信息流动、沟通顺畅、选择保有弹性',
      _ => '边界清楚、反馈及时、节奏稳定',
    };

String _supportState(String? element) =>
    '当生活里有${_supportScene(element)}时，你更容易恢复判断力，不必靠硬撑维持表现。这样的状态会让原本的优势变得稳定，而不是偶尔爆发。';

String _drainState(String? element, String strength) {
  final drain = switch (element) {
    '火' => '长期冷处理、缺少回应、只积累任务却迟迟不行动',
    '木' => '方向频繁变化、只救眼前问题、看不到成长空间',
    '土' => '作息混乱、承诺反复、同时处理太多不确定事项',
    '金' => '边界模糊、标准反复、舍不得结束低价值关系或任务',
    '水' => '信息封闭、沟通停滞、被迫困在唯一方案里',
    _ => '目标模糊、边界不清、长期没有恢复与反馈',
  };
  return '$drain会更消耗你。${_isWeak(strength) ? '你可能表面仍在配合，但判断和情绪会先变钝。' : '你可能继续用力顶住，却越来越难听见真实需求。'}';
}

String _supportDaily(String? element) => switch (element) {
      '火' => '优先选择能形成行动、反馈和真实连接的事情；固定运动、晒太阳、当面沟通、公开交付，都比继续闷想更有帮助。',
      '木' => '给自己一条清晰的半年主线，把学习、项目和关系放进长期成长里；凡是只有消耗、没有生长的事，都要重新评估。',
      '土' => '先稳作息、现金流、工作流程和承诺边界；可重复的小秩序，比偶尔一次拼命更能托住你。',
      '金' => '建立标准和截止条件，及时结束低价值任务；少而精、可衡量、有边界，会比面面俱到更适合你。',
      '水' => '主动交换信息、拓宽渠道、保留备选方案；当局面卡住时，先让人和资源重新流动起来。',
      _ => '优先选择边界清楚、反馈真实、能够长期积累的事情，并为恢复精力留出固定空间。',
    };

String _decisionAdvice(String? element, String strength) {
  final question = switch (element) {
    '火' => '这件事会让我更清醒、更愿意行动，还是只让我继续冷掉',
    '木' => '它能带来长期生长，还是只解决眼前焦虑',
    '土' => '它能进入稳定生活，还是会持续打乱基本秩序',
    '金' => '它符合我的标准吗，代价和退出边界清楚吗',
    '水' => '它会增加选择与连接，还是让我被困在一个答案里',
    _ => '它是真的适合我，还是我只是不想让别人失望',
  };
  return '先问自己：“$question？”${_isWeak(strength) ? '再确认时间、精力和支持是否足够，能承接的选择才是好选择。' : '再设定一个可验证的阶段结果，避免只凭一时冲劲。'}';
}

String _elementOfGan(String gan) =>
    const {
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
    }[gan] ??
    '';

String _strengthLabel(String text) {
  for (final label in const ['身衰', '身弱', '偏弱', '身旺', '身强', '偏强', '中和', '平衡']) {
    if (text.contains(label)) return label == '平衡' ? '中和' : label;
  }
  return '';
}

String _tenGodFull(String god) =>
    const {
      '比': '比肩',
      '劫': '劫财',
      '食': '食神',
      '伤': '伤官',
      '才': '偏财',
      '财': '正财',
      '杀': '七杀',
      '官': '正官',
      '枭': '偏印',
      '印': '正印',
    }[god] ??
    '本气';

List<String> _rootPillars(BaziResult result, String dayElement) {
  const labels = ['年支', '月支', '日支', '时支'];
  final roots = <String>[];
  for (var index = 0; index < result.zhiCangGan.length; index++) {
    if (result.zhiCangGan[index]
        .split('')
        .any((stem) => _elementOfGan(stem) == dayElement)) {
      roots.add('${labels[index]}${result.zhis[index]}');
    }
  }
  return roots;
}

Map<String, int> _tenGodGroupCounts(
  BaziResult result,
  String monthCommandGod,
) {
  final counts = <String, int>{
    '比劫': 0,
    '食伤': 0,
    '财星': 0,
    '官杀': 0,
    '印星': 0,
  };
  final stems = <String>[
    result.yearGan,
    result.monthGan,
    result.timeGan,
  ];
  for (final stem in stems) {
    final group = _tenGodGroup(shiShenJianForDayGanVsStem(result.dayGan, stem));
    if (group != null) counts[group] = counts[group]! + 1;
  }
  final commandGroup = _tenGodGroup(monthCommandGod);
  if (commandGroup != null) counts[commandGroup] = counts[commandGroup]! + 2;
  for (final pillar in result.zhiCangGan) {
    final hidden = pillar.split('');
    for (var index = 0; index < hidden.length; index++) {
      final group = _tenGodGroup(
        shiShenJianForDayGanVsStem(result.dayGan, hidden[index]),
      );
      if (group != null) {
        // 各支主气优先；余气只作组合补充，避免把藏干简单等量计数。
        counts[group] = counts[group]! + (index == 0 ? 2 : 1);
      }
    }
  }
  return counts;
}

String? _tenGodGroup(String god) {
  if (god == '比' || god == '劫') return '比劫';
  if (god == '食' || god == '伤') return '食伤';
  if (god == '才' || god == '财') return '财星';
  if (god == '杀' || god == '官') return '官杀';
  if (god == '枭' || god == '印') return '印星';
  return null;
}

int _groupOrder(String group) =>
    const {
      '比劫': 0,
      '食伤': 1,
      '财星': 2,
      '官杀': 3,
      '印星': 4,
    }[group] ??
    9;

({int visible, int hidden}) _godPresence(
  BaziResult result,
  Set<String> gods,
) {
  var visible = 0;
  var hidden = 0;
  for (final stem in [result.yearGan, result.monthGan, result.timeGan]) {
    if (gods.contains(shiShenJianForDayGanVsStem(result.dayGan, stem))) {
      visible++;
    }
  }
  for (final stem in result.zhiCangGan.expand((value) => value.split(''))) {
    if (gods.contains(shiShenJianForDayGanVsStem(result.dayGan, stem))) {
      hidden++;
    }
  }
  return (visible: visible, hidden: hidden);
}

String _dayMasterNature(String gan) =>
    const {
      '甲': '甲木取象乔木，重方向、成长与担当',
      '乙': '乙木取象花藤，善顺势、连接与细致经营',
      '丙': '丙火取象太阳，重坦荡、行动与影响力',
      '丁': '丁火取象灯烛，重感受、专注与持续照见',
      '戊': '戊土取象高地，重稳定、承载与整体秩序',
      '己': '己土取象田园，重实际、培育与细节落实',
      '庚': '庚金取象刚铁，重效率、决断与规则边界',
      '辛': '辛金取象珠玉，重品质、分寸与精细判断',
      '壬': '壬水取象江海，重流动、视野与资源连接',
      '癸': '癸水取象雨露，重观察、渗透与细腻回应',
    }[gan] ??
    '日主的实际表现须放回月令与全局中判断';

String _groupTemperament(List<String> groups) {
  final key = groups.join('');
  if (key.contains('食伤') && key.contains('印星')) return '既有表达和输出欲，也会反复求证、整理与吸收';
  if (key.contains('官杀') && key.contains('印星')) {
    return '对责任、规则和成长路径较敏感，遇到要求时倾向先建立方法';
  }
  if (key.contains('财星') && key.contains('食伤')) {
    return '重现实反馈，也善于把想法、技能或关系转成可见成果';
  }
  if (key.contains('比劫') && key.contains('财星')) {
    return '自主性与现实经营并重，资源边界会直接影响安全感';
  }
  if (key.contains('比劫') && key.contains('官杀')) {
    return '一面坚持自我，一面又会回应责任与竞争，内在张力较强';
  }
  if (groups.isNotEmpty) return '${groups.first}的行为倾向会更常成为你处理事情的起点';
  return '需要结合岁运观察哪一类倾向更先被引动';
}

String _relationshipKeyword(String god) => switch (god) {
      '比' || '劫' => '平等与边界',
      '食' || '伤' => '交流与精神回应',
      '才' || '财' => '现实投入与兑现',
      '杀' || '官' => '责任与稳定',
      '枭' || '印' => '理解与安全感',
      _ => '理解与稳定回应',
    };

String _careerReading(String god) => switch (god) {
      '比' => '独立负责、专业深耕或自主推进的路径',
      '劫' => '团队竞合、项目开拓与资源整合的路径',
      '食' => '技能输出、内容产品、服务体验和长期作品沉淀',
      '伤' => '创新表达、方案优化、技术突破和解决复杂旧问题',
      '才' => '市场连接、机会判断、项目经营和灵活资源配置',
      '财' => '稳定经营、流程管理、持续交付和现实成果积累',
      '杀' => '高要求环境、难题攻坚、风险处理和快速执行',
      '官' => '规则清晰、职责明确、重资历信誉与长期晋升的路径',
      '枭' => '研究判断、冷门专长、系统重构和独立解决问题',
      '印' => '学习研究、知识体系、资质积累和支持型专业',
      _ => '能承接月令气势、并与喜用相合的长期路径',
    };

String _strengthCareerReminder(String strength) {
  if (strength == '身弱' || strength == '身衰' || strength == '偏弱') {
    return '日主偏弱时，先借助专业、团队或稳定平台，再逐步增加责任，比一次承担过多更合局';
  }
  if (strength == '身强' || strength == '身旺' || strength == '偏强') {
    return '日主偏强时，宜把自身能量导向明确结果，并接受规则、市场与协作的校验';
  }
  return '取舍仍要结合喜用与岁运，不只看职业名称';
}

String _wealthStrengthReading(String strength) {
  if (strength == '身弱' || strength == '身衰' || strength == '偏弱') {
    return '身偏弱时先增强承载能力，避免资源与责任同时铺得过大';
  }
  if (strength == '身强' || strength == '身旺' || strength == '偏强') {
    return '身偏强时可通过清晰目标、经营和兑现，把能量落实为成果';
  }
  return '是否真正任财，还须结合日主根气、全局流通与岁运';
}
