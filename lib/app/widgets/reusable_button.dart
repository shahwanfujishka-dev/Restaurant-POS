import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:shimmer/shimmer.dart';

import '../theme/app_theme.dart';
import '../theme/app_typography.dart';

class PrimaryButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String text;
  final double? width;
  final TextStyle? style;
  final double? height;
  final bool isLoading;
  final Color? color;
  final IconData? icon;

  const PrimaryButton({
    super.key,
    required this.onPressed,
    required this.text,
    this.style,
    this.width,
    this.height,
    this.isLoading = false,
    this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final Color buttonColor = color ?? AppTheme.primaryGreen;

    if (isLoading) {
      return Shimmer.fromColors(
        baseColor: buttonColor.withOpacity(0.4),
        highlightColor: buttonColor.withOpacity(0.2),
        child: Container(
          width: width ?? double.infinity,
          height: height ?? 50.h,
          decoration: BoxDecoration(
            color: buttonColor,
            borderRadius: BorderRadius.circular(8.r),
          ),
        ),
      );
    }

    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: buttonColor,
        minimumSize: Size(width ?? 0, height ?? 50.h),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8.r),
        ),
        disabledBackgroundColor: buttonColor.withOpacity(0.6),
        padding: icon != null ? EdgeInsets.symmetric(horizontal: 12.w) : null,
      ),
      onPressed: onPressed,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, size: AppTypography.sizeText, color: Colors.white),
            SizedBox(width: 1.w),
          ],
          Text(
            text,
            style: style ?? AppTypography.button,
          ),
        ],
      ),
    );
  }
}
