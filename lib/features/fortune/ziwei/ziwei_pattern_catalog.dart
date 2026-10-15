enum ZiweiPatternCategory {
  imperial,
  luminary,
  academic,
  wealth,
  noble,
  challenging,
  timing,
}

class ZiweiPatternDefinition {
  const ZiweiPatternDefinition(
    this.code,
    this.name,
    this.category,
    this.condition, {
    this.aliases = const [],
    this.automatic = true,
  });

  final int code;
  final String name;
  final ZiweiPatternCategory category;
  final String condition;
  final List<String> aliases;

  /// 条件不完整的条目仍收录在目录中，但禁止向用户自动报格局。
  final bool automatic;
}

/// 用户确认的87项格局目录。这里只描述规则，不参与专业排盘计算。
const ziweiPatternCatalog = <ZiweiPatternDefinition>[
  ZiweiPatternDefinition(
      1, '紫府同宫格', ZiweiPatternCategory.imperial, '紫微、天府同在寅或申宫坐命'),
  ZiweiPatternDefinition(
      2, '紫府朝垣格', ZiweiPatternCategory.imperial, '命宫三方四正得庙旺紫微、天府合照'),
  ZiweiPatternDefinition(
      3, '天府朝垣格', ZiweiPatternCategory.imperial, '天府在戌宫坐命，三方得吉曜会照'),
  ZiweiPatternDefinition(
      4, '君臣庆会格', ZiweiPatternCategory.imperial, '紫微坐命，三方会天府、天相及辅弼昌曲等吉曜'),
  ZiweiPatternDefinition(
      5, '府相朝垣格', ZiweiPatternCategory.imperial, '命宫三方四正会照天府、天相'),
  ZiweiPatternDefinition(
      6, '极向离明格', ZiweiPatternCategory.imperial, '紫微在午宫坐命，无煞冲破并加吉曜'),
  ZiweiPatternDefinition(
      7, '辅弼拱主格', ZiweiPatternCategory.imperial, '紫微坐命，左辅右弼三方会照或夹命'),
  ZiweiPatternDefinition(8, '金灿光辉格', ZiweiPatternCategory.luminary, '太阳在午宫坐命',
      aliases: ['日丽中天格']),
  ZiweiPatternDefinition(
      9, '日照雷门格', ZiweiPatternCategory.luminary, '太阳在卯宫坐命，白天生人更佳',
      aliases: ['日出扶桑格']),
  ZiweiPatternDefinition(
      10, '月朗天门格', ZiweiPatternCategory.luminary, '太阴在亥宫坐命，夜生更佳'),
  ZiweiPatternDefinition(11, '月生沧海格', ZiweiPatternCategory.luminary, '太阴在辰宫坐命',
      aliases: ['水澄桂萼格']),
  ZiweiPatternDefinition(
      12, '日月并明格', ZiweiPatternCategory.luminary, '命宫在丑，太阳在巳、太阴在酉拱照；或太阳辰、太阴戌'),
  ZiweiPatternDefinition(
      13, '明珠出海格', ZiweiPatternCategory.luminary, '命宫在未且无主星，太阳卯、太阴亥三方照命'),
  ZiweiPatternDefinition(
      14, '日月同宫格', ZiweiPatternCategory.luminary, '命宫在丑或未，太阳、太阴同宫坐守'),
  ZiweiPatternDefinition(
      15, '日月夹命格', ZiweiPatternCategory.luminary, '命宫被太阳、太阴两星夹辅'),
  ZiweiPatternDefinition(
      16, '日月照壁格', ZiweiPatternCategory.luminary, '太阳、太阴在田宅宫或三方会照田宅'),
  ZiweiPatternDefinition(
      17, '丹墀桂墀格', ZiweiPatternCategory.luminary, '太阳、太阴在庙旺之地会照命宫'),
  ZiweiPatternDefinition(
      18, '日月反背格', ZiweiPatternCategory.challenging, '太阳、太阴均落陷且不得吉曜救应'),
  ZiweiPatternDefinition(
      19, '阳梁昌禄格', ZiweiPatternCategory.academic, '命宫三方四正会齐太阳、天梁、文昌、禄存或化禄'),
  ZiweiPatternDefinition(
      20, '机月同梁格', ZiweiPatternCategory.academic, '命宫三方四正会齐天机、太阴、天同、天梁'),
  ZiweiPatternDefinition(
      21, '机梁加会格', ZiweiPatternCategory.academic, '天机、天梁在辰或戌宫坐命',
      aliases: ['善荫朝纲格']),
  ZiweiPatternDefinition(
      22, '文梁振纪格', ZiweiPatternCategory.academic, '文昌或文曲与天梁同宫或在命宫三方会照'),
  ZiweiPatternDefinition(
      23, '文桂文华格', ZiweiPatternCategory.academic, '文昌、文曲在命宫，且为卯或酉时生人'),
  ZiweiPatternDefinition(
      24, '辅拱文星格', ZiweiPatternCategory.academic, '文昌坐命，得左辅、右弼拱照'),
  ZiweiPatternDefinition(
      25, '禄文拱命格', ZiweiPatternCategory.academic, '禄存与文昌、文曲拱照命宫'),
  ZiweiPatternDefinition(
      26, '科名会禄格', ZiweiPatternCategory.academic, '化科星与禄存会合于命宫三方',
      aliases: ['甲第登庙格']),
  ZiweiPatternDefinition(
      27, '廉贞文武格', ZiweiPatternCategory.academic, '廉贞坐命，三方会文昌、文曲、左辅、右弼'),
  ZiweiPatternDefinition(
      28, '文星拱命格', ZiweiPatternCategory.academic, '文昌、文曲出现在命宫三方四正'),
  ZiweiPatternDefinition(
      29, '三合火贪格', ZiweiPatternCategory.wealth, '贪狼遇火星在命宫或三方会照',
      aliases: ['火贪格']),
  ZiweiPatternDefinition(
      30, '贪铃朝垣格', ZiweiPatternCategory.wealth, '贪狼遇铃星在命宫或三方会照',
      aliases: ['铃贪格']),
  ZiweiPatternDefinition(
      31, '雄宿朝垣格', ZiweiPatternCategory.wealth, '廉贞在寅或申宫入命并逢吉曜',
      aliases: ['雄宿乾元格']),
  ZiweiPatternDefinition(32, '将星得地格', ZiweiPatternCategory.wealth, '武曲在辰或戌宫坐命'),
  ZiweiPatternDefinition(
      33, '贪武同行格', ZiweiPatternCategory.wealth, '武曲、贪狼在丑或未宫坐命',
      aliases: ['武贪守身格']),
  ZiweiPatternDefinition(
      34, '禄马交驰格', ZiweiPatternCategory.wealth, '禄存与天马同宫或在命宫三方会照',
      aliases: ['禄马佩印格']),
  ZiweiPatternDefinition(
      35, '双禄朝垣格', ZiweiPatternCategory.wealth, '禄存与化禄同宫、六合，或分守命财官',
      aliases: ['禄合鸳鸯格']),
  ZiweiPatternDefinition(
      36, '明禄暗禄格', ZiweiPatternCategory.wealth, '命宫有明禄，暗合宫有暗禄或化科',
      aliases: ['科明暗禄格']),
  ZiweiPatternDefinition(
      37, '财禄夹马格', ZiweiPatternCategory.wealth, '天马坐命，命宫被禄存和化禄夹辅'),
  ZiweiPatternDefinition(
      38, '擎羊入庙格', ZiweiPatternCategory.wealth, '擎羊坐命于丑、辰、未、戌四墓库'),
  ZiweiPatternDefinition(
      39, '天乙拱命格', ZiweiPatternCategory.noble, '命宫和迁移宫分别坐天魁、天钺',
      aliases: ['坐贵向贵格']),
  ZiweiPatternDefinition(
      40, '贵星夹命格', ZiweiPatternCategory.noble, '命宫被天魁天钺或左辅右弼夹辅'),
  ZiweiPatternDefinition(
      41, '三奇嘉会格', ZiweiPatternCategory.noble, '命财官迁三方四正会齐化禄、化权、化科',
      aliases: ['三奇加会格']),
  ZiweiPatternDefinition(
      42, '权禄巡逢格', ZiweiPatternCategory.noble, '化禄与化权在命宫三方四正会合'),
  ZiweiPatternDefinition(
      43, '科权禄夹格', ZiweiPatternCategory.noble, '命宫被化科、化权、化禄中的两种夹辅'),
  ZiweiPatternDefinition(
      44, '左右同宫格', ZiweiPatternCategory.noble, '左辅、右弼同宫于命宫或命宫三方'),
  ZiweiPatternDefinition(45, '寿星入庙格', ZiweiPatternCategory.noble, '天梁在午宫入命'),
  ZiweiPatternDefinition(46, '英星入庙格', ZiweiPatternCategory.noble, '破军在子或午宫入命'),
  ZiweiPatternDefinition(
      47, '七杀朝斗格', ZiweiPatternCategory.noble, '七杀在寅、申、子或午宫入命'),
  ZiweiPatternDefinition(
      48, '石中隐玉格', ZiweiPatternCategory.noble, '巨门在子或午宫坐命，逢化科、化权、化禄或禄存'),
  ZiweiPatternDefinition(
      49, '巨日同宫格', ZiweiPatternCategory.noble, '巨门、太阳在寅或申宫同宫坐命'),
  ZiweiPatternDefinition(
      50, '巨机同临格', ZiweiPatternCategory.noble, '巨门、天机在卯或酉宫同宫坐命',
      aliases: ['巨机同宫格']),
  ZiweiPatternDefinition(
      51, '权煞化禄格', ZiweiPatternCategory.noble, '权星与煞星同宫，并得化禄救应'),
  ZiweiPatternDefinition(
      52, '化星返贵格', ZiweiPatternCategory.noble, '特定星曜于特定宫位化科权禄',
      aliases: ['化星还贵格'], automatic: false),
  ZiweiPatternDefinition(
      53, '命无正曜格', ZiweiPatternCategory.challenging, '命宫无十四正曜主星'),
  ZiweiPatternDefinition(
      54, '极居卯酉格', ZiweiPatternCategory.challenging, '紫微、贪狼在卯或酉坐命',
      aliases: ['桃花犯主格']),
  ZiweiPatternDefinition(
      55, '杀拱廉贞格', ZiweiPatternCategory.challenging, '七杀拱照廉贞，组合失和'),
  ZiweiPatternDefinition(
      56, '巨逢四煞格', ZiweiPatternCategory.challenging, '巨门与擎羊、陀罗、火星、铃星同宫或会照'),
  ZiweiPatternDefinition(
      57, '马头带剑格', ZiweiPatternCategory.challenging, '午宫安命值擎羊，并会天马',
      aliases: ['马头带箭格']),
  ZiweiPatternDefinition(
      58, '命里逢空格', ZiweiPatternCategory.challenging, '命宫逢地空、地劫'),
  ZiweiPatternDefinition(
      59, '劫空夹命格', ZiweiPatternCategory.challenging, '命宫被地空、地劫夹辅'),
  ZiweiPatternDefinition(
      60, '羊陀夹忌格', ZiweiPatternCategory.challenging, '命宫化忌被擎羊、陀罗夹辅'),
  ZiweiPatternDefinition(
      61, '火铃夹命格', ZiweiPatternCategory.challenging, '命宫被火星、铃星夹辅'),
  ZiweiPatternDefinition(
      62, '刑囚夹印格', ZiweiPatternCategory.challenging, '天相坐命，被擎羊与廉贞夹辅'),
  ZiweiPatternDefinition(
      63, '刑忌夹印格', ZiweiPatternCategory.challenging, '天相坐命，被化忌与天刑夹辅'),
  ZiweiPatternDefinition(
      64, '文星失位格', ZiweiPatternCategory.challenging, '文昌、文曲落陷、逢煞或被恶星夹辅',
      aliases: ['文星遇夹格']),
  ZiweiPatternDefinition(
      65, '科星煞凑格', ZiweiPatternCategory.challenging, '化科星被煞星同宫或会照冲破',
      aliases: ['科星逢破格']),
  ZiweiPatternDefinition(
      66, '魁钺凶冲格', ZiweiPatternCategory.challenging, '天魁、天钺被空劫或煞星冲破'),
  ZiweiPatternDefinition(
      67, '月同遇煞格', ZiweiPatternCategory.challenging, '太阴、天同同宫或会照煞曜'),
  ZiweiPatternDefinition(
      68, '日月藏辉格', ZiweiPatternCategory.challenging, '太阳、太阴落陷或同时受煞'),
  ZiweiPatternDefinition(
      69, '马落空亡格', ZiweiPatternCategory.challenging, '天马与地空、地劫、旬空或截空同宫'),
  ZiweiPatternDefinition(
      70, '梁马飘荡格', ZiweiPatternCategory.challenging, '天梁与天马同宫或在命宫三方会照'),
  ZiweiPatternDefinition(
      71, '巨机化酉格', ZiweiPatternCategory.challenging, '巨门、天机在酉宫坐命'),
  ZiweiPatternDefinition(
      72, '禄逢两煞格', ZiweiPatternCategory.challenging, '禄存坐命并被擎羊、陀罗夹击'),
  ZiweiPatternDefinition(
      73, '天机天梁擎羊会', ZiweiPatternCategory.challenging, '天机天梁在辰戌坐命，加会擎羊',
      aliases: ['刑曜格']),
  ZiweiPatternDefinition(
      74, '昌贪曲贪格', ZiweiPatternCategory.challenging, '贪狼与文昌或文曲同宫或会照'),
  ZiweiPatternDefinition(
      75, '财与囚仇格', ZiweiPatternCategory.challenging, '武曲与廉贞同宫或会照且组合受煞'),
  ZiweiPatternDefinition(
      76, '生不逢时格', ZiweiPatternCategory.challenging, '吉曜落陷、煞忌当道的综合结构',
      aliases: ['君子在野格'], automatic: false),
  ZiweiPatternDefinition(
      77, '两重华盖格', ZiweiPatternCategory.challenging, '命宫三方四正重复见华盖或空亡类星曜'),
  ZiweiPatternDefinition(
      78, '路上埋尸格', ZiweiPatternCategory.challenging, '特定恶煞组合',
      automatic: false),
  ZiweiPatternDefinition(
      79, '君臣不义格', ZiweiPatternCategory.challenging, '君臣星系受煞忌导致组合失和',
      automatic: false),
  ZiweiPatternDefinition(
      80, '巨火擎羊格', ZiweiPatternCategory.challenging, '巨门坐命，火星、擎羊同宫或会照'),
  ZiweiPatternDefinition(
      81, '衣锦还乡格', ZiweiPatternCategory.timing, '离乡发展后在中年吉运有所成果的运限格',
      automatic: false),
  ZiweiPatternDefinition(
      82, '禄衰马困格', ZiweiPatternCategory.timing, '运限禄马衰败且无吉曜救应',
      aliases: ['步数无依格'], automatic: false),
  ZiweiPatternDefinition(83, '水上架屋格', ZiweiPatternCategory.timing, '运限虚空不实之象',
      automatic: false),
  ZiweiPatternDefinition(
      84, '枯木逢春格', ZiweiPatternCategory.timing, '原局受制而在运限逢吉复苏',
      automatic: false),
  ZiweiPatternDefinition(85, '风云际会格', ZiweiPatternCategory.timing, '运限吉星聚集会照',
      automatic: false),
  ZiweiPatternDefinition(
      86, '锦上添花格', ZiweiPatternCategory.timing, '原局成格，运限再得吉化',
      automatic: false),
  ZiweiPatternDefinition(
      87, '失格杂录格', ZiweiPatternCategory.timing, '格局因煞忌冲破而不纯，吉凶混杂',
      aliases: ['吉凶相伴格'], automatic: false),
];
