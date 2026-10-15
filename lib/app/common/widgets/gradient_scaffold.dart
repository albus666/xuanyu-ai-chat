import 'package:flutter/material.dart';
import 'package:xuanyu/app/common/style/colors.dart';
import 'package:xuanyu/app/common/values/images.dart';

/// 通用背景脚手架。
///
/// 默认使用 [ImageAssets.loginBg] 作为顶部背景图，底色为白。
/// - 传入 [backgroundImage] 可覆盖默认背景图。
/// - 设置 [useGradient] 为 true 可退回原背景渐变。
class GradientScaffold extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final bool extendBodyBehindAppBar;
  final bool resizeToAvoidBottomInset;
  final List<Color>? gradientColors;
  final List<double>? gradientStops;
  final String? backgroundImage;
  final ImageProvider? backgroundImageProvider;
  final bool useGradient;

  const GradientScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.extendBodyBehindAppBar = false,
    this.resizeToAvoidBottomInset = true,
    this.gradientColors,
    this.gradientStops,
    this.backgroundImage,
    this.backgroundImageProvider,
    this.useGradient = false,
  });

  @override
  Widget build(BuildContext context) {
    final BoxDecoration decoration = backgroundImageProvider != null
        ? BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: gradientColors ?? AppColors.pageBgGradient,
              stops: gradientStops ?? const [0.0, 0.4, 1.0],
            ),
            image: DecorationImage(
              image: backgroundImageProvider!,
              fit: BoxFit.cover,
              colorFilter: ColorFilter.mode(
                Colors.white.withValues(alpha: 0.14),
                BlendMode.srcOver,
              ),
            ),
          )
        : useGradient
        ? BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: gradientColors ?? AppColors.pageBgGradient,
              stops: gradientStops ?? const [0.0, 0.4, 1.0],
            ),
          )
        : BoxDecoration(
            color: Colors.white,
            image: DecorationImage(
              image: AssetImage(backgroundImage ?? ImageAssets.loginBg),
              fit: BoxFit.fitWidth,
              alignment: Alignment.topCenter,
            ),
          );

    return Container(
      decoration: decoration,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: extendBodyBehindAppBar,
        resizeToAvoidBottomInset: resizeToAvoidBottomInset,
        appBar: appBar,
        body: body,
        bottomNavigationBar: bottomNavigationBar,
        floatingActionButton: floatingActionButton,
        floatingActionButtonLocation: floatingActionButtonLocation,
      ),
    );
  }
}
