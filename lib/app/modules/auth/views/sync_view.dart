import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:get/get_navigation/src/extension_navigation.dart';
import 'package:get/get_state_manager/src/rx_flutter/rx_obx_widget.dart';
import 'package:get/get_state_manager/src/simple/get_view.dart';
import 'dart:math' as math;

import '../../../theme/app_theme.dart';
import '../../../theme/app_typography.dart';
import '../controllers/sync_controller.dart';

class SyncView extends GetView<SyncController> {
  const SyncView({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      backgroundColor: colors.bg,
      body: Stack(
        children: [
          _AnimatedBackground(isDark: colors.isDark),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: 40.w, vertical: 24.h),
                child: Obx(() => AnimatedSwitcher(
                  duration: const Duration(milliseconds: 450),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.08),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: controller.hasError.value
                      ? _ErrorBody(
                    key: const ValueKey('error'),
                    message: controller.errorMessage.value,
                    onRetry: controller.startSync,
                  )
                      : _SyncingBody(
                    key: const ValueKey('syncing'),
                    controller: controller,
                  ),
                )),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Syncing Body ──────────────────────────────────────────────────────────

class _SyncingBody extends StatelessWidget {
  final SyncController controller;
  const _SyncingBody({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(height: 16.h),

        _FadeSlideIn(
          delay: const Duration(milliseconds: 100),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 6.h),
            decoration: BoxDecoration(
              color: AppTheme.primaryGreen.withOpacity(0.1),
              borderRadius: BorderRadius.circular(100),
              border: Border.all(
                color: AppTheme.primaryGreen.withOpacity(0.35),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _PulsingDot(),
                SizedBox(width: 7.w),
                Text(
                  "INITIALIZING SYSTEM",
                  style: TextStyle(
                    fontSize: AppTypography.smallText,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryGreen,
                    letterSpacing: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ),

        SizedBox(height: 10.h),
        const _SyncOrb(),
        SizedBox(height: 15.h),

        _FadeSlideIn(
          delay: const Duration(milliseconds: 400),
          child: Text(
            "Getting your station ready",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: AppTypography.sizeText,
              fontWeight: FontWeight.w700,
              color: colors.text,
              letterSpacing: 0.3,
              height: 1.3,
            ),
          ),
        ),

        SizedBox(height: 10.h),

        _FadeSlideIn(
          delay: const Duration(milliseconds: 500),
          child: Obx(() => AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.3),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: Text(
              controller.statusMessage.value,
              key: ValueKey(controller.statusMessage.value),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AppTypography.smallText,
                color: colors.subtext,
                letterSpacing: 0.2,
                height: 1.5,
              ),
            ),
          )),
        ),

        SizedBox(height: 20.h),

        _FadeSlideIn(
          delay: const Duration(milliseconds: 700),
          child: Obx(() => _ProgressSection(progress: controller.progress.value)),
        ),

        SizedBox(height: 25.h),

        _FadeSlideIn(
          delay: const Duration(milliseconds: 900),
          child: Obx(() => _StepDots(progress: controller.progress.value)),
        ),

        SizedBox(height: 10.h),

        _FadeSlideIn(
          delay: const Duration(milliseconds: 1100),
          child: Text(
            "Please keep the app open while we\nsync your restaurant data.",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: AppTypography.smallText,
              color: colors.subtext.withOpacity(0.7),
              letterSpacing: 0.3,
              height: 1.7,
            ),
          ),
        ),

        SizedBox(height: 16.h),
      ],
    );
  }
}

// ─── Error Body ────────────────────────────────────────────────────────────

class _ErrorBody extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorBody({super.key, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(height: 40.h),

        Container(
          width: 110.w,
          height: 110.w,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [colors.card, colors.textField],
              center: const Alignment(-0.3, -0.3),
            ),
            border: Border.all(
              color: const Color(0xFFE74C3C).withOpacity(0.22),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFE74C3C).withOpacity(0.13),
                blurRadius: 28,
                spreadRadius: 4,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(
            Icons.wifi_off_rounded,
            size: 42.sp,
            color: const Color(0xFFE74C3C),
          ),
        ),

        SizedBox(height: 28.h),

        Text(
          "Connection Failed",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: AppTypography.sizeText,
            fontWeight: FontWeight.w700,
            color: colors.text,
            letterSpacing: 0.3,
          ),
        ),

        SizedBox(height: 14.h),

        Container(
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(14.r),
            border: Border.all(color: const Color(0xFFFFE5E5).withOpacity(0.3), width: 1),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFE74C3C).withOpacity(0.06),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 15.sp,
                color: const Color(0xFFE74C3C).withOpacity(0.65),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    fontSize: AppTypography.smallText,
                    color: colors.text,
                    height: 1.55,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ],
          ),
        ),

        SizedBox(height: 28.h),

        // Retry button
        GestureDetector(
          onTap: onRetry,
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(vertical: 15.h),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF27AE60), Color(0xFF2ECC71)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(14.r),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF2ECC71).withOpacity(0.32),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.refresh_rounded, color: Colors.white, size: 18.sp),
                SizedBox(width: 8.w),
                Text(
                  "Retry Sync",
                  style: TextStyle(
                    fontSize: AppTypography.sizeText,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),

        SizedBox(height: 14.h),

        GestureDetector(
          onTap: () => Get.offAllNamed('/login'),
          child: Text(
            "Back to Login",
            style: TextStyle(
              fontSize: AppTypography.smallText,
              color: colors.subtext,
              decoration: TextDecoration.underline,
              decorationColor: colors.subtext,
              letterSpacing: 0.3,
            ),
          ),
        ),

        SizedBox(height: 40.h),
      ],
    );
  }
}

// ─── Pulsing Green Dot ─────────────────────────────────────────────────────

class _PulsingDot extends StatefulWidget {
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Container(
        width: 6.w,
        height: 6.w,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Color.lerp(
            const Color(0xFF2ECC71),
            const Color(0xFF27AE60),
            _ctrl.value,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF2ECC71).withOpacity(0.5 * _ctrl.value),
              blurRadius: 6,
              spreadRadius: 1,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Animated Background ───────────────────────────────────────────────────

class _AnimatedBackground extends StatefulWidget {
  final bool isDark;
  const _AnimatedBackground({required this.isDark});

  @override
  State<_AnimatedBackground> createState() => _AnimatedBackgroundState();
}

class _AnimatedBackgroundState extends State<_AnimatedBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 9),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => CustomPaint(
        painter: _BackgroundPainter(_ctrl.value, widget.isDark),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _BackgroundPainter extends CustomPainter {
  final double t;
  final bool isDark;
  _BackgroundPainter(this.t, this.isDark);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = isDark ? AppTheme.darkBg : const Color(0xFFF7FAF8),
    );

    final greenGlow = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF2ECC71)
              .withOpacity((isDark ? 0.05 : 0.10) + 0.04 * math.sin(t * 2 * math.pi)),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(
        center: Offset(size.width * 0.1, size.height * 0.12),
        radius: size.width * 0.7,
      ));
    canvas.drawCircle(
        Offset(size.width * 0.1, size.height * 0.12), size.width * 0.7, greenGlow);

    final mintGlow = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF82E0AA)
              .withOpacity((isDark ? 0.03 : 0.07) + 0.03 * math.sin(t * 2 * math.pi + 1.5)),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(
        center: Offset(size.width * 0.9, size.height * 0.88),
        radius: size.width * 0.55,
      ));
    canvas.drawCircle(
        Offset(size.width * 0.9, size.height * 0.88), size.width * 0.55, mintGlow);

    final warmGlow = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFF9E4B7)
              .withOpacity((isDark ? 0.08 : 0.18) + 0.06 * math.sin(t * 2 * math.pi + 3.0)),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(
        center: Offset(size.width * 0.05, size.height * 0.9),
        radius: size.width * 0.45,
      ));
    canvas.drawCircle(
        Offset(size.width * 0.05, size.height * 0.9), size.width * 0.45, warmGlow);

    final dotPaint = Paint()
      ..color = const Color(0xFF2ECC71).withOpacity(0.07);
    final random = math.Random(42);
    for (int i = 0; i < 18; i++) {
      final x = random.nextDouble() * size.width;
      final baseY = random.nextDouble() * size.height;
      final y = (baseY + t * 40 * (random.nextDouble() + 0.5)) % size.height;
      final r = random.nextDouble() * 3 + 1;
      canvas.drawCircle(Offset(x, y), r, dotPaint);
    }

    final linePaint = Paint()
      ..color = const Color(0xFF2ECC71).withOpacity(isDark ? 0.015 : 0.025)
      ..strokeWidth = 0.6;
    for (int i = 0; i < 8; i++) {
      final y = (size.height * i / 8 + t * 50) % size.height;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }
  }

  @override
  bool shouldRepaint(_BackgroundPainter old) => old.t != t || old.isDark != isDark;
}

// ─── Sync Orb ──────────────────────────────────────────────────────────────

class _SyncOrb extends StatefulWidget {
  const _SyncOrb();

  @override
  State<_SyncOrb> createState() => _SyncOrbState();
}

class _SyncOrbState extends State<_SyncOrb> with TickerProviderStateMixin {
  late AnimationController _rotCtrl;
  late AnimationController _pulseCtrl;
  late AnimationController _ringCtrl;

  @override
  void initState() {
    super.initState();
    _rotCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _ringCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _rotCtrl.dispose();
    _pulseCtrl.dispose();
    _ringCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final orbSize = math.min(130.w, 130.h);
    final colors = AppColors.of(context);

    return SizedBox(
      width: orbSize * 1.8,
      height: orbSize * 1.8,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _ringCtrl,
            builder: (_, __) {
              final scale = 1.0 + _ringCtrl.value * 0.55;
              final opacity = (1 - _ringCtrl.value) * 0.25;
              return Transform.scale(
                scale: scale,
                child: Container(
                  width: orbSize,
                  height: orbSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF2ECC71).withOpacity(opacity),
                      width: 1.5,
                    ),
                  ),
                ),
              );
            },
          ),
          AnimatedBuilder(
            animation: _ringCtrl,
            builder: (_, __) {
              final t2 = (_ringCtrl.value + 0.5) % 1.0;
              final scale = 1.0 + t2 * 0.55;
              final opacity = (1 - t2) * 0.15;
              return Transform.scale(
                scale: scale,
                child: Container(
                  width: orbSize,
                  height: orbSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF2ECC71).withOpacity(opacity),
                      width: 1.0,
                    ),
                  ),
                ),
              );
            },
          ),
          AnimatedBuilder(
            animation: _pulseCtrl,
            builder: (_, __) {
              return Container(
                width: orbSize * (1.0 + 0.07 * _pulseCtrl.value),
                height: orbSize * (1.0 + 0.07 * _pulseCtrl.value),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF2ECC71)
                          .withOpacity(0.18 + 0.12 * _pulseCtrl.value),
                      blurRadius: 28,
                      spreadRadius: 6,
                    ),
                  ],
                ),
              );
            },
          ),
          Container(
            width: orbSize,
            height: orbSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [colors.card, colors.textField],
                center: const Alignment(-0.3, -0.3),
              ),
              border: Border.all(
                color: const Color(0xFF2ECC71).withOpacity(0.25),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF2ECC71).withOpacity(0.12),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
          ),
          AnimatedBuilder(
            animation: _rotCtrl,
            builder: (_, __) {
              return Transform.rotate(
                angle: _rotCtrl.value * 2 * math.pi,
                child: CustomPaint(
                  painter: _ArcPainter(),
                  size: Size(orbSize, orbSize),
                ),
              );
            },
          ),
          Icon(
            Icons.restaurant_menu_rounded,
            size: 38.sp,
            color: const Color(0xFF27AE60),
          ),
        ],
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.8
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        colors: [
          Colors.transparent,
          const Color(0xFF2ECC71).withOpacity(0.85),
        ],
        stops: const [0.65, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawArc(
      Rect.fromLTWH(0, 0, size.width, size.height),
      0,
      math.pi * 1.6,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_ArcPainter old) => false;
}

// ─── Progress Section ──────────────────────────────────────────────────────

class _ProgressSection extends StatelessWidget {
  final double progress;
  const _ProgressSection({required this.progress});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 16.h),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: colors.border.withOpacity(0.5), width: 1),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2ECC71).withOpacity(0.07),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Syncing data...",
                style: TextStyle(
                  fontSize: AppTypography.sizeText,
                  color: colors.text,
                  letterSpacing: 0.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: progress),
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeOut,
                builder: (_, val, __) => Text(
                  "${(val * 100).toInt()}%",
                  style:  TextStyle(
                    fontSize: AppTypography.sizeText,
                    color: Color(0xFF27AE60),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 12.h),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: progress),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOut,
            builder: (_, val, __) {
              return Stack(
                children: [
                  Container(
                    height: 6.h,
                    decoration: BoxDecoration(
                      color: colors.textField,
                      borderRadius: BorderRadius.circular(100),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: val.clamp(0.0, 1.0),
                    child: Container(
                      height: 6.h,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(100),
                        gradient: const LinearGradient(
                          colors: [Color(0xFF27AE60), Color(0xFF52D68A)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF2ECC71).withOpacity(0.45),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

// ─── Step Dots ─────────────────────────────────────────────────────────────

class _StepDots extends StatelessWidget {
  final double progress;
  const _StepDots({required this.progress});

  static const _labels = [
    (Icons.wifi_rounded, "Connect"),
    (Icons.menu_book_rounded, "Menu"),
    (Icons.table_restaurant_rounded, "Tables"),
    (Icons.inventory_2_rounded, "Stock"),
    (Icons.check_circle_rounded, "Done"),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final activeIndex =
    (progress * _labels.length).floor().clamp(0, _labels.length - 1);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_labels.length, (i) {
        final isDone = i < activeIndex;
        final isActive = i == activeIndex;

        return Padding(
          padding: EdgeInsets.symmetric(horizontal: 6.w),
          child: Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOut,
                width: isActive ? 25.w : 19.w,
                height: isActive ? 25.w : 19.w,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDone
                      ? const Color(0xFF27AE60)
                      : isActive
                      ? colors.card
                      : colors.textField,
                  border: Border.all(
                    color: isDone || isActive
                        ? const Color(0xFF2ECC71)
                        : colors.border,
                    width: isActive ? 2 : 1,
                  ),
                  boxShadow: isActive
                      ? [
                    BoxShadow(
                      color: const Color(0xFF2ECC71).withOpacity(0.25),
                      blurRadius: 12,
                      spreadRadius: 2,
                    ),
                  ]
                      : isDone
                      ? [
                    BoxShadow(
                      color: const Color(0xFF27AE60).withOpacity(0.2),
                      blurRadius: 8,
                    ),
                  ]
                      : null,
                ),
                child: Icon(
                  _labels[i].$1,
                  size: isActive ? 16.sp : 13.sp,
                  color: isDone
                      ? Colors.white
                      : isActive
                      ? const Color(0xFF27AE60)
                      : colors.subtext.withOpacity(0.5),
                ),
              ),
              SizedBox(height: 6.h),
              Text(
                _labels[i].$2,
                style: TextStyle(
                  fontSize: AppTypography.smallText,
                  color: isDone || isActive
                      ? const Color(0xFF27AE60)
                      : colors.subtext.withOpacity(0.5),
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

// ─── Fade + Slide In ───────────────────────────────────────────────────────

class _FadeSlideIn extends StatefulWidget {
  final Widget child;
  final Duration delay;
  const _FadeSlideIn({required this.child, required this.delay});

  @override
  State<_FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<_FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _opacity;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));

    Future.delayed(widget.delay, () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}