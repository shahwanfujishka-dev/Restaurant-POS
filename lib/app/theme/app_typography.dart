import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../helper/screen_type.dart';
import 'app_theme.dart';

class AppTypography {
  AppTypography._();

  // ---------- HEADLINES ----------
  static TextStyle get headline1 => TextStyle(
    fontSize: ScreenType.isMobile() ? 28.sp : 10.sp,
    fontWeight: FontWeight.bold,
  );

  static TextStyle get headline2 => TextStyle(
    fontSize: ScreenType.isMobile() ? 24.sp : 8.sp,
    fontWeight: FontWeight.bold,
  );

  // ---------- APP BAR ----------
  static TextStyle get appBarTitle => TextStyle(
    fontSize: ScreenType.isMobile() ? 20.sp : 8.sp,
    fontWeight: FontWeight.w500,
  );

  // ---------- TEXT ----------
  static TextStyle get subtitle => TextStyle(
    fontSize: ScreenType.isMobile() ? 16.sp : 7.sp,
    color: AppTheme.subTextColor,
  );

  static TextStyle get bodyText => TextStyle(
    fontSize: ScreenType.isMobile() ? 16.sp : 7.sp,
  );

// ---------- CARD TEXT ----------
  static TextStyle get cardTitle => TextStyle(
    fontWeight: FontWeight.bold,
    fontSize: ScreenType.isMobile() ? 16.sp : 5.sp,
  );

  static TextStyle get cardSubtitle => TextStyle(
    color: AppTheme.subTextColor,
    fontSize: ScreenType.isMobile() ? 12.sp : 3.sp,
  );

  static TextStyle get cardInfo => TextStyle(
    fontWeight: FontWeight.bold,
    fontSize: ScreenType.isMobile() ? 12.sp : 3.sp,
    color: AppTheme.primaryGreen,
  );

  static TextStyle get button => TextStyle(
    fontSize: ScreenType.isMobile() ? 18.sp : 5.sp,
    fontWeight: FontWeight.w500,
    color: AppTheme.white,
  );

  static double get iconSmall =>
      ScreenType.isMobile() ? 18.sp : 36.sp;

  static double get iconMedium =>
      ScreenType.isMobile() ? 24.sp : 44.sp;

  static double get iconLarge =>
      ScreenType.isMobile() ? 30.sp : 8.sp;

  static double get iconXL =>
      ScreenType.isMobile() ? 36.sp : 12.sp;

  static double get foodIcon =>
      ScreenType.isMobile() ? 60.sp : 20.sp;

  static double get sizeTable =>
      ScreenType.isMobile() ? 20.sp : 5.sp;
  static double get sizeCategory =>
      ScreenType.isMobile() ? 12.sp : 6.sp;

  static double get sizeText =>
      ScreenType.isMobile() ? 18.sp : 5.sp;

  static double get smallText =>
      ScreenType.isMobile() ? 12.sp : 3.sp;

  static double get sizeArea =>
      ScreenType.isMobile() ? 200.sp : 50.sp;

  static double get sizeDialogue =>
      ScreenType.isMobile() ? 200.sp : 150.sp;
}