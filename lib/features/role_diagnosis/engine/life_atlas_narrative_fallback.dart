import '../models/life_atlas_models.dart';
import '../models/role_diagnosis_models.dart';

class LifeAtlasNarrativeFallback {
  LifeAtlasNarrativeFallback._();

  static LifeAtlasEventAnalysis analyze(String input) {
    final text = input.trim();
    if (_hasAny(text, const ['编制', '事业编', '公务员'])) {
      return _analysis(
        eventKey: 'exam_staff_passed',
        summary: '考取编制',
        domain: LifeAtlasDomain.career,
        question: '这次考上，对你最像哪一种？',
        options: const [
          ('long_wait', '备考很久，终于有了结果'),
          ('repeat', '经历过失利，这次终于上岸'),
          ('stability', '从不安定走向了安定'),
          ('family', '终于能把好消息带回家'),
          ('simple_joy', '就是为自己高兴一次'),
        ],
      );
    }
    if (_hasAny(text, const ['创业', '开公司', '开店'])) {
      return _analysis(
        eventKey: 'business_first_start',
        summary: '第一次创业',
        domain: LifeAtlasDomain.career,
        stage: 'started',
        question: '这次开始，对你最像哪一种？',
        options: const [
          ('from_zero', '从零开始，把想法真正做出来'),
          ('bet_self', '终于决定为自己赌一次'),
          ('long_idea', '想了很久，今天终于开张'),
          ('new_life', '想离开旧轨道，重新开始'),
          ('first_customer', '已经等到了第一位客户'),
        ],
      );
    }
    if (_hasAny(text, const ['国外', '出国', '境外'])) {
      return _analysis(
        eventKey: 'overseas_first',
        summary: '第一次去国外',
        domain: LifeAtlasDomain.journey,
        question: '这趟远行，对你更像哪一种？',
        options: const [
          ('delayed_fulfillment', '攒了很久，终于轮到自己'),
          ('solo_crossing', '第一次独自面对陌生世界'),
          ('new_life', '离开熟悉生活，重新开始'),
          ('promise', '和重要的人兑现一个约定'),
          ('simple_joy', '就是一次开心的旅行'),
        ],
      );
    }
    if (_hasAny(text, const ['驾照', '科三', '科二', '练车'])) {
      return _analysis(
        eventKey: 'drivers_license',
        summary: '驾照与驾驶考试',
        domain: LifeAtlasDomain.growth,
        question: '这一次，你走到了哪一步？',
        options: const [
          ('started', '刚报名或第一次开始练车'),
          ('stage_passed', '通过了一个考试科目'),
          ('retry_passed', '经历失利后终于通过'),
          ('licensed', '正式拿到了驾驶证'),
          ('keep_going', '这次没过，但还会继续'),
        ],
      );
    }
    return _analysis(
      eventKey: 'other_growth',
      summary: text.length > 24 ? '${text.substring(0, 24)}…' : text,
      domain: LifeAtlasDomain.growth,
      question: '这件事对你最重要的意义是什么？',
      options: const [
        ('first_time', '这是我人生中的第一次'),
        ('long_wait', '我为它准备或等待了很久'),
        ('comeback', '经历过不顺，终于走到这里'),
        ('new_life', '它让我开始了新的生活'),
        ('simple_joy', '它只是让我真心高兴'),
      ],
    );
  }

  static List<LifeAtlasAchievement> generate({
    required String input,
    required LifeAtlasEventAnalysis analysis,
    required LifeAtlasMeaningOption meaning,
    required RoleDiagnosisReport report,
  }) {
    final seed = _stableHash('${report.pillars}|${input.trim()}|${meaning.id}');
    final curated = _curated[analysis.eventKey]?[meaning.id];
    final generic = _generic[_genericMeaning(meaning.id)]!;
    final selected = curated == null
        ? <(String, String)>[
            for (var i = 0; i < 3; i++) generic[(seed + i) % generic.length],
          ]
        : <(String, String)>[
            curated[seed % curated.length],
            curated[(seed + 1) % curated.length],
            generic[(seed ~/ curated.length) % generic.length],
          ];
    return [
      for (var i = 0; i < selected.length; i++)
        LifeAtlasAchievement(
          id: '${analysis.eventKey}_${meaning.id}_${seed}_$i',
          title: selected[i].$1,
          quote: selected[i].$2,
          domain: analysis.domain,
          rarityLabel: _levelLabel(analysis.level),
          eventKey: analysis.eventKey,
          sceneKey: analysis.eventKey,
          eventSummary: analysis.summary,
          meaningLabel: meaning.label,
        ),
    ];
  }

  static LifeAtlasEventAnalysis _analysis({
    required String eventKey,
    required String summary,
    required LifeAtlasDomain domain,
    required String question,
    required List<(String, String)> options,
    String stage = 'completed',
    String level = 'milestone',
  }) {
    return LifeAtlasEventAnalysis(
      eventKey: eventKey,
      summary: summary,
      domain: domain,
      stage: stage,
      level: level,
      question: question,
      options: [
        for (final item in options)
          LifeAtlasMeaningOption(id: item.$1, label: item.$2),
      ],
    );
  }

  static bool _hasAny(String text, List<String> words) =>
      words.any(text.contains);

  static String _genericMeaning(String value) => switch (value) {
        'repeat' || 'retry_passed' || 'keep_going' => 'comeback',
        'stability' || 'new_life' => 'new_life',
        'from_zero' ||
        'started' ||
        'stage_passed' ||
        'licensed' =>
          'first_time',
        'bet_self' || 'long_idea' || 'first_customer' => 'first_time',
        'delayed_fulfillment' => 'long_wait',
        'solo_crossing' || 'promise' => 'first_time',
        'self_reliance' || 'being_seen' => 'first_time',
        'protection' => 'simple_joy',
        'letting_go' => 'new_life',
        'family' || 'simple_joy' => 'simple_joy',
        'first_time' || 'long_wait' || 'comeback' => value,
        _ => 'simple_joy',
      };

  static String _levelLabel(String value) => switch (value) {
        'milestone' => '人生里程碑',
        'turning_point' => '人生转折',
        'hidden' => '隐藏人生章',
        _ => '人生印记',
      };

  static int _stableHash(String value) {
    var hash = 2166136261;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 16777619) & 0x7fffffff;
    }
    return hash;
  }

  static const _generic = <String, List<(String, String)>>{
    'first_time': [
      ('第一次，人生有了新页', '有些改变并不喧哗，只是在今天以后，你再也不是从前那个自己。'),
      ('今天以后，多了一种可能', '第一次不是为了证明你天生会，而是证明你愿意真的开始。'),
      ('把没做过，变成做到了', '世界没有突然改变，是你亲手跨过了一条从未走过的线。'),
    ],
    'long_wait': [
      ('漫长终于有了回音', '那些没有人替你计算的等待，今天终于给了你一个真实的回答。'),
      ('这一次，轮到我了', '看过许多人的好消息以后，今天，故事终于写到了你的名字。'),
      ('把以后等成了今天', '曾经只能放在心里的愿望，终于从一句以后，变成了正在发生。'),
    ],
    'comeback': [
      ('没赢在开始，赢在没走', '你不是一路顺利的人，但你是跌下去以后，仍愿意再往前一步的人。'),
      ('这次没有错过自己', '曾经没有得到的答案，没有让你停下；今天，你亲手把它重新写了一遍。'),
      ('走慢一点，也走到了', '时间没有辜负那个人——一次次失望以后，仍然没有放弃自己。'),
    ],
    'new_life': [
      ('旧生活到这里为止', '真正跨过去的不是某一件事，而是过去那种生活能够困住你的边界。'),
      ('把退路走成了前路', '起初只是想离开原地，后来才发现，你已经走出了新的方向。'),
      ('人生重新亮了一次', '你没有等世界替你翻篇，而是亲手把今天写成了新的开头。'),
    ],
    'simple_joy': [
      ('今天值得高兴', '不是每一个瞬间都要改变人生；能让你真心笑一次，就已经值得被留下。'),
      ('这一刻，归我珍藏', '它也许不是宏大的胜利，却是今天真实落在你身上的快乐。'),
      ('普通一天，也有光', '生活没有发生传奇，但这一刻的高兴是真的，也只属于你。'),
    ],
  };

  static const _curated = <String, Map<String, List<(String, String)>>>{
    'exam_staff_passed': {
      'long_wait': [
        ('把漫长考成答案', '那些一页页翻过去的日子没有出声，直到今天，它们一起替你回答了生活。'),
        ('这次，轮到我了', '那些没有写进成绩单里的坚持，今天终于和你的名字一起出现在名单上。'),
        ('名字终于有了回音', '你等的不是一张纸，而是那些认真生活的日子，终于被世界看见。'),
      ],
      'repeat': [
        ('岸一直没有走远', '你不是一次就赢的人，但你是失利以后，仍然坐回书桌前的人。'),
        ('输过以后，仍然落笔', '没有如愿的日子没有带走你，反而让今天的名字，比想象中更有分量。'),
        ('这一次没有错过我', '曾经擦肩而过的答案，终于在你没有放弃以后，重新走回了面前。'),
      ],
      'stability': [
        ('生活终于有了落点', '真正放下来的不是一份工作，而是那些一直悬着、不敢安排的明天。'),
        ('悬着的明天落了地', '从今天开始，你终于敢认真想一想，那些曾经不敢安排的以后。'),
        ('以后，终于可以安排', '名单上的名字很短，却替你接住了很长一段不确定的生活。'),
      ],
      'family': [
        ('好消息终于敲门', '这一次带回家的不再是“再等等”，而是名单上真实出现的名字。'),
        ('把再等等换成了考上', '你终于能把那句说过很多次的“快了”，换成一个确定的好消息。'),
        ('名单里的名字回了家', '这一份结果写的是你的名字，落下来的，却是一家人悬了很久的心。'),
      ],
    },
    'business_first_start': {
      'from_zero': [
        ('从零号桌开始', '没有现成的位置，你就亲手摆下第一张桌子，让想法第一次有了地址。'),
        ('先把第一盏灯点亮', '世界还不知道它会走多远，但今天，你已经让自己的那扇窗先亮了。'),
        ('从没有，到开张', '真正困难的从来不是宏大的未来，而是你终于把第一步变成了现实。'),
      ],
      'bet_self': [
        ('这一次，我押自己', '没有谁能提前保证结果，你还是把筹码放在了那个最想成为的自己身上。'),
        ('把安稳换成可能', '你不是不知道风险，只是不想让余生只剩一句“如果当时”。'),
        ('亲自做自己的东风', '等不到刚好的机会，你就决定先成为那个让事情开始的人。'),
      ],
      'long_idea': [
        ('想了很久，今天开张', '那个在脑海里排练过无数次的未来，终于有了一扇真实打开的门。'),
        ('把以后写成了开业', '你不再只谈论想做的事，今天，它第一次以真实的名字出现。'),
        ('念头终于有了门牌', '从一个不敢说出口的想法，到今天可以被世界找到，你走了很久。'),
      ],
    },
    'overseas_first': {
      'delayed_fulfillment': [
        ('远方终于轮到我', '看过那么多别人的世界，这一次，异国的灯终于照在了你身上。'),
        ('世界终于不是屏幕', '你攒下的不只是一次出发，也把曾经隔着屏幕羡慕的人生，过成了自己的。'),
        ('把以后走成了抵达', '曾经只能放进愿望里的远方，今天终于真实地出现在了你的脚下。'),
      ],
      'solo_crossing': [
        ('一个人，也抵达世界', '没人替你认路，也没人替你壮胆；你还是拖着行李，走出了熟悉人生的边界。'),
        ('独自穿过国境线', '陌生没有退开，是你带着不安往前走，让世界第一次为自己展开。'),
        ('没有同行，也没有退回', '你第一次发现，所谓独立，是在听不懂的语言里也能安顿好自己。'),
      ],
      'new_life': [
        ('在世界另一边重启', '那天跨过的不只是一条国境线，也是旧生活能够困住你的最后边界。'),
        ('换一个时区生活', '当熟悉的一切留在身后，你终于有机会重新决定，往后的日子怎么过。'),
        ('旧坐标到这里为止', '你没有逃离人生，只是走得足够远，终于看见另一种活法。'),
      ],
      'promise': [
        ('把以后走成风景', '曾经随口说过的远方，这一次真实地出现在了你们脚下。'),
        ('约定终于有了坐标', '那句说过很多次的“一起去”，今天终于不再只是聊天记录。'),
        ('远方替你们作证', '有些约定没有被时间吹散，而是在今天，变成了共同走过的路。'),
      ],
    },
    'drivers_license': {
      'retry_passed': [
        ('把熄火练成远方', '方向不是一开始就稳，是一次次重新点火后，终于握在了自己手里。'),
        ('这次，路没有把我拦下', '失利没有替你决定终点，你重新坐回驾驶位，把没走完的路继续开完。'),
        ('方向盘终于有了回音', '那些紧张和重来没有白费，今天，你终于把不确定开成了通过。'),
      ],
      'licensed': [
        ('从今天起，自己掌舵', '拿到的不只是一张证，也是以后想去哪里时，多了一份自己出发的底气。'),
        ('人生多了一条自己开的路', '曾经坐在副驾驶看过的远方，从今天开始，也可以由你亲自抵达。'),
        ('方向终于握在手里', '世界没有因此变小，但从今天起，你能亲手决定下一段路往哪里开。'),
      ],
    },
  };
}
