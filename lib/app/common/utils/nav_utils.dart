import 'package:get/get.dart';
import 'package:xuanyu/app/common/routers/names.dart';

class NavUtils {
  NavUtils._();

  /// 安全返回：如果路由栈可以 pop 则返回上一页，否则跳转 fallbackRoute
  static void goBack({String? fallbackRoute}) {
    if (Get.key.currentState != null && Get.key.currentState!.canPop()) {
      Get.back();
    } else {
      Get.offAllNamed(fallbackRoute ?? RouteNames.main);
    }
  }
}
