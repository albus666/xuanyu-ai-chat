import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:xuanyu/features/merit/models/merit_models.dart';

/// 已收集文案列表（设置页入口，无需木鱼等级解锁）
class MeritCollectedPage extends StatelessWidget {
  const MeritCollectedPage({super.key, required this.bundle, required this.data});

  final MeritBundle bundle;
  final MeritSaveData data;

  @override
  Widget build(BuildContext context) {
    final collected = bundle.texts.where((t) => data.collectedTextIds.contains(t.id)).toList();
    final categories = <String, List<MeritTextItem>>{};
    for (final t in collected) {
      categories.putIfAbsent(t.category, () => []).add(t);
    }

    return Scaffold(
      backgroundColor: MeritColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(
          '已收集文案 (${collected.length})',
          style: const TextStyle(color: MeritColors.textPrimary),
        ),
        iconTheme: const IconThemeData(color: MeritColors.textPrimary),
      ),
      body: collected.isEmpty
          ? Center(
              child: Text(
                '还没有收集到文案\n继续敲木鱼试试',
                textAlign: TextAlign.center,
                style: TextStyle(color: MeritColors.textSecondary, fontSize: 14.sp),
              ),
            )
          : ListView(
              padding: EdgeInsets.all(16.w),
              children: categories.entries.map((e) {
                return Container(
                  margin: EdgeInsets.only(bottom: 12.h),
                  padding: EdgeInsets.all(14.w),
                  decoration: BoxDecoration(
                    color: MeritColors.card,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_catLabel(e.key)}  ${e.value.length}',
                        style: TextStyle(color: MeritColors.gold, fontSize: 14.sp, fontWeight: FontWeight.w700),
                      ),
                      SizedBox(height: 8.h),
                      ...e.value.map((t) => Padding(
                            padding: EdgeInsets.only(bottom: 6.h),
                            child: Text(
                              t.content,
                              style: TextStyle(
                                color: t.rarity == 'epic'
                                    ? MeritColors.epic
                                    : t.rarity == 'rare'
                                        ? MeritColors.rare
                                        : MeritColors.textPrimary,
                                fontSize: 12.sp,
                              ),
                            ),
                          )),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }

  String _catLabel(String c) => switch (c) {
        'toxic' => '毒舌扎心款',
        'absurd' => '无厘头脑洞款',
        'bazi' => '八字能量款',
        'scene' => '场景共鸣款',
        'rebirth' => '转生专属款',
        'hidden' => '隐藏款',
        _ => c,
      };
}
