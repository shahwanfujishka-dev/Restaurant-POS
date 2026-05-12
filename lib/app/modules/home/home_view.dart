import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:get/get_instance/src/extension_instance.dart';
import 'package:get/get_navigation/src/extension_navigation.dart';
import 'package:get/get_state_manager/src/rx_flutter/rx_obx_widget.dart';
import 'package:get/get_state_manager/src/simple/get_view.dart';
import 'package:get/get_utils/src/extensions/internacionalization.dart';

import '../../../helper/screen_type.dart';
import '../../data/services/sync_service.dart';
import '../../data/utils/AppState.dart';
import '../../routes/app_pages.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_typography.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/custom_drawer.dart';
import '../../widgets/navigation_rail.dart';
import '../cart/controller/cart_controller.dart';
import '../order_type/controller/order_type_controller.dart';
import 'controller/home_controller.dart';

class HomeView extends GetView<HomeController> {
  const HomeView({super.key});

  void _toggleLanguage() {
    if (Get.locale?.languageCode == 'ar') {
      Get.updateLocale(const Locale('en', 'US'));
    } else {
      Get.updateLocale(const Locale('ar', 'AR'));
    }
  }

  Future<bool> _onWillPop() async {
    if (controller.selectedIndex.value != 0) {
      controller.changeIndex(0);
      return false;
    }

    final shouldExit = await Get.dialog<bool>(
      AlertDialog(
        title: const Text("Exit App"),
        content: const Text("Are you sure you want to exit?"),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Get.back(result: true),
            child: const Text("Exit"),
          ),
        ],
      ),
    );

    return shouldExit ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final cartController = Get.find<CartController>();
    final syncService = Get.find<SyncService>();
    final orderTypeController = Get.find<OrderTypeController>();
    final colors = AppColors.of(context);

    if (ScreenType.isMobile()) {
      controller.setOrientation(isMobile: true);
    } else {
      controller.setOrientation(isMobile: false);
    }
    return Obx(
          () => WillPopScope(
        onWillPop: _onWillPop,
        child: Scaffold(
          appBar: AppBar(
            backgroundColor: colors.card,
            elevation: 0,
            iconTheme: IconThemeData(color: colors.text),
            title: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      controller.pageTitle.tr,
                      style: AppTypography.appBarTitle.copyWith(color: colors.text),
                    ),
                  ],
                ),
                SizedBox(width: 8.w),
                Obx(() => syncService.isSyncing.value
                    ? SizedBox(
                  width: 16.w,
                  height: 16.w,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.w,
                    valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryGreen),
                  ),
                )
                    : const SizedBox.shrink()),
              ],
            ),
            actions: [
              if (ScreenType.isTabletOrDesktop())
                Padding(
                  padding: EdgeInsets.only(right: 12.w),
                  child: Row(
                    children: [
                      // Change Order Type Button
                      TextButton.icon(
                        onPressed: () => Get.toNamed(Routes.ORDER_TYPE),
                        icon: Icon(Icons.swap_horiz, size: 4.sp, color: AppTheme.primaryGreen),
                        label:  Container(
                          padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 7.h),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryGreen.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4.r),
                          ),
                          child: Text(
                            (orderTypeController.selectedType.value ?? AppState.orderType).displayName.toUpperCase(),
                            style: TextStyle(
                              fontSize: ScreenType.isMobile() ? 12.sp : 5.sp,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryGreen,
                            ),
                          ),
                        ),
                      ),
                      Text(
                        AppState.username.toUpperCase(),
                        style: TextStyle(
                          fontSize: 4.sp,
                          fontWeight: FontWeight.w600,
                          color: colors.text,
                        ),
                      ),
                      SizedBox(width: 2.w),
                      _buildThemeToggle(context),
                      _buildLanguageToggle(context),
                    ],
                  ),
                ),

              if (ScreenType.isMobile() && controller.selectedIndex.value == 0)
                Padding(
                  padding: EdgeInsets.only(right: 8.w),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      IconButton(
                        icon: Icon(Icons.shopping_cart, color: colors.text),
                        onPressed: () {
                          Get.toNamed(Routes.CART);
                        },
                      ),
                      Obx(() {
                        int count = cartController.totalItemsCount;
                        if (count == 0) return const SizedBox.shrink();
                        return Positioned(
                          right: 8,
                          top: 8,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            constraints: BoxConstraints(
                              minWidth: 16.w,
                              minHeight: 16.w,
                            ),
                            child: Text(
                              '$count',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10.sp,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
            ],
          ),
          drawer: ScreenType.isMobile()
              ? AppDrawer(
            userName: AppState.username,         // or from your auth state
            onLogout: controller.logout,
            onSettings: () => Get.toNamed(Routes.SETTINGS),
            onChangeOrderType: () => Get.toNamed(Routes.ORDER_TYPE),
            onToggleLanguage: _toggleLanguage,
            isArabic: Get.locale?.languageCode == 'ar',
          )
              : null,
          body: Row(
            children: [
              if (ScreenType.isTabletOrDesktop())
                PosSidebar(
                  selectedIndex: controller.selectedIndex.value,
                  onItemSelected: controller.changeIndex,
                  onLogout: controller.logout,
                ),
              Expanded(
                child: Container(
                  color: colors.bg,
                  child: IndexedStack(
                    index: controller.selectedIndex.value,
                    children: controller.pages,
                  ),
                ),
              ),
            ],
          ),
          bottomNavigationBar: ScreenType.isMobile()
              ? BottomNavigationBar(
            backgroundColor: colors.card,
            selectedItemColor: AppTheme.primaryGreen,
            unselectedItemColor: colors.subtext,
            currentIndex: controller.selectedIndex.value,
            onTap: controller.changeIndex,
            type: BottomNavigationBarType.fixed,
            items: [
              BottomNavigationBarItem(
                icon: const Icon(Icons.dashboard),
                label: 'dashboard'.tr,
              ),
              BottomNavigationBarItem(
                icon: const Icon(Icons.table_restaurant),
                label: 'tables'.tr,
              ),
              BottomNavigationBarItem(
                icon: const Icon(Icons.receipt),
                label: 'orders'.tr,
              ),
              BottomNavigationBarItem(
                icon: const Icon(Icons.print),
                label: 'printers'.tr,
              ),
            ],
          )
              : null,
        ),
      ),
    );
  }

  Widget _buildThemeToggle(BuildContext context) {
    return Obx(() {
      final isDark = ThemeController.to.isDark.value;
      final colors = AppColors.of(context);
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: 4.w),
        child: ActionChip(
          avatar: Icon(
            isDark ? Icons.nightlight_round : Icons.wb_sunny_rounded,
            size: 4.sp,
            color: isDark ? Colors.white : Colors.orange,
          ),
          label: Text(isDark ? 'dark_mode'.tr : 'light_mode'.tr),
          backgroundColor: isDark ? AppTheme.accentPurple : colors.textField,
          labelStyle: TextStyle(
            color: isDark ? Colors.white : colors.text,
            fontSize: 3.5.sp,
          ),
          onPressed: ThemeController.to.toggleTheme,
        ),
      );
    });
  }

  Widget _buildLanguageToggle(BuildContext context) {
    bool isArabic = Get.locale?.languageCode == 'ar';
    final colors = AppColors.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 2.w),
      child: ActionChip(
        avatar: Icon(
          Icons.translate,
          size: 4.sp,
          color: isArabic ? Colors.white : colors.text,
        ),
        label: Text(isArabic ? 'English' : 'العربية'),
        backgroundColor: isArabic
            ? AppTheme.primaryGreen
            : colors.textField,
        labelStyle: TextStyle(color: isArabic ? Colors.white : colors.text, fontSize: 3.5.sp),
        onPressed: _toggleLanguage,
      ),
    );
  }
}
