import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../../../../helper/screen_type.dart';
import '../../../../../../theme/app_theme.dart';
import '../../../../../../theme/app_typography.dart';

class CategoryChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const CategoryChip({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        padding: EdgeInsets.symmetric(horizontal: ScreenType.isMobile()?10.w:2.w, vertical: AppTypography.sizeCategory),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryGreen : colors.card,
          borderRadius: BorderRadius.circular(10.r),
          border: Border.all(
            color: isSelected ? AppTheme.primaryGreen : colors.border,
          ),
          boxShadow: isSelected
              ? [
            BoxShadow(
              color: AppTheme.primaryGreen.withOpacity(0.3),
              blurRadius: 10,
              spreadRadius: 2,
              offset: const Offset(0, 4),
            ),
          ]
              : [],
        ),
        child: Text(
          label,
          style: AppTypography.cardSubtitle.copyWith(
            color: isSelected ? Colors.white : colors.text,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}