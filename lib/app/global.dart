import 'package:flutter/material.dart';

class Global {
  static Future<void> init() async {
    WidgetsFlutterBinding.ensureInitialized();
    // 后续如有 GetxService 在此注册
  }
}
