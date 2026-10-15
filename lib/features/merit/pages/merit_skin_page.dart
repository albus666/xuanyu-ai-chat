import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:xuanyu/features/merit/models/merit_models.dart';
import 'package:xuanyu/features/merit/models/merit_skins.dart';
import 'package:xuanyu/features/merit/services/merit_storage_service.dart';

/// 木鱼皮肤图鉴 / 切换（祈福版：全部解锁）
class MeritSkinPage extends StatelessWidget {
  const MeritSkinPage({
    super.key,
    required this.data,
    required this.onChanged,
  });

  final MeritSaveData data;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final d = data;
    return Scaffold(
      backgroundColor: MeritColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('木鱼皮肤',
            style: TextStyle(color: MeritColors.textPrimary)),
        iconTheme: const IconThemeData(color: MeritColors.textPrimary),
      ),
      body: ListView.separated(
        padding: EdgeInsets.all(16.w),
        itemCount: MeritSkinDef.defaults.length,
        separatorBuilder: (_, __) => SizedBox(height: 12.h),
        itemBuilder: (context, i) {
          final skin = MeritSkinDef.defaults[i];
          final selected = d.activeSkin == skin.id;
          return Material(
            color: MeritColors.card,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () async {
                d.activeSkin = skin.id;
                if (!d.unlockedSkins.contains(skin.id)) {
                  d.unlockedSkins.add(skin.id);
                }
                await MeritStorageService.save(d);
                onChanged();
                if (context.mounted) Navigator.pop(context);
              },
              child: Padding(
                padding: EdgeInsets.all(12.w),
                child: Row(
                  children: [
                    Container(
                      width: 72.w,
                      height: 72.w,
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selected
                              ? MeritColors.gold
                              : MeritColors.cardBorder,
                          width: selected ? 2 : 1,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(11),
                        child: _skinImage(skin),
                      ),
                    ),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            skin.name,
                            style: TextStyle(
                              color: MeritColors.textPrimary,
                              fontSize: 14.sp,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: 4.h),
                          Text(
                            skin.unlockHint,
                            style: TextStyle(
                              color: MeritColors.textSecondary,
                              fontSize: 11.sp,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (selected)
                      const Icon(Icons.check_circle, color: MeritColors.gold),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _skinImage(MeritSkinDef skin) {
    final url = skin.imageUrl.trim();
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return Image.network(url,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) =>
              Image.asset(skin.asset, fit: BoxFit.contain));
    }
    return Image.asset(skin.asset, fit: BoxFit.contain);
  }
}
