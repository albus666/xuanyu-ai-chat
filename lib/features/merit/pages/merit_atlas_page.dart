import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:xuanyu/features/merit/models/merit_models.dart';

class MeritAtlasPage extends StatelessWidget {
  const MeritAtlasPage({super.key, required this.bundle, required this.data});

  final MeritBundle bundle;
  final MeritSaveData data;

  @override
  Widget build(BuildContext context) {
    final categories = <String, List<MeritTextItem>>{};
    for (final t in bundle.texts) {
      categories.putIfAbsent(t.category, () => []).add(t);
    }

    return Scaffold(
      backgroundColor: MeritColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('文案图鉴', style: TextStyle(color: MeritColors.textPrimary)),
        iconTheme: const IconThemeData(color: MeritColors.textPrimary),
      ),
      body: ListView(
        padding: EdgeInsets.all(16.w),
        children: categories.entries.map((e) {
          final collected = e.value.where((t) => data.collectedTextIds.contains(t.id)).length;
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
                  '${_catLabel(e.key)}  $collected/${e.value.length}',
                  style: TextStyle(color: MeritColors.gold, fontSize: 14.sp, fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 8.h),
                ...e.value.map((t) {
                  final got = data.collectedTextIds.contains(t.id);
                  return Padding(
                    padding: EdgeInsets.only(bottom: 6.h),
                    child: Text(
                      got ? t.content : '???',
                      style: TextStyle(
                        color: got
                            ? (t.rarity == 'epic' ? MeritColors.epic : MeritColors.textPrimary)
                            : MeritColors.textSecondary,
                        fontSize: 12.sp,
                      ),
                    ),
                  );
                }),
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
