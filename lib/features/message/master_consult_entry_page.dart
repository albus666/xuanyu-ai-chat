import 'package:flutter/material.dart';

import '../consultation/consultation_center_page.dart';

/// 兼容原有路由名称，咨询入口统一进入真人咨询中心。
class MasterConsultEntryPage extends StatelessWidget {
  const MasterConsultEntryPage({super.key});

  @override
  Widget build(BuildContext context) =>
      const ConsultationCenterPage();
}
