import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'features/main/main_shell_page.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '玄遇',
      theme: AppTheme.light,
      debugShowCheckedModeBanner: false,
      home: const MainShellPage(isMinorMode: false),
    );
  }
}
