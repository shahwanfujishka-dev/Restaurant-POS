import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get_utils/src/extensions/internacionalization.dart';
import '../theme/app_theme.dart';
import '../theme/app_typography.dart';

class PosSidebar extends StatelessWidget {
  final int selectedIndex;
  final Function(int) onItemSelected;
  final VoidCallback onLogout;

  const PosSidebar({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
    required this.onLogout,
  });

  static const double _itemHeight = 90;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      width: 30.w,
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(24.r),
          bottomRight: Radius.circular(24.r),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(colors.isDark ? 0.2 : 0.05),
            blurRadius: 12,
            offset: const Offset(4, 0),
          ),
        ],
      ),
      child: Stack(
        children: [
          AnimatedPositioned(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeInOutCubic,
            top: 5.h + (selectedIndex * _itemHeight),
            left: 1.w,
            right: 1.w,
            height: 75.h,
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.primaryGreen.withOpacity(0.12),
                borderRadius: BorderRadius.circular(16.r),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryGreen.withOpacity(0.25),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
            ),
          ),
          Column(
            children: [
              _navItem(context, Icons.dashboard, "dashboard".tr, 0),
              _navItem(context, Icons.table_restaurant, "tables".tr, 1),
              _navItem(context, Icons.receipt, "orders".tr, 2),
              _navItem(context, Icons.print, "printers".tr, 3),
              _navItem(context, Icons.settings_outlined, "settings".tr, 4),
              // const Spacer(),
              Padding(
                padding: EdgeInsets.only(bottom: 10.h),
                child: _actionItem(context, Icons.logout, "logout".tr, onLogout, color: Colors.red),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _navItem(BuildContext context, IconData icon, String label, int index) {
    final isSelected = selectedIndex == index;
    final colors = AppColors.of(context);
    return GestureDetector(
      onTap: () => onItemSelected(index),
      child: SizedBox(
        height: _itemHeight,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedScale(
                scale: isSelected ? 1.15 : 1.0,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                child: Icon(
                  icon,
                  size: AppTypography.iconLarge,
                  color: isSelected ? AppTheme.primaryGreen : colors.subtext,
                ),
              ),
              SizedBox(height: 6.h),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                style: TextStyle(
                  fontSize: 4.sp,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected ? AppTheme.primaryGreen : colors.subtext,
                ),
                child: Text(label),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionItem(BuildContext context, IconData icon, String label, VoidCallback onTap, {Color? color}) {
    final colors = AppColors.of(context);
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        height: 70.h,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 7.sp, color: color ?? colors.subtext),
              SizedBox(height: 4.h),
              Text(
                label,
                style: TextStyle(
                  fontSize: 3.5.sp,
                  fontWeight: FontWeight.w400,
                  color: color ?? colors.subtext,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
