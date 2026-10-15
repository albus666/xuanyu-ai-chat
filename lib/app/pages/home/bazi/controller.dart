import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:xuanyu/core/profile/account_birth_profile.dart';
import 'package:xuanyu/core/utils/app_toast.dart';
import 'package:xuanyu/features/fortune/archive_relationship.dart';
import 'package:xuanyu/features/fortune/paipan/models/region.dart';
import 'package:xuanyu/features/fortune/paipan/paipan_result_host_page.dart';
import 'package:xuanyu/features/fortune/paipan/utils/date_util.dart';
import 'package:xuanyu/features/fortune/paipan/utils/region_loader.dart';
import 'package:xuanyu/features/fortune/paipan/utils/true_solar_time.dart';
import 'package:xuanyu/features/fortune/paipan/widgets/birth_date_picker_sheet.dart';
import 'package:xuanyu/features/fortune/paipan/widgets/birth_place_picker_sheet.dart';
import 'package:xuanyu/features/fortune/paipan_record_archive_page.dart';

enum BaziGender { male, female }

enum BaziCalendar { gongli, nongli, sizhu }

class BaziController extends GetxController {
  BaziController({this.startForOther = false});

  final bool startForOther;

  final nameCtrl = TextEditingController(text: '我的八字');
  bool isSelf = true;
  String relationship = ArchiveRelationship.self;
  BaziGender gender = BaziGender.male;
  BaziCalendar calendar = BaziCalendar.gongli;
  DateTime birthDate = DateTime(2000, 1, 1, 12);
  Region? birthPlace;
  bool accountBirthLoaded = false;
  bool accountLoadFinished = false;
  bool selfResultOpening = false;
  bool _birthInputTouched = false;
  String _accountName = '我的八字';

  int get calendarTypeIndex {
    switch (calendar) {
      case BaziCalendar.gongli:
        return 0;
      case BaziCalendar.nongli:
        return 1;
      case BaziCalendar.sizhu:
        return 2;
    }
  }

  @override
  void onInit() {
    super.onInit();
    RegionLoader.preload();
    if (startForOther) {
      isSelf = false;
      relationship = ArchiveRelationship.family;
      nameCtrl.clear();
    }
    _loadAccountBirthProfile();
  }

  Future<void> _loadAccountBirthProfile() async {
    try {
      final profile = await AccountBirthProfileRepository.load();
      _accountName = profile.nickname.isEmpty ? '我的八字' : profile.nickname;
      final parsed = profile.birthDateTime;
      if (parsed == null ||
          !profile.isComplete ||
          _birthInputTouched ||
          startForOther) {
        return;
      }
      birthDate = parsed;
      if (profile.gender == 2) {
        gender = BaziGender.female;
      } else {
        gender = BaziGender.male;
      }
      calendar = BaziCalendar.gongli;
      if (isSelf) {
        nameCtrl.text = _accountName;
      }
      accountBirthLoaded = true;
    } on DioException catch (_) {
      // 保持缺失态，绝不使用当前时间伪造本人命盘。
    } finally {
      accountLoadFinished = true;
      update(['bazi']);
    }
  }

  Future<void> completeSelfProfileAndOpen(BuildContext context) async {
    final profile = await AccountBirthProfileRepository.ensure(
      context,
      reason: '完善一次后，八字、斗数和其他本人功能都会自动使用',
    );
    if (profile == null || !context.mounted) return;
    final parsed = profile.birthDateTime;
    if (parsed == null) return;
    birthDate = parsed;
    gender = profile.isFemale ? BaziGender.female : BaziGender.male;
    calendar = BaziCalendar.gongli;
    _accountName = profile.safeNickname;
    nameCtrl.text = _accountName;
    accountBirthLoaded = true;
    accountLoadFinished = true;
    update(['bazi']);
    openSelfResult(context);
  }

  void openSelfResult(BuildContext context) {
    if (selfResultOpening || !accountBirthLoaded || !context.mounted) return;
    selfResultOpening = true;
    onSubmit(context, replaceCurrent: true);
  }

  void selectGender(BaziGender g) {
    _birthInputTouched = true;
    gender = g;
    update(['bazi']);
  }

  void selectOwner(bool value) {
    if (isSelf == value) return;
    isSelf = value;
    relationship =
        value ? ArchiveRelationship.self : ArchiveRelationship.family;
    nameCtrl.text = value ? _accountName : '';
    update(['bazi']);
  }

  void selectRelationship(String value) {
    relationship = value;
    update(['bazi']);
  }

  void selectCalendar(BaziCalendar c) {
    _birthInputTouched = true;
    calendar = c;
    update(['bazi']);
  }

  Future<void> pickBirthDate(BuildContext context) async {
    await BirthDatePickerSheet.show(
      context,
      initialDate: birthDate,
      initialTabIndex: calendarTypeIndex,
      onConfirm: (date) {
        _birthInputTouched = true;
        birthDate = date;
        update(['bazi']);
      },
    );
  }

  Future<void> pickBirthPlace(BuildContext context) async {
    await BirthPlacePickerSheet.show(
      context,
      initialRegion: birthPlace,
      onConfirm: (r) {
        birthPlace = r;
        update(['bazi']);
      },
    );
  }

  String get dateText {
    switch (calendar) {
      case BaziCalendar.gongli:
        return DateUtil.formatGregorian(birthDate);
      case BaziCalendar.nongli:
        return DateUtil.formatLunar(birthDate);
      case BaziCalendar.sizhu:
        return DateUtil.getEightCharColumns(birthDate)
            .map((s) => s.replaceAll('\n', ''))
            .join(' ');
    }
  }

  String get birthPlaceText {
    if (birthPlace == null) return '选填，用于真太阳时';
    return birthPlace!.extPath.replaceAll(' ', ' / ');
  }

  DateTime get displaySolarTime {
    if (birthPlace?.lng != null) {
      return TrueSolarTime.toTrueSolar(birthDate, birthPlace!.lng!);
    }
    return birthDate;
  }

  String get trueSolarTimeText =>
      '真太阳时 ${DateUtil.formatGregorian(displaySolarTime)}';

  String get coordText {
    final lng = birthPlace?.lng?.toStringAsFixed(3) ?? '';
    final lat = birthPlace?.lat?.toStringAsFixed(3) ?? '';
    return '经度：$lng    维度：$lat';
  }

  void openArchive(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const PaipanRecordArchivePage()),
    );
  }

  void onSubmit(BuildContext context, {bool replaceCurrent = false}) {
    final name = nameCtrl.text.trim();
    if (!isSelf && name.isEmpty) {
      showAppToast(context, '请填写对方的姓名或称呼');
      return;
    }
    if (!isSelf && ArchiveRelationship.isReservedSelfName(name)) {
      showAppToast(context, '他人档案不能使用“本人”类名称');
      return;
    }
    var dt = birthDate;
    if (calendar == BaziCalendar.gongli && birthPlace?.lng != null) {
      dt = TrueSolarTime.toTrueSolar(birthDate, birthPlace!.lng!);
    }
    final route = MaterialPageRoute<void>(
      builder: (_) => PaipanResultPage(
        birthDateTime: dt,
        isFemale: gender == BaziGender.female,
        birthPlace: birthPlace,
        calendarTypeIndex: calendarTypeIndex,
        displayName: name.isEmpty ? '我的八字' : name,
        isSelf: isSelf,
        relationship: relationship,
      ),
    );
    if (replaceCurrent) {
      Navigator.of(context).pushReplacement(route);
    } else {
      Navigator.of(context).push(route);
    }
  }

  @override
  void onClose() {
    nameCtrl.dispose();
    super.onClose();
  }
}
