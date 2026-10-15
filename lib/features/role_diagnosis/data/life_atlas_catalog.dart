import '../models/life_atlas_models.dart';

LifeAtlasQuestion _question(
  String id,
  LifeAtlasDomain domain,
  String question,
  String quote,
  String titles, {
  bool sensitive = false,
}) {
  return LifeAtlasQuestion(
    id: id,
    domain: domain,
    question: question,
    quote: quote,
    titles: titles.split('|'),
    sensitive: sensitive,
  );
}

/// 每一项真实经历都配置 11 个原创称号版本。48 项经历共 528 个基础称号，
/// 再叠加命盘底色与交汇称号；八字只负责在同一真实经历中选择表达，不会
/// 反推或捏造用户没有确认过的人生事实。
final List<LifeAtlasQuestion> lifeAtlasQuestions = [
  _question(
      'career_start',
      LifeAtlasDomain.career,
      '你是否真正创过业、开过店，或独立经营过一门生意？',
      '上一代没有留下地图，你决定让自己成为起点。',
      '白手成局|创一代|从零开张|自己做东|无图开路|第一块招牌|以身入局|生意起于我|空手搭台|一人成军|开局者'),
  _question(
      'career_side',
      LifeAtlasDomain.career,
      '你是否把下班后的副业，做成过稳定收入或正式事业？',
      '你在下班后点起的那盏灯，后来成了自己的招牌。',
      '副业转正|第二曲线|夜航成岸|下班后开局|暗线生长|双栖生存者|业余不业余|灯下创业者|侧翼突围|另一份答案|时间炼金者'),
  _question(
      'career_change',
      LifeAtlasDomain.career,
      '你是否主动离开熟悉行业，完成过一次跨行或职业重启？',
      '你没有困在已经会的事情里，而是重新学习如何出发。',
      '跨界重启|半路换轨|职业换骨|再选一次|离岸转身|重开职业线|换道超车|陌生赛道来客|第二身份|旧履历作废|人生转岗者'),
  _question(
      'career_lead',
      LifeAtlasDomain.career,
      '你是否独立带成过团队、项目，或为一个重要结果负责到底？',
      '真正的担当，不是站在最前面，而是最后一个离场。',
      '成事主理人|幕后操盘手|项目定海针|结果负责人|团队掌舵者|最后离场的人|把事做成|局面收束者|扛旗的人|全链控制者|交付守门人'),
  _question(
      'career_rebuild',
      LifeAtlasDomain.career,
      '你是否经历过失业、项目失败或事业停摆后重新开始？',
      '工作暂时停了，你的人生没有。',
      '失业不失速|废墟重开|事业复燃|停摆后起航|从失败里返场|重新上桌|逆风复工|断档续写者|归零再战|谷底开工|事业二次点火'),
  _question(
      'career_craft',
      LifeAtlasDomain.career,
      '你是否在一个专业或手艺上持续投入了五年以上？',
      '没有一夜成名，只有把同一件事做过许多个夜晚。',
      '长期磨剑者|一技成山|五年深耕|手艺守夜人|专业钉子户|慢功夫赢家|把时间做厚|领域老兵|深水区行者|重复的力量|一事终成'),
  _question(
      'wealth_first',
      LifeAtlasDomain.wealth,
      '你是否靠自己赚到过一笔真正改变生活的收入？',
      '那不只是钱，是你第一次确认自己能够改变生活。',
      '第一桶金|现金破晓|收入跃迁者|自挣底气|第一次变富|能力兑现|钱包翻身仗|财富起跑线|靠自己买单|价值落袋|收入开门红'),
  _question(
      'wealth_debt',
      LifeAtlasDomain.wealth,
      '你是否经历过债务或严重资金压力，并已经还清或持续走出？',
      '你曾被数字压得喘不过气，最后还是一笔一笔拿回了生活。',
      '负债归零|账单突围者|现金流复健|债务上岸|数字松绑|从欠到有|还清一座山|财务止血者|重新有余额|账本翻篇|上岸以后',
      sensitive: true),
  _question(
      'wealth_save',
      LifeAtlasDomain.wealth,
      '你是否从月光或冲动消费，变成了能稳定储蓄的人？',
      '你不再用明天的钱，安慰今天的情绪。',
      '月光终结者|存款生长者|消费清醒|钱包守门人|余额培育师|慢慢有钱|储蓄觉醒|克制换自由|财务打底者|先存下自己|现金垫高者'),
  _question(
      'wealth_invest',
      LifeAtlasDomain.wealth,
      '你是否用自己的钱经历过完整的投资涨跌周期？',
      '家里没人教你认识涨跌，你用自己的钱读懂了周期。',
      '股一代|周期读者|市场交过学费|波动幸存者|独立投资人|涨跌见证者|仓位修行者|风险启蒙者|K线成年礼|牛熊过客|本金守望者',
      sensitive: true),
  _question(
      'wealth_support',
      LifeAtlasDomain.wealth,
      '你是否长期承担家庭主要开支，或成为家人的经济支柱？',
      '你的收入不只属于自己，也托住了身后的一盏盏灯。',
      '家庭现金流|收入顶梁柱|为家买单的人|生活供给者|账单背后的你|一人养一城|家庭财务舵手|薪水有去处|身后有灯|养家主力|经济后盾',
      sensitive: true),
  _question(
      'wealth_asset',
      LifeAtlasDomain.wealth,
      '你是否靠自己完成过买房、置业或其他重要资产积累？',
      '你把许多个普通日子，慢慢换成了一处安稳。',
      '全款置业者|第一套房|安稳落地|资产筑基|一砖一瓦靠自己|钥匙到手|生活有锚|家的持有人|长期主义买家|落脚资本|把漂泊买下',
      sensitive: true),
  _question(
      'love_long',
      LifeAtlasDomain.love,
      '你是否与一个人彼此选择，并认真同行了五年以上？',
      '世界给过你们许多分开的理由，你们还是把彼此选了回来。',
      '双向坚定|长期爱人|五年同行者|反复选择你|守住热爱|两个人的长期主义|关系合伙人|相爱耐力赛|共同生活家|时间作证|爱有回音',
      sensitive: true),
  _question(
      'love_leave',
      LifeAtlasDomain.love,
      '你是否主动结束过一段长期消耗你的关系？',
      '离开不是失败，是你终于不再把自己留在原地。',
      '清醒离场|止损爱人|关系断舍离|把自己带走|告别消耗|不再等回头|爱里自救者|边界觉醒|终于转身|离开也勇敢|从关系里上岸',
      sensitive: true),
  _question(
      'love_restart',
      LifeAtlasDomain.love,
      '你是否在一段重要关系结束后，重新相信过爱或自己？',
      '你没有忘记受过的伤，只是不再让它决定余生。',
      '重新相信|爱后重生|心门复开|伤后有春|再次心动者|关系复健|把爱捡回来|温柔返场|心动二周目|旧伤新生|仍敢相爱',
      sensitive: true),
  _question(
      'love_single',
      LifeAtlasDomain.love,
      '你是否有过两年以上主动单身，并把生活过得完整？',
      '你没有等谁来补全，而是先把自己的生活过成了答案。',
      '完整单身者|一人也丰盛|独自圆满|不凑合的人|单身长期主义|自给自足的爱|关系留白者|一个人的完整版|宁缺毋滥|先爱自己|独处有光'),
  _question(
      'love_distance',
      LifeAtlasDomain.love,
      '你是否认真维系过一段异地关系？',
      '距离把见面变少，却也让每一次奔赴有了重量。',
      '跨城奔赴|异地守望者|公里之外爱你|双城恋人|车票作证|远距离坚定|地图上的两颗心|时差爱人|奔赴有回程|见面倒计时|距离耐力赛',
      sensitive: true),
  _question(
      'love_boundary',
      LifeAtlasDomain.love,
      '你是否学会在亲密关系中明确表达边界和需求？',
      '成熟不是不需要爱，而是终于敢说自己怎样被爱。',
      '边界建立者|会说需要|关系清醒者|爱里有自己|停止猜心|沟通升级者|不再委屈求全|亲密有尺度|需求发声者|温柔有边界|爱己及人'),
  _question(
      'family_support',
      LifeAtlasDomain.family,
      '你是否在家庭困难时期，成为大家主要依靠的人？',
      '你也想倒下，可身后的人还在等你站着。',
      '活成后盾|家中顶梁|家庭定海针|最后的依靠|撑伞的人|一家人的底气|不敢倒下的人|风雨守门人|家中主心骨|把家托住|沉默支柱',
      sensitive: true),
  _question(
      'family_firstgen',
      LifeAtlasDomain.family,
      '你是否成为家里第一位大学生、创业者或某种职业开拓者？',
      '你走过的陌生路，会变成后来人的路标。',
      '家族第一人|代际开路者|第一张新地图|从我开始|后来人的路标|家门新章|首位抵达者|代际破圈|家族新坐标|没有前例的人|起点改写者'),
  _question(
      'family_care',
      LifeAtlasDomain.family,
      '你是否长期照顾过孩子、老人或生病的家人？',
      '有些爱没有掌声，只藏在日复一日的照料里。',
      '照料守夜人|家庭护理者|长久陪护|日常英雄|无声照看者|把爱做成小事|耐心持有人|家人身边的人|岁月照料师|长情陪伴者|温柔值守',
      sensitive: true),
  _question(
      'family_breakcycle',
      LifeAtlasDomain.family,
      '你是否主动改变过原生家庭中不健康的相处模式？',
      '你没有把受过的伤，继续交给下一代。',
      '代际止损者|家族破局人|伤害到此为止|旧模式终结者|关系改写者|不再复制过去|家庭新规则|代际清醒|把循环截断|新一代答案|温柔革命者',
      sensitive: true),
  _question(
      'family_home',
      LifeAtlasDomain.family,
      '你是否离家多年后，重新选择回乡、陪伴或建设家乡？',
      '走过很远以后，你把新的自己带回了来处。',
      '归乡重启|带着世界回家|故土新生|返乡建设者|回家不是退场|来处再出发|归根开新局|故乡合伙人|回程有方向|家门再开|返乡主理人'),
  _question(
      'family_responsibility',
      LifeAtlasDomain.family,
      '你是否很早就开始分担家庭责任，比同龄人更早懂事？',
      '别人还在被照顾的年纪，你已经学会照顾生活。',
      '提前懂事|少年担当|早熟支撑者|长大得太早|小小顶梁柱|先学会负责|童年加速者|家务合伙人|懂事没有假期|年少扛事|提早上场',
      sensitive: true),
  _question(
      'growth_low',
      LifeAtlasDomain.growth,
      '你是否独自熬过一段很少有人知道的低谷？',
      '最暗的日子没有杀死你，反而让你学会了自己发光。',
      '低谷里开花|命硬一回|暗处发光者|无人接住|自己上岸|黑夜毕业生|谷底幸存者|独自渡劫|深处生根|没有提前退场|从暗夜返场',
      sensitive: true),
  _question(
      'growth_exam',
      LifeAtlasDomain.growth,
      '你是否在一次重要失败后，重新准备并完成了第二次挑战？',
      '第一次没有答对的题，你后来用了很久重新作答。',
      '人生补考|二次应战|再考一次|失败重修者|重做这道题|第二次抵达|复盘后返场|不服输的后来|重新交卷|改写第一次|再战成章'),
  _question(
      'growth_solo',
      LifeAtlasDomain.growth,
      '你是否在没有支持和资源的情况下，独自完成过一件大事？',
      '没有人为你开门，你就学会了自己造一扇门。',
      '孤身成事|无援开局|一人破阵|自己造门|零资源突围|单兵作战者|没有靠山的人|空手抵达|独行成章|一己之力|自带梯子'),
  _question(
      'growth_failure',
      LifeAtlasDomain.growth,
      '你是否公开失败、被否定或被嘲笑后，仍继续做自己的选择？',
      '你见过旁人的目光，最后还是把方向交还给自己。',
      '被否定后继续|逆评而行|不靠掌声|嘲声之外|自我裁判者|不被定义|争议中生长|方向归己|冷眼通关者|没有取悦世界|偏要走下去'),
  _question(
      'growth_recover',
      LifeAtlasDomain.growth,
      '你是否在生活失序后，一点点重新建立作息、工作和日常？',
      '你没有突然变好，只是每天把自己捡回来一点。',
      '生活重建者|把日子捡回来|秩序复原|缓慢归位|日常修复师|一点点变好|重新过生活|微小复苏|自救进行时|生活重装|恢复出厂设置'),
  _question(
      'growth_choice',
      LifeAtlasDomain.growth,
      '你是否做过一个不被多数人理解、但后来证明适合自己的决定？',
      '你没有走大家都懂的路，却走到了自己的答案。',
      '少数派选择|自选人生|离开标准答案|不合群的正确|独立决定者|逆向人生|自己的路标|拒绝默认设置|偏航抵达|不按剧本|选择作证'),
  _question(
      'health_sleep',
      LifeAtlasDomain.health,
      '你是否从长期熬夜或失眠中，重新找回较稳定的睡眠？',
      '你终于不再用深夜，惩罚白天没有过好的人生。',
      '重新会睡|睡眠复健者|深夜和解|关灯以后|作息归岸|夜晚还给身体|不再透支黑夜|好眠重启|早睡练习生|睡意失而复得|把夜还给梦',
      sensitive: true),
  _question(
      'health_routine',
      LifeAtlasDomain.health,
      '你是否持续半年以上保持运动、规律饮食或健康习惯？',
      '真正改变你的，不是某次用力，而是那些没有中断的普通日子。',
      '长期自律者|日常复利|习惯持有人|半年不断线|生活训练家|规律的力量|身体长期主义|普通日子的胜利|坚持成形|健康打卡毕业生|稳定胜过热血'),
  _question(
      'health_overwork',
      LifeAtlasDomain.health,
      '你是否经历过过度工作或连续透支，并开始主动调整？',
      '你曾拿身体换进度，后来终于明白自己不是耗材。',
      '透支到期|停止燃烧自己|身体不是耗材|过劳止损者|从忙碌中撤退|精力守门人|工作边界重建|不再硬撑|休息合法化|告别连轴转|把命还给生活',
      sensitive: true),
  _question(
      'health_sport',
      LifeAtlasDomain.health,
      '你是否通过运动完成过一次明显的身体或精神状态改变？',
      '你不是突然热爱运动，只是终于决定把力量还给自己。',
      '运动重启者|身体翻盘|汗水复健|力量归来|跑出低谷|肌肉记得你|重新有劲|体能回春|运动救场|把自己练回来|身体觉醒者'),
  _question(
      'health_recover',
      LifeAtlasDomain.health,
      '你是否经历过一段身体不适、手术或康复期，并认真走过恢复过程？',
      '恢复不是回到从前，而是学会用新的方式照顾自己。',
      '康复长跑者|身体重建|恢复期毕业生|慢慢好起来|带着痕迹前行|生命修复师|复原进行时|身体二次生长|从病床到日常|重新站稳|恢复有期',
      sensitive: true),
  _question(
      'health_selfcare',
      LifeAtlasDomain.health,
      '你是否开始定期体检、记录状态，并主动照顾自己的身体？',
      '你不再等身体大声求救，才想起听见它。',
      '身体倾听者|自我照料师|健康有档案|提前关心自己|状态记录员|体检行动派|身体合伙人|照顾自己这件事|生命维护者|不等警报|主动养护者'),
  _question(
      'social_few',
      LifeAtlasDomain.social,
      '你是否拥有一段超过十年的稳定友谊？',
      '你们见过彼此许多版本，仍然愿意留在对方的人生里。',
      '十年知己|长期朋友|旧友仍在|岁月合伙人|友情长跑者|彼此见证人|多年如初|老友记|关系常青树|时间留下的人|知己有期'),
  _question(
      'social_help',
      LifeAtlasDomain.social,
      '你是否在别人最困难的时候，真正陪伴或帮助过对方？',
      '你没有替他走完那段路，却让那段路不再只有一个人。',
      '接住过别人|心灵支点|低谷陪跑者|为人撑伞|善意有行动|朋友的岸|陪他走一段|关系救生圈|雪中送炭|温暖传递者|有人因你不孤单'),
  _question(
      'social_leave',
      LifeAtlasDomain.social,
      '你是否主动离开过一段反复消耗、失衡或伤害你的友情？',
      '结束一段友情也会痛，但你终于不再拿真心填无底洞。',
      '友情止损|关系清仓|离开烂关系|朋友也要边界|不再单向付出|社交断舍离|告别消耗者|真心不再贱卖|关系退出键|友情毕业生|把热情收回',
      sensitive: true),
  _question(
      'social_introvert',
      LifeAtlasDomain.social,
      '你是否从害怕社交，成长到能够独立表达、沟通或公开发言？',
      '你不是变得外向，而是终于不再让害怕替你说话。',
      '社恐营业|表达破冰者|人群里开口|公开发声者|从沉默到清晰|社交升级|不再躲在最后|沟通成年礼|声音被听见|内向突围|开口有力量'),
  _question(
      'social_reconcile',
      LifeAtlasDomain.social,
      '你是否与一位重要朋友经历误会、分开后又认真和解？',
      '真正的和解不是当作没发生，而是愿意重新理解彼此。',
      '友情复航|和解以后|重修旧好|误会退场|关系二次开机|朋友再见面|把话说开|旧谊返场|理解迟到但到|重新握手|友谊补丁'),
  _question(
      'social_community',
      LifeAtlasDomain.social,
      '你是否组织过社群、团队或活动，让一群陌生人彼此连接？',
      '你做的不只是聚集人群，而是让一些人从此认识彼此。',
      '关系织网者|社群发起人|人群连接器|组局成事|朋友制造者|场域主理人|同频召集人|把陌生变熟悉|关系建筑师|聚光成群|社交引力场'),
  _question(
      'journey_city',
      LifeAtlasDomain.journey,
      '你是否独自在异乡生活、工作超过三年？',
      '这座城市没有答应你什么，你却把最好的几年押在了这里。',
      '异乡扎根|城市长期玩家|漂泊有岸|他乡建设者|三年远行人|把陌生住熟|城市候鸟停驻|远方生根|外地生活家|异乡不异客|新城居民'),
  _question(
      'journey_abroad',
      LifeAtlasDomain.journey,
      '你是否有过长期海外学习、工作或生活经历？',
      '跨过的不只是国界，还有曾经以为世界只有一种样子的自己。',
      '海外打卡者|跨国生活家|时差居民|世界第二住址|越界生长|异国长期玩家|远洋之后|跨文化行者|地图展开的人|地球通勤者|世界见习生'),
  _question(
      'journey_return',
      LifeAtlasDomain.journey,
      '你是否离开大城市或海外，主动回到家乡重新开始？',
      '回去不是认输，是你终于知道自己想把生活放在哪里。',
      '回乡重启|归来开新局|离城返航|故土二周目|回家创业者|逆向迁徙|归乡生活家|把远方带回来|返乡新青年|回程有野心|故乡再出发'),
  _question(
      'journey_solo',
      LifeAtlasDomain.journey,
      '你是否完成过一次真正意义上的独自旅行？',
      '那段路没有同伴替你记住，却让你第一次完整地陪伴自己。',
      '独行远方|一个人的地图|单人出发|独旅成年礼|自己的旅伴|远方独白|孤身看世界|一人一程|独自抵达|与自己同行|单程自由者'),
  _question(
      'journey_move',
      LifeAtlasDomain.journey,
      '你是否为了新的生活，独立完成过跨城市搬迁？',
      '你把生活装进箱子，也把未来搬到了另一个坐标。',
      '城市迁徙者|跨城重装|坐标刷新|搬家即重生|新城开机|生活换地址|带着未来迁徙|一箱人生|城市切换者|地图重置|搬向下一章'),
  _question(
      'journey_root',
      LifeAtlasDomain.journey,
      '你是否在一个原本陌生的地方建立了稳定关系、事业或家庭？',
      '后来让你安定的地方，起初连一盏熟悉的灯都没有。',
      '远方成家|陌生地生根|新故乡建造者|他乡有家|漂泊终成岸|异地安家者|从过客到主人|远方落地|第二故乡|把他乡活成家|扎根成功'),
];

const List<LifeAtlasHiddenRule> lifeAtlasHiddenRules = [
  LifeAtlasHiddenRule(
      id: 'cross_city_founder',
      requiredQuestionIds: ['career_start', 'journey_city'],
      title: '异乡开局',
      quote: '你没有带着答案来到这座城，却在这里开出了自己的局。',
      domain: LifeAtlasDomain.career),
  LifeAtlasHiddenRule(
      id: 'second_fire',
      requiredQuestionIds: ['career_start', 'career_rebuild'],
      title: '二次点火',
      quote: '第一次教会你如何开始，第二次教会你为什么不能停。',
      domain: LifeAtlasDomain.career),
  LifeAtlasHiddenRule(
      id: 'after_debt_founder',
      requiredQuestionIds: ['wealth_debt', 'career_start'],
      title: '逆债开局',
      quote: '你先把过去一笔笔还清，又替未来开了一扇门。',
      domain: LifeAtlasDomain.wealth),
  LifeAtlasHiddenRule(
      id: 'freedom_builder',
      requiredQuestionIds: ['wealth_save', 'wealth_asset'],
      title: '安稳建造师',
      quote: '你不是突然拥有安稳，只是很久以前就开始为它存下今天。',
      domain: LifeAtlasDomain.wealth),
  LifeAtlasHiddenRule(
      id: 'love_after_low',
      requiredQuestionIds: ['growth_low', 'love_restart'],
      title: '仍敢相爱',
      quote: '你见过最暗的自己，仍愿意把真心交给明天。',
      domain: LifeAtlasDomain.love),
  LifeAtlasHiddenRule(
      id: 'long_distance',
      requiredQuestionIds: ['love_long', 'love_distance'],
      title: '万里同心',
      quote: '距离拉长了路，却没有缩短你们一次次选择彼此的决心。',
      domain: LifeAtlasDomain.love),
  LifeAtlasHiddenRule(
      id: 'cycle_guardian',
      requiredQuestionIds: ['family_breakcycle', 'family_care'],
      title: '温柔截流者',
      quote: '你照顾的不只是眼前的人，也是不再被旧伤抵达的后来。',
      domain: LifeAtlasDomain.family),
  LifeAtlasHiddenRule(
      id: 'family_pioneer',
      requiredQuestionIds: ['family_firstgen', 'career_start'],
      title: '家门新坐标',
      quote: '你把自己走过的路，变成了家族地图上新的方向。',
      domain: LifeAtlasDomain.family),
  LifeAtlasHiddenRule(
      id: 'body_return',
      requiredQuestionIds: ['health_overwork', 'health_routine'],
      title: '把命还给生活',
      quote: '你不再以透支证明努力，而是让每一天都可以持续。',
      domain: LifeAtlasDomain.health),
  LifeAtlasHiddenRule(
      id: 'night_return',
      requiredQuestionIds: ['health_sleep', 'growth_recover'],
      title: '清晨归还者',
      quote: '你把无数个失序的夜晚，慢慢换回了可以醒来的清晨。',
      domain: LifeAtlasDomain.health),
  LifeAtlasHiddenRule(
      id: 'support_network',
      requiredQuestionIds: ['family_support', 'social_help'],
      title: '人间承重墙',
      quote: '你不是天生不会累，只是很多人因为你才没有倒下。',
      domain: LifeAtlasDomain.family),
  LifeAtlasHiddenRule(
      id: 'voice_gatherer',
      requiredQuestionIds: ['social_introvert', 'social_community'],
      title: '从沉默到召集',
      quote: '曾经不敢开口的你，后来让一群人的声音被听见。',
      domain: LifeAtlasDomain.social),
  LifeAtlasHiddenRule(
      id: 'return_builder',
      requiredQuestionIds: ['journey_return', 'career_start'],
      title: '归乡造局者',
      quote: '你不是退回原点，而是把远方学会的本事带回了起点。',
      domain: LifeAtlasDomain.journey),
  LifeAtlasHiddenRule(
      id: 'root_and_home',
      requiredQuestionIds: ['journey_city', 'journey_root'],
      title: '他乡长成故乡',
      quote: '你曾是地图上的过客，后来成为了这里生活的一部分。',
      domain: LifeAtlasDomain.journey),
  LifeAtlasHiddenRule(
      id: 'solo_rebuild',
      requiredQuestionIds: ['growth_solo', 'growth_recover'],
      title: '自己把自己带回来',
      quote: '那次没有人替你收拾残局，你却把生活一件件放回原位。',
      domain: LifeAtlasDomain.growth),
  LifeAtlasHiddenRule(
      id: 'choice_proved',
      requiredQuestionIds: ['growth_choice', 'career_change'],
      title: '偏航抵达',
      quote: '所有人都以为你走偏了，后来那条路成了你的正路。',
      domain: LifeAtlasDomain.growth),
  LifeAtlasHiddenRule(
      id: 'relation_reborn',
      requiredQuestionIds: ['love_leave', 'love_boundary'],
      title: '爱里重获姓名',
      quote: '你离开的不只是消耗，也是不敢表达自己的旧版本。',
      domain: LifeAtlasDomain.love),
  LifeAtlasHiddenRule(
      id: 'steady_life',
      requiredQuestionIds: ['wealth_save', 'health_routine'],
      title: '日常复利者',
      quote: '真正托住你的，是那些看起来并不起眼、却从未中断的选择。',
      domain: LifeAtlasDomain.wealth),
  LifeAtlasHiddenRule(
      id: 'world_home',
      requiredQuestionIds: ['journey_abroad', 'family_home'],
      title: '带世界回家',
      quote: '你走出去看见世界，又把新的眼光带回了来处。',
      domain: LifeAtlasDomain.journey),
  LifeAtlasHiddenRule(
      id: 'later_road',
      requiredQuestionIds: ['family_firstgen', 'social_help'],
      title: '为后来者留路',
      quote: '你曾经没有路可走，所以后来总想替别人多留一盏灯。',
      domain: LifeAtlasDomain.family),
];

const Map<String, (String, String)> lifeAtlasBaseByGod = {
  '正官': ('守序成事者', '你擅长把混乱变成秩序，也愿意为承诺负责到底。'),
  '七杀': ('逆风推进者', '局面越难，你越容易找到必须向前的那个方向。'),
  '正印': ('温厚承接者', '你习惯理解、吸收并托住他人，也需要给自己留下位置。'),
  '偏印': ('独门探索者', '你不急着沿用标准答案，更愿意走到少有人抵达的深处。'),
  '正财': ('稳步建造者', '你相信可持续的积累，并擅长把生活一点点安顿下来。'),
  '偏财': ('机会捕手', '你对变化和机会保持敏锐，也敢在窗口出现时迅速行动。'),
  '食神': ('丰盛创造者', '你愿意把经验变成作品，也懂得让生活保留滋味。'),
  '伤官': ('清醒表达者', '你很难对不合理保持沉默，也常能说出别人没有说出的部分。'),
  '比肩': ('并肩开路者', '你重视自主与同伴，适合在平等关系里一起把事情做成。'),
  '劫财': ('破局行动者', '你不喜欢站在局外等待，常常先行动，再让局面出现出口。'),
};

int get lifeAtlasCuratedTitleCount =>
    lifeAtlasQuestions.fold<int>(0, (sum, item) => sum + item.titles.length) +
    lifeAtlasHiddenRules.length +
    lifeAtlasBaseByGod.length;

LifeAtlasQuestion? lifeAtlasQuestionById(String id) {
  for (final question in lifeAtlasQuestions) {
    if (question.id == id) return question;
  }
  return null;
}
