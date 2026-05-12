import 'package:get/get_core/src/get_main.dart';
import 'package:get/get_navigation/src/extension_navigation.dart';

class ScreenType {
  // Mobile: < 450
  static bool isMobile() => Get.width < 450;

  // Tablet: 450 to 1100
  static bool isTablet() => Get.width >= 450 && Get.width < 1100;

  // Desktop: >= 1100
  static bool isDesktop() => Get.width >= 1100;

  // Combined check for larger screens
  static bool isTabletOrDesktop() => isTablet() || isDesktop();
}