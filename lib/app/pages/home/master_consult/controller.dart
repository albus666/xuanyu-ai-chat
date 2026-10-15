import 'package:get/get.dart';

class MasterConsultController extends GetxController {
  MasterConsultController();

  void onSelectAi() {
    Get.snackbar('AI 名师', '智能答疑入口（Demo）',
        snackPosition: SnackPosition.BOTTOM);
  }

  void onSelectHuman() {
    Get.snackbar('真人名师', '一对一咨询入口（Demo）',
        snackPosition: SnackPosition.BOTTOM);
  }
}
