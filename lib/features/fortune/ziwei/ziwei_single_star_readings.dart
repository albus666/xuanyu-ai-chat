import 'ziwei_models.dart';

/// 面向个人信息页的单星断宫文案。
///
/// 这里只解释本宫主题，不处理三方四正、换象、四化或运限，也不参与排盘。
/// 文案统一描述可观察的倾向与可执行建议，避免把传统文化象意写成必然结果。
enum ZiweiReadingTopic {
  personality,
  relationship,
  career,
  wealth,
  social,
  inner,
}

extension ZiweiReadingTopicX on ZiweiReadingTopic {
  String get title => switch (this) {
        ZiweiReadingTopic.personality => '性格底色',
        ZiweiReadingTopic.relationship => '关系模式',
        ZiweiReadingTopic.career => '事业方式',
        ZiweiReadingTopic.wealth => '财富习惯',
        ZiweiReadingTopic.social => '人际连接',
        ZiweiReadingTopic.inner => '内在成长',
      };

  List<String> get palaceAliases => switch (this) {
        ZiweiReadingTopic.personality => const ['命宫'],
        ZiweiReadingTopic.relationship => const ['夫妻'],
        ZiweiReadingTopic.career => const ['官禄', '事业'],
        ZiweiReadingTopic.wealth => const ['财帛'],
        ZiweiReadingTopic.social => const ['交友', '仆役'],
        ZiweiReadingTopic.inner => const ['福德'],
      };
}

class ZiweiSingleStarReading {
  const ZiweiSingleStarReading({
    required this.star,
    required this.summary,
    required this.detail,
  });

  final String star;
  final String summary;
  final String detail;
}

class ZiweiSingleStarReadings {
  const ZiweiSingleStarReadings._();

  static ZiweiPalace palaceFor(
    ZiweiChartData data,
    ZiweiReadingTopic topic,
  ) {
    for (final palace in data.astrolabe.palaces) {
      final name = _modernPalaceName(palace.name);
      if (topic.palaceAliases.any(name.contains)) return palace;
    }
    return data.astrolabe.palaces.firstWhere(
      (palace) => palace.earthlyBranch == data.astrolabe.soulPalaceBranch,
    );
  }

  static List<ZiweiSingleStarReading> forChart(
    ZiweiChartData data,
    ZiweiReadingTopic topic,
  ) {
    final palace = palaceFor(data, topic);
    final results = <ZiweiSingleStarReading>[];
    for (final star in data.effectiveMajorStarsFor(palace)) {
      final text = _texts[star.name]?[topic];
      if (text == null) continue;
      results.add(
        ZiweiSingleStarReading(
          star: star.name,
          summary: text.$1,
          detail: text.$2,
        ),
      );
    }
    return results;
  }

  static String summaryFor(
    ZiweiChartData data,
    ZiweiReadingTopic topic,
  ) {
    final readings = forChart(data, topic);
    if (readings.isEmpty) return '主星线索较少，适合结合长期表现观察';
    return readings.map((item) => item.summary).take(2).join('；');
  }

  static String detailFor(
    ZiweiChartData data,
    ZiweiReadingTopic topic, {
    bool showStarNames = true,
  }) {
    final readings = forChart(data, topic);
    if (readings.isEmpty) {
      return '本宫与对宫暂无可用的十四主星线索，建议结合三方四正与长期重复出现的行为继续观察。';
    }
    return readings.map((item) {
      if (!showStarNames) return item.detail;
      return '${item.star}：${item.detail}';
    }).join('\n\n');
  }
}

String _modernPalaceName(String name) {
  if (name.contains('仆役')) return name.replaceAll('仆役', '交友');
  if (name.contains('事业')) return name.replaceAll('事业', '官禄');
  return name;
}

typedef _ReadingText = (String, String);

const Map<String, Map<ZiweiReadingTopic, _ReadingText>> _texts = {
  '紫微': {
    ZiweiReadingTopic.personality: (
      '有主见，也重视统筹',
      '你通常有主见，重视尊严与自我价值，也愿意在关键时刻承担责任。需要留意的是，替所有人作决定容易让自己过度承担；先听取不同意见，反而更能发挥组织能力。',
    ),
    ZiweiReadingTopic.relationship: (
      '重尊重，也在意主导方式',
      '你在关系中重视尊重、责任与双方的身份认同，也容易形成由一方推动方向的相处模式。保持平等商量，能避免关心逐渐变成替对方决定。',
    ),
    ZiweiReadingTopic.career: (
      '适合统筹、管理与承担责任',
      '你的工作方式偏向统筹方向、协调资源和承担结果，适合能够发挥判断力或专业影响力的位置。与其只追求职位名称，更应建立可以长期被认可的能力。',
    ),
    ZiweiReadingTopic.wealth: (
      '收入常随能力与影响力提升',
      '你的收入容易与职位、专业声誉、管理责任或个人影响力同步变化，也可能为了体面和责任增加支出。把能力转化为长期价值，比追逐短期机会更稳妥。',
    ),
    ZiweiReadingTopic.social: (
      '重视可靠、有分量的连接',
      '你在人际中重视相互尊重与可靠程度，容易承担组织者或协调者的角色。放下不必要的身份压力，让关系保持平等，会更容易得到真诚回应。',
    ),
    ZiweiReadingTopic.inner: (
      '内心需要成就感与掌控感',
      '你的精神满足多来自成就、认可和对生活的掌控。现实暂时不符合预期时，适当放松标准、允许自己求助，会比独自支撑更有利于恢复状态。',
    ),
  },
  '天机': {
    ZiweiReadingTopic.personality: (
      '反应快，善观察与调整',
      '你思维灵活、学习和适应速度较快，面对变化时常能找到新办法。想法较多时也可能频繁调整方向，把一个想法持续做深，会让优势更容易沉淀。',
    ),
    ZiweiReadingTopic.relationship: (
      '重沟通，也需要节奏空间',
      '关系中容易出现忙碌、计划变化或相处节奏不同的情况。及时说明安排并保留各自空间，能够减少因为临时变化产生的误会。',
    ),
    ZiweiReadingTopic.career: (
      '适合策划、分析与动态工作',
      '你擅长计划、分析、协调信息和应对变化，适合接触面较广或需要持续解决新问题的工作。职业方向可以变化，但最好逐步沉淀一个长期专长。',
    ),
    ZiweiReadingTopic.wealth: (
      '财源思路灵活，也容易分散',
      '你善于发现不同渠道和流动机会，也愿意用计划改善资源配置。机会较多时应先确定主线，避免同时铺开太多方向而增加成本。',
    ),
    ZiweiReadingTopic.social: (
      '圈子多元，连接随阶段变化',
      '你容易接触不同背景的人，也能根据场合调整沟通方式。人际面广不等于都要深入，筛选长期可信赖的关系会更轻松。',
    ),
    ZiweiReadingTopic.inner: (
      '脑中想法多，需要定期清空',
      '你的内在反应快、思考多，常在事情发生前预演不同可能。把想法记录下来并安排固定休息，可以减少反复思量造成的消耗。',
    ),
  },
  '太阳': {
    ZiweiReadingTopic.personality: (
      '坦率热心，重视口碑担当',
      '你通常愿意表达、分享和帮助他人，也重视自己的口碑与责任感。热心投入时别忽略自己的承受范围，稳定发光比持续透支更长久。',
    ),
    ZiweiReadingTopic.relationship: (
      '重坦诚，也愿意主动付出',
      '你在关系里偏向坦率表达和主动照顾，希望彼此能公开、明确地回应。避免把持续付出当作唯一的爱，给双方留下接受与反馈的空间更重要。',
    ),
    ZiweiReadingTopic.career: (
      '适合公开表达与服务公众',
      '你的工作方式重视影响力、口碑和对外连接，适合传播、服务、教育、品牌或需要承担公众责任的环境。建立稳定成果，能让曝光真正转化为认可。',
    ),
    ZiweiReadingTopic.wealth: (
      '收入与口碑、影响范围相关',
      '你的资源机会容易跟名誉、职位、品牌或服务人数一起增长，同时也可能为了人情和体面增加花费。清楚区分长期投入与情绪消费，会更容易留下成果。',
    ),
    ZiweiReadingTopic.social: (
      '待人热情，社交覆盖面较广',
      '你在人际中较主动，容易成为带动气氛或提供帮助的人。无需对所有关系负责，选择真正值得投入的人会让社交更有质量。',
    ),
    ZiweiReadingTopic.inner: (
      '需要目标感，也需要被看见',
      '内在状态常与目标感、价值感和外界回应有关。暂时得不到肯定时，先确认自己已经完成的部分，能减少因为比较而产生的失落。',
    ),
  },
  '武曲': {
    ZiweiReadingTopic.personality: (
      '果断务实，重边界与结果',
      '你做事直接、重视效率和实际成果，遇到问题更习惯行动而不是反复解释。表达结论前多说明过程，能让别人更容易理解你的认真。',
    ),
    ZiweiReadingTopic.relationship: (
      '重现实责任，以行动表达',
      '关系中重视现实基础、责任分工和未来安排，表达关心时也更偏向实际行动。金钱观和家庭责任越早沟通，关系越容易稳定。',
    ),
    ZiweiReadingTopic.career: (
      '适合执行、专业技术与财务',
      '你重视把事情做成，适合需要执行力、专业技能、数据标准或资源管理的工作。凡事亲力亲为虽然可靠，也要逐步建立协作和授权能力。',
    ),
    ZiweiReadingTopic.wealth: (
      '先把事做好，再形成积累',
      '你的财富多来自持续行动、专业能力和可交付的成果，适合稳步积累。面对高风险机会时先核对承受范围，不必用一次选择证明自己的判断力。',
    ),
    ZiweiReadingTopic.social: (
      '朋友不求多，更看重可靠',
      '你偏好清楚、守信和能共事的人际关系，未必擅长热络表达，但会用实际帮助建立信任。偶尔说出感受，能让重要关系更有温度。',
    ),
    ZiweiReadingTopic.inner: (
      '内在务实，容易为目标忙碌',
      '你常通过解决问题获得安全感，压力大时也可能继续做事而忽略疲惫。把休息列入计划，并不影响效率，反而能维持长期判断力。',
    ),
  },
  '天同': {
    ZiweiReadingTopic.personality: (
      '温和重感受，富有生活情趣',
      '你通常随和、感受力丰富，也容易从兴趣、美感和舒适关系中获得动力。把喜欢的事落实成稳定行动，可以避免只停留在设想与等待。',
    ),
    ZiweiReadingTopic.relationship: (
      '需要温柔回应与轻松陪伴',
      '你重视关系中的情绪照顾、陪伴和轻松感，也容易为了维持和谐而回避问题。温和地说清需求，比长期迁就更有利于亲密。',
    ),
    ZiweiReadingTopic.career: (
      '适合文化、服务与支持角色',
      '你的工作方式重视体验、氛围和对人的支持，适合文化、艺术、行政协助或服务类环境。建立清楚的期限和标准，能让温和变成可靠的生产力。',
    ),
    ZiweiReadingTopic.wealth: (
      '重生活体验，适合渐进积累',
      '你愿意为舒适、兴趣和人情投入，财富节奏更适合循序渐进。先建立固定储备，再安排体验型消费，会兼顾当下感受与长期安全。',
    ),
    ZiweiReadingTopic.social: (
      '亲和易相处，也需学会筛选',
      '你容易营造轻松友善的相处气氛，也常愿意包容别人。面对持续消耗的关系，及时表达不适和边界会更保护自己。',
    ),
    ZiweiReadingTopic.inner: (
      '内心重舒适，也有艺术感受',
      '你需要温和的节奏、兴趣和情感连接来恢复能量。状态低落时，不要只等待心情变化，从一件小而喜欢的事开始更容易重新启动。',
    ),
  },
  '廉贞': {
    ZiweiReadingTopic.personality: (
      '原则清楚，情感与理性并重',
      '你重视规则、边界和选择的正当性，面对在意的人和事也会投入较强情感。减少反复试探、直接说明底线，能让判断更加清晰。',
    ),
    ZiweiReadingTopic.relationship: (
      '互动浓度高，需要明确边界',
      '关系中的吸引力和互动强度通常较高，双方对原则、边界与回应都较敏感。把规则提前说清，比冷处理或反复试探更有利于稳定。',
    ),
    ZiweiReadingTopic.career: (
      '适合规则、竞争与资源协调',
      '你对规则、竞争和复杂关系较敏感，适合监督、研究、管理、资源协调或需要判断边界的工作。坚持正当流程，能让能力形成长期信誉。',
    ),
    ZiweiReadingTopic.wealth: (
      '财务决策有策略，也重得失',
      '你在资源竞争和方案规划上较有意识，但也容易因急于争取或证明判断而增加压力。重要往来留存记录、提前明确责任，有助于减少纠纷。',
    ),
    ZiweiReadingTopic.social: (
      '重立场与忠诚，关系浓淡分明',
      '你对人与关系有自己的原则，建立信任后会认真投入，不认同时也容易快速拉开距离。给彼此一次说明的机会，可避免仅凭情绪做判断。',
    ),
    ZiweiReadingTopic.inner: (
      '内心忙碌，满足来自投入感',
      '你常在兴趣、目标或重要关系中获得精神动力，即使休息也可能想着尚未完成的事。把责任与个人感受分开整理，更容易真正放松。',
    ),
  },
  '天府': {
    ZiweiReadingTopic.personality: (
      '稳健包容，重积累与承接',
      '你通常谨慎、厚道，擅长承接事务并维持稳定，也会认真衡量长期利益。避免因为求稳而迟迟不行动，小步验证能带来更多选择。',
    ),
    ZiweiReadingTopic.relationship: (
      '重稳定责任，也重长期经营',
      '你希望关系可靠、生活有秩序，也看重双方是否愿意承担责任。避免把每一次付出都换算成得失，直接表达期待会让关系更轻松。',
    ),
    ZiweiReadingTopic.career: (
      '适合稳守、统筹与长期经营',
      '你擅长在成熟平台或稳定结构中积累经验、统筹事务，一步步建立位置。面对新机会可以先评估再试行，不必因追求确定性错过成长。',
    ),
    ZiweiReadingTopic.wealth: (
      '重储备与稳定，擅长长期管理',
      '你看重财务安全和持续积累，适合预算、储备和长期管理。过度保守时可能错过合理机会，给可控尝试预留一小部分空间会更平衡。',
    ),
    ZiweiReadingTopic.social: (
      '关系稳定，善于承接资源',
      '你重视长期可靠的人际网络，也常成为别人信赖和托付事务的对象。帮助他人时明确自己的容量，能避免责任不断叠加。',
    ),
    ZiweiReadingTopic.inner: (
      '内在重秩序、责任与安全感',
      '你需要稳定节奏和可预期的安排来获得安心，也愿意为重要的人事承担责任。适度接受变化，可以让安全感不只依赖外部秩序。',
    ),
  },
  '太阴': {
    ZiweiReadingTopic.personality: (
      '细腻敏锐，善观察与计划',
      '你对细节、氛围和他人情绪较敏感，通常善于思考与规划。感受很多时不要只在心里推演，及时确认事实能减少不必要的担忧。',
    ),
    ZiweiReadingTopic.relationship: (
      '慢热细腻，重理解与安全感',
      '你重视细节照顾、情绪理解和稳定陪伴，外在平静时内心仍可能反复消化感受。温和而明确地表达，比期待对方自行察觉更有效。',
    ),
    ZiweiReadingTopic.career: (
      '适合策划、财务与细节管理',
      '你擅长计划、整理、观察和处理细节，适合财务、策划、文字、设计或需要持续积累的工作。避免长期隐藏成果，适时表达贡献会得到更多支持。',
    ),
    ZiweiReadingTopic.wealth: (
      '善规划与积累，决策受感受影响',
      '你通常愿意规划钱财并追求稳定，也可能因为安全感不足而反复权衡。为重要决定设置明确标准，能避免在情绪波动时频繁改变计划。',
    ),
    ZiweiReadingTopic.social: (
      '重走心连接，不喜表面热络',
      '你更看重能够理解彼此感受的关系，未必追求很大的社交圈。不要把沉默当作默认共识，适度说出需求会让关系更稳。',
    ),
    ZiweiReadingTopic.inner: (
      '内心细腻，需要安静与理解',
      '你需要独处、安稳环境和情绪被理解的感觉来恢复能量。反复思考时可以把感受写下来，再区分哪些是事实、哪些只是担心。',
    ),
  },
  '贪狼': {
    ZiweiReadingTopic.personality: (
      '善连接、重体验，适应力强',
      '你通常有社交敏感度，懂得观察场合，也愿意探索不同体验。选择太多时先确认真正想要什么，能避免被短期热度牵着走。',
    ),
    ZiweiReadingTopic.relationship: (
      '重情趣互动，也要清楚边界',
      '你在关系中重视吸引力、情趣和共同体验，也较容易受到外界关注。提前约定彼此认可的社交边界，能减少猜疑和不透明感。',
    ),
    ZiweiReadingTopic.career: (
      '适合社交、消费服务与创意',
      '你擅长连接人和资源，也容易在销售、公关、内容、审美或体验服务中发挥优势。把灵活手段建立在长期信誉上，发展会更稳定。',
    ),
    ZiweiReadingTopic.wealth: (
      '机会来自连接，消费也重体验',
      '你的资源机会常来自社交、合作、审美或信息差，也愿意为体验和兴趣花费。重要选择先看真实价值和退出成本，可减少冲动投入。',
    ),
    ZiweiReadingTopic.social: (
      '社交面广，善于活跃关系',
      '你善于打开话题、经营氛围和连接不同圈层，容易认识很多人。明确哪些是合作、哪些是朋友，可以减少期待错位。',
    ),
    ZiweiReadingTopic.inner: (
      '欲望与兴趣丰富，需要取舍',
      '你容易被新鲜感、美感和多样体验激发，精神世界并不单调。把兴趣排出优先级，才能让满足感不被不断出现的新目标稀释。',
    ),
  },
  '巨门': {
    ZiweiReadingTopic.personality: (
      '善分析表达，也容易多想',
      '你对信息和细节较敏感，擅长提问、分析和表达不同意见。判断形成前多核对事实，能避免因为想得太快而增加猜疑。',
    ),
    ZiweiReadingTopic.relationship: (
      '沟通影响很大，需减少猜测',
      '关系中的问题常来自语气、细节和彼此对一句话的不同理解。把事实、感受和需求分开说明，比边猜边说更能减少消耗。',
    ),
    ZiweiReadingTopic.career: (
      '适合表达、研究与解决争议',
      '你的工作优势在语言、分析、研究、销售、教育或处理复杂意见。表达观点时同时给出依据和方案，更容易把争论转化成专业影响力。',
    ),
    ZiweiReadingTopic.wealth: (
      '可凭表达与信息能力获得机会',
      '你的收入机会容易来自沟通、知识、分析和多渠道连接，但过程也可能较费心。合作前写清范围、价格和交付标准，能减少后续争议。',
    ),
    ZiweiReadingTopic.social: (
      '重观点交流，也易因话起波澜',
      '你容易通过讨论建立连接，也会敏锐发现话语中的矛盾。不是每个分歧都需要立即说服，保留差异能让关系更长久。',
    ),
    ZiweiReadingTopic.inner: (
      '心中问题多，需要清楚出口',
      '你习惯在心里分析事情的前因后果，压力大时容易反复回想对话。把问题分成可行动与暂不可控两类，会让思绪更有秩序。',
    ),
  },
  '天相': {
    ZiweiReadingTopic.personality: (
      '公正协调，重秩序与分寸',
      '你重视公平、礼貌与关系中的分寸，善于观察各方需要。照顾别人之前先确认自己的立场，能避免因为顾虑过多而难以决定。',
    ),
    ZiweiReadingTopic.relationship: (
      '重配合支持，也需平衡决定权',
      '你重视互相支持、体面沟通和稳定协作，也容易在关系中承担配合角色。让双方轮流表达和作决定，能避免一方长期压住真实需要。',
    ),
    ZiweiReadingTopic.career: (
      '适合协调、支持与专业服务',
      '你擅长在团队或平台中协调资源、支持决策和维持秩序，适合专业服务、运营或副手型岗位。把幕后贡献清楚呈现，有助于获得公平认可。',
    ),
    ZiweiReadingTopic.wealth: (
      '资源多经合作流转，重信誉',
      '你的财务机会容易来自平台、合作、介绍或为他人管理资源。合作能带来助力，也会形成约束，明确权责和收益分配十分重要。',
    ),
    ZiweiReadingTopic.social: (
      '善协调关系，容易获得助力',
      '你在人际中懂得顾全大局，也愿意支援他人，因此较容易获得信任。不要总把自己的需求放到最后，平等互助才更持久。',
    ),
    ZiweiReadingTopic.inner: (
      '在意评价，内心常反复权衡',
      '你会考虑他人感受和事情是否合宜，做决定前容易权衡很多方面。先确定自己的核心原则，可以减少因外界评价产生的犹豫。',
    ),
  },
  '天梁': {
    ZiweiReadingTopic.personality: (
      '有原则与保护心，善看问题',
      '你重视合理、公正和责任，也常能发现问题并提醒他人。提出意见时同时给予支持和方法，更容易让善意被接受。',
    ),
    ZiweiReadingTopic.relationship: (
      '重原则照顾，可能存在节奏差',
      '你希望关系成熟、可靠并能相互照顾，双方在年龄、经历或心理节奏上也可能有所差异。少一些评判，多说明关心的出发点，互动会更柔和。',
    ),
    ZiweiReadingTopic.career: (
      '适合监督、顾问与专业服务',
      '你擅长依据原则发现问题、提供建议和保护整体利益，适合监督、咨询、教育或专业服务。建立专业边界，能避免长期替别人收拾问题。',
    ),
    ZiweiReadingTopic.wealth: (
      '资源来自专业与信任，宜稳健',
      '你的财务机会常来自专业能力、可信度和为他人解决问题，不必依赖高频冒险。涉及共同资金时保持透明，会更容易维持信任。',
    ),
    ZiweiReadingTopic.social: (
      '容易连接长辈或专业型伙伴',
      '你重视有原则、有经验或值得信赖的人，也常在关系中扮演提醒和保护角色。给别人保留自主空间，帮助会更有分寸。',
    ),
    ZiweiReadingTopic.inner: (
      '内心有标准，也容易看见不足',
      '你习惯思考什么更合理、更长久，也容易先看见问题。每天保留一些只为愉悦而做的事，可以让责任感与生活感保持平衡。',
    ),
  },
  '七杀': {
    ZiweiReadingTopic.personality: (
      '独立果断，有自己的判断',
      '你独立意识较强，面对压力时敢于作决定，也不喜欢盲目附和。行动前多听一轮反馈，能让果断不必以承担额外代价为交换。',
    ),
    ZiweiReadingTopic.relationship: (
      '重独立尊重，需要清楚空间',
      '关系中重视彼此能力、直接回应和个人空间，不喜欢被过度约束。明确各自责任并保留独立性，反而更容易建立尊重。',
    ),
    ZiweiReadingTopic.career: (
      '适合开创、执行与处理难题',
      '你面对压力和新局面时有较强行动力，适合需要开创、执行或专业突破的工作。管理关系时少用单向命令，多建立共同目标会更有效。',
    ),
    ZiweiReadingTopic.wealth: (
      '财富随开创而来，风险需设边界',
      '你的资源机会常伴随竞争、责任和开创新局，成果与压力往往同时出现。预先设置止损和储备，能避免把全部资源放在一次判断上。',
    ),
    ZiweiReadingTopic.social: (
      '关系重能力与目标，不喜勉强',
      '你容易欣赏有行动力、能承担的人，人际交往也较直接。给不同节奏的人留出表达空间，合作会更加顺畅。',
    ),
    ZiweiReadingTopic.inner: (
      '内心有抱负，压力下更想掌控',
      '你希望通过独立判断和实际成果确认价值，遇到压力时可能更少表达感受。把求助视作资源配置，而不是示弱，会走得更稳。',
    ),
  },
  '破军': {
    ZiweiReadingTopic.personality: (
      '敢改变重建，不喜长期受限',
      '你对不合适的旧方式有较强调整意愿，也愿意尝试新路径。改变之前保留必要基础，并为试错设置范围，能让突破更可持续。',
    ),
    ZiweiReadingTopic.relationship: (
      '关系随阶段调整，重共同成长',
      '关系容易伴随工作、居住或人生计划的变化，不一定适合一成不变的相处方式。遇到问题时共同调整规则，比用结束代替沟通更有效。',
    ),
    ZiweiReadingTopic.career: (
      '适合变革、创新与重整局面',
      '你在变化、开拓和重整旧流程时更容易发挥能力，过度稳定的环境可能限制动力。每次创新都留下可复用成果，才能避免总从头开始。',
    ),
    ZiweiReadingTopic.wealth: (
      '财务波动感较强，重开源也要留存',
      '你的资源容易随着项目、环境和选择而变化，开创新渠道时也伴随投入。建立储备、分阶段验证，能让变化带来机会而不是反复消耗。',
    ),
    ZiweiReadingTopic.social: (
      '圈层随成长变化，重真实与自由',
      '你不太愿意为了维持表面关系长期压抑自己，人生阶段变化时圈子也可能更新。处理旧关系时保留尊重，会让转变更加从容。',
    ),
    ZiweiReadingTopic.inner: (
      '需要变化感，也要建立内在锚点',
      '你容易在突破、尝试和更新中获得精神动力，长期停滞时会感到受限。保留固定作息或长期目标，能让变化不至于失去方向。',
    ),
  },
};
