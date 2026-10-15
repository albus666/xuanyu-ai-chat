import 'package:flutter/material.dart';
import 'package:xuanyu/shared/widgets/cultural_reference_notice.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../core/profile/account_birth_profile.dart';
import '../../core/utils/app_toast.dart';
import '../../core/utils/share_card_capture.dart';
import '../../core/widgets/app_share_more_button.dart';
import 'zodiac_profile.dart';

class ZodiacPage extends StatefulWidget {
  const ZodiacPage({super.key});

  @override
  State<ZodiacPage> createState() => _ZodiacPageState();
}

class _ZodiacPageState extends State<ZodiacPage> {
  final GlobalKey _shareKey = GlobalKey();

  ZodiacReading? _reading;
  bool _loading = true;
  bool _profileMissing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final profile = await AccountBirthProfileRepository.load();
      final date = DateTime.tryParse(profile.birthDate.split('T').first);
      if (!mounted) return;
      setState(() {
        _reading = date == null ? null : ZodiacReading.fromBirthDate(date);
        _profileMissing = date == null;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '生肖印记暂时走丢了，请稍后再试';
      });
    }
  }

  Future<void> _completeProfile() async {
    final profile = await AccountBirthProfileRepository.ensure(
      context,
      reason: '用于生成你的生肖印记；具体出生日期不会展示在页面或分享图中',
    );
    if (profile == null || !mounted) return;
    final date = DateTime.tryParse(profile.birthDate.split('T').first);
    if (date == null) return;
    setState(() {
      _reading = ZodiacReading.fromBirthDate(date);
      _profileMissing = false;
      _error = null;
    });
  }

  Future<void> _share() async {
    final reading = _reading;
    if (reading == null) return;
    try {
      await showAppShareSheet(
        context,
        title: '生肖印记',
        imageBuilder: () =>
            ShareCardCapture.captureWidget(repaintKey: _shareKey),
        shareText:
            '【玄遇生肖印记】${reading.companion.branch}${reading.companion.animal} · ${reading.companion.title}\n${reading.companion.quote}',
      );
    } catch (_) {
      if (mounted) showAppToast(context, '分享图生成失败，请稍后再试');
    }
  }

  @override
  Widget build(BuildContext context) {
    final reading = _reading;
    return Scaffold(
      backgroundColor: const Color(0xFFF9FBFF),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF9FBFF),
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: const Text(
          '生肖印记',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: <Widget>[
          IconButton(
            tooltip: '分享生肖印记',
            onPressed: reading == null ? null : _share,
            icon: const Icon(Icons.more_horiz_rounded),
          ),
        ],
      ),
      body: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[
                    const Color(0xFFF6F2FF).withValues(alpha: .66),
                    const Color(0xFFF9FBFF),
                    const Color(0xFFF0FCFA).withValues(alpha: .72),
                  ],
                ),
              ),
            ),
          ),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_profileMissing)
            _ProfileMissing(onComplete: _completeProfile)
          else if (_error != null)
            _LoadError(message: _error!, onRetry: _loadProfile)
          else if (reading != null)
            ZodiacReadingContent(reading: reading),
          if (reading != null)
            Positioned(
              left: -10000,
              top: 0,
              child: IgnorePointer(
                child: RepaintBoundary(
                  key: _shareKey,
                  child: ZodiacShareCard(reading: reading),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class ZodiacReadingContent extends StatelessWidget {
  const ZodiacReadingContent({super.key, required this.reading});

  final ZodiacReading reading;

  ZodiacCompanion get item => reading.companion;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        16.w,
        8.h,
        16.w,
        28.h + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _HeroCard(reading: reading),
          SizedBox(height: 14.h),
          _SparkCard(item: item),
          SizedBox(height: 12.h),
          _RelationshipCard(item: item),
          SizedBox(height: 12.h),
          _ReminderCard(item: item),
          SizedBox(height: 12.h),
          _BaseCard(item: item),
          SizedBox(height: 12.h),
          _LongReadingCard(item: item),
          SizedBox(height: 14.h),
          Text(
            CulturalReferenceNotice.text,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: const Color(0xFF98A2B2),
              fontSize: 10.5.sp,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.reading});

  final ZodiacReading reading;

  @override
  Widget build(BuildContext context) {
    final item = reading.companion;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28.r),
        border: Border.all(color: const Color(0xFFE8E8F4)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x142F3D78),
            blurRadius: 26,
            offset: Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AspectRatio(
            aspectRatio: 1.25,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                Image.asset(
                  item.assetPath,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.high,
                ),
                Positioned(
                  left: 16.w,
                  top: 15.h,
                  child: Container(
                    padding:
                        EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .84),
                      borderRadius: BorderRadius.circular(18.r),
                      border: Border.all(
                        color: Color(item.accentValue).withValues(alpha: .28),
                      ),
                    ),
                    child: Text(
                      '你的生肖印记',
                      style: TextStyle(
                        color: Color(item.accentValue),
                        fontSize: 11.5.sp,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(18.w, 15.h, 18.w, 18.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Text(
                      '${item.branch}${item.animal}',
                      style: TextStyle(
                        color: const Color(0xFF272A3B),
                        fontSize: 30.sp,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
                    SizedBox(width: 10.w),
                    Expanded(
                      child: Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: const Color(0xFF566073),
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      '${reading.ganZhiYear}年',
                      style: TextStyle(
                        color: const Color(0xFF8B94A5),
                        fontSize: 11.sp,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 13.h),
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.fromLTRB(14.w, 11.h, 14.w, 12.h),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: <Color>[
                        Color(item.accentValue).withValues(alpha: .11),
                        const Color(0xFFFFF3E8).withValues(alpha: .74),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(15.r),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(
                        Icons.format_quote_rounded,
                        color: Color(item.accentValue),
                        size: 20.r,
                      ),
                      SizedBox(width: 7.w),
                      Expanded(
                        child: Text(
                          item.quote,
                          style: TextStyle(
                            color: const Color(0xFF444A5B),
                            fontSize: 13.5.sp,
                            height: 1.55,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 12.h),
                Wrap(
                  spacing: 8.w,
                  runSpacing: 7.h,
                  children: <String>[
                    item.branchElement,
                    item.yinYang,
                    '${item.branch}时',
                    item.direction,
                    '立春划分',
                  ]
                      .map((text) =>
                          _InfoChip(text: text, color: Color(item.accentValue)))
                      .toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(18.r),
        border: Border.all(color: color.withValues(alpha: .25)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11.5.sp,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SparkCard extends StatelessWidget {
  const _SparkCard({required this.item});

  final ZodiacCompanion item;

  @override
  Widget build(BuildContext context) {
    const colors = <Color>[
      Color(0xFF7786DE),
      Color(0xFF4EAF9B),
      Color(0xFFE48779),
    ];
    const icons = <IconData>[
      Icons.search_rounded,
      Icons.shield_outlined,
      Icons.favorite_border_rounded,
    ];
    return _SectionCard(
      title: '你的闪光点',
      icon: Icons.auto_awesome_rounded,
      color: Color(item.accentValue),
      child: Row(
        children: List<Widget>.generate(item.sparks.length, (index) {
          return Expanded(
            child: Container(
              margin: EdgeInsets.only(left: index == 0 ? 0 : 7.w),
              padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 10.h),
              decoration: BoxDecoration(
                color: colors[index].withValues(alpha: .07),
                borderRadius: BorderRadius.circular(15.r),
                border: Border.all(
                  color: colors[index].withValues(alpha: .16),
                ),
              ),
              child: Column(
                children: <Widget>[
                  Icon(icons[index], color: colors[index], size: 20.r),
                  SizedBox(height: 5.h),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      item.sparks[index],
                      style: TextStyle(
                        color: const Color(0xFF3F4555),
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _RelationshipCard extends StatelessWidget {
  const _RelationshipCard({required this.item});

  final ZodiacCompanion item;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: '生肖关系',
      icon: Icons.people_alt_outlined,
      color: Color(item.accentValue),
      child: Row(
        children: <Widget>[
          _RelationItem(label: '默契搭子', value: item.sanHeText),
          _RelationDivider(),
          _RelationItem(label: '六合好友', value: item.liuHe),
          _RelationDivider(),
          _RelationItem(label: '需要磨合', value: '${item.clash} · ${item.harm}'),
        ],
      ),
    );
  }
}

class _RelationItem extends StatelessWidget {
  const _RelationItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: <Widget>[
          Text(
            label,
            style: TextStyle(
              color: const Color(0xFF7A8292),
              fontSize: 11.sp,
            ),
          ),
          SizedBox(height: 6.h),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                color: const Color(0xFF2F3444),
                fontSize: 14.sp,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RelationDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 38.h,
      margin: EdgeInsets.symmetric(horizontal: 6.w),
      color: const Color(0xFFE9ECF3),
    );
  }
}

class _ReminderCard extends StatelessWidget {
  const _ReminderCard({required this.item});

  final ZodiacCompanion item;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: '懂你的提醒',
      icon: Icons.nightlight_round,
      color: Color(item.accentValue),
      child: Column(
        children: <Widget>[
          _ReminderRow(
            icon: Icons.cloud_outlined,
            label: '容易累在',
            value: item.tiredAt,
            color: const Color(0xFF7B83D8),
          ),
          SizedBox(height: 9.h),
          _ReminderRow(
            icon: Icons.chat_bubble_outline_rounded,
            label: '可以试试',
            value: item.suggestion,
            color: const Color(0xFF4EAF9B),
          ),
        ],
      ),
    );
  }
}

class _ReminderRow extends StatelessWidget {
  const _ReminderRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 11.w, vertical: 9.h),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(13.r),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, color: color, size: 18.r),
          SizedBox(width: 8.w),
          SizedBox(
            width: 60.w,
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11.5.sp,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: const Color(0xFF454B5C),
                fontSize: 11.5.sp,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BaseCard extends StatelessWidget {
  const _BaseCard({required this.item});

  final ZodiacCompanion item;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: '生肖底牌',
      icon: Icons.bookmark_border_rounded,
      color: Color(item.accentValue),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              _BaseItem(label: '五行', value: item.branchElement),
              SizedBox(width: 9.w),
              _BaseItem(label: '阴阳', value: item.yinYang),
            ],
          ),
          SizedBox(height: 9.h),
          Row(
            children: <Widget>[
              _BaseItem(label: '时辰', value: item.hours),
              SizedBox(width: 9.w),
              _BaseItem(label: '方位', value: item.direction),
            ],
          ),
        ],
      ),
    );
  }
}

class _LongReadingCard extends StatelessWidget {
  const _LongReadingCard({required this.item});

  final ZodiacCompanion item;

  @override
  Widget build(BuildContext context) {
    final accent = Color(item.accentValue);
    return _SectionCard(
      title: '你的完整解读',
      icon: Icons.menu_book_rounded,
      color: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(horizontal: 11.w, vertical: 8.h),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: .07),
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Text(
              '解读依据：${item.branch}${item.animal} · ${item.branchElement} · ${item.yinYang}支 · 三合六合与冲害关系',
              style: TextStyle(
                color: accent,
                fontSize: 10.5.sp,
                height: 1.45,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          SizedBox(height: 14.h),
          _ReadingParagraph(title: '性格底色', body: item.coreReading),
          _ReadingDivider(color: accent),
          _ReadingParagraph(title: '关系模式', body: item.relationshipReading),
          _ReadingDivider(color: accent),
          _ReadingParagraph(title: '压力与盲点', body: item.pressureReading),
          _ReadingDivider(color: accent),
          _ReadingParagraph(title: '适合你的成长方式', body: item.growthReading),
          SizedBox(height: 4.h),
          Text(
            '生肖提供的是传统文化中的共性观察，不能代替完整八字信息或现实判断。',
            style: TextStyle(
              color: const Color(0xFF8B94A5),
              fontSize: 10.5.sp,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadingParagraph extends StatelessWidget {
  const _ReadingParagraph({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: TextStyle(
            color: const Color(0xFF343A4C),
            fontSize: 13.sp,
            fontWeight: FontWeight.w800,
          ),
        ),
        SizedBox(height: 7.h),
        Text(
          body,
          style: TextStyle(
            color: const Color(0xFF51596B),
            fontSize: 12.5.sp,
            height: 1.75,
          ),
        ),
      ],
    );
  }
}

class _ReadingDivider extends StatelessWidget {
  const _ReadingDivider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 13.h),
      child: Divider(
        height: 1,
        color: color.withValues(alpha: .12),
      ),
    );
  }
}

class _BaseItem extends StatelessWidget {
  const _BaseItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F9FD),
          borderRadius: BorderRadius.circular(13.r),
          border: Border.all(color: const Color(0xFFEAEDF3)),
        ),
        child: Row(
          children: <Widget>[
            Text(
              label,
              style: TextStyle(
                color: const Color(0xFF7C8595),
                fontSize: 11.sp,
              ),
            ),
            SizedBox(width: 6.w),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  value,
                  maxLines: 1,
                  style: TextStyle(
                    color: const Color(0xFF333949),
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(14.w, 13.h, 14.w, 14.h),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .96),
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(color: const Color(0xFFE9ECF3)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x0D34405F),
            blurRadius: 14,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, color: color, size: 19.r),
              SizedBox(width: 7.w),
              Text(
                title,
                style: TextStyle(
                  color: const Color(0xFF303647),
                  fontSize: 15.sp,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          SizedBox(height: 12.h),
          child,
        ],
      ),
    );
  }
}

class _ProfileMissing extends StatelessWidget {
  const _ProfileMissing({required this.onComplete});

  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(28.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(28.r),
              child: Image.asset(
                'assets/zodiac/rabbit.webp',
                width: 230.r,
                height: 230.r,
                fit: BoxFit.cover,
              ),
            ),
            SizedBox(height: 22.h),
            Text(
              '让生肖印记找到你',
              style: TextStyle(
                color: const Color(0xFF2B3040),
                fontSize: 22.sp,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 10.h),
            Text(
              '补充一次出生资料，即可匹配你的农历生肖。\n具体日期不会展示在页面或分享图中。',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: const Color(0xFF768091),
                fontSize: 13.sp,
                height: 1.65,
              ),
            ),
            SizedBox(height: 24.h),
            FilledButton(
              onPressed: onComplete,
              style: FilledButton.styleFrom(
                minimumSize: Size(220.w, 48.h),
                backgroundColor: const Color(0xFF7B83D8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(17.r),
                ),
              ),
              child: const Text('完善出生资料'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(28.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.sentiment_dissatisfied_rounded,
              color: Color(0xFF8D94A5),
              size: 44,
            ),
            SizedBox(height: 12.h),
            Text(message, style: TextStyle(fontSize: 14.sp)),
            SizedBox(height: 18.h),
            OutlinedButton(onPressed: onRetry, child: const Text('重新寻找')),
          ],
        ),
      ),
    );
  }
}

class ZodiacShareCard extends StatelessWidget {
  const ZodiacShareCard({super.key, required this.reading});

  final ZodiacReading reading;

  @override
  Widget build(BuildContext context) {
    final item = reading.companion;
    final accent = Color(item.accentValue);
    return Container(
      width: 720,
      height: 1280,
      padding: const EdgeInsets.fromLTRB(48, 42, 48, 34),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color(0xFFF5F0FF),
            Color(0xFFFFFBF8),
            Color(0xFFECFAF8),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Text(
                '玄遇 · 生肖印记',
                style: TextStyle(
                  color: Color(0xFF272C3C),
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .72),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: accent.withValues(alpha: .28)),
                ),
                child: Text(
                  '你的生肖印记',
                  style: TextStyle(
                    color: accent,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          ClipRRect(
            borderRadius: BorderRadius.circular(42),
            child: SizedBox(
              height: 545,
              child: Image.asset(item.assetPath, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(height: 28),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                '${item.branch}${item.animal}',
                style: const TextStyle(
                  color: Color(0xFF252A39),
                  fontSize: 58,
                  height: 1,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Text(
                  item.title,
                  style: const TextStyle(
                    color: Color(0xFF596174),
                    fontSize: 25,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${reading.ganZhiYear}年',
                style: const TextStyle(
                  color: Color(0xFF8C94A4),
                  fontSize: 19,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 22),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .82),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: accent.withValues(alpha: .14)),
            ),
            child: Text(
              '“${item.quote}”',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF3E4556),
                fontSize: 28,
                height: 1.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: item.sparks.map((spark) {
              return Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 5),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    spark,
                    style: TextStyle(
                      color: accent,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          Row(
            children: <Widget>[
              _ShareRelation(label: '默契搭子', value: item.sanHeText),
              _ShareRelation(label: '六合好友', value: item.liuHe),
              _ShareRelation(
                label: '需要磨合',
                value: '${item.clash} · ${item.harm}',
              ),
            ],
          ),
          const Spacer(),
          const Divider(color: Color(0xFFDDE2E9)),
          const SizedBox(height: 14),
          const Text(
            CulturalReferenceNotice.text,
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF939BA9), fontSize: 16),
          ),
        ],
      ),
    );
  }
}

class _ShareRelation extends StatelessWidget {
  const _ShareRelation({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: <Widget>[
          Text(
            label,
            style: const TextStyle(color: Color(0xFF858D9C), fontSize: 17),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF333949),
              fontSize: 23,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
