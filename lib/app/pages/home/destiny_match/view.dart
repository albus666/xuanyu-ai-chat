import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:xuanyu/app/common/index.dart';
import 'package:xuanyu/app/bootstrap/auth_state.dart';

import 'archive_card_load_gate.dart';

import 'package:xuanyu/app/pages/home/destiny_match/controller.dart';
import 'package:xuanyu/app/pages/home/destiny_match/archive_card_background.dart';
import 'package:xuanyu/app/pages/home/home_index/widgets/index.dart';
import 'package:xuanyu/features/fortune/paipan/models/region.dart';
import 'package:xuanyu/features/fortune/paipan/widgets/birth_place_picker_sheet.dart';
import 'package:xuanyu/core/utils/app_toast.dart';
import 'package:xuanyu/core/utils/gallery_image_saver.dart';
import 'package:xuanyu/features/community/user_profile_page.dart';
import 'package:xuanyu/features/message/chat_page.dart';

class DestinyMatchPage extends StatelessWidget {
  const DestinyMatchPage({super.key});

  Future<void> _saveArchiveCard(
    BuildContext context,
    DestinyMatchController controller,
  ) async {
    if (controller.savingArchiveCard || !controller.archiveReady) {
      return;
    }
    controller.savingArchiveCard = true;
    try {
      final boundary = controller.archiveCardKey.currentContext
          ?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null || boundary.size.shortestSide <= 0) {
        throw const GalleryImageSaveException('卡片尚未准备好，请稍后重试');
      }
      final targetRatio = (1200 / boundary.size.width).clamp(2.0, 4.0);
      final image = await boundary.toImage(pixelRatio: targetRatio);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) throw const GalleryImageSaveException('卡片生成失败');
      final now = DateTime.now().millisecondsSinceEpoch;
      final destination = await GalleryImageSaver.savePng(
        data.buffer.asUint8List(),
        fileName: 'xuanyu_destiny_card_$now.png',
      );
      if (context.mounted) {
        final location = destination == GalleryImageSaveDestination.file
            ? '已保存图片文件'
            : '已保存到相册';
        showAppToast(
          context,
          controller.hideMyBirthDate
              ? '$location（出生日期已隐藏）'
              : '$location（包含出生日期）',
        );
      }
    } on PlatformException catch (error) {
      if (!context.mounted) return;
      showAppToast(
        context,
        error.code == 'PHOTO_PERMISSION_DENIED'
            ? '请允许玄遇添加照片后再保存'
            : (error.message ?? '保存失败，请重试'),
      );
    } on GalleryImageSaveException catch (error) {
      if (context.mounted) showAppToast(context, error.message);
    } catch (_) {
      if (context.mounted) showAppToast(context, '保存失败，请重试');
    } finally {
      controller.savingArchiveCard = false;
    }
  }

  Widget _archivePlaceholder(DestinyMatchController c) {
    return Container(
      key: const ValueKey('destiny-archive-placeholder'),
      height: 204.h,
      margin: EdgeInsets.symmetric(horizontal: 16.w),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(18.r)),
      child: Stack(
        children: [
          const Positioned.fill(child: ArchiveCardBackground()),
          Center(
            child: c.archiveError == null
                ? const Text('正在准备命理档案…', style: TextStyle(color: Colors.white))
                : TextButton(
                    onPressed: c.loadArchive,
                    child: Text(
                      c.archiveError!,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // ============ 我的命理档案 banner ============
  Widget _buildArchiveCard(BuildContext context, DestinyMatchController c) {
    if (!c.archiveReady) return _archivePlaceholder(c);
    final tags = <String>[
      if (c.xishen.isNotEmpty) c.xishen,
      if (c.yongshen.isNotEmpty) c.yongshen,
      if (c.ziweiPattern.isNotEmpty) '紫微格局 ${c.ziweiPattern}',
      if (c.zodiac.isNotEmpty) '生肖 ${c.zodiac}',
      if (c.constellation.isNotEmpty) '${c.constellation}座',
    ];
    return ArchiveCardLoadGate(
      assetPath: c.minglingAssetPath,
      placeholder: _archivePlaceholder(c),
      child: Semantics(
        button: true,
        explicitChildNodes: true,
        label: '保存命理卡片',
        hint: c.hideMyBirthDate ? '出生日期已隐藏' : '将包含出生日期',
        child: GestureDetector(
          key: const ValueKey('destiny-archive-card-save'),
          behavior: HitTestBehavior.opaque,
          onTap: () => _saveArchiveCard(context, c),
          child: RepaintBoundary(
            key: c.archiveCardKey,
            child: Container(
              height: 204.h,
              margin: EdgeInsets.symmetric(horizontal: 16.w),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18.r),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF42C9C7).withValues(alpha: .18),
                    blurRadius: 18.r,
                    offset: Offset(0, 8.h),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  const Positioned.fill(child: ArchiveCardBackground()),
                  Padding(
                    padding: EdgeInsets.fromLTRB(16.w, 14.h, 10.w, 12.h),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  _birthDateSwitch(c),
                                  if (c.visibleBirthDate != '--' &&
                                      c.visibleBirthDate.isNotEmpty) ...[
                                    SizedBox(width: 8.w),
                                    Flexible(
                                      child: Text(
                                        c.visibleBirthDate,
                                        maxLines: 1,
                                        overflow: TextOverflow.fade,
                                        softWrap: false,
                                        style: TextStyle(
                                          fontSize: 12.sp,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.white.withValues(
                                            alpha: .92,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              SizedBox(height: 10.h),
                              Text(
                                c.minglingTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 21.sp,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: .3,
                                  color: Colors.white,
                                  shadows: [
                                    Shadow(
                                      color: const Color(0xFF247E91)
                                          .withValues(alpha: .18),
                                      blurRadius: 4.r,
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(height: 3.h),
                              Text(
                                c.minglingTemperament,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11.5.sp,
                                  color: Colors.white.withValues(alpha: .84),
                                ),
                              ),
                              SizedBox(height: 12.h),
                              if (tags.isEmpty)
                                Text(
                                  '完善出生资料后查看命理标签',
                                  style: TextStyle(
                                    fontSize: 11.sp,
                                    color: Colors.white.withValues(alpha: .72),
                                  ),
                                )
                              else
                                Wrap(
                                  spacing: 6.w,
                                  runSpacing: 6.h,
                                  children: tags.map(_archiveTag).toList(),
                                ),
                            ],
                          ),
                        ),
                        SizedBox(width: 6.w),
                        SizedBox(
                          width: 104.w,
                          height: double.infinity,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Positioned(
                                right: 2.w,
                                top: 0,
                                child: Icon(
                                  Icons.favorite_outline_rounded,
                                  size: 17.r,
                                  color: Colors.white.withValues(alpha: .62),
                                ),
                              ),
                              if (c.minglingAssetPath != null)
                                Positioned.fill(
                                  top: 18.h,
                                  child: Image.asset(
                                    c.minglingAssetPath!,
                                    fit: BoxFit.contain,
                                    alignment: Alignment.bottomCenter,
                                    errorBuilder: (_, __, ___) =>
                                        const SizedBox.shrink(),
                                  ),
                                )
                              else
                                Center(
                                  child: Icon(
                                    Icons.auto_awesome_rounded,
                                    size: 46.r,
                                    color: Colors.white.withValues(alpha: .38),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _birthDateSwitch(DestinyMatchController c) {
    return Semantics(
      button: true,
      label: c.hideMyBirthDate ? '显示出生日期' : '隐藏出生日期',
      child: GestureDetector(
        onTap: c.toggleBirthDateVisibility,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 34.w,
          height: 19.h,
          padding: EdgeInsets.all(2.r),
          decoration: BoxDecoration(
            color: c.hideMyBirthDate
                ? Colors.white.withValues(alpha: .38)
                : Colors.white.withValues(alpha: .22),
            borderRadius: BorderRadius.circular(20.r),
            border: Border.all(
              color: Colors.white.withValues(alpha: .58),
              width: .8,
            ),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 180),
            alignment: c.hideMyBirthDate
                ? Alignment.centerRight
                : Alignment.centerLeft,
            child: Container(
              width: 14.r,
              height: 14.r,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF237C8D).withValues(alpha: .2),
                    blurRadius: 3.r,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _archiveTag(String text) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 7.w, vertical: 3.h),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.20),
        borderRadius: BorderRadius.circular(6.r),
        border: Border.all(
          color: Colors.white.withValues(alpha: .16),
          width: .6,
        ),
      ),
      child: Text(
        text,
        maxLines: 1,
        softWrap: false,
        style: TextStyle(
          fontSize: 10.5.sp,
          fontWeight: FontWeight.w500,
          color: Colors.white.withValues(alpha: .94),
        ),
      ),
    );
  }

  // ============ 筛选条件 ============
  Widget _segmentBtn({
    required String text,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 32.h,
        constraints: BoxConstraints(minWidth: 56.w),
        padding: EdgeInsets.symmetric(horizontal: 14.w),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.08)
              : const Color(0xFFF2F2F2),
          border: Border.all(
            color: selected ? AppColors.primary : Colors.transparent,
            width: 1.2,
          ),
          borderRadius: BorderRadius.circular(8.r),
        ),
        alignment: Alignment.center,
        child: Text(
          text,
          maxLines: 1,
          softWrap: false,
          style: TextStyle(
            fontSize: 13.sp,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? AppColors.primary : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }

  Widget _filterRow({
    required String label,
    required Widget right,
    bool divider = true,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 10.h),
      decoration: BoxDecoration(
        border: divider
            ? const Border(
                bottom: BorderSide(color: AppColors.divider, width: 0.5),
              )
            : null,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 56.w,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14.sp,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          Expanded(child: right),
        ],
      ),
    );
  }

  Widget _filterInput({
    required TextEditingController controller,
    required String hint,
    TextInputType? keyboardType,
  }) {
    return Container(
      width: 70.w,
      height: 32.h,
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7F7),
        borderRadius: BorderRadius.circular(8.r),
        border: Border.all(color: const Color(0xFFE6E6E6), width: 1),
      ),
      alignment: Alignment.center,
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13.sp, color: AppColors.textPrimary),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary),
          border: InputBorder.none,
          isCollapsed: true,
        ),
      ),
    );
  }

  Widget _selectFilterField({
    required String? value,
    required String placeholder,
    required VoidCallback onTap,
  }) {
    final selected = value != null && value.isNotEmpty;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            selected ? value : placeholder,
            style: TextStyle(
              fontSize: 14.sp,
              color: selected ? AppColors.textPrimary : AppColors.textSecondary,
            ),
          ),
          SizedBox(width: 4.w),
          Icon(Icons.chevron_right, size: 16.r, color: AppColors.textSecondary),
        ],
      ),
    );
  }

  Future<void> _pickDesignatedRegion(
    BuildContext context,
    DestinyMatchController c,
  ) async {
    Region? initial;
    if (c.designatedRegionCode != null) {
      initial = Region.placeholder(
        name: c.designatedRegionLabel ?? '',
        extPath: c.designatedRegionCode,
      );
    }
    await BirthPlacePickerSheet.show(
      context,
      initialRegion: initial,
      onConfirm: (region) {
        final label = region.extPath.isNotEmpty ? region.extPath : region.name;
        c.setDesignatedRegion(code: label, label: _shortRegionLabel(region));
      },
    );
  }

  String _shortRegionLabel(Region r) {
    if (r.extPath.isNotEmpty) {
      final parts = r.extPath.split('/');
      if (parts.length >= 2) return parts[parts.length - 2];
      return parts.last;
    }
    return r.name;
  }

  Future<void> _pickFilterOption(
    BuildContext context,
    DestinyMatchController c, {
    required String title,
    required List<String> options,
    required String? current,
    required void Function(String?) onSelected,
  }) async {
    final picked = await showModalBottomSheet<String?>(
      context: context,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.r)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 16.h),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                SizedBox(height: 12.h),
                Wrap(
                  spacing: 10.w,
                  runSpacing: 10.h,
                  children: [
                    _pickerChip(
                      label: '不限',
                      selected: current == null,
                      onTap: () => Navigator.pop(ctx, null),
                    ),
                    for (final item in options)
                      _pickerChip(
                        label: item,
                        selected: current == item,
                        onTap: () => Navigator.pop(ctx, item),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    if (!context.mounted) return;
    onSelected(picked);
  }

  Future<void> _pickMultipleFilterOptions(
    BuildContext context, {
    required String title,
    required List<String> options,
    required List<String> current,
    required ValueChanged<String> onToggle,
    required VoidCallback onClear,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.r)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 18.h),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 16.sp,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        onClear();
                        setSheetState(() {});
                      },
                      child: const Text('清空'),
                    ),
                  ],
                ),
                Text(
                  '可多选；同类条件命中任意一个即可',
                  style: TextStyle(fontSize: 11.sp, color: AppColors.textHint),
                ),
                SizedBox(height: 12.h),
                Wrap(
                  spacing: 10.w,
                  runSpacing: 10.h,
                  children: [
                    for (final item in options)
                      _pickerChip(
                        label: item,
                        selected: current.contains(item),
                        onTap: () {
                          onToggle(item);
                          setSheetState(() {});
                        },
                      ),
                  ],
                ),
                SizedBox(height: 16.h),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(
                    current.isEmpty ? '不限' : '完成（已选${current.length}个）',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _pickerChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.08)
              : const Color(0xFFF2F2F2),
          border: Border.all(
            color: selected ? AppColors.primary : Colors.transparent,
            width: 1.2,
          ),
          borderRadius: BorderRadius.circular(8.r),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13.sp,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? AppColors.primary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildFilterCard(BuildContext context, DestinyMatchController c) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      child: SectionCard(
        padding: EdgeInsets.symmetric(horizontal: 14.w),
        child: Column(
          children: [
            _filterRow(
              label: '想聊',
              right: Wrap(
                alignment: WrapAlignment.end,
                spacing: 6.w,
                runSpacing: 6.h,
                children: MatchIntent.values
                    .map(
                      (item) => _segmentBtn(
                        text: item.label,
                        selected: c.intent == item,
                        onTap: () => c.setIntent(item),
                      ),
                    )
                    .toList(),
              ),
            ),
            _filterRow(
              label: '性别',
              right: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _segmentBtn(
                    text: '全部',
                    selected: c.gender == MatchGender.all,
                    onTap: () => c.setGender(MatchGender.all),
                  ),
                  SizedBox(width: 10.w),
                  _segmentBtn(
                    text: '男',
                    selected: c.gender == MatchGender.male,
                    onTap: () => c.setGender(MatchGender.male),
                  ),
                  SizedBox(width: 10.w),
                  _segmentBtn(
                    text: '女',
                    selected: c.gender == MatchGender.female,
                    onTap: () => c.setGender(MatchGender.female),
                  ),
                ],
              ),
            ),
            _filterRow(
              label: '年龄',
              right: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _filterInput(
                    controller: c.minAgeCtrl,
                    hint: '最小',
                    keyboardType: TextInputType.number,
                  ),
                  SizedBox(width: 10.w),
                  Text(
                    '至',
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  SizedBox(width: 10.w),
                  _filterInput(
                    controller: c.maxAgeCtrl,
                    hint: '最大',
                    keyboardType: TextInputType.number,
                  ),
                ],
              ),
            ),
            _filterRow(
              label: '生日',
              right: Container(
                alignment: Alignment.centerRight,
                padding: EdgeInsets.symmetric(vertical: 4.h),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: IntrinsicWidth(
                        child: _segmentBtn(
                          text: '同年同月同日同时出生',
                          selected: c.sameBirth,
                          onTap: c.toggleSameBirth,
                        ),
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      '仅展示与您公历出生日期和时辰完全相同的用户',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 10.sp,
                        color: AppColors.textHint,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _filterRow(
              label: '天干',
              right: _selectFilterField(
                value: c.filterStems.isEmpty ? null : c.filterStems.join('、'),
                placeholder: '十天干（不限）',
                onTap: () => _pickMultipleFilterOptions(
                  context,
                  title: '选择天干',
                  options: DestinyMatchController.stemOptions,
                  current: c.filterStems,
                  onToggle: c.toggleFilterStem,
                  onClear: c.clearFilterStems,
                ),
              ),
            ),
            _filterRow(
              label: '地支',
              right: _selectFilterField(
                value: c.filterBranches.isEmpty
                    ? null
                    : c.filterBranches.join('、'),
                placeholder: '十二地支（不限）',
                onTap: () => _pickMultipleFilterOptions(
                  context,
                  title: '选择地支',
                  options: DestinyMatchController.branchOptions,
                  current: c.filterBranches,
                  onToggle: c.toggleFilterBranch,
                  onClear: c.clearFilterBranches,
                ),
              ),
            ),
            _filterRow(
              label: '五行',
              right: Wrap(
                alignment: WrapAlignment.end,
                spacing: 6.w,
                runSpacing: 6.h,
                children: DestinyMatchController.elementOptions
                    .map(
                      (element) => _elementChip(
                        element,
                        selected: c.filterElements.contains(element),
                        onTap: () => c.toggleFilterElement(element),
                      ),
                    )
                    .toList(),
              ),
            ),
            _filterRow(
              label: '地区',
              right: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _segmentBtn(
                    text: '同城',
                    selected: c.region == MatchRegion.sameCity,
                    onTap: () => c.setRegion(MatchRegion.sameCity),
                  ),
                  SizedBox(width: 10.w),
                  _segmentBtn(
                    text: c.designatedRegionLabel ?? '指定地区',
                    selected: c.region == MatchRegion.designated,
                    onTap: () => _pickDesignatedRegion(context, c),
                  ),
                  if (c.designatedRegionLabel != null) ...[
                    SizedBox(width: 4.w),
                    GestureDetector(
                      onTap: c.clearDesignatedRegion,
                      child: Icon(
                        Icons.close,
                        size: 16.r,
                        color: AppColors.textHint,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            _filterRow(
              label: '生肖',
              right: _selectFilterField(
                value: c.filterZodiac,
                placeholder: '请选择',
                onTap: () => _pickFilterOption(
                  context,
                  c,
                  title: '选择生肖',
                  options: DestinyMatchController.zodiacOptions,
                  current: c.filterZodiac,
                  onSelected: c.setFilterZodiac,
                ),
              ),
            ),
            _filterRow(
              label: '星座',
              divider: false,
              right: _selectFilterField(
                value: c.filterConstellation,
                placeholder: '请选择',
                onTap: () => _pickFilterOption(
                  context,
                  c,
                  title: '选择星座',
                  options: DestinyMatchController.constellationOptions,
                  current: c.filterConstellation,
                  onSelected: c.setFilterConstellation,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _elementChip(
    String element, {
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36.w,
        height: 30.h,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: .1)
              : const Color(0xFFF2F2F2),
          borderRadius: BorderRadius.circular(8.r),
          border: Border.all(
            color: selected ? AppColors.primary : Colors.transparent,
          ),
        ),
        child: Text(
          element,
          style: TextStyle(
            fontSize: 12.sp,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
            color: selected ? AppColors.primary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  // ============ 有缘人列表 ============
  Widget _buildUserListHeader(DestinyMatchController c) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 8.h),
      child: Row(
        children: [
          Text(
            '同频推荐',
            style: TextStyle(
              fontSize: 15.sp,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(width: 4.w),
          Container(
            width: 4.r,
            height: 4.r,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primaryLight,
            ),
          ),
          const Spacer(),
          Text(
            '共${c.total}位',
            style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _avatar(FateUser user, double size) {
    final url = user.avatarUrl;
    if (url == null || url.isEmpty) {
      return AvatarPlaceholder(text: user.name, size: size);
    }
    return ClipOval(
      child: Image.network(
        url,
        width: size.r,
        height: size.r,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            AvatarPlaceholder(text: user.name, size: size),
      ),
    );
  }

  Future<void> _openProfile(BuildContext context, FateUser user) async {
    final userId = user.userId;
    if (userId == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => UserProfilePage(userId: userId)),
    );
  }

  Future<void> _startChat(
    BuildContext context,
    DestinyMatchController c,
    FateUser user,
  ) async {
    try {
      final data = await c.createConversation(user);
      if (!context.mounted || data == null) return;
      final conversationId = (data['conversationId'] as num?)?.toInt();
      if (conversationId == null) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ChatPage(
            conversationId: conversationId,
            title: (data['title'] as String?)?.trim().isNotEmpty == true
                ? (data['title'] as String).trim()
                : user.name,
            conversationType: 'single',
            peerUserId: user.userId,
          ),
        ),
      );
    } on DioException catch (error) {
      if (!context.mounted) return;
      final body = error.response?.data;
      showAppToast(
        context,
        body is Map ? body['message']?.toString() ?? '无法发起私信' : '无法发起私信',
      );
    }
  }

  Future<void> _showMatchDetail(
    BuildContext context,
    DestinyMatchController c,
    FateUser user,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22.r)),
      ),
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * .82,
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20.w, 18.h, 20.w, 22.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 34.w,
                    height: 4.h,
                    decoration: BoxDecoration(
                      color: const Color(0xFFDDE4E3),
                      borderRadius: BorderRadius.circular(99.r),
                    ),
                  ),
                ),
                SizedBox(height: 16.h),
                Row(
                  children: [
                    _avatar(user, 58),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user.name,
                            style: TextStyle(
                              fontSize: 18.sp,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          SizedBox(height: 4.h),
                          Text(
                            [
                              user.age,
                              if (user.region.isNotEmpty) user.region,
                              user.zodiac,
                            ].join(' · '),
                            style: TextStyle(
                              fontSize: 12.sp,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${user.matchScore}%',
                      style: TextStyle(
                        fontSize: 23.sp,
                        fontWeight: FontWeight.w900,
                        color: AppColors.primaryDark,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 16.h),
                Text(
                  user.matchTitle,
                  style: TextStyle(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (user.matchReason.isNotEmpty) ...[
                  SizedBox(height: 6.h),
                  Text(
                    user.matchReason,
                    style: TextStyle(
                      fontSize: 13.sp,
                      height: 1.55,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
                SizedBox(height: 12.h),
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(
                    horizontal: 12.w,
                    vertical: 10.h,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7FAFA),
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                  child: Text(
                    user.intro,
                    style: TextStyle(
                      fontSize: 12.sp,
                      height: 1.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                if (user.dimensions.isNotEmpty) ...[
                  SizedBox(height: 18.h),
                  Text(
                    '匹配维度',
                    style: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  SizedBox(height: 9.h),
                  for (final entry in user.dimensions.entries)
                    Padding(
                      padding: EdgeInsets.only(bottom: 9.h),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 72.w,
                            child: Text(
                              entry.key,
                              style: TextStyle(
                                fontSize: 12.sp,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(99.r),
                              child: LinearProgressIndicator(
                                minHeight: 6.h,
                                value: entry.value / 100,
                                backgroundColor: const Color(0xFFEDF3F2),
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                          SizedBox(width: 8.w),
                          Text(
                            '${entry.value}',
                            style: TextStyle(
                              fontSize: 11.sp,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                _detailList(
                  '容易同频的地方',
                  user.highlights,
                  Icons.auto_awesome_rounded,
                  AppColors.primaryDark,
                ),
                _detailList(
                  '相处时可以留意',
                  user.watchouts,
                  Icons.chat_bubble_outline_rounded,
                  const Color(0xFF9B7A45),
                ),
                _detailList(
                  '可以这样开场',
                  user.topics,
                  Icons.forum_outlined,
                  const Color(0xFF6574B8),
                ),
                SizedBox(height: 12.h),
                Text(
                  '匹配全程免费。结果用于传统文化交友参考，不代表关系承诺。对方回复前，私信仍受陌生人发送条数限制。',
                  style: TextStyle(
                    fontSize: 10.sp,
                    height: 1.45,
                    color: AppColors.textHint,
                  ),
                ),
                SizedBox(height: 16.h),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          _openProfile(context, user);
                        },
                        child: const Text('查看主页'),
                      ),
                    ),
                    SizedBox(width: 10.w),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          _startChat(context, c, user);
                        },
                        child: const Text('免费打个招呼'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _detailList(
    String title,
    List<String> items,
    IconData icon,
    Color color,
  ) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(top: 14.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 14.sp,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 7.h),
          for (final item in items)
            Padding(
              padding: EdgeInsets.only(bottom: 5.h),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 14.r, color: color),
                  SizedBox(width: 6.w),
                  Expanded(
                    child: Text(
                      item,
                      style: TextStyle(
                        fontSize: 12.sp,
                        height: 1.45,
                        color: AppColors.textSecondary,
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

  Widget _buildUserItem(
    BuildContext context,
    DestinyMatchController c,
    FateUser u,
  ) {
    final gIcon = u.gender == 2 ? Icons.female : Icons.male;
    final gColor = u.gender == 2 ? Colors.pinkAccent : AppColors.primary;
    return GestureDetector(
      onTap: () => _showMatchDetail(context, c, u),
      child: SectionCard(
        margin: EdgeInsets.only(bottom: 10.h),
        padding: EdgeInsets.all(12.r),
        child: Column(
          children: [
            Row(
              children: [
                _avatar(u, 44),
                SizedBox(width: 10.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            u.name,
                            style: TextStyle(
                              fontSize: 14.sp,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          SizedBox(width: 4.w),
                          Icon(gIcon, size: 12.r, color: gColor),
                        ],
                      ),
                      SizedBox(height: 4.h),
                      Text(
                        [
                          u.age,
                          if (u.region.isNotEmpty) u.region,
                          u.zodiac,
                        ].join('·'),
                        style: TextStyle(
                          fontSize: 11.sp,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 9.w, vertical: 5.h),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: .09),
                    borderRadius: BorderRadius.circular(99.r),
                  ),
                  child: Text(
                    '${u.matchScore}%',
                    style: TextStyle(
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primaryDark,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 10.h),
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
              decoration: BoxDecoration(
                color: const Color(0xFFF7FBFA),
                borderRadius: BorderRadius.circular(9.r),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    u.matchTitle,
                    style: TextStyle(
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryDark,
                    ),
                  ),
                  if (u.matchReason.isNotEmpty) ...[
                    SizedBox(height: 3.h),
                    Text(
                      u.matchReason,
                      style: TextStyle(
                        fontSize: 10.sp,
                        height: 1.35,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(height: 8.h),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  '查看匹配详情 · 免费打招呼',
                  style: TextStyle(
                    fontSize: 10.sp,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryDark,
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 15.r,
                  color: AppColors.primaryDark,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOptIn(DestinyMatchController c) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 26.h, 16.w, 20.h),
      child: Column(
        children: [
          Container(
            width: 74.r,
            height: 74.r,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: .1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.favorite_border_rounded,
              size: 34.r,
              color: AppColors.primaryDark,
            ),
          ),
          SizedBox(height: 16.h),
          Text(
            '免费开启缘分匹配',
            style: TextStyle(
              fontSize: 19.sp,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 9.h),
          Text(
            '仅向同样主动开启的成年用户展示匹配卡。不公开你的完整八字、出生日期和时辰，也不收取任何费用。',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.sp,
              height: 1.6,
              color: AppColors.textSecondary,
            ),
          ),
          SizedBox(height: 20.h),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: c.enabling ? null : c.enableMatching,
              child: Text(c.enabling ? '正在开启...' : '同意并开启免费匹配'),
            ),
          ),
          if ((c.loadError ?? '').isNotEmpty) ...[
            SizedBox(height: 10.h),
            Text(
              c.loadError!,
              style: TextStyle(fontSize: 12.sp, color: AppColors.textHint),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GetBuilder<DestinyMatchController>(
      init: DestinyMatchController(
        preferences:
            Get.isRegistered<AuthState>() ? Get.find<AuthState>().prefs : null,
      ),
      id: 'destiny',
      builder: (c) {
        return Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_ios_new, size: 18.r),
              onPressed: () => NavUtils.goBack(),
            ),
            title: const Text('缘分匹配'),
          ),
          body: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: EdgeInsets.only(bottom: 16.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: 4.h),
                  _buildArchiveCard(context, c),
                  if (!c.privacyReady)
                    SizedBox(height: 240.h)
                  else if (!c.allowFateMatch)
                    _buildOptIn(c)
                  else ...[
                    Padding(
                      padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 8.h),
                      child: Row(
                        children: [
                          Text(
                            '找到更同频的人',
                            style: TextStyle(
                              fontSize: 15.sp,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          SizedBox(width: 4.w),
                          Container(
                            width: 4.r,
                            height: 4.r,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.primaryLight,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _buildFilterCard(context, c),
                    Padding(
                      padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 0),
                      child: PrimaryButton(
                        text: '免费重新匹配',
                        onPressed: c.onSearch,
                      ),
                    ),
                    if (c.loading)
                      Padding(
                        padding: EdgeInsets.only(top: 12.h),
                        child: const Center(child: CircularProgressIndicator()),
                      ),
                    if (!c.loading &&
                        c.loadError != null &&
                        c.loadError!.isNotEmpty)
                      Padding(
                        padding: EdgeInsets.fromLTRB(16.w, 10.h, 16.w, 0),
                        child: Text(
                          c.loadError!,
                          style: TextStyle(
                            fontSize: 12.sp,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    _buildUserListHeader(c),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16.w),
                      child: Column(
                        children: c.users.isEmpty
                            ? [
                                Padding(
                                  padding: EdgeInsets.symmetric(vertical: 18.h),
                                  child: Text(
                                    c.loading ? '加载中...' : '暂无匹配结果',
                                    style: TextStyle(
                                      fontSize: 12.sp,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                              ]
                            : c.users
                                .map(
                                  (user) => _buildUserItem(context, c, user),
                                )
                                .toList(),
                      ),
                    ),
                    if (c.hasMore)
                      Padding(
                        padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 0),
                        child: SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: c.loading ? null : c.loadMore,
                            child: Text(c.loading ? '加载中...' : '查看更多同频用户'),
                          ),
                        ),
                      ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(20.w, 14.h, 20.w, 0),
                      child: Text(
                        '本功能全程免费；命理特征只是破冰参考，不代表命定关系或结果承诺。',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 10.sp,
                          height: 1.45,
                          color: AppColors.textHint,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
