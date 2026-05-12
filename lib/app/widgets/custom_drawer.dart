import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Usage:
//   Scaffold(
//     drawer: AppDrawer(
//       userName: 'Captain 3',
//       branchName: 'Murshid — mpm',
//       onLogout: controller.logout,
//       onSettings: () => Get.toNamed(Routes.SETTINGS),
//       onChangeOrderType: () => Get.toNamed(Routes.ORDER_TYPE),
//       onToggleLanguage: _toggleLanguage,
//       isArabic: Get.locale?.languageCode == 'ar',
//     ),
//   )
// ─────────────────────────────────────────────────────────────────────────────

class AppDrawer extends StatefulWidget {
  final String userName;
  final String? avatarUrl;
  final VoidCallback onLogout;
  final VoidCallback onSettings;
  final VoidCallback onChangeOrderType;
  final VoidCallback onToggleLanguage;
  final bool isArabic;

  const AppDrawer({
    super.key,
    required this.userName,
    this.avatarUrl,
    required this.onLogout,
    required this.onSettings,
    required this.onChangeOrderType,
    required this.onToggleLanguage,
    required this.isArabic,
  });

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  static const _itemCount = 7; // header + divider + 4 tiles + logout
  final List<Animation<double>> _fades = [];
  final List<Animation<Offset>> _slides = [];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    for (int i = 0; i < _itemCount; i++) {
      final s = (i * 0.11).clamp(0.0, 0.70);
      final e = (s + 0.34).clamp(0.0, 1.0);
      final iv = _CurvedInterval(s, e, curve: Curves.easeOutCubic);

      _fades.add(Tween<double>(begin: 0, end: 1)
          .animate(CurvedAnimation(parent: _ctrl, curve: iv)));
      _slides.add(Tween<Offset>(
        begin: const Offset(-0.15, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: _ctrl, curve: iv)));
    }

    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// Call this to replay entry animations (e.g. onDrawerChanged callback).
  void replay() {
    _ctrl.reset();
    _ctrl.forward();
  }

  @override
  Widget build(BuildContext context) {
    // Obx: re-render when theme switches
    return Obx(() {
      final isDark = ThemeController.to.isDark.value;
      final dc = _DC(isDark: isDark);

      return Drawer(
        width: 290.w,
        backgroundColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.horizontal(right: Radius.circular(28)),
        ),
        child: _body(dc),
      );
    });
  }

  Widget _body(_DC dc) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        borderRadius:
        const BorderRadius.horizontal(right: Radius.circular(28)),
        color: dc.bg,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(dc.isDark ? 0.45 : 0.12),
            blurRadius: 28,
            offset: const Offset(6, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          _Anim(fade: _fades[0], slide: _slides[0],
              child: _Header(
                  userName: widget.userName,
                  avatarUrl: widget.avatarUrl,
                  dc: dc)),

          SizedBox(height: 6.h),

          _Anim(fade: _fades[1], slide: _slides[1],
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 20.w),
                child: Divider(color: dc.divider, thickness: 1, height: 1),
              )),

          SizedBox(height: 6.h),

          _Anim(fade: _fades[2], slide: _slides[2],
              child: _MenuTile(
                icon: Icons.swap_horiz_rounded,
                label: 'change_order_type'.tr.isEmpty
                    ? 'Change Order Type'
                    : 'change_order_type'.tr,
                accent: AppTheme.accentTeal,
                dc: dc,
                onTap: () { Get.back(); widget.onChangeOrderType(); },
              )),

          _Anim(fade: _fades[3], slide: _slides[3],
              child: _MenuTile(
                icon: Icons.tune_rounded,
                label: 'settings'.tr.isEmpty ? 'Settings' : 'settings'.tr,
                accent: AppTheme.accentPurple,
                dc: dc,
                onTap: () { Get.back(); widget.onSettings(); },
              )),

          _Anim(fade: _fades[4], slide: _slides[4],
              child: _LangTile(
                  label: 'language'.tr,
                  isArabic: widget.isArabic,
                  dc: dc,
                  onToggle: widget.onToggleLanguage)),

          _Anim(fade: _fades[5], slide: _slides[5],
              child: _ThemeTile(dc: dc)),

          const Spacer(),

          _Anim(fade: _fades[6], slide: _slides[6],
              child: _LogoutTile(dc: dc, onTap: widget.onLogout)),

          SizedBox(height: 34.h),
        ],
      ),
    );
  }
}

// ─── Design tokens ────────────────────────────────────────────────────────────

class _DC {
  final bool isDark;
  const _DC({required this.isDark});

  Color get bg         => isDark ? AppTheme.darkBg       : AppTheme.scaffoldBackgroundColor;
  Color get card       => isDark ? AppTheme.darkCard      : AppTheme.white;
  Color get divider    => isDark ? const Color(0x14FFFFFF): AppTheme.borderColor;
  Color get tileBg     => isDark ? const Color(0x0AFFFFFF): const Color(0x05000000);
  Color get tileBorder => isDark ? const Color(0x12FFFFFF): AppTheme.borderColor;
  Color get tilePress  => isDark ? const Color(0x16FFFFFF): const Color(0x0A000000);
  Color get titleText  => isDark ? AppTheme.darkText      : const Color(0xFF1A1D23);
  Color get subText    => isDark ? AppTheme.darkSubtext   : AppTheme.subTextColor;
  Color get arrowColor => isDark ? const Color(0x33FFFFFF): const Color(0x2D000000);
  Color get avatarRing => isDark ? AppTheme.darkBg        : AppTheme.white;
}

// ─── Header ───────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final String userName;
  final String? avatarUrl;
  final _DC dc;

  const _Header({
    required this.userName,
    required this.dc,
    this.avatarUrl,
  });

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Padding(
      padding: EdgeInsets.only(
        top: top + 26.h, bottom: 22.h,
        left: 20.w, right: 20.w,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Stack(children: [
          Container(
            width: 58.r, height: 58.r,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [AppTheme.accentTeal, AppTheme.primaryGreen],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
              boxShadow: [BoxShadow(
                color: AppTheme.accentTeal.withOpacity(0.35),
                blurRadius: 14, spreadRadius: 1,
              )],
            ),
            child: avatarUrl != null
                ? ClipOval(child: Image.network(avatarUrl!, fit: BoxFit.cover))
                : Center(child: Text(
              userName.isNotEmpty ? userName[0].toUpperCase() : 'U',
              style: TextStyle(fontSize: 22.sp, fontWeight: FontWeight.w700,
                  color: Colors.white),
            )),
          ),
          Positioned(bottom: 2, right: 2,
            child: Container(
              width: 12.r, height: 12.r,
              decoration: BoxDecoration(
                color: AppTheme.primaryGreen,
                shape: BoxShape.circle,
                border: Border.all(color: dc.avatarRing, width: 2),
              ),
            ),
          ),
        ]),

        SizedBox(height: 12.h),

        Text(userName,
            style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700,
                color: dc.titleText, letterSpacing: 0.2)),

        SizedBox(height: 3.h),

        Row(children: [
          Container(width: 5.r, height: 5.r,
              decoration: const BoxDecoration(
                  color: AppTheme.accentTeal, shape: BoxShape.circle)),

        ]),
      ]),
    );
  }
}

// ─── Generic menu tile ────────────────────────────────────────────────────────

class _MenuTile extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color accent;
  final _DC dc;
  final VoidCallback onTap;

  const _MenuTile({
    required this.icon, required this.label, required this.accent,
    required this.dc, required this.onTap,
  });

  @override State<_MenuTile> createState() => _MenuTileState();
}

class _MenuTileState extends State<_MenuTile> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final dc = widget.dc;
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) { setState(() => _down = false); widget.onTap(); },
      onTapCancel: () => setState(() => _down = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        margin: EdgeInsets.symmetric(horizontal: 14.w, vertical: 3.h),
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 11.h),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12.r),
          color: _down ? widget.accent.withOpacity(0.11) : dc.tileBg,
          border: Border.all(
            color: _down ? widget.accent.withOpacity(0.32) : dc.tileBorder,
            width: 1,
          ),
        ),
        child: Row(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 130),
            width: 34.r, height: 34.r,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9.r),
              color: widget.accent.withOpacity(_down ? 0.20 : 0.12),
            ),
            child: Icon(widget.icon, color: widget.accent, size: 17.r),
          ),
          SizedBox(width: 12.w),
          Expanded(child: Text(widget.label,
              style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w500,
                  color: dc.titleText))),
          Icon(Icons.arrow_forward_ios_rounded, size: 10.r, color: dc.arrowColor),
        ]),
      ),
    );
  }
}

// ─── Language tile ────────────────────────────────────────────────────────────

class _LangTile extends StatelessWidget {
  final String label;
  final bool isArabic;
  final _DC dc;
  final VoidCallback onToggle;

  const _LangTile({
    required this.label, required this.isArabic,
    required this.dc, required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return _BaseTile(
      dc: dc,
      iconColor: AppTheme.accentAmber,
      icon: Icons.language_rounded,
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 13.sp,
                  fontWeight: FontWeight.w500, color: dc.titleText)),
              Text(isArabic ? 'العربية' : 'English',
                  style: TextStyle(fontSize: 11.sp,
                      color: AppTheme.accentAmber.withOpacity(0.85))),
            ])),
        GestureDetector(
          onTap: onToggle,
          child: _Toggle(value: isArabic, activeColor: AppTheme.accentAmber,
              inactiveColor: dc.tileBorder),
        ),
      ]),
    );
  }
}

// ─── Theme tile ───────────────────────────────────────────────────────────────

class _ThemeTile extends StatelessWidget {
  final _DC dc;
  const _ThemeTile({required this.dc});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isDark = ThemeController.to.isDark.value;
      const sunColor  = Color(0xFFFFB800);
      const moonColor = AppTheme.accentPurple;
      final color = isDark ? moonColor : sunColor;

      return GestureDetector(
        onTap: ThemeController.to.toggleTheme,
        child: _BaseTile(
          dc: dc,
          iconColor: color,
          icon: isDark ? Icons.nightlight_round : Icons.wb_sunny_rounded,
          iconAnimKey: isDark,
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Appearance', style: TextStyle(fontSize: 13.sp,
                      fontWeight: FontWeight.w500, color: dc.titleText)),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Text(
                      isDark ? 'Dark mode' : 'Light mode',
                      key: ValueKey(isDark),
                      style: TextStyle(fontSize: 11.sp,
                          color: color.withOpacity(0.85)),
                    ),
                  ),
                ])),
            _Toggle(value: isDark, activeColor: moonColor,
                inactiveColor: dc.tileBorder),
          ]),
        ),
      );
    });
  }
}

// ─── Base tile (shared tile shell) ───────────────────────────────────────────

class _BaseTile extends StatelessWidget {
  final _DC dc;
  final Color iconColor;
  final IconData icon;
  final Widget child;
  final bool? iconAnimKey;

  const _BaseTile({
    required this.dc, required this.iconColor,
    required this.icon, required this.child,
    this.iconAnimKey,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 14.w, vertical: 3.h),
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 11.h),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12.r),
        color: dc.tileBg,
        border: Border.all(color: dc.tileBorder, width: 1),
      ),
      child: Row(children: [
        Container(
          width: 34.r, height: 34.r,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9.r),
            color: iconColor.withOpacity(0.12),
          ),
          child: iconAnimKey != null
              ? AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            transitionBuilder: (c, a) => RotationTransition(
              turns: Tween(begin: 0.75, end: 1.0).animate(a),
              child: FadeTransition(opacity: a, child: c),
            ),
            child: Icon(icon, key: ValueKey(iconAnimKey),
                color: iconColor, size: 17.r),
          )
              : Icon(icon, color: iconColor, size: 17.r),
        ),
        SizedBox(width: 12.w),
        Expanded(child: child),
      ]),
    );
  }
}

// ─── Logout tile ──────────────────────────────────────────────────────────────

class _LogoutTile extends StatefulWidget {
  final _DC dc;
  final VoidCallback onTap;
  const _LogoutTile({required this.dc, required this.onTap});

  @override State<_LogoutTile> createState() => _LogoutTileState();
}

class _LogoutTileState extends State<_LogoutTile> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    const red = AppTheme.redColor;
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) { setState(() => _down = false); widget.onTap(); },
      onTapCancel: () => setState(() => _down = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        margin: EdgeInsets.symmetric(horizontal: 14.w, vertical: 3.h),
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 11.h),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12.r),
          color: red.withOpacity(_down ? 0.16 : 0.07),
          border: Border.all(
              color: red.withOpacity(_down ? 0.45 : 0.18), width: 1),
        ),
        child: Row(children: [
          Container(
            width: 34.r, height: 34.r,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9.r),
              color: red.withOpacity(0.12),
            ),
            child: Icon(Icons.logout_rounded, color: red, size: 17.r),
          ),
          SizedBox(width: 12.w),
          Text('logout'.tr,
              style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600,
                  color: red)),
        ]),
      ),
    );
  }
}

// ─── Smooth toggle pill ───────────────────────────────────────────────────────

class _Toggle extends StatelessWidget {
  final bool value;
  final Color activeColor;
  final Color inactiveColor;

  const _Toggle({
    required this.value,
    required this.activeColor,
    required this.inactiveColor,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 230),
      curve: Curves.easeInOut,
      width: 42.w, height: 23.h,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(11.5.r),
        color: value ? activeColor : inactiveColor,
      ),
      child: Stack(children: [
        AnimatedPositioned(
          duration: const Duration(milliseconds: 230),
          curve: Curves.easeInOut,
          left: value ? 20.w : 2.w, top: 1.5.h,
          child: Container(
            width: 20.r, height: 20.r,
            decoration: const BoxDecoration(
                color: Colors.white, shape: BoxShape.circle),
          ),
        ),
      ]),
    );
  }
}

// ─── Animation helpers ────────────────────────────────────────────────────────

class _Anim extends StatelessWidget {
  final Animation<double> fade;
  final Animation<Offset> slide;
  final Widget child;

  const _Anim({required this.fade, required this.slide, required this.child});

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: fade,
    child: SlideTransition(position: slide, child: child),
  );
}

class _CurvedInterval extends Curve {
  final double begin, end;
  final Curve curve;
  const _CurvedInterval(this.begin, this.end, {this.curve = Curves.linear});

  @override
  double transformInternal(double t) {
    if (t <= begin) return 0.0;
    if (t >= end) return 1.0;
    return curve.transform((t - begin) / (end - begin));
  }
}