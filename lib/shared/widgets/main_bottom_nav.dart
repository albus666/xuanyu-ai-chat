import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// 底部导航栏 - 视觉升级版
class MainBottomNav extends StatelessWidget {
  const MainBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.isMinorMode = false,
    this.messageBadgeCount = 0,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final bool isMinorMode;
  final int messageBadgeCount;

  static const int tabHome = 0;
  static const int tabCommunity = 1;
  static const int tabPublish = 2;
  static const int tabMessage = 3;
  static const int tabProfile = 4;

  static List<int> get visibleIndicesInMinorMode => [0, 1, 4];

  List<_NavItem> get _items {
    const items = [
      _NavItem(
          icon: Icons.explore_outlined, activeIcon: Icons.explore, label: '首页'),
      _NavItem(
          icon: Icons.auto_awesome_motion_outlined,
          activeIcon: Icons.auto_awesome_motion,
          label: '社区'),
      _NavItem(
          icon: Icons.add, activeIcon: Icons.add, label: '发布', isSpecial: true),
      _NavItem(
          icon: Icons.chat_bubble_outline_rounded,
          activeIcon: Icons.chat_bubble_rounded,
          label: '消息'),
      _NavItem(
          icon: Icons.person_outline_rounded,
          activeIcon: Icons.person_rounded,
          label: '我的'),
    ];
    if (isMinorMode) {
      return [items[0], items[1], items[4]];
    }
    return items;
  }

  int _mapIndexToLogical(int visibleIndex) {
    if (isMinorMode) return visibleIndicesInMinorMode[visibleIndex];
    return visibleIndex;
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: items.asMap().entries.map((e) {
              final index = e.key;
              final item = e.value;
              final logicalIndex = _mapIndexToLogical(index);
              final isSelected = logicalIndex == currentIndex;

              if (item.isSpecial) {
                return Expanded(
                  child: GestureDetector(
                    onTap: () => onTap(logicalIndex),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: const BoxDecoration(
                            gradient: AppColors.primaryGradient,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Color(0x2922D4C5),
                                blurRadius: 8,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Icon(item.icon, color: Colors.white, size: 25),
                        ),
                        const SizedBox(height: 1),
                        const Text(
                          '发布',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return Expanded(
                child: InkWell(
                  onTap: () => onTap(logicalIndex),
                  highlightColor: Colors.transparent,
                  splashColor: Colors.transparent,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildIcon(item, logicalIndex, isSelected),
                      const SizedBox(height: 4),
                      Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildIcon(_NavItem item, int logicalIndex, bool isSelected) {
    final icon = isSelected ? item.activeIcon : item.icon;
    final color = isSelected ? AppColors.primary : AppColors.textSecondary;

    Widget iconWidget = Icon(icon, size: 24, color: color);

    if (logicalIndex == tabMessage && messageBadgeCount > 0) {
      return Badge(
        label: Text(messageBadgeCount > 99 ? '99+' : '$messageBadgeCount'),
        backgroundColor: AppColors.primary,
        child: iconWidget,
      );
    }
    return iconWidget;
  }
}

class _NavItem {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    this.isSpecial = false,
  });
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isSpecial;
}
