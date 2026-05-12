import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppTheme {
  AppTheme._();

  // ── Existing colours (unchanged) ──────────────────────────────────────────
  static const Color white                   = Color(0xffffffff);
  static const Color borderColor             = Color(0xffE4EBF3);
  static const Color scaffoldBackgroundColor = Color(0xffF6F6F6);
  static const Color subTextColor            = Color(0xff797676);
  static const Color progressUnselectedColor = Color(0xff6A6F7A);
  static const Color redColor                = Color(0xffE54848);
  static const Color textFieldColor          = Color(0xfff8f9fa);
  static const Color progressBarColor        = Color(0xffD9D9D9);

  static const Color primaryGreen            = Color(0xff49AE52);
  static const Color greenTransLight         = Color(0xffD6F8B2);
  static const Color greenLight              = Color(0xffA1DB65);
  static const Color greenDark               = Color(0xff206634);

  static const Color whitishGreenLight       = Color(0xffCFECB1);
  static const Color whitishGreenDark        = Color(0xffBCE4AD);

  static const Color cancelColor             = Color(0xFFF9F9FA);
  static const Color primaryOrange           = Color(0xffE55525);
  static const Color pendingYellow           = Color(0xffFFCC19);

  // ── New: drawer accent colours ────────────────────────────────────────────
  static const Color accentTeal              = Color(0xFF4ECDC4);
  static const Color accentPurple            = Color(0xFF7C83FD);
  static const Color accentAmber             = Color(0xFFFFA94D);

  // ── New: dark surface tokens ──────────────────────────────────────────────
  static const Color darkBg                  = Color(0xFF0F1923);
  static const Color darkCard                = Color(0xFF162230);
  static const Color darkBorder              = Color(0xFF1E2D3D);
  static const Color darkText                = Color(0xFFF0F4F8);
  static const Color darkSubtext             = Color(0xFF8FA3B1);
  static const Color darkTextField           = Color(0xFF1A2A38);

  // ── Existing light theme (structure unchanged, extensions added) ──────────
  static final ThemeData lightTheme = ThemeData(
    primaryColor: primaryGreen,
    scaffoldBackgroundColor: scaffoldBackgroundColor,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primaryGreen,
      brightness: Brightness.light,
    ),
    dividerColor: Colors.transparent,
    visualDensity: VisualDensity.adaptivePlatformDensity,
    appBarTheme: const AppBarTheme(
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    ),
    extensions: const [AppColors.light], // ← only addition to existing theme
  );

  // ── New: dark theme ───────────────────────────────────────────────────────
  static final ThemeData darkTheme = ThemeData(
    primaryColor: primaryGreen,
    scaffoldBackgroundColor: darkBg,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primaryGreen,
      brightness: Brightness.dark,
      surface: darkCard,
      background: darkBg,
    ),
    cardColor: darkCard,
    dividerColor: Colors.transparent,
    visualDensity: VisualDensity.adaptivePlatformDensity,
    appBarTheme: const AppBarTheme(
      backgroundColor: darkCard,
      foregroundColor: darkText,
      elevation: 0,
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    ),
    textTheme: const TextTheme(
      bodyLarge:   TextStyle(color: darkText),
      bodyMedium:  TextStyle(color: darkText),
      bodySmall:   TextStyle(color: darkSubtext),
      titleLarge:  TextStyle(color: darkText,    fontWeight: FontWeight.w600),
      titleMedium: TextStyle(color: darkText,    fontWeight: FontWeight.w500),
      titleSmall:  TextStyle(color: darkSubtext),
      labelLarge:  TextStyle(color: darkText,    fontWeight: FontWeight.w500),
      labelMedium: TextStyle(color: darkSubtext),
    ),
    inputDecorationTheme: InputDecorationTheme(
      fillColor: darkTextField,
      filled: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: darkBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: darkBorder),
      ),
    ),
    extensions: const [AppColors.dark],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// AppColors — ThemeExtension for semantic surface colours.
//
// Usage anywhere in the app:
//   final c = AppColors.of(context);
//   Container(color: c.card)
//   Text('hi', style: TextStyle(color: c.subtext))
// ─────────────────────────────────────────────────────────────────────────────
@immutable
class AppColors extends ThemeExtension<AppColors> {
  final Color bg;
  final Color card;
  final Color border;
  final Color text;
  final Color subtext;
  final Color textField;
  final bool  isDark;

  const AppColors({
    required this.bg,
    required this.card,
    required this.border,
    required this.text,
    required this.subtext,
    required this.textField,
    required this.isDark,
  });

  static const light = AppColors(
    bg:        AppTheme.scaffoldBackgroundColor,
    card:      AppTheme.white,
    border:    AppTheme.borderColor,
    text:      Color(0xFF1A1D23),
    subtext:   AppTheme.subTextColor,
    textField: AppTheme.textFieldColor,
    isDark:    false,
  );

  static const dark = AppColors(
    bg:        AppTheme.darkBg,
    card:      AppTheme.darkCard,
    border:    AppTheme.darkBorder,
    text:      AppTheme.darkText,
    subtext:   AppTheme.darkSubtext,
    textField: AppTheme.darkTextField,
    isDark:    true,
  );

  /// Safe accessor — falls back to light if extension isn't registered.
  static AppColors of(BuildContext context) =>
      Theme.of(context).extension<AppColors>() ?? AppColors.light;

  @override
  AppColors copyWith({
    Color? bg, Color? card, Color? border,
    Color? text, Color? subtext, Color? textField, bool? isDark,
  }) => AppColors(
    bg:        bg        ?? this.bg,
    card:      card      ?? this.card,
    border:    border    ?? this.border,
    text:      text      ?? this.text,
    subtext:   subtext   ?? this.subtext,
    textField: textField ?? this.textField,
    isDark:    isDark    ?? this.isDark,
  );

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      bg:        Color.lerp(bg,        other.bg,        t)!,
      card:      Color.lerp(card,      other.card,       t)!,
      border:    Color.lerp(border,    other.border,     t)!,
      text:      Color.lerp(text,      other.text,       t)!,
      subtext:   Color.lerp(subtext,   other.subtext,    t)!,
      textField: Color.lerp(textField, other.textField,  t)!,
      isDark:    t > 0.5 ? other.isDark : isDark,
    );
  }
}