import 'package:lunar/lunar.dart';

/// 十二生肖的稳定内容配置。
///
/// 生肖按命理常用的立春分界匹配；性格与关系文案用于传统文化交流和娱乐参考。
class ZodiacCompanion {
  const ZodiacCompanion({
    required this.animal,
    required this.branch,
    required this.element,
    required this.yinYang,
    required this.hours,
    required this.direction,
    required this.title,
    required this.quote,
    required this.coreReading,
    required this.sparks,
    required this.tiredAt,
    required this.suggestion,
    required this.sanHe,
    required this.liuHe,
    required this.clash,
    required this.harm,
    required this.assetPath,
    required this.accentValue,
  });

  final String animal;
  final String branch;
  final String element;
  final String yinYang;
  final String hours;
  final String direction;
  final String title;
  final String quote;
  final String coreReading;
  final List<String> sparks;
  final String tiredAt;
  final String suggestion;
  final List<String> sanHe;
  final String liuHe;
  final String clash;
  final String harm;
  final String assetPath;
  final int accentValue;

  String get branchElement => '$branch$element';

  String get sanHeText => sanHe.join(' · ');

  String get relationshipReading =>
      '你在人际关系里往往会先拿出“${sparks[1]}”的一面，希望相处既真诚又有分寸。'
      '传统生肖关系中，$sanHeText属于三合参考，$liuHe属于六合参考，通常象征节奏更容易协调；'
      '$clash与$harm则提醒双方需要多确认边界和表达方式。'
      '这些关系只描述传统文化中的互动倾向，不等于现实中的关系结论。';

  String get pressureReading => '压力上来时，你较容易$tiredAt。这并不是性格缺点，而是原本的优势使用过度后形成的疲惫。'
      '比起强迫自己立刻振作，更适合先辨认真正消耗你的事情，再减少一项不必要的承担。'
      '给你的具体提醒是：$suggestion。';

  String get growthReading {
    final elementRhythm = switch (element) {
      '木' => '木的象征重在生长与舒展，适合通过持续学习、创作和建立边界，让力量慢慢长出来',
      '火' => '火的象征重在表达与行动，适合把热情集中到少数真正重要的目标上，同时安排稳定的休息',
      '土' => '土的象征重在承载与稳定，适合用清晰节奏积累成果，也要避免把所有责任都揽到自己身上',
      '金' => '金的象征重在判断与取舍，适合发挥条理和品质感，同时给变化与不完美留出空间',
      _ => '水的象征重在感受与适应，适合相信观察力和直觉，也需要用明确行动为情绪建立安全边界',
    };
    final yinYangRhythm = yinYang == '阳'
        ? '阳支更强调主动开启，先做出一个小动作，通常比反复等待更能帮你找到方向。'
        : '阴支更强调沉淀与回应，留出独处和整理时间，往往能让你的判断更加稳定。';
    return '$branchElement、$yinYang支是这份生肖印记的传统分类。$elementRhythm。$yinYangRhythm';
  }

  static ZodiacCompanion byAnimal(String animal) {
    return all.firstWhere(
      (item) => item.animal == animal,
      orElse: () => all.first,
    );
  }

  static const List<ZodiacCompanion> all = <ZodiacCompanion>[
    ZodiacCompanion(
      animal: '鼠',
      branch: '子',
      element: '水',
      yinYang: '阳',
      hours: '23:00–01:00',
      direction: '北',
      title: '机灵，也很柔软',
      quote: '你不必一直把答案想完，先让自己安心。',
      coreReading: '传统生肖意象中的子鼠，优势不只在反应快，更在于会从细节里判断环境是否安全。'
          '你通常能够较早察觉气氛和变化，也愿意为了重要的人调整方法；只是思绪转得太快时，容易在事情真正发生前就预演许多结果。'
          '当你不必防备时，幽默、好奇和细腻会自然显现出来。',
      sparks: <String>['察觉变化', '适应力强', '重安全感'],
      tiredAt: '总在提前担心，习惯把不安藏起来',
      suggestion: '把今天拆小一点，你已经做得很好',
      sanHe: <String>['龙', '猴'],
      liuHe: '牛',
      clash: '马',
      harm: '羊',
      assetPath: 'assets/zodiac/rat.webp',
      accentValue: 0xFF7384D6,
    ),
    ZodiacCompanion(
      animal: '牛',
      branch: '丑',
      element: '土',
      yinYang: '阴',
      hours: '01:00–03:00',
      direction: '东北',
      title: '可靠，也值得被照顾',
      quote: '照顾别人之前，也给自己留一点力气。',
      coreReading: '丑牛的传统意象强调稳定、耐力与对承诺的重视。你更相信经得起时间检验的关系和成果，'
          '面对复杂任务时也常能按自己的节奏一步步推进。别人容易依赖你的可靠，却未必及时看到你承担后的疲惫；'
          '真正适合你的状态，是坚定而不僵硬，负责也允许自己被照顾。',
      sparks: <String>['踏实耐心', '守住承诺', '慢而坚定'],
      tiredAt: '习惯硬撑，不愿让别人担心',
      suggestion: '说一句“我也需要”，不会削弱你的可靠',
      sanHe: <String>['蛇', '鸡'],
      liuHe: '鼠',
      clash: '羊',
      harm: '马',
      assetPath: 'assets/zodiac/ox.webp',
      accentValue: 0xFFC28A57,
    ),
    ZodiacCompanion(
      animal: '虎',
      branch: '寅',
      element: '木',
      yinYang: '阳',
      hours: '03:00–05:00',
      direction: '东北',
      title: '勇敢，也可以偶尔示弱',
      quote: '真正的勇敢，也包括允许自己休息。',
      coreReading: '寅虎象征向外开拓的勇气与保护重要事物的本能。你面对不公或机会时往往反应直接，'
          '不喜欢长期停留在模糊和犹豫里；这种行动力能带动身边的人，也可能让你习惯先解决问题、后处理感受。'
          '当力量不再只用来硬撑，你的担当会更有持续性。',
      sparks: <String>['果断行动', '护短重义', '敢于担当'],
      tiredAt: '总想先解决问题，忘了照顾情绪',
      suggestion: '停一下不是退缩，是在积蓄下一次出发',
      sanHe: <String>['马', '狗'],
      liuHe: '猪',
      clash: '猴',
      harm: '蛇',
      assetPath: 'assets/zodiac/tiger.webp',
      accentValue: 0xFFE2A14B,
    ),
    ZodiacCompanion(
      animal: '兔',
      branch: '卯',
      element: '木',
      yinYang: '阴',
      hours: '05:00–07:00',
      direction: '东',
      title: '温柔，也有自己的边界',
      quote: '不需要讨好所有人，你的感受也很重要。',
      coreReading: '卯兔的传统意象重视感受力、审美与关系中的分寸。你可能很快注意到别人语气和情绪的细微变化，'
          '也擅长把环境照顾得舒服自然。过度顾全气氛时，你自己的需要容易被排到最后；'
          '真正成熟的温柔不是一味退让，而是既能体谅别人，也能清楚表达自己的界限。',
      sparks: <String>['感知细腻', '体贴周全', '审美敏锐'],
      tiredAt: '太在意气氛，把委屈留给自己',
      suggestion: '温柔地拒绝，也是在认真保护关系',
      sanHe: <String>['羊', '猪'],
      liuHe: '狗',
      clash: '鸡',
      harm: '龙',
      assetPath: 'assets/zodiac/rabbit.webp',
      accentValue: 0xFF9A8AD8,
    ),
    ZodiacCompanion(
      animal: '龙',
      branch: '辰',
      element: '土',
      yinYang: '阳',
      hours: '07:00–09:00',
      direction: '东南',
      title: '有方向，也懂得守护',
      quote: '你不必每次都做到最好，真实就很有力量。',
      coreReading: '辰龙在传统文化中承载开拓、愿景和责任感。你容易被有意义、有成长空间的目标吸引，'
          '也希望自己的行动能够带来真实影响。目标感强时，你会主动整合资源并照顾整体，但也可能因为期待过高而难以放松。'
          '允许过程有调整，不会削弱你的力量，反而能让方向走得更远。',
      sparks: <String>['开拓果断', '有担当', '带动他人'],
      tiredAt: '对自己要求太高，偶尔忘了松弛',
      suggestion: '把期待放轻一点，依然不会失去光芒',
      sanHe: <String>['鼠', '猴'],
      liuHe: '鸡',
      clash: '狗',
      harm: '兔',
      assetPath: 'assets/zodiac/dragon.webp',
      accentValue: 0xFF50B8AD,
    ),
    ZodiacCompanion(
      animal: '蛇',
      branch: '巳',
      element: '火',
      yinYang: '阴',
      hours: '09:00–11:00',
      direction: '东南',
      title: '清醒，也很温柔',
      quote: '慢一点也没关系，你一直在向前。',
      coreReading: '巳蛇的传统意象偏向观察、判断与内在定力。你通常不会急着把所有想法说出来，'
          '而是先确认信息和彼此的可信度；一旦真正认定，投入往往比外表看起来更深。敏锐让你能看见隐藏的问题，'
          '但也可能让思绪长时间停不下来。把感受说清楚，会比独自推演更轻松。',
      sparks: <String>['观察细致', '内心坚定', '重感情'],
      tiredAt: '想得太多，却不愿麻烦别人',
      suggestion: '把感受说出来，也是一种勇敢',
      sanHe: <String>['牛', '鸡'],
      liuHe: '猴',
      clash: '猪',
      harm: '虎',
      assetPath: 'assets/zodiac/snake.webp',
      accentValue: 0xFF7B83D8,
    ),
    ZodiacCompanion(
      animal: '马',
      branch: '午',
      element: '火',
      yinYang: '阳',
      hours: '11:00–13:00',
      direction: '南',
      title: '热烈，也需要慢慢充电',
      quote: '跑累了就停一停，风也会来抱抱你。',
      coreReading: '午马象征行动、自由与鲜明的生命力。你容易在看见方向后快速投入，也愿意用坦率和热情感染别人。'
          '持续的新鲜感会让你保持活力，但节奏过快时，身体和情绪的疲惫可能被暂时忽略。'
          '真正适合你的自由，不是一直奔跑，而是能够自主决定何时出发、何时休息。',
      sparks: <String>['行动力强', '坦率真诚', '热爱自由'],
      tiredAt: '节奏太快，容易忽略自己的疲惫',
      suggestion: '今天只完成最重要的一件事就很好',
      sanHe: <String>['虎', '狗'],
      liuHe: '羊',
      clash: '鼠',
      harm: '牛',
      assetPath: 'assets/zodiac/horse.webp',
      accentValue: 0xFFE68F6A,
    ),
    ZodiacCompanion(
      animal: '羊',
      branch: '未',
      element: '土',
      yinYang: '阴',
      hours: '13:00–15:00',
      direction: '西南',
      title: '柔软，也藏着坚定',
      quote: '敏感不是负担，它让你看见更多细小的美好。',
      coreReading: '未羊的传统意象强调共情、创造与柔韧的坚持。你可能不喜欢用强硬方式争取位置，'
          '却会在认定的人和事情上投入很长时间。细腻让你能接住别人没有说出口的情绪，也容易把外界压力带回自己心里。'
          '当你先照顾好内在秩序，温和就会成为稳定而清醒的力量。',
      sparks: <String>['共情细腻', '温和有韧性', '富有创造'],
      tiredAt: '接住太多情绪，最后忘了自己的需要',
      suggestion: '先安顿好自己，再去拥抱世界',
      sanHe: <String>['兔', '猪'],
      liuHe: '马',
      clash: '牛',
      harm: '鼠',
      assetPath: 'assets/zodiac/goat.webp',
      accentValue: 0xFF8CA884,
    ),
    ZodiacCompanion(
      animal: '猴',
      branch: '申',
      element: '金',
      yinYang: '阳',
      hours: '15:00–17:00',
      direction: '西南',
      title: '聪明，也渴望被认真回应',
      quote: '你可以保持好奇，也可以不急着逗所有人开心。',
      coreReading: '申猴的传统意象重视学习速度、应变和创造性。你通常能迅速找到更省力的方法，'
          '也擅长用幽默化解僵局。脑中同时运行太多想法时，你可能用忙碌或热闹避开真正的压力；'
          '如果能把聪明集中到一个长期方向，并允许自己偶尔安静下来，灵活就会沉淀成真正的能力。',
      sparks: <String>['灵活机敏', '创意丰富', '化解尴尬'],
      tiredAt: '脑子停不下来，用热闹盖住压力',
      suggestion: '给自己一段安静，不必时时有趣',
      sanHe: <String>['鼠', '龙'],
      liuHe: '蛇',
      clash: '虎',
      harm: '猪',
      assetPath: 'assets/zodiac/monkey.webp',
      accentValue: 0xFFC07F5E,
    ),
    ZodiacCompanion(
      animal: '鸡',
      branch: '酉',
      element: '金',
      yinYang: '阴',
      hours: '17:00–19:00',
      direction: '西',
      title: '清醒，也需要被肯定',
      quote: '认真生活的你，值得被好好看见。',
      coreReading: '酉鸡的传统意象强调秩序、表达和对品质的敏感。你容易发现细节中的不协调，'
          '也愿意通过整理、修正和清楚沟通把事情做好。标准感是你的优势，但当它全部转向自己时，可能变成持续挑剔。'
          '让“完成”先于“完美”，会使你的判断力更有温度，也更容易被看见。',
      sparks: <String>['条理清晰', '表达直接', '重视品质'],
      tiredAt: '太怕出错，容易对自己挑剔',
      suggestion: '完成比完美更重要，先肯定已经做到的',
      sanHe: <String>['牛', '蛇'],
      liuHe: '龙',
      clash: '兔',
      harm: '狗',
      assetPath: 'assets/zodiac/rooster.webp',
      accentValue: 0xFFE17C67,
    ),
    ZodiacCompanion(
      animal: '狗',
      branch: '戌',
      element: '土',
      yinYang: '阳',
      hours: '19:00–21:00',
      direction: '西北',
      title: '忠诚，也别忘了忠于自己',
      quote: '你总在守护别人，也有人愿意陪着你。',
      coreReading: '戌狗的传统意象看重真诚、原则和关系中的责任。你通常愿意为信任的人站稳立场，'
          '也会认真兑现说过的话。敏锐的责任感有时会让你把别人的情绪和困难也当成自己的任务；'
          '真正稳固的忠诚需要双向回应，你既可以守护关系，也有权保留自己的边界和节奏。',
      sparks: <String>['真诚可靠', '共情力强', '重视关系'],
      tiredAt: '过度承担，把别人的情绪当成责任',
      suggestion: '界限不会推远爱你的人',
      sanHe: <String>['虎', '马'],
      liuHe: '兔',
      clash: '龙',
      harm: '鸡',
      assetPath: 'assets/zodiac/dog.webp',
      accentValue: 0xFFD49A54,
    ),
    ZodiacCompanion(
      animal: '猪',
      branch: '亥',
      element: '水',
      yinYang: '阴',
      hours: '21:00–23:00',
      direction: '西北',
      title: '松弛，也有自己的坚持',
      quote: '你享受当下的样子，本身就很可爱。',
      coreReading: '亥猪的传统意象偏向真诚、包容和对生活感受的重视。你往往愿意先相信善意，'
          '也懂得从日常里找到让自己和别人放松的部分。为了不让场面难看，你可能把需要解决的问题向后放；'
          '当你能温和而及时地表达真实想法，松弛就不再是回避，而会成为有边界的从容。',
      sparks: <String>['真诚豁达', '懂得生活', '内心丰盈'],
      tiredAt: '不想让场面难看，容易把问题拖后',
      suggestion: '清楚表达一次，会换来更轻松的以后',
      sanHe: <String>['兔', '羊'],
      liuHe: '虎',
      clash: '蛇',
      harm: '猴',
      assetPath: 'assets/zodiac/pig.webp',
      accentValue: 0xFFE99886,
    ),
  ];
}

class ZodiacReading {
  const ZodiacReading({
    required this.companion,
    required this.ganZhiYear,
  });

  final ZodiacCompanion companion;
  final String ganZhiYear;

  factory ZodiacReading.fromBirthDate(DateTime birthDate) {
    final date = DateTime(birthDate.year, birthDate.month, birthDate.day, 12);
    final lunar = Lunar.fromDate(date);
    return ZodiacReading(
      companion: ZodiacCompanion.byAnimal(
        lunar.getYearShengXiaoByLiChun(),
      ),
      ganZhiYear: lunar.getYearInGanZhiByLiChun(),
    );
  }
}
