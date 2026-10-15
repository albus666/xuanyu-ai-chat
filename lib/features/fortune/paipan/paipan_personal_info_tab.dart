/// 八字个人信息：动态命灵、五行助力、人生阶段与现有旺衰/用神解读。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:lunar/lunar.dart';
import 'package:xuanyu/app/common/routers/names.dart';
import 'package:xuanyu/core/theme/app_colors.dart';

import 'share/paipan_extra_content_service.dart';
import 'share/paipan_shared.dart';
import 'mingling_identity.dart';
import 'utils/bazi_result.dart';
import 'utils/decline_yongshen_parse.dart';
import 'utils/ziping_self_insight.dart';

class PaipanPersonalInfoTab extends StatelessWidget {
  const PaipanPersonalInfoTab({
    super.key,
    required this.result,
    required this.extraFuture,
  });

  final BaziResult result;
  final Future<PaipanExtraContent> extraFuture;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PaipanExtraContent>(
      future: extraFuture,
      builder: (context, snapshot) {
        final extra = snapshot.data ?? const PaipanExtraContent();
        final loading = snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData;
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final dailyProfiles = List.generate(
          4,
          (index) => MinglingProfile.from(
            result,
            extra,
            now: today.add(Duration(days: index)),
          ),
        );
        final profile = dailyProfiles.first;
        return ColoredBox(
          color: const Color(0xFFF8FCFB),
          child: ListView(
            key: const ValueKey('paipan-personal-info-content'),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 28),
            children: [
              _MinglingHero(profile: profile),
              const SizedBox(height: 10),
              _SupportPanel(profile: profile),
              const SizedBox(height: 10),
              _LifeStagePanel(
                result: result,
                profile: profile,
              ),
              const SizedBox(height: 10),
              _TodayMinglingPanel(
                dates: List.generate(
                  4,
                  (index) => today.add(Duration(days: index)),
                ),
                profiles: dailyProfiles,
              ),
              const SizedBox(height: 10),
              _RuleReadingPanel(extra: extra, loading: loading),
              const SizedBox(height: 10),
              _SelfInsightPanel(
                result: result,
                extra: extra,
              ),
              const SizedBox(height: 12),
              _MatchBanner(
                onTap: () => Get.toNamed(RouteNames.homeDestinyMatch),
              ),
              const SizedBox(height: 18),
              const PaipanDisclaimer(),
            ],
          ),
        );
      },
    );
  }
}

const _detailBodyStyle = TextStyle(
  fontSize: 13,
  height: 1.55,
  color: AppColors.textSecondary,
);

const _ganElement = <String, String>{
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

class MinglingProfile {
  const MinglingProfile({
    required this.name,
    required this.framePaths,
    required this.identity,
    required this.temperament,
    required this.dayElement,
    required this.qiElement,
    required this.growthElement,
    required this.state,
    required this.stateDescription,
    required this.todayGanZhi,
    required this.yongElement,
    required this.xiElement,
    required this.accent,
    required this.softAccent,
    required this.patternIndex,
    required this.motifIndex,
    required this.secondaryAccent,
    required this.ornamentName,
    required this.ornamentIcon,
  });

  final String name;
  final List<String> framePaths;
  final String identity;
  final String temperament;
  final String dayElement;
  final String qiElement;
  final String growthElement;
  final String state;
  final String stateDescription;
  final String todayGanZhi;
  final String? yongElement;
  final String? xiElement;
  final Color accent;
  final Color softAccent;
  final int patternIndex;
  final int motifIndex;
  final Color secondaryAccent;
  final String ornamentName;
  final IconData ornamentIcon;

  String get assetPath => framePaths.first;

  bool get hasStructuredSupport => yongElement != null && xiElement != null;

  String get supportLabel {
    if (!hasStructuredSupport) return '助力待综合判断';
    if (yongElement == xiElement) return '喜用 $yongElement';
    return '用神 $yongElement · 喜神 $xiElement';
  }

  factory MinglingProfile.from(
    BaziResult result,
    PaipanExtraContent extra, {
    DateTime? now,
  }) {
    final dayGan = result.dayGan;
    final identity = minglingIdentityForDayGan(dayGan);
    final base = identity == null
        ? const ('玄遇灵', 'gui_full_v3', '温和灵动')
        : (identity.name, identity.assetKey, identity.temperament);
    final parsed =
        extra.yongShen.isEmpty ? null : parseYongshenYsToXiYong(extra.yongShen);
    final yong = parsed?['用神'];
    final xi = parsed?['喜神'];
    final dayElement = _ganElement[dayGan] ?? '水';
    final current = now ?? DateTime.now();
    final todayGanZhi = dayGanZhiFromDate(current);
    final todayElement = todayGanZhi.isEmpty
        ? dayElement
        : (_ganElement[todayGanZhi[0]] ?? dayElement);
    final age = _nominalAge(result.solarDate, current);
    final starts = _daYunStartAges(result);
    var daYunIndex = -1;
    for (var i = 0; i < starts.length; i++) {
      if (age >= starts[i]) daYunIndex = i;
    }
    final daYun = daYunIndex >= 0 && daYunIndex < result.daYun.length
        ? result.daYun[daYunIndex]
        : '';
    final yearGanZhi = ganZhiForLiuNian(current.year);
    final dailyState = _buildDailyMinglingState(
      result: result,
      date: current,
      todayGanZhi: todayGanZhi,
      todayElement: todayElement,
      daYun: daYun,
      yearGanZhi: yearGanZhi,
      dayElement: dayElement,
      yongElement: yong,
      xiElement: xi,
      wangShuai: extra.wangShuai,
    );
    final visualElement = yong ?? xi ?? dayElement;
    final palette = _elementPalette(visualElement);
    final patternSeed = result.fourPillarsStr.codeUnits.fold<int>(
      0,
      (value, code) => (value * 31 + code) & 0x7fffffff,
    );
    const ornaments = <(String, IconData)>[
      ('星芒结', Icons.auto_awesome_rounded),
      ('月辉铃', Icons.nightlight_round),
      ('云纹环', Icons.cloud_outlined),
      ('山岚印', Icons.landscape_outlined),
      ('花藤坠', Icons.local_florist_outlined),
      ('清泉珠', Icons.water_drop_outlined),
      ('日曜牌', Icons.wb_sunny_outlined),
      ('灵羽扣', Icons.air_rounded),
    ];
    final ornament = ornaments[patternSeed % ornaments.length];
    final secondaryElement = _ganElement[result.monthGan] ??
        _ganElement[result.timeGan] ??
        dayElement;
    final secondaryPalette = _elementPalette(secondaryElement);
    return MinglingProfile(
      name: base.$1,
      framePaths: _minglingFrames(base.$2),
      identity: '$dayGan$dayElement命灵',
      temperament: base.$3,
      dayElement: dayElement,
      qiElement: _ganElement[result.timeGan] ?? dayElement,
      growthElement: yong ?? xi ?? _ganElement[result.monthGan] ?? dayElement,
      state: dailyState.state,
      stateDescription: dailyState.description,
      todayGanZhi: todayGanZhi,
      yongElement: yong,
      xiElement: xi,
      accent: palette.$1,
      softAccent: palette.$2,
      patternIndex: (patternSeed ~/ 8) % 8,
      motifIndex: (patternSeed ~/ 64) % 6,
      secondaryAccent: secondaryPalette.$1,
      ornamentName: ornament.$1,
      ornamentIcon: ornament.$2,
    );
  }
}

List<String> _minglingFrames(String key) {
  return List.filled(4, 'assets/mingling_v2/$key.png');
}

class _DailyMinglingState {
  const _DailyMinglingState(this.state, this.description);

  final String state;
  final String description;
}

const _zhiRelations = <String, Map<String, String>>{
  '合': {
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
  },
  '冲': {
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
  },
};

_DailyMinglingState _buildDailyMinglingState({
  required BaziResult result,
  required DateTime date,
  required String todayGanZhi,
  required String todayElement,
  required String daYun,
  required String yearGanZhi,
  required String dayElement,
  required String? yongElement,
  required String? xiElement,
  required String wangShuai,
}) {
  final phaseElements = <String>[
    todayElement,
    if (daYun.isNotEmpty) _ganElement[daYun[0]] ?? '',
    if (yearGanZhi.isNotEmpty) _ganElement[yearGanZhi[0]] ?? '',
  ];
  var supportScore = 0;
  for (var index = 0; index < phaseElements.length; index++) {
    final element = phaseElements[index];
    final weight = index == 0 ? 2 : 1;
    if (element == yongElement) {
      supportScore += weight * 2;
    } else if (element == xiElement) {
      supportScore += weight;
    }
  }
  final todayZhi = todayGanZhi.length > 1 ? todayGanZhi[1] : '';
  final hasCombine = _zhiRelations['合']?[todayZhi] == result.dayZhi;
  final hasClash = _zhiRelations['冲']?[todayZhi] == result.dayZhi;
  final dayGod = todayGanZhi.isEmpty
      ? ''
      : shiShenJianForDayGanVsStem(result.dayGan, todayGanZhi[0]);

  late final String state;
  if (supportScore >= 4) {
    state = hasClash ? '通透' : '舒展';
  } else if (supportScore >= 2) {
    state = hasCombine ? '和鸣' : '明朗';
  } else if (todayElement == dayElement) {
    state = '安定';
  } else if (hasClash || wangShuai.contains('身弱') || wangShuai.contains('身衰')) {
    state = '蓄力';
  } else {
    state = '平和';
  }

  final identitySeed = result.fourPillarsStr.codeUnits.fold<int>(
    0,
    (value, code) => (value * 37 + code) & 0x7fffffff,
  );
  final dateSeed = date.year * 372 + date.month * 31 + date.day;
  final ganZhiSeed = todayGanZhi.codeUnits.fold<int>(
    0,
    (value, code) => value * 31 + code,
  );
  final seed = identitySeed ^ dateSeed ^ ganZhiSeed;
  final openingPool = _stateOpenings[state] ?? _stateOpenings['平和']!;
  final daySerial = date.toUtc().difference(DateTime.utc(2000)).inDays;
  final opening = openingPool[daySerial.abs() % openingPool.length];
  final focus = _stablePick(
    _focusSentences[dayGod] ?? _focusSentences['']!,
    seed ~/ 7 + 3,
  );
  final relation = hasClash
      ? _stablePick(_clashSentences, seed ~/ 11 + 5)
      : hasCombine
          ? _stablePick(_combineSentences, seed ~/ 13 + 7)
          : _stablePick(_neutralSentences, seed ~/ 17 + 11);
  final closingPool = supportScore >= 2
      ? _supportedClosings
      : wangShuai.contains('身弱') || wangShuai.contains('身衰')
          ? _restClosings
          : _steadyClosings;
  final closing = _stablePick(closingPool, seed ~/ 19 + 13);
  final description = '$opening$focus$relation$closing';
  return _DailyMinglingState(state, description);
}

T _stablePick<T>(List<T> values, int seed) =>
    values[seed.abs() % values.length];

const _stateOpenings = <String, List<String>>{
  '舒展': ['今天状态舒展，', '今天心气较顺，', '今天更容易打开局面，', '今天行动感较强，'],
  '通透': ['今天适合破开旧节奏，', '今天变化感较强，', '今天更容易看清取舍，', '今天适合边走边调整，'],
  '和鸣': ['今天关系感较柔和，', '今天容易得到回应，', '今天适合把话说开，', '今天与人配合更顺手，'],
  '明朗': ['今天思路较明朗，', '今天表达欲更清晰，', '今天容易找到着力点，', '今天判断更干脆，'],
  '安定': ['今天节奏相对安定，', '今天内在更有定力，', '今天适合守住自己的步调，', '今天做熟悉的事更顺手，'],
  '蓄力': ['今天宜先收拢精力，', '今天不用把步子迈得太大，', '今天更适合留出余量，', '今天先照顾好自己的节奏，'],
  '平和': ['今天整体较平和，', '今天适合循序推进，', '今天可按原计划展开，', '今天不必刻意求快，'],
};

const _focusSentences = <String, List<String>>{
  '比': ['适合确认自己的立场，', '可以独立处理重要事项，', '把自己的边界说明白，'],
  '劫': ['协作时先讲清分工，', '资源往来宜留好边界，', '与同伴并肩比单打独斗更有效，'],
  '食': ['适合输出作品和分享想法，', '把擅长的事做得更具体，', '轻松表达反而更有感染力，'],
  '伤': ['新想法值得记录和验证，', '表达可以直接但留一点余地，', '适合优化旧方法和旧流程，'],
  '才': ['留意灵活出现的机会，', '适合处理短期资源和现实安排，', '先看投入产出再做选择，'],
  '财': ['适合梳理计划与账目，', '把时间放在能落地的事情上，', '稳定经营比临时起意更合适，'],
  '杀': ['先处理最有压力的那件事，', '越是忙碌越要明确优先级，', '主动承担也要给自己留余量，'],
  '官': ['适合落实责任和正式事项，', '按规则推进更容易得到认可，', '承诺之前先确认时间边界，'],
  '枭': ['适合独处思考和补充信息，', '先观察再行动会更从容，', '不同视角可能带来新解法，'],
  '印': ['适合学习、复盘和整理，', '接受支持会比硬撑更有效，', '把基础补牢后推进更稳，'],
  '': ['先抓住今天最重要的一件事，', '减少分心会更容易看到进展，', '按轻重缓急安排精力，'],
};

const _combineSentences = ['沟通时多听一句会有新发现，', '适合修复一段重要关系，', '合作与回应值得优先关注，'];
const _clashSentences = ['遇到变化先调整顺序，', '别急着在情绪上做最终决定，', '临时变化中也能看见新的出口，'];
const _neutralSentences = [
  '重要决定可以多核对一次，',
  '给自己留一段不被打扰的时间，',
  '把注意力收回到可控制的部分，',
  '完成一件小事也能带动后续节奏，'
];
const _supportedClosings = ['适合主动向前一步。', '今天值得把握一次清晰的机会。', '做出具体行动会比反复设想更有效。'];
const _restClosings = ['先恢复精力，再处理复杂问题。', '减少无谓消耗，结果反而更稳。', '留出休息和复盘的空间会更合适。'];
const _steadyClosings = [
  '不必追赶别人，保持自己的速度即可。',
  '稳稳完成比一次做满更重要。',
  '给变化留一点空间，事情会更从容。'
];

(Color, Color) _elementPalette(String element) => switch (element) {
      '木' => (const Color(0xFF28A984), const Color(0xFFE5F8F1)),
      '火' => (const Color(0xFFE76F61), const Color(0xFFFFEFEC)),
      '土' => (const Color(0xFFC18C47), const Color(0xFFFFF5E5)),
      '金' => (const Color(0xFF8A78C5), const Color(0xFFF1EEFF)),
      _ => (const Color(0xFF3C9BCB), const Color(0xFFE7F7FC)),
    };

class _MinglingHero extends StatelessWidget {
  const _MinglingHero({required this.profile});

  final MinglingProfile profile;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('mingling-full-body-hero'),
      height: 310,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFFFCFFFE),
            profile.softAccent.withValues(alpha: .78),
            const Color(0xFFF5F1FF),
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFCDEDEA)),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -28,
            top: -30,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: profile.accent.withValues(alpha: .08),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 20, 8, 14),
            child: Row(
              children: [
                Expanded(
                  flex: 6,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.name,
                        style: const TextStyle(
                          fontSize: 31,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF126A64),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        profile.identity,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF2D6E69),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        profile.temperament,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _chip('灵核 ${profile.dayElement}'),
                          _chip('气质 ${profile.qiElement}'),
                          _chip('成长 ${profile.growthElement}'),
                          _chipWithIcon(
                            profile.ornamentIcon,
                            profile.ornamentName,
                          ),
                        ],
                      ),
                      const Spacer(),
                    ],
                  ),
                ),
                Expanded(
                  flex: 7,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 2),
                    child: Align(
                      key: const ValueKey('mingling-safe-position'),
                      alignment: Alignment.center,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: SizedBox(
                          width: 190,
                          height: 268,
                          child: _AnimatedMingling(
                            profile: profile,
                            facing: _MinglingFacing.left,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .82),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: const Color(0xFFCDEDEA)),
        ),
        child: Text(
          text,
          style: const TextStyle(fontSize: 11, color: Color(0xFF326663)),
        ),
      );

  Widget _chipWithIcon(IconData icon, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .9),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: profile.accent.withValues(alpha: .35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: profile.accent),
            const SizedBox(width: 4),
            Text(
              text,
              style: const TextStyle(fontSize: 11, color: Color(0xFF326663)),
            ),
          ],
        ),
      );
}

enum _MinglingFacing { left, right }

class _AnimatedMingling extends StatefulWidget {
  const _AnimatedMingling({
    required this.profile,
    required this.facing,
    this.compact = false,
  });

  final MinglingProfile profile;
  final _MinglingFacing facing;
  final bool compact;

  @override
  State<_AnimatedMingling> createState() => _AnimatedMinglingState();
}

class _AnimatedMinglingState extends State<_AnimatedMingling>
    with TickerProviderStateMixin {
  late final AnimationController _idleController;
  late final AnimationController _reactionController;

  @override
  void initState() {
    super.initState();
    _idleController = AnimationController(
      vsync: this,
      duration: _motionDuration(widget.profile.state),
    )..repeat();
    _reactionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 760),
    );
  }

  @override
  void didUpdateWidget(covariant _AnimatedMingling oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile.state != widget.profile.state) {
      _idleController.duration = _motionDuration(widget.profile.state);
      _idleController.repeat();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    precacheImage(AssetImage(widget.profile.assetPath), context);
  }

  @override
  void dispose() {
    _idleController.dispose();
    _reactionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.compact ? const Size(72, 92) : const Size(190, 268);
    return GestureDetector(
      onTap: () => _reactionController.forward(from: 0),
      child: AnimatedBuilder(
        animation: Listenable.merge([_idleController, _reactionController]),
        builder: (context, _) {
          final reacting = _reactionController.isAnimating &&
              _reactionController.value < .96;
          final idle = _idleController.value;
          final reaction = _reactionController.value;
          final expressionOpacity = reacting
              ? (math.sin(reaction * math.pi).clamp(0.0, 1.0) * .75)
              : (idle >= .16 && idle < .23 ? .42 : 0.0);
          return Stack(
            alignment: Alignment.bottomCenter,
            clipBehavior: Clip.none,
            children: [
              Container(
                width: size.width * .82,
                height: size.width * .82,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: widget.profile.accent.withValues(alpha: .2),
                      blurRadius: widget.compact ? 16 : 32,
                      spreadRadius: widget.compact ? 2 : 5,
                    ),
                  ],
                ),
              ),
              _MinglingAura(
                profile: widget.profile,
                compact: widget.compact,
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _MinglingIdentityPainter(
                      motifIndex: widget.profile.motifIndex,
                      primary: widget.profile.accent,
                      secondary: widget.profile.secondaryAccent,
                      compact: widget.compact,
                    ),
                  ),
                ),
              ),
              SizedBox(
                key: widget.compact
                    ? null
                    : const ValueKey('mingling-visual-frame'),
                width: size.width,
                height: size.height,
                child: Padding(
                  padding: EdgeInsets.all(widget.compact ? 2 : 4),
                  child: Transform.flip(
                    key: ValueKey('mingling-facing-${widget.facing.name}'),
                    // 基础命灵素材朝左：右侧大命灵保持原向，左侧小命灵
                    // 水平翻转后朝右，让两处角色都面向相邻内容。
                    flipX: widget.facing == _MinglingFacing.right,
                    child: ColorFiltered(
                      colorFilter:
                          _minglingTint(widget.profile.secondaryAccent),
                      child: Image.asset(
                        widget.profile.assetPath,
                        key: ValueKey(widget.profile.assetPath),
                        fit: BoxFit.contain,
                        alignment: Alignment.center,
                        filterQuality: FilterQuality.high,
                        gaplessPlayback: true,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: widget.compact ? 5 : 12,
                right: widget.compact ? 2 : 5,
                child: Opacity(
                  opacity: expressionOpacity,
                  child: Icon(
                    reacting
                        ? Icons.favorite_rounded
                        : Icons.auto_awesome_rounded,
                    size: widget.compact ? 13 : 25,
                    color: widget.profile.accent,
                  ),
                ),
              ),
              Positioned(
                left: widget.compact ? 0 : 6,
                bottom: widget.compact ? 7 : 20,
                child: Container(
                  width: widget.compact ? 22 : 40,
                  height: widget.compact ? 22 : 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        widget.profile.accent,
                        widget.profile.secondaryAccent,
                      ],
                    ),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: .88),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: widget.profile.accent.withValues(alpha: .18),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    widget.profile.ornamentIcon,
                    size: widget.compact ? 13 : 22,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MinglingAura extends StatelessWidget {
  const _MinglingAura({required this.profile, required this.compact});

  final MinglingProfile profile;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    const alignments = [
      [Alignment(.82, -.68), Alignment(-.76, .1), Alignment(.62, .66)],
      [Alignment(-.7, -.58), Alignment(.78, -.06), Alignment(-.42, .76)],
      [Alignment(.66, -.76), Alignment(-.82, -.04), Alignment(.76, .42)],
      [Alignment(-.72, -.72), Alignment(.72, .12), Alignment(-.6, .62)],
    ];
    final points = alignments[profile.patternIndex % alignments.length];
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          children: points
              .asMap()
              .entries
              .map(
                (entry) => Align(
                  alignment: entry.value,
                  child: Icon(
                    Icons.auto_awesome,
                    size: compact ? 8 : 14,
                    color: (entry.key.isEven
                            ? profile.accent
                            : profile.secondaryAccent)
                        .withValues(alpha: .62),
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

ColorFilter _minglingTint(Color color) {
  const mix = .08;
  return ColorFilter.matrix(<double>[
    1 - mix,
    0,
    0,
    0,
    color.r * 255 * mix,
    0,
    1 - mix,
    0,
    0,
    color.g * 255 * mix,
    0,
    0,
    1 - mix,
    0,
    color.b * 255 * mix,
    0,
    0,
    0,
    1,
    0,
  ]);
}

/// 完整四柱生成的稳定视觉签名。日主相同时仍会在灵阵和护符上
/// 呈现明显差异；命灵朝向则由所在版位统一控制，避免随机向外。
class _MinglingIdentityPainter extends CustomPainter {
  const _MinglingIdentityPainter({
    required this.motifIndex,
    required this.primary,
    required this.secondary,
    required this.compact,
  });

  final int motifIndex;
  final Color primary;
  final Color secondary;
  final bool compact;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * .52, size.height * .63);
    final radius = size.width * (compact ? .34 : .39);
    final stroke = compact ? 1.0 : 1.6;
    final primaryPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = primary.withValues(alpha: .32);
    final secondaryPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = secondary.withValues(alpha: .24);
    final dotPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = primary.withValues(alpha: .42);

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      math.pi * .12,
      math.pi * .76,
      false,
      primaryPaint,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius * .84),
      math.pi * 1.02,
      math.pi * .68,
      false,
      secondaryPaint,
    );

    switch (motifIndex % 6) {
      case 0:
        for (var i = 0; i < 4; i++) {
          final angle = math.pi * (.22 + i * .42);
          canvas.drawCircle(
            center + Offset(math.cos(angle), math.sin(angle)) * radius,
            compact ? 1.6 : 2.7,
            dotPaint,
          );
        }
        break;
      case 1:
        final top = Offset(center.dx, center.dy - radius);
        final right = Offset(center.dx + radius * .42, center.dy);
        final bottom = Offset(center.dx, center.dy + radius * .72);
        final left = Offset(center.dx - radius * .42, center.dy);
        canvas.drawPath(
          Path()
            ..moveTo(top.dx, top.dy)
            ..lineTo(right.dx, right.dy)
            ..lineTo(bottom.dx, bottom.dy)
            ..lineTo(left.dx, left.dy)
            ..close(),
          secondaryPaint,
        );
        break;
      case 2:
        for (var i = 0; i < 3; i++) {
          canvas.drawCircle(
            Offset(center.dx - radius * .62 + i * radius * .62,
                center.dy + radius * .72),
            radius * (.08 + i * .015),
            i.isEven ? primaryPaint : secondaryPaint,
          );
        }
        break;
      case 3:
        canvas.drawArc(
          Rect.fromCircle(
            center: Offset(center.dx - radius * .54, center.dy - radius * .5),
            radius: radius * .24,
          ),
          -math.pi * .52,
          math.pi * 1.05,
          false,
          primaryPaint,
        );
        break;
      case 4:
        final path = Path()
          ..moveTo(center.dx - radius, center.dy + radius * .72);
        for (var i = 0; i <= 6; i++) {
          final x = center.dx - radius + radius * 2 * i / 6;
          final y = center.dy +
              radius * .72 +
              math.sin(i * math.pi / 2) * radius * .08;
          path.lineTo(x, y);
        }
        canvas.drawPath(path, secondaryPaint);
        break;
      case 5:
        for (var i = 0; i < 5; i++) {
          final angle = -math.pi * .9 + i * math.pi * .2;
          final start =
              center + Offset(math.cos(angle), math.sin(angle)) * radius * .86;
          final end =
              center + Offset(math.cos(angle), math.sin(angle)) * radius * 1.05;
          canvas.drawLine(start, end, primaryPaint);
        }
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _MinglingIdentityPainter oldDelegate) =>
      motifIndex != oldDelegate.motifIndex ||
      primary != oldDelegate.primary ||
      secondary != oldDelegate.secondary ||
      compact != oldDelegate.compact;
}

Duration _motionDuration(String state) => switch (state) {
      '舒展' => const Duration(milliseconds: 1900),
      '明朗' => const Duration(milliseconds: 2200),
      '蓄力' => const Duration(milliseconds: 3600),
      _ => const Duration(milliseconds: 2800),
    };

class _SupportPanel extends StatelessWidget {
  const _SupportPanel({required this.profile});

  final MinglingProfile profile;

  @override
  Widget build(BuildContext context) {
    final elements = <String>{
      if (profile.yongElement != null) profile.yongElement!,
      if (profile.xiElement != null) profile.xiElement!,
    }.toList();
    final meta = _supportMeta(elements);
    return _section(
      title: '五行助力${elements.isEmpty ? '' : '｜${elements.join(' · ')}'}',
      child: profile.hasStructuredSupport
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _colorSupportItem(meta.colors)),
                _supportDivider(),
                Expanded(
                  child: _textSupportItem('助力方位', meta.directions),
                ),
                _supportDivider(),
                Expanded(
                  child: _textSupportItem('行动时段', meta.times),
                ),
              ],
            )
          : const Text(
              '暂未形成稳定的助力提示',
              style: _detailBodyStyle,
            ),
    );
  }

  Widget _colorSupportItem(List<Color> colors) => Column(
        children: [
          const Text('助力颜色', style: _supportLabelStyle),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: colors
                .take(3)
                .map(
                  (color) => Container(
                    width: 23,
                    height: 23,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFE3E8E6)),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      );

  Widget _textSupportItem(String label, List<String> values) => Column(
        children: [
          Text(label, style: _supportLabelStyle),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 4,
            runSpacing: 4,
            children: values
                .take(2)
                .map(
                  (value) => Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FCFB),
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(color: const Color(0xFFD9EEEB)),
                    ),
                    child: Text(
                      value,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF326663),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      );

  Widget _supportDivider() => Container(
        width: 1,
        height: 55,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        color: const Color(0xFFE2F2F0),
      );
}

const _supportLabelStyle = TextStyle(
  fontSize: 11,
  color: AppColors.textHint,
);

class _SupportMeta {
  const _SupportMeta(this.colors, this.directions, this.times);

  final List<Color> colors;
  final List<String> directions;
  final List<String> times;
}

_SupportMeta _supportMeta(List<String> elements) {
  const data = <String, _SupportMeta>{
    '木': _SupportMeta(
      [Color(0xFF55B98A), Color(0xFF9BD9BD), Color(0xFFF2EAD6)],
      ['东方', '东南'],
      ['寅时', '卯时'],
    ),
    '火': _SupportMeta(
      [Color(0xFFF26F68), Color(0xFFF7B94B), Color(0xFFFFF0D6)],
      ['南方', '东南'],
      ['巳时', '午时'],
    ),
    '土': _SupportMeta(
      [Color(0xFFD6A45D), Color(0xFFF1CD8E), Color(0xFFF7EEDB)],
      ['中央', '西南'],
      ['辰时', '未时'],
    ),
    '金': _SupportMeta(
      [Color(0xFFF7F3E8), Color(0xFFD7CDEA), Color(0xFFB8C9D9)],
      ['西方', '西北'],
      ['申时', '酉时'],
    ),
    '水': _SupportMeta(
      [Color(0xFF65B7CF), Color(0xFFA8DCE4), Color(0xFFE6F4F6)],
      ['北方', '东北'],
      ['亥时', '子时'],
    ),
  };
  if (elements.isEmpty) {
    return const _SupportMeta(
      [Color(0xFFE5F4F1)],
      ['—'],
      ['—'],
    );
  }
  final colors = <Color>[];
  final directions = <String>[];
  final times = <String>[];
  for (final element in elements) {
    final item = data[element];
    if (item == null) continue;
    colors.addAll(item.colors);
    directions.addAll(item.directions);
    times.addAll(item.times);
  }
  return _SupportMeta(
    colors.isEmpty ? const [Color(0xFFE5F4F1)] : colors,
    directions.isEmpty ? const ['—'] : directions.toSet().toList(),
    times.isEmpty ? const ['—'] : times.toSet().toList(),
  );
}

class LifeStageProfile {
  const LifeStageProfile({
    required this.currentDaYunIndex,
    required this.currentDaYun,
    required this.currentDaYunRange,
    required this.currentYear,
    required this.currentYearGanZhi,
    required this.nominalAge,
    required this.daYunTenGod,
    required this.yearTenGod,
    required this.focuses,
    required this.relationship,
    required this.career,
    required this.wealth,
    required this.status,
  });

  final int currentDaYunIndex;
  final String currentDaYun;
  final String currentDaYunRange;
  final int currentYear;
  final String currentYearGanZhi;
  final int nominalAge;
  final String daYunTenGod;
  final String yearTenGod;
  final List<String> focuses;
  final String relationship;
  final String career;
  final String wealth;
  final String status;

  factory LifeStageProfile.from(
    BaziResult result,
    MinglingProfile profile, {
    DateTime? now,
  }) {
    final current = now ?? DateTime.now();
    final age = _nominalAge(result.solarDate, current);
    final starts = _daYunStartAges(result);
    var index = -1;
    for (var i = 0; i < starts.length; i++) {
      if (age >= starts[i]) index = i;
    }
    if (index >= result.daYun.length) index = result.daYun.length - 1;
    return LifeStageProfile.forSelection(
      result,
      profile,
      daYunIndex: index,
      year: current.year,
    );
  }

  factory LifeStageProfile.forSelection(
    BaziResult result,
    MinglingProfile profile, {
    required int daYunIndex,
    required int year,
  }) {
    final starts = _daYunStartAges(result);
    var index = daYunIndex;
    if (index >= result.daYun.length) index = result.daYun.length - 1;
    final currentDaYun =
        index >= 0 && index < result.daYun.length ? result.daYun[index] : '童限';
    final range = index >= 0
        ? _daYunRangeLabel(result, index)
        : starts.isEmpty
            ? '起运前'
            : '1~${math.max(1, starts.first - 1)}岁';
    final yearGanZhi = ganZhiForLiuNian(year);
    final daYunGod = currentDaYun.length >= 2
        ? shiShenJianForDayGanVsStem(result.dayGan, currentDaYun[0])
        : '';
    final yearGod = yearGanZhi.length >= 2
        ? shiShenJianForDayGanVsStem(result.dayGan, yearGanZhi[0])
        : '';
    final daYunTheme = _tenGodTheme(daYunGod);
    final yearTheme = _tenGodTheme(yearGod);
    final daYunZhi = currentDaYun.length >= 2 ? currentDaYun[1] : '';
    final yearZhi = yearGanZhi.length >= 2 ? yearGanZhi[1] : '';
    final daYunDayRelation = _zhiRelation(daYunZhi, result.dayZhi);
    final yearDayRelation = _zhiRelation(yearZhi, result.dayZhi);
    final phaseRelation = _zhiRelation(daYunZhi, yearZhi);
    final yearElement = yearGanZhi.isEmpty ? '' : _ganElement[yearGanZhi[0]];
    final support = yearElement == profile.yongElement
        ? _StageSupport.yong
        : yearElement == profile.xiElement
            ? _StageSupport.xi
            : yearElement == profile.dayElement
                ? _StageSupport.same
                : _StageSupport.neutral;

    final focuses = <String>[];
    void addFocus(String value) {
      if (value.isNotEmpty && !focuses.contains(value)) focuses.add(value);
    }

    addFocus(daYunTheme.focuses.first);
    addFocus(yearTheme.focuses.first);
    addFocus(switch (yearDayRelation) {
      _StageRelation.combine => '关系联结',
      _StageRelation.clash => '关系重整',
      _ => switch (phaseRelation) {
          _StageRelation.combine => '内外协同',
          _StageRelation.clash => '节奏转换',
          _ => switch (daYunDayRelation) {
              _StageRelation.combine => '长期协作',
              _StageRelation.clash => '阶段转向',
              _ => switch (support) {
                  _StageSupport.yong => '顺势推进',
                  _StageSupport.xi => '机会展开',
                  _ => yearTheme.focuses.last,
                },
            },
        },
    });
    for (final fallback in [
      ...daYunTheme.focuses.skip(1),
      ...yearTheme.focuses.skip(1),
      '节奏调整',
    ]) {
      if (focuses.length >= 3) break;
      addFocus(fallback);
    }

    final relationship = _stageRelationship(
      daYunTheme: daYunTheme,
      yearTheme: yearTheme,
      daYunDayRelation: daYunDayRelation,
      yearDayRelation: yearDayRelation,
    );
    final career = _stageCareer(
      daYunGod: daYunGod,
      yearGod: yearGod,
      yearTheme: yearTheme,
      phaseRelation: phaseRelation,
    );
    final wealth = _stageWealth(
      daYunGod: daYunGod,
      yearGod: yearGod,
      yearTheme: yearTheme,
      support: support,
    );
    final stageStatus = _stageStatus(
      yearTheme: yearTheme,
      support: support,
      yearDayRelation: yearDayRelation,
      phaseRelation: phaseRelation,
    );
    return LifeStageProfile(
      currentDaYunIndex: index,
      currentDaYun: currentDaYun,
      currentDaYunRange: range,
      currentYear: year,
      currentYearGanZhi: yearGanZhi,
      nominalAge: math.max(1, year - result.solarDate.year + 1),
      daYunTenGod: daYunGod,
      yearTenGod: yearGod,
      focuses: focuses.take(3).toList(),
      relationship: relationship,
      career: career,
      wealth: wealth,
      status: stageStatus,
    );
  }
}

enum _StageRelation { none, combine, clash }

enum _StageSupport { yong, xi, same, neutral }

_StageRelation _zhiRelation(String first, String second) {
  if (first.isEmpty || second.isEmpty) return _StageRelation.none;
  if (_zhiRelations['合']?[first] == second) return _StageRelation.combine;
  if (_zhiRelations['冲']?[first] == second) return _StageRelation.clash;
  return _StageRelation.none;
}

class _TenGodTheme {
  const _TenGodTheme({
    required this.focuses,
    required this.relationship,
    required this.career,
    required this.wealth,
    required this.status,
  });

  final List<String> focuses;
  final String relationship;
  final String career;
  final String wealth;
  final String status;
}

_TenGodTheme _tenGodTheme(String god) => switch (god) {
      '比' => const _TenGodTheme(
          focuses: ['自我定位', '同侪协力'],
          relationship: '保持自我',
          career: '自主拓展',
          wealth: '量入为出',
          status: '宜定方向',
        ),
      '劫' => const _TenGodTheme(
          focuses: ['圈层重组', '资源边界'],
          relationship: '边界磨合',
          career: '竞合提速',
          wealth: '谨慎分配',
          status: '宜明边界',
        ),
      '食' => const _TenGodTheme(
          focuses: ['才华落地', '生活舒展'],
          relationship: '相处松弛',
          career: '成果输出',
          wealth: '技能生财',
          status: '宜多表达',
        ),
      '伤' => const _TenGodTheme(
          focuses: ['表达破局', '规则调整'],
          relationship: '坦诚磨合',
          career: '创新破局',
          wealth: '机会流动',
          status: '宜先疏导',
        ),
      '才' => const _TenGodTheme(
          focuses: ['机会经营', '现实选择'],
          relationship: '缘分流动',
          career: '灵活尝试',
          wealth: '机会经营',
          status: '宜抓机会',
        ),
      '财' => const _TenGodTheme(
          focuses: ['稳定经营', '责任落实'],
          relationship: '关系落地',
          career: '务实推进',
          wealth: '正财积累',
          status: '宜做规划',
        ),
      '杀' => const _TenGodTheme(
          focuses: ['压力转化', '行动升级'],
          relationship: '强弱磨合',
          career: '迎难跃升',
          wealth: '风险取舍',
          status: '宜减压力',
        ),
      '官' => const _TenGodTheme(
          focuses: ['身份责任', '秩序建设'],
          relationship: '承诺议题',
          career: '职位进阶',
          wealth: '稳健配置',
          status: '宜守秩序',
        ),
      '枭' => const _TenGodTheme(
          focuses: ['独立研判', '路径重塑'],
          relationship: '需要空间',
          career: '路径转向',
          wealth: '先守后动',
          status: '宜先观察',
        ),
      '印' => const _TenGodTheme(
          focuses: ['学习积累', '支持系统'],
          relationship: '信任加深',
          career: '资质沉淀',
          wealth: '稳守积累',
          status: '宜补基础',
        ),
      _ => const _TenGodTheme(
          focuses: ['方向确认', '节奏调整'],
          relationship: '平稳相处',
          career: '稳步推进',
          wealth: '稳健安排',
          status: '宜稳步走',
        ),
    };

String _tenGodGroup(String god) => switch (god) {
      '比' || '劫' => '同伴',
      '食' || '伤' => '输出',
      '才' || '财' => '经营',
      '杀' || '官' => '责任',
      '枭' || '印' => '积累',
      _ => '',
    };

String _stageRelationship({
  required _TenGodTheme daYunTheme,
  required _TenGodTheme yearTheme,
  required _StageRelation daYunDayRelation,
  required _StageRelation yearDayRelation,
}) {
  if (yearDayRelation == _StageRelation.combine) return '联结加深';
  if (yearDayRelation == _StageRelation.clash) return '关系重整';
  if (daYunDayRelation == _StageRelation.combine) {
    return yearTheme.relationship == '需要空间' ? '亲疏有度' : '长期联结';
  }
  if (daYunDayRelation == _StageRelation.clash) {
    return yearTheme.relationship == '相处松弛' ? '松弛磨合' : '边界重塑';
  }
  return yearTheme.relationship.isEmpty
      ? daYunTheme.relationship
      : yearTheme.relationship;
}

String _stageCareer({
  required String daYunGod,
  required String yearGod,
  required _TenGodTheme yearTheme,
  required _StageRelation phaseRelation,
}) {
  final daYunGroup = _tenGodGroup(daYunGod);
  final yearGroup = _tenGodGroup(yearGod);
  if (phaseRelation == _StageRelation.combine) return '协同推进';
  if (phaseRelation == _StageRelation.clash) return '调整主线';
  if (daYunGroup == '积累' && yearGroup == '输出') return '学用并进';
  if (daYunGroup == '责任' && yearGroup == '积累') return '资质进阶';
  if (daYunGroup == '经营' && yearGroup == '责任') return '责任兑现';
  if (daYunGroup == '同伴' && yearGroup == '经营') return '合作经营';
  if (daYunGroup == '输出' && yearGroup == '经营') return '成果变现';
  return yearTheme.career;
}

String _stageWealth({
  required String daYunGod,
  required String yearGod,
  required _TenGodTheme yearTheme,
  required _StageSupport support,
}) {
  final daYunGroup = _tenGodGroup(daYunGod);
  final yearGroup = _tenGodGroup(yearGod);
  if (daYunGroup == '输出' && yearGroup == '经营') return '成果兑现';
  if (daYunGroup == '经营' && yearGroup == '经营') return '经营增效';
  if (daYunGroup == '同伴' && yearGroup == '经营') return '合作分配';
  if (support == _StageSupport.yong && yearGroup != '同伴') return '顺势配置';
  if (support == _StageSupport.xi && yearGroup == '经营') return '灵活增配';
  return yearTheme.wealth;
}

String _stageStatus({
  required _TenGodTheme yearTheme,
  required _StageSupport support,
  required _StageRelation yearDayRelation,
  required _StageRelation phaseRelation,
}) {
  if (yearDayRelation == _StageRelation.clash) return '宜留余量';
  if (yearDayRelation == _StageRelation.combine) return '宜多联结';
  if (phaseRelation == _StageRelation.clash) return '宜调节奏';
  if (support == _StageSupport.yong) return '宜顺势走';
  if (support == _StageSupport.xi) return '宜多展开';
  if (support == _StageSupport.same) return '宜稳步走';
  return yearTheme.status;
}

List<int> _daYunStartAges(BaziResult result) {
  final starts = <int>[];
  for (final label in result.daYunAgeRanges) {
    final value = RegExp(r'\d+').firstMatch(label)?.group(0);
    if (value != null) starts.add(int.parse(value));
  }
  if (starts.isEmpty && result.daYun.isNotEmpty) {
    return List.generate(
      result.daYun.length,
      (index) => result.daYunStartXuSui + index * 10,
    );
  }
  return starts;
}

String _daYunRangeLabel(BaziResult result, int index) {
  final starts = _daYunStartAges(result);
  if (index < 0 || index >= starts.length) return '—';
  final start = starts[index];
  final end = index + 1 < starts.length ? starts[index + 1] - 1 : start + 9;
  return '$start~$end岁';
}

class _LifeStagePanel extends StatefulWidget {
  const _LifeStagePanel({required this.result, required this.profile});

  final BaziResult result;
  final MinglingProfile profile;

  @override
  State<_LifeStagePanel> createState() => _LifeStagePanelState();
}

class _LifeStagePanelState extends State<_LifeStagePanel> {
  late int _selectedDaYunIndex;
  late int _selectedYear;
  bool _trajectoryExpanded = false;

  @override
  void initState() {
    super.initState();
    final current = LifeStageProfile.from(widget.result, widget.profile);
    _selectedDaYunIndex = current.currentDaYunIndex;
    if (_selectedDaYunIndex < 0 && widget.result.daYun.isNotEmpty) {
      _selectedDaYunIndex = 0;
    }
    _selectedYear = current.currentYear;
    _selectedYear = _selectedYear.clamp(
      _yearBounds(_selectedDaYunIndex).$1,
      _yearBounds(_selectedDaYunIndex).$2,
    );
  }

  (int, int) _yearBounds(int index) {
    final starts = _daYunStartAges(widget.result);
    if (index < 0 || index >= starts.length) {
      final year = DateTime.now().year;
      return (year, year);
    }
    final startYear = widget.result.solarDate.year + starts[index] - 1;
    final endAge =
        index + 1 < starts.length ? starts[index + 1] - 1 : starts[index] + 9;
    return (startYear, widget.result.solarDate.year + endAge - 1);
  }

  void _selectDaYun(int index) {
    if (index < 0 || index >= widget.result.daYun.length) return;
    final bounds = _yearBounds(index);
    final nowYear = DateTime.now().year;
    setState(() {
      _selectedDaYunIndex = index;
      _selectedYear = nowYear.clamp(bounds.$1, bounds.$2);
    });
  }

  void _selectYear(int year) {
    final bounds = _yearBounds(_selectedDaYunIndex);
    setState(() => _selectedYear = year.clamp(bounds.$1, bounds.$2));
  }

  @override
  Widget build(BuildContext context) {
    final stage = LifeStageProfile.forSelection(
      widget.result,
      widget.profile,
      daYunIndex: _selectedDaYunIndex,
      year: _selectedYear,
    );
    final bounds = _yearBounds(_selectedDaYunIndex);
    return _section(
      key: const ValueKey('current-life-stage'),
      title: '当前人生阶段',
      titleIcon: Icons.location_history_rounded,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FCFB),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2F2F0)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _stageHeadline(
                    label: '大运',
                    value: stage.currentDaYun,
                    caption: stage.currentDaYunRange,
                    previousKey: const ValueKey('life-stage-dayun-prev'),
                    nextKey: const ValueKey('life-stage-dayun-next'),
                    onPrevious: _selectedDaYunIndex > 0
                        ? () => _selectDaYun(_selectedDaYunIndex - 1)
                        : null,
                    onNext: _selectedDaYunIndex + 1 < widget.result.daYun.length
                        ? () => _selectDaYun(_selectedDaYunIndex + 1)
                        : null,
                  ),
                ),
                Container(width: 1, height: 42, color: const Color(0xFFE2F2F0)),
                Expanded(
                  child: _stageHeadline(
                    label: '流年',
                    value: stage.currentYearGanZhi,
                    caption: '${stage.currentYear} · ${stage.nominalAge}岁',
                    previousKey: const ValueKey('life-stage-year-prev'),
                    nextKey: const ValueKey('life-stage-year-next'),
                    onPrevious: _selectedYear > bounds.$1
                        ? () => _selectYear(_selectedYear - 1)
                        : null,
                    onNext: _selectedYear < bounds.$2
                        ? () => _selectYear(_selectedYear + 1)
                        : null,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 9),
          Row(
            children: stage.focuses
                .map(
                  (focus) => Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE1EFED)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(_focusIcon(focus),
                              size: 14, color: const Color(0xFF65A9A3)),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              focus,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 11, color: Color(0xFF47726E)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                  child: _stageMetric(Icons.favorite_border, '感情',
                      stage.relationship, const Color(0xFFE97883))),
              Expanded(
                  child: _stageMetric(Icons.trending_up_rounded, '事业',
                      stage.career, const Color(0xFF6EAEB2))),
              Expanded(
                  child: _stageMetric(Icons.paid_outlined, '财运', stage.wealth,
                      const Color(0xFFD3A43C))),
              Expanded(
                  child: _stageMetric(Icons.spa_outlined, '状态', stage.status,
                      const Color(0xFF9873C8))),
            ],
          ),
          const SizedBox(height: 7),
          InkWell(
            key: const ValueKey('fortune-trajectory-action'),
            onTap: () =>
                setState(() => _trajectoryExpanded = !_trajectoryExpanded),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _trajectoryExpanded ? '收起运势轨迹' : '查看运势轨迹',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primaryDark,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _trajectoryExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: AppColors.primaryDark,
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            alignment: Alignment.topCenter,
            child: _trajectoryExpanded
                ? _inlineTrajectory(stage)
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _stageHeadline({
    required String label,
    required String value,
    required String caption,
    required Key previousKey,
    required Key nextKey,
    required VoidCallback? onPrevious,
    required VoidCallback? onNext,
  }) =>
      Column(
        children: [
          Text(label,
              style: const TextStyle(fontSize: 10, color: AppColors.textHint)),
          Row(
            children: [
              IconButton(
                key: previousKey,
                onPressed: onPrevious,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints.tightFor(width: 28, height: 28),
                icon: const Icon(Icons.chevron_left_rounded, size: 18),
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(value,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary)),
                    Text(caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 9, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              IconButton(
                key: nextKey,
                onPressed: onNext,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints.tightFor(width: 28, height: 28),
                icon: const Icon(Icons.chevron_right_rounded, size: 18),
              ),
            ],
          ),
        ],
      );

  Widget _inlineTrajectory(LifeStageProfile stage) {
    final bounds = _yearBounds(_selectedDaYunIndex);
    return Container(
      key: const ValueKey('fortune-trajectory-inline'),
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FBFA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0EFED)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('大运', style: _inlineTrajectoryTitleStyle),
          const SizedBox(height: 6),
          SizedBox(
            height: 58,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: widget.result.daYun.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final selected = index == _selectedDaYunIndex;
                return InkWell(
                  key: ValueKey('dayun-option-$index'),
                  onTap: () => _selectDaYun(index),
                  borderRadius: BorderRadius.circular(9),
                  child: Container(
                    width: 78,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                    decoration: BoxDecoration(
                      color: selected ? const Color(0xFFE0F5F1) : Colors.white,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(
                        color: selected
                            ? AppColors.primary
                            : const Color(0xFFE2EEEC),
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(widget.result.daYun[index],
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w900)),
                        Text(_daYunRangeLabel(widget.result, index),
                            style: const TextStyle(
                                fontSize: 9, color: AppColors.textHint)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          const Text('流年', style: _inlineTrajectoryTitleStyle),
          const SizedBox(height: 6),
          SizedBox(
            height: 58,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: bounds.$2 - bounds.$1 + 1,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final year = bounds.$1 + index;
                final selected = year == _selectedYear;
                return InkWell(
                  key: ValueKey('liunian-option-$year'),
                  onTap: () => _selectYear(year),
                  borderRadius: BorderRadius.circular(9),
                  child: Container(
                    width: 68,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                    decoration: BoxDecoration(
                      color: selected ? const Color(0xFFE7F6FA) : Colors.white,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(
                        color: selected
                            ? const Color(0xFF58A8C4)
                            : const Color(0xFFE2EEEC),
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('$year',
                            style: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w800)),
                        Text(ganZhiForLiuNian(year),
                            style: const TextStyle(
                                fontSize: 11, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              '${stage.currentDaYun}大运 · ${stage.currentYearGanZhi}流年 · ${stage.focuses.join(' · ')}',
              style: const TextStyle(fontSize: 10, color: Color(0xFF47726E)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stageMetric(IconData icon, String label, String value, Color color) =>
      Column(
        children: [
          Icon(icon, size: 21, color: color),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(fontSize: 10, color: AppColors.textHint)),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      );
}

const _inlineTrajectoryTitleStyle = TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.w900,
  color: Color(0xFF174E4B),
);

IconData _focusIcon(String focus) {
  if (focus.contains('关系') || focus.contains('同伴')) {
    return Icons.favorite_border_rounded;
  }
  if (focus.contains('表达') || focus.contains('创意')) {
    return Icons.chat_bubble_outline_rounded;
  }
  if (focus.contains('事业') || focus.contains('责任')) {
    return Icons.work_outline_rounded;
  }
  if (focus.contains('资源')) return Icons.paid_outlined;
  if (focus.contains('学习')) return Icons.menu_book_outlined;
  return Icons.tune_rounded;
}

int _nominalAge(DateTime birth, DateTime now) =>
    math.max(1, now.year - birth.year + 1);

class _TodayMinglingPanel extends StatefulWidget {
  const _TodayMinglingPanel({required this.dates, required this.profiles});

  final List<DateTime> dates;
  final List<MinglingProfile> profiles;

  @override
  State<_TodayMinglingPanel> createState() => _TodayMinglingPanelState();
}

class _TodayMinglingPanelState extends State<_TodayMinglingPanel> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final date = widget.dates[_selectedIndex];
    final profile = widget.profiles[_selectedIndex];
    final lunar = Lunar.fromDate(date);
    return Container(
      key: const ValueKey('today-mingling-state'),
      height: 174,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            profile.softAccent,
            const Color(0xFFFBFEFD),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD8EFEC)),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 125,
            child: Row(
              children: [
                SizedBox(
                  width: 105,
                  child: Center(
                    child: _AnimatedMingling(
                      profile: profile,
                      facing: _MinglingFacing.right,
                      compact: true,
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _selectedIndex == 0 ? '今日命灵状态' : '未来命灵状态',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF4D8580),
                          ),
                        ),
                        Text(
                          profile.state,
                          style: const TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF174E4B),
                          ),
                        ),
                        Text(
                          profile.stateDescription,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10,
                            height: 1.35,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 12, 10, 0),
                  child: Align(
                    alignment: Alignment.topRight,
                    child: Text(
                      '${lunar.getMonthInChinese()}月${lunar.getDayInChinese()}',
                      style: const TextStyle(
                        fontSize: 9,
                        color: AppColors.textHint,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 9),
            child: Row(
              children: List.generate(widget.dates.length, (index) {
                final selected = index == _selectedIndex;
                final itemDate = widget.dates[index];
                return Expanded(
                  child: InkWell(
                    key: ValueKey('mingling-day-$index'),
                    onTap: () => setState(() => _selectedIndex = index),
                    borderRadius: BorderRadius.circular(9),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected
                            ? Colors.white.withValues(alpha: .86)
                            : Colors.white.withValues(alpha: .42),
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(
                          color: selected
                              ? profile.accent.withValues(alpha: .55)
                              : Colors.transparent,
                        ),
                      ),
                      child: Text(
                        index == 0 ? '今天' : '${itemDate.month}.${itemDate.day}',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight:
                              selected ? FontWeight.w800 : FontWeight.w500,
                          color: selected
                              ? AppColors.primaryDark
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class _RuleReadingPanel extends StatelessWidget {
  const _RuleReadingPanel({required this.extra, required this.loading});

  final PaipanExtraContent extra;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return _section(
      title: '命局解读',
      child: loading
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : Column(
              children: [
                _reading('旺衰', extra.wangShuai),
                const Divider(height: 20, color: Color(0xFFE2F2F0)),
                _reading('用神', extra.yongShen),
                if (extra.yongShen.isNotEmpty) ...[
                  if (parseYongshenYsToXiYong(extra.yongShen)
                      case final parsed?) ...[
                    const Divider(height: 20, color: Color(0xFFE2F2F0)),
                    _reading(
                      '喜用神',
                      '喜神：${parsed['喜神']}　用神：${parsed['用神']}',
                    ),
                  ],
                ],
              ],
            ),
    );
  }

  Widget _reading(String title, String content) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            padding: const EdgeInsets.symmetric(vertical: 4),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppColors.primaryDark,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              content.trim().isEmpty ? '暂无对应条文' : content.trim(),
              style: _detailBodyStyle,
            ),
          ),
        ],
      );
}

class _SelfInsightPanel extends StatelessWidget {
  const _SelfInsightPanel({
    required this.result,
    required this.extra,
  });

  final BaziResult result;
  final PaipanExtraContent extra;

  @override
  Widget build(BuildContext context) {
    final items = _selfInsightItems(
      result: result,
      extra: extra,
    );
    return _section(
      title: '认识自己',
      titleIcon: Icons.person_search_outlined,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = (constraints.maxWidth - 8) / 2;
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: items
                .map(
                  (item) => SizedBox(
                    width: width,
                    child: InkWell(
                      onTap: () => _showInsight(context, item),
                      borderRadius: BorderRadius.circular(10),
                      child: Ink(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFBFDFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE1EFED)),
                        ),
                        child: Row(
                          children: [
                            Icon(item.icon, size: 22, color: item.color),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.title,
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800)),
                                  const SizedBox(height: 2),
                                  Text(
                                    item.summary,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      height: 1.3,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded,
                                size: 16, color: AppColors.textHint),
                          ],
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          );
        },
      ),
    );
  }

  Future<void> _showInsight(BuildContext context, _InsightItem item) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: const Color(0xFFFBFEFD),
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.88,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: item.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(item.icon, color: item.color, size: 22),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item.title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                key: ValueKey('self-insight-detail-${item.title}'),
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
                    decoration: BoxDecoration(
                      color: item.color.withValues(alpha: 0.09),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: item.color.withValues(alpha: 0.18),
                      ),
                    ),
                    child: Text(
                      '“${item.summary}。”',
                      style: const TextStyle(
                        fontSize: 17,
                        height: 1.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...item.sections.map(
                    (section) => _InsightSectionBlock(
                      section: section,
                      color: item.color,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InsightSectionBlock extends StatelessWidget {
  const _InsightSectionBlock({
    required this.section,
    required this.color,
  });

  final ZipingInsightSection section;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final isEvidence = section.title == '命局依据';
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 14,
                decoration: BoxDecoration(
                  color: isEvidence ? AppColors.textHint : color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                section.title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: isEvidence
                      ? AppColors.textSecondary
                      : AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            section.content,
            style: _detailBodyStyle.copyWith(
              fontSize: isEvidence ? 12 : 14,
              color: isEvidence ? AppColors.textHint : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _InsightItem {
  const _InsightItem({
    required this.title,
    required this.summary,
    required this.sections,
    required this.icon,
    required this.color,
  });

  final String title;
  final String summary;
  final List<ZipingInsightSection> sections;
  final IconData icon;
  final Color color;
}

List<_InsightItem> _selfInsightItems({
  required BaziResult result,
  required PaipanExtraContent extra,
}) {
  final readings = buildZipingSelfInsights(
    result: result,
    wangShuai: extra.wangShuai,
    yongShen: extra.yongShen,
  );
  const icons = <IconData>[
    Icons.account_tree_outlined,
    Icons.eco_outlined,
    Icons.favorite_border_rounded,
    Icons.work_outline_rounded,
    Icons.account_balance_wallet_outlined,
    Icons.balance_outlined,
  ];
  const colors = <Color>[
    Color(0xFF3C847C),
    Color(0xFF55B98A),
    Color(0xFFE684B3),
    Color(0xFF55A99F),
    Color(0xFFD3A43C),
    Color(0xFF8A78C5),
  ];
  return List.generate(
    readings.length,
    (index) => _InsightItem(
      title: readings[index].title,
      summary: readings[index].summary,
      sections: readings[index].sections,
      icon: icons[index],
      color: colors[index],
    ),
  );
}

class _MatchBanner extends StatelessWidget {
  const _MatchBanner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFE0F4F1), Color(0xFFDCEAF6)],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFB7DAD7)),
          ),
          child: Row(
            children: [
              const Icon(Icons.favorite_border_rounded,
                  color: Color(0xFF136D69), size: 30),
              const SizedBox(width: 11),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '找到与你更合拍的人',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF174F58),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      '去遇见更懂你、也更合拍的人',
                      style: TextStyle(fontSize: 10, color: Color(0xFF456B73)),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF075F5B),
                  borderRadius: BorderRadius.circular(99),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: .55)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x26003F3B),
                      blurRadius: 10,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '开启匹配',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(width: 2),
                    Icon(Icons.chevron_right_rounded,
                        size: 16, color: Colors.white),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _section({
  Key? key,
  required String title,
  required Widget child,
  Widget? trailing,
  IconData? titleIcon,
}) {
  return Container(
    key: key,
    padding: const EdgeInsets.fromLTRB(15, 14, 15, 15),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE2F2F0)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (titleIcon != null) ...[
              Icon(titleIcon, size: 19, color: AppColors.primaryDark),
              const SizedBox(width: 7),
            ],
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: Color(0xFF174E4B),
              ),
            ),
            const Spacer(),
            if (trailing != null) trailing,
          ],
        ),
        const SizedBox(height: 13),
        child,
      ],
    ),
  );
}
