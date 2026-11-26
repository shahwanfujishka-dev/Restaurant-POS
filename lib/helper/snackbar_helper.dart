import 'package:get/get_core/src/get_main.dart';
import 'package:get/get_navigation/src/extension_navigation.dart';
import 'package:get/get_navigation/src/snackbar/snackbar.dart';

void showSafeSnackbar(
  String title,
  String message, {
  Duration duration = const Duration(seconds: 2),
}) {
  Get.closeAllSnackbars();
  Get.snackbar(
    title,
    message,
    snackPosition: SnackPosition.BOTTOM,
    duration: duration,
  );
}
