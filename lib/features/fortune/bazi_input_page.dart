import 'package:flutter/material.dart';
import 'package:xuanyu/app/pages/home/bazi/view.dart';

/// 八字排盘输入页（与首页九宫格 UI 一致，排盘结果自动保存至命理档案）
class BaziInputPage extends StatelessWidget {
  const BaziInputPage({
    super.key,
    this.forOther = false,
    this.replaceInputWithResult = false,
  });

  final bool forOther;
  final bool replaceInputWithResult;

  @override
  Widget build(BuildContext context) => BaziPage(
        startForOther: forOther,
        replaceInputWithResult: replaceInputWithResult,
      );
}
