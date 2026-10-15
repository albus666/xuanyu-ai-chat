import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:xuanyu/app/common/index.dart';
import 'package:xuanyu/features/fortune/paipan/widgets/birth_date_picker_sheet.dart';

enum Gender { male, female }

class ProfileSetupController extends GetxController {
  ProfileSetupController();

  final nicknameCtrl = TextEditingController();
  final introCtrl = TextEditingController();

  Gender gender = Gender.male;
  DateTime? birthDate;
  TimeOfDay? birthTime;

  void selectGender(Gender g) {
    gender = g;
    update(['profile']);
  }

  Future<void> pickBirthDateTime(BuildContext context) async {
    final date = birthDate ?? DateTime(2000, 1, 1);
    final time = birthTime ?? const TimeOfDay(hour: 12, minute: 0);
    await BirthDatePickerSheet.show(
      context,
      initialDate: DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      ),
      onConfirm: (picked) {
        if (picked.isAfter(DateTime.now())) {
          Get.snackbar(
            '提示',
            '出生时间不能晚于当前时间',
            snackPosition: SnackPosition.BOTTOM,
          );
          return;
        }
        birthDate = DateTime(picked.year, picked.month, picked.day);
        birthTime = TimeOfDay(hour: picked.hour, minute: picked.minute);
        update(['profile']);
      },
    );
  }

  String get dateText {
    if (birthDate == null) return '去选择';
    final d = birthDate!;
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  String get timeText {
    if (birthTime == null) return '去选择';
    final t = birthTime!;
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  void onComplete() {
    if (nicknameCtrl.text.trim().isEmpty) {
      Get.snackbar('提示', '请输入昵称', snackPosition: SnackPosition.BOTTOM);
      return;
    }
    Get.offAllNamed(RouteNames.main);
  }

  @override
  void onClose() {
    nicknameCtrl.dispose();
    introCtrl.dispose();
    super.onClose();
  }
}
