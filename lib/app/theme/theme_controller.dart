import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

import '../theme/app_theme.dart';

/// Manages light/dark theme preference reactively.
/// Registered in main() as a permanent service.
///
/// Toggle from anywhere:
///   ThemeController.to.toggleTheme();
///
/// Read current state:
///   ThemeController.to.isDark.value
class ThemeController extends GetxController {
  static ThemeController get to => Get.find();

  final _storage = GetStorage();
  static const _storageKey = 'is_dark_mode';

  final isDark = false.obs;

  @override
  void onInit() {
    super.onInit();
    isDark.value = _storage.read<bool>(_storageKey) ?? false;
  }

  void toggleTheme() => _applyTheme(!isDark.value);

  void setDark(bool value) {
    if (isDark.value == value) return;
    _applyTheme(value);
  }

  void _applyTheme(bool dark) {
    isDark.value = dark;
    _storage.write(_storageKey, dark);
    Get.changeThemeMode(dark ? ThemeMode.dark : ThemeMode.light);
  }
}