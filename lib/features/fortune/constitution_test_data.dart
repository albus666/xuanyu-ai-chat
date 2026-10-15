// 体质问诊题目（与 assets 文档「核心状况—诱因」一致；辨证权重由服务端解析 v2 载荷）。

typedef ConstitutionOption = ({String key, String label});

class ConstitutionQuestion {
  const ConstitutionQuestion({
    required this.id,
    this.section,
    required this.title,
    required this.type,
    this.options = const [],
  });

  final int id;
  final String? section;
  final String title;
  final ConstitutionQuestionType type;
  final List<ConstitutionOption> options;
}

enum ConstitutionQuestionType { text, single, multi }

/// 第2题选 C（无明显怕冷怕热）则不出第3题。
bool showQuestion3(String? q2Answer) {
  if (q2Answer == null || q2Answer.isEmpty) return false;
  return q2Answer != 'C';
}

const constitutionQuestions = <ConstitutionQuestion>[
  ConstitutionQuestion(
    id: 1,
    section: '第一部分：核心状况（主诉与寒热）',
    title: '您目前最不舒服、最想解决的主要问题是什么？',
    type: ConstitutionQuestionType.text,
  ),
  ConstitutionQuestion(
    id: 2,
    title: '您整体的怕冷或怕热感觉是怎样的？',
    type: ConstitutionQuestionType.single,
    options: [
      (key: 'A', label: '非常怕冷，喜暖恶风'),
      (key: 'B', label: '比较怕冷'),
      (key: 'C', label: '没有明显怕冷或怕热'),
      (key: 'D', label: '比较怕热'),
      (key: 'E', label: '非常怕热，喜凉恶热'),
      (key: 'F', label: '一阵冷一阵热，自己不能调节'),
      (key: 'G', label: '手脚心发热，心里觉得烦热'),
    ],
  ),
  ConstitutionQuestion(
    id: 3,
    title: '如果怕冷/怕热，主要在哪个部位明显？（可多选）',
    type: ConstitutionQuestionType.multi,
    options: [
      (key: 'A', label: '全身都怕'),
      (key: 'B', label: '后背特别怕冷/怕热'),
      (key: 'C', label: '腹部怕冷/怕热'),
      (key: 'D', label: '四肢或手脚特别冰凉/发热'),
      (key: 'E', label: '关节部位怕冷/怕热'),
    ],
  ),
  ConstitutionQuestion(
    id: 4,
    title: '近期是否有发烧？',
    type: ConstitutionQuestionType.single,
    options: [
      (key: 'A', label: '是，发烧时怕冷明显'),
      (key: 'B', label: '是，发烧时怕热明显'),
      (key: 'C', label: '是，但不怕冷也不怕热'),
      (key: 'D', label: '否，没有发烧'),
    ],
  ),
  ConstitutionQuestion(
    id: 5,
    section: '第二部分：汗、头身',
    title: '您平时容易出汗吗？',
    type: ConstitutionQuestionType.single,
    options: [
      (key: 'A', label: '非常容易，稍动就出（自汗）'),
      (key: 'B', label: '只有夜间或睡着时出汗（盗汗）'),
      (key: 'C', label: '不容易出汗，即使天气热或运动后'),
      (key: 'D', label: '出汗量正常，没有特别感觉'),
    ],
  ),
  ConstitutionQuestion(
    id: 6,
    title: '出汗主要在哪个部位明显？',
    type: ConstitutionQuestionType.single,
    options: [
      (key: 'A', label: '头面部出汗多'),
      (key: 'B', label: '胸口、后背出汗多'),
      (key: 'C', label: '全身均匀出汗'),
      (key: 'D', label: '仅手脚心出汗'),
    ],
  ),
  ConstitutionQuestion(
    id: 7,
    title: '出汗后身体感觉如何？',
    type: ConstitutionQuestionType.single,
    options: [
      (key: 'A', label: '出汗后舒服，不怕风'),
      (key: 'B', label: '出汗后更怕风，觉得难受'),
      (key: 'C', label: '出汗后疲劳乏力感加重'),
    ],
  ),
  ConstitutionQuestion(
    id: 8,
    title: '您是否有头晕、头痛或身体沉重的感觉？',
    type: ConstitutionQuestionType.single,
    options: [
      (key: 'A', label: '经常头晕'),
      (key: 'B', label: '经常头痛（需选择类型）'),
      (key: 'C', label: '身体沉重，像裹着湿衣服'),
      (key: 'D', label: '身体乏力，提不起劲'),
      (key: 'E', label: '四肢关节酸痛、麻木'),
      (key: 'F', label: '以上都没有'),
    ],
  ),
  ConstitutionQuestion(
    id: 9,
    section: '第三部分：二便（核心）',
    title: '您小便的通常颜色是？',
    type: ConstitutionQuestionType.single,
    options: [
      (key: 'A', label: '清亮如水'),
      (key: 'B', label: '淡黄色'),
      (key: 'C', label: '深黄色'),
      (key: 'D', label: '黄赤，甚至如茶色'),
    ],
  ),
  ConstitutionQuestion(
    id: 10,
    title: '您小便的量和感觉是？',
    type: ConstitutionQuestionType.single,
    options: [
      (key: 'A', label: '量多，次数多，色清'),
      (key: 'B', label: '量少，次数少，色黄'),
      (key: 'C', label: '排尿顺畅，无感'),
      (key: 'D', label: '排尿时有灼热或涩痛感'),
    ],
  ),
  ConstitutionQuestion(
    id: 11,
    title: '您大便最常见的质地是？',
    type: ConstitutionQuestionType.single,
    options: [
      (key: 'A', label: '干硬，成颗粒状'),
      (key: 'B', label: '成形，但黏腻，粘马桶不易冲净'),
      (key: 'C', label: '稀软，不成形，或像糊状'),
      (key: 'D', label: '时干时稀'),
      (key: 'E', label: '正常香蕉状，顺畅'),
    ],
  ),
  ConstitutionQuestion(
    id: 12,
    title: '您大便时的感觉是？',
    type: ConstitutionQuestionType.single,
    options: [
      (key: 'A', label: '顺畅，很快解完'),
      (key: 'B', label: '费力，排便困难'),
      (key: 'C', label: '排不干净，有下坠感'),
      (key: 'D', label: '肛门有灼热感'),
      (key: 'E', label: '腹部冷痛，遇冷加重'),
    ],
  ),
  ConstitutionQuestion(
    id: 13,
    section: '第四部分：饮食、睡眠、情绪精力',
    title: '您的胃口和消化情况如何？',
    type: ConstitutionQuestionType.single,
    options: [
      (key: 'A', label: '胃口好，消化快'),
      (key: 'B', label: '没胃口，不想吃'),
      (key: 'C', label: '容易饿，但吃一点就饱'),
      (key: 'D', label: '饭后容易腹胀、消化不良'),
      (key: 'E', label: '常有嗳气、反酸'),
    ],
  ),
  ConstitutionQuestion(
    id: 14,
    title: '您口渴的感觉和饮水偏好是？',
    type: ConstitutionQuestionType.single,
    options: [
      (key: 'A', label: '不觉得口渴，不想喝水'),
      (key: 'B', label: '口干，但只想用热水润一下'),
      (key: 'C', label: '口干，想喝冷饮或凉水'),
      (key: 'D', label: '口苦'),
      (key: 'E', label: '口中发甜/发黏'),
    ],
  ),
  ConstitutionQuestion(
    id: 15,
    title: '您的睡眠质量如何？',
    type: ConstitutionQuestionType.single,
    options: [
      (key: 'A', label: '入睡困难，思绪多'),
      (key: 'B', label: '睡眠浅，容易惊醒'),
      (key: 'C', label: '多梦，睡不踏实'),
      (key: 'D', label: '嗜睡，总睡不够'),
      (key: 'E', label: '总体还好'),
    ],
  ),
  ConstitutionQuestion(
    id: 16,
    title: '您白天的精力和情绪通常如何？',
    type: ConstitutionQuestionType.single,
    options: [
      (key: 'A', label: '精力充沛，情绪平和'),
      (key: 'B', label: '容易疲劳，气短乏力'),
      (key: 'C', label: '烦躁易怒，控制不住脾气'),
      (key: 'D', label: '情绪低落，思虑过多'),
      (key: 'E', label: '紧张焦虑，心神不宁'),
    ],
  ),
  ConstitutionQuestion(
    id: 17,
    section: '第五部分：胸腹、感官与经带（专项）',
    title: '您是否有以下胸部或腹部的不适？（可多选）',
    type: ConstitutionQuestionType.multi,
    options: [
      (key: 'A', label: '胸闷，喜欢叹气'),
      (key: 'B', label: '心慌、心悸（感觉心跳不正常）'),
      (key: 'C', label: '胁肋部（身体两侧）胀痛'),
      (key: 'D', label: '腹部胀满，不舒服'),
      (key: 'E', label: '腹痛，喜欢按压或热敷（喜按喜暖）'),
      (key: 'F', label: '腹痛，拒绝按压（拒按）'),
    ],
  ),
  ConstitutionQuestion(
    id: 18,
    title: '您的月经情况最接近以下哪种？',
    type: ConstitutionQuestionType.single,
    options: [
      (key: 'A', label: '周期准，量色正常，无不适'),
      (key: 'B', label: '周期推迟，量少，色暗'),
      (key: 'C', label: '周期提前，量多，色鲜红'),
      (key: 'D', label: '有血块，痛经明显'),
      (key: 'E', label: '经期乳房胀痛，情绪差'),
    ],
  ),
  ConstitutionQuestion(
    id: 19,
    title: '您的白带情况如何？',
    type: ConstitutionQuestionType.single,
    options: [
      (key: 'A', label: '量少，无明显感觉'),
      (key: 'B', label: '量多，色白，质稀'),
      (key: 'C', label: '量多，色黄，质稠，或有异味'),
    ],
  ),
  ConstitutionQuestion(
    id: 20,
    title: '性功能方面是否有以下情况？（可多选）',
    type: ConstitutionQuestionType.multi,
    options: [
      (key: 'a', label: '阳痿'),
      (key: 'b', label: '早泄'),
      (key: 'c', label: '敏感'),
      (key: 'd', label: '遗精'),
    ],
  ),
  ConstitutionQuestion(
    id: 21,
    section: '第六部分：诱因与补充',
    title: '您认为当前不适，与以下哪项关系最密切？（可多选）',
    type: ConstitutionQuestionType.multi,
    options: [
      (key: 'A', label: '受凉、吹风'),
      (key: 'B', label: '潮湿、闷热环境'),
      (key: 'C', label: '劳累过度'),
      (key: 'D', label: '情绪波动、压力大'),
      (key: 'E', label: '饮食不节（生冷、油腻、暴饮暴食）'),
      (key: 'F', label: '其他'),
    ],
  ),
];

ConstitutionQuestion? questionById(int id) {
  for (final q in constitutionQuestions) {
    if (q.id == id) return q;
  }
  return null;
}

/// 头痛子类型（第8题选 B 时必填其一）
const headacheSubOptions = <ConstitutionOption>[
  (key: '1', label: '胀痛'),
  (key: '2', label: '刺痛'),
  (key: '3', label: '昏沉痛'),
  (key: '4', label: '空痛'),
];
