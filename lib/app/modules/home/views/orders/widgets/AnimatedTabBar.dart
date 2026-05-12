import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../../theme/app_theme.dart';
import '../../../../../theme/app_typography.dart';
import '../../../controller/order_controller.dart';

class AnimatedTabBar extends StatefulWidget {
  final TabController tabController; // ← explicit, no DefaultTabController.of()
  const AnimatedTabBar({required this.tabController, super.key});

  @override
  State<AnimatedTabBar> createState() => _AnimatedTabBarState();
}

class _AnimatedTabBarState extends State<AnimatedTabBar> {

  static const _tabs = [
    _TabItem(icon: Icons.restaurant_outlined,      label: 'Dine In',     color: Colors.orange),
    _TabItem(icon: Icons.delivery_dining_outlined,  label: 'Delivery',    color: Colors.blue),
    _TabItem(icon: Icons.shopping_bag_outlined,    label: 'Pick Up',     color: AppTheme.primaryGreen),
    _TabItem(icon: Icons.check_circle_outline,     label: 'Paid',        color: Colors.teal),
  ];

  @override
  void initState() {
    super.initState();
    widget.tabController.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (!widget.tabController.indexIsChanging && mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    widget.tabController.removeListener(_onTabChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.tabController.index;

    return Container(
      height: AppTypography.foodIcon,
      padding: EdgeInsets.symmetric(horizontal: 2.w, vertical: 5.h),
      decoration: BoxDecoration(
        color: AppColors.of(context).bg,
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(
          color: AppColors.of(context).border.withOpacity(0.15),
          width: 0.5,
        ),
      ),
      child: Row(
        children: List.generate(_tabs.length, (i) {
          final isActive = selected == i;
          final tabColor = _tabs[i].color;
          return Expanded(
            child: GestureDetector(
              onTap: () => widget.tabController.animateTo(i),
              child: AnimatedContainer(
                height: AppTypography.foodIcon,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOut,
                decoration: BoxDecoration(
                  color: isActive ? tabColor : Colors.transparent,
                  borderRadius: BorderRadius.circular(5.r),
                  boxShadow: isActive
                      ? [BoxShadow(
                    color: tabColor.withOpacity(0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )]
                      : [],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _tabs[i].icon,
                      size: AppTypography.sizeCategory,
                      color: isActive ? Colors.white : AppColors.of(context).subtext,
                    ),
                    SizedBox(width: 3.w),
                    Text(
                      _tabs[i].label,
                      style: AppTypography.button.copyWith(
                        fontWeight: FontWeight.w600,
                        color: isActive ? Colors.white : AppColors.of(context).subtext,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _TabItem {
  final IconData icon;
  final String label;
  final Color color;
  const _TabItem({required this.icon, required this.label, required this.color});
}