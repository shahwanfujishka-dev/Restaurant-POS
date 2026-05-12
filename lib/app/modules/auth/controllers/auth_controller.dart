import 'dart:convert';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:get/get_instance/src/extension_instance.dart';
import 'package:get/get_navigation/src/extension_navigation.dart';
import 'package:get/get_rx/src/rx_types/rx_types.dart';
import 'package:get/get_state_manager/src/simple/get_controllers.dart';
import 'package:get_storage/get_storage.dart';

import '../../../data/services/api_services.dart';
import '../../../data/utils/AppState.dart';

class AuthController extends GetxController {
  final isPasswordVisible = false.obs;
  final storage = GetStorage();
  final ApiService _apiService = Get.find<ApiService>();

  final serverUrl = ''.obs;
  final companyCode = ''.obs;
  final branchId = ''.obs;
  final branchName = ''.obs;

  final isVerified = false.obs;
  final isLoading = false.obs;

  final TextEditingController usernameController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  @override
  void onInit() {
    super.onInit();
    _loadStoredConfig();
    _checkSessionExpired();
  }

  void _checkSessionExpired() {
    if (storage.read('session_expired_flag') == true) {
      storage.remove('session_expired_flag');
      // Use a slight delay to ensure the UI is ready to show a snackbar/dialog
      Future.delayed(const Duration(milliseconds: 500), () {
        Get.dialog(
          AlertDialog(
            title: const Text("Session Expired"),
            content: const Text("Your session has expired or the app has been deactivated. Please login again."),
            actions: [
              TextButton(
                onPressed: () => Get.back(),
                child: const Text("OK"),
              ),
            ],
          ),
          barrierDismissible: false,
        );
      });
    }
  }

  void _loadStoredConfig() {
    serverUrl.value = storage.read('base_url') ?? '';
    companyCode.value = storage.read('company_code') ?? '';
    branchId.value = storage.read('branch_id')?.toString() ?? '';
    branchName.value = storage.read('branch_name') ?? '';

    _checkVerificationStatus();
  }

  void _checkVerificationStatus() {
    if (AppState.branchToken.isNotEmpty && serverUrl.value.isNotEmpty) {
      isVerified.value = true;
    } else {
      isVerified.value = false;
    }
  }

  String getBranchInfo() {
    if (companyCode.value.isEmpty) return "No branch selected";
    return "${companyCode.value} - ${storage.read('branch_name')}";
  }


  void togglePasswordVisibility() {
    isPasswordVisible.value = !isPasswordVisible.value;
  }

  Future<void> updateBranchConfig(Map<String, dynamic> config) async {
    final String url = config['server_url'] ?? config['servel_url'] ?? '';
    final String code = config['company_code'] ?? '';
    final String bId = config['branch_id']?.toString() ?? '';

    if (url.isEmpty || code.isEmpty || bId.isEmpty) {
      Get.snackbar("Error", "Invalid QR Code", backgroundColor: Colors.red, colorText: Colors.white);
      return;
    }

    isLoading.value = true;

    try {
      final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
      Map<String, dynamic> deviceData = {};
      String deviceToken = "";

      if (Platform.isAndroid) {
        final AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
        deviceData = {
          "model": androidInfo.model,
          "brand": androidInfo.brand,
          "device": androidInfo.device,
          "version": androidInfo.version.release,
        };
        deviceToken = androidInfo.id;
      } else if (Platform.isIOS) {
        final IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
        deviceData = {
          "name": iosInfo.name,
          "model": iosInfo.model,
          "systemName": iosInfo.systemName,
          "systemVersion": iosInfo.systemVersion,
        };
        deviceToken = iosInfo.identifierForVendor ?? "ios_device";
      }

      storage.write('base_url', url);

      final response = await _apiService.post('api/get_branch_token', data: {
        "branch_id": int.parse(bId),
        "company_code": code,
        "device_details": jsonEncode([deviceData]),
        "device_token": deviceToken,
      });

      if (response.statusCode == 200 && response.data != null) {
        final List<dynamic> dataList = response.data;

        if (dataList.isNotEmpty) {
          final branchData = dataList[0];
          final String token = branchData['token'] ?? '';
          final String bName = branchData['branch_name'] ?? branchData['branch_display_name'];

          serverUrl.value = url;
          companyCode.value = code;
          branchId.value = bId;
          branchName.value = bName;

          storage.write('company_code', code);
          storage.write('branch_id', bId);
          storage.write('branch_name', bName);
          storage.write('branch_token', token);

          isVerified.value = true;
          Get.snackbar("✓ Verified", "Branch verified: $code", backgroundColor: Colors.green, colorText: Colors.white);
        }
      }
    } catch (e) {
      debugPrint("❌ Verification Error: $e");
      Get.snackbar("Error", "Verification failed", backgroundColor: Colors.red, colorText: Colors.white);
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> login() async {
    final username = usernameController.text.trim();
    final password = passwordController.text.trim();

    if (username.isEmpty || password.isEmpty) return;
    isLoading.value = true;

    try {
      final response = await _apiService.post('mobileapp/user/caption_login', data: {
        "usr_name": username,
        "usr_password": password,
      });

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;

        if (data['status'] == 200) {
          AppState.updateSession(
            profile: data['profile'] ?? {},
          );
          // Redirect to Sync screen instead of Home
          Get.offAllNamed('/sync');
        } else {
          Get.snackbar("Error", data['error'] ?? "Login failed", backgroundColor: Colors.red, colorText: Colors.white);
        }
      }
    } catch (e) {
      debugPrint("❌ Login Error: $e");
    } finally {
      isLoading.value = false;
    }
  }

  void resetBranchVerification() {
    storage.remove('base_url');
    storage.remove('branch_token');
    storage.remove('company_code');
    storage.remove('branch_id');
    isVerified.value = false;
  }
}