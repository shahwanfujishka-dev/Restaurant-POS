import 'package:flutter/material.dart';
import 'package:get/get_state_manager/src/simple/get_view.dart';
import 'package:restaurant_pos/app/modules/home/views/dashoard/widgets/cart_panel.dart';
import 'package:restaurant_pos/app/modules/home/views/dashoard/widgets/dashboard_widgets/main_content.dart';

import '../../../../../helper/screen_type.dart';
import '../../../../theme/app_theme.dart';
import '../../controller/dashboard_controller.dart';

class DashboardPage extends GetView<DashboardController> {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      backgroundColor: colors.bg,
      body: TweenAnimationBuilder(
        duration: const Duration(milliseconds: 400),
        tween: Tween<double>(begin: 30, end: 0),
        curve: Curves.easeOutCubic,
        builder: (context, double value, child) {
          return Transform.translate(
            offset: Offset(value, 0),
            child: Opacity(
              opacity: 1 - (value / 30),
              child: child,
            ),
          );
        },
        child: ScreenType.isMobile()
            ? const MainContent()
            : Row(
          children: const [
            Expanded(
              flex: 7,
              child: MainContent(),
            ),
            Expanded(
              flex: 3,
              child: CartPanel(),
            ),
          ],
        ),
      ),
    );
  }
}
