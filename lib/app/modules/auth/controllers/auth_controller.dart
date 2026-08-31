import 'dart:convert';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final branchDisplayName = ''.obs;
  final branchAddress = ''.obs;
  final branchMob = ''.obs;
  final branchVat = ''.obs;
  final branchPhNo = ''.obs;
  final isVerified = false.obs;
  final isLoading = false.obs;

  final TextEditingController usernameController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController qrCodeController = TextEditingController();

  @override
  void onInit() {
    super.onInit();
    _loadStoredConfig();
    _checkSessionExpired();
  }

  void setOrientation({required bool isMobile}) {
    if (isMobile) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }

  void _checkSessionExpired() {
    if (storage.read('session_expired_flag') == true) {
      storage.remove('session_expired_flag');
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
    branchDisplayName.value = storage.read('branch_display_name') ?? '';
    branchAddress.value = storage.read('branch_address') ?? '';
    branchPhNo.value = storage.read('branch_phone') ?? '';
    branchMob.value = storage.read('branch_mob') ?? '';
    branchVat.value = storage.read('branch_mob') ?? '';

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

  Future<void> processQrValue(String rawValue) async {
    final trimmed = rawValue.trim();
    if (trimmed.isEmpty) return;

    // Safety check: If it looks like a file path, ignore it
    if (trimmed.startsWith('/') || trimmed.startsWith('C:\\')) {
      debugPrint("⚠️ Ignoring suspected file path input: $trimmed");
      return;
    }

    try {
      String decodedString = trimmed;

      if (!trimmed.startsWith('{')) {
        try {
          final decodedBytes = base64Decode(trimmed);
          decodedString = utf8.decode(decodedBytes);
        } catch (_) {
          // If base64 decode fails, we keep decodedString as trimmed and let jsonDecode handle it
        }
      }

      if (!decodedString.startsWith('{')) {
        throw const FormatException("Invalid JSON format");
      }

      final parsed = jsonDecode(decodedString);

      if (parsed is Map<String, dynamic>) {
        await updateBranchConfig(parsed);
      } else {
        Get.snackbar("Error", "Invalid configuration format", backgroundColor: Colors.red, colorText: Colors.white);
      }
    } catch (e) {
      debugPrint("❌ Manual Entry Error: $e");
      // Only show snackbar if it's not a background/empty trigger
      if (trimmed.length > 5) {
        Get.snackbar("Error", "Invalid configuration code", backgroundColor: Colors.red, colorText: Colors.white);
      }
    }
  }

  Future<void> updateBranchConfig(Map<String, dynamic> config) async {
    final String url = config['server_url'] ?? config['servel_url'] ?? '';
    final String code = config['company_code'] ?? '';
    final String bId = config['branch_id']?.toString() ?? '';

    if (url.isEmpty || code.isEmpty || bId.isEmpty) {
      Get.snackbar("Error", "Invalid Branch Configuration", backgroundColor: Colors.red, colorText: Colors.white);
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
      } else if (Platform.isMacOS) {
        final MacOsDeviceInfo macInfo = await deviceInfo.macOsInfo;
        deviceData = {
          "model": macInfo.model,
          "computerName": macInfo.computerName,
          "osRelease": macInfo.osRelease,
        };
        deviceToken = macInfo.systemGUID ?? "macos_device";
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
          final String bName = branchData['branch_name'] ?? '';
          final String bDisName = branchData['branch_display_name'] ?? '';
          final String bAddress = branchData['branch_address'] ?? '';
          final String bMob = branchData['branch_mob'] ?? '';
          final String bPh = branchData['branch_phone'] ?? '';
          final String bTin = branchData['branch_tin'] ?? '';
          final int taxType = branchData['cmp_tax_type'] ?? 1;
          debugPrint("✅ Branch Display Name: $bDisName");
          serverUrl.value = url;
          companyCode.value = code;
          branchId.value = bId;
          branchName.value = bName;
          branchDisplayName.value = bDisName;
          branchAddress.value = bAddress;
          branchMob.value = bMob;
          branchPhNo.value = bPh;
          branchVat.value = bTin;
          storage.write('company_code', code);
          storage.write('branch_id', bId);
          storage.write('branch_name', bName);
          storage.write('branch_display_name', bDisName);
          storage.write('branch_address', bAddress);
          storage.write('branch_mob', bMob);
          storage.write('branch_phone', bPh);
          storage.write('branch_tin', bTin);
          storage.write('branch_token', token);
          storage.write('cmp_tax_type', taxType);

          isVerified.value = true;
          Get.snackbar("✓ Verified", "Branch verified: $code", backgroundColor: Colors.green, colorText: Colors.white);
          qrCodeController.clear();
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
      final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
      String systemId = "";

      if (Platform.isAndroid) {
        final AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;

        final id = androidInfo.id;
        final deviceName = "${androidInfo.manufacturer} ${androidInfo.model}";

        systemId = "$id - $deviceName";

      } else if (Platform.isIOS) {
        final IosDeviceInfo iosInfo = await deviceInfo.iosInfo;

        final id = iosInfo.identifierForVendor ?? "ios_device";
        final deviceName = iosInfo.utsname.machine; // or use name if available

        systemId = "$id - $deviceName";

      } else if (Platform.isMacOS) {
        final MacOsDeviceInfo macInfo = await deviceInfo.macOsInfo;

        final id = macInfo.systemGUID ?? "macos_device";
        final deviceName = macInfo.model;

        systemId = "$id - $deviceName";
      }
      final requestBody = {
        "company_code": companyCode.value,
        "usr_email": username,
        "usr_password": password,
        "system_id": systemId,
      };
      debugPrint("📤 LOGIN REQUEST BODY: $requestBody");
      final response = await _apiService.post(
        'mobileapp/login',
        data: requestBody,
      );
      debugPrint("📥 STATUS CODE: ${response.statusCode}");
      debugPrint("📥 RESPONSE DATA: ${response.data}");
      debugPrint("Branch Name: ${AppState.branchDisName}");

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;

        if (data['status'] == 200) {
          debugPrint("✅ LOGIN SUCCESS");

          AppState.updateSession(
            profile: data['profile'] ?? {},
          );
          debugPrint("Branch Disp: ${AppState.branchDisName}");
          Get.offAllNamed('/sync');
        } else {
          debugPrint("❌ API ERROR: ${data['error']}");

          Get.snackbar(
            "Error",
            data['error'] ?? "Login failed",
            backgroundColor: Colors.red,
            colorText: Colors.white,
          );
        }
      }
    } catch (e, stackTrace) {
      debugPrint("❌ LOGIN EXCEPTION: $e");
      debugPrint("📌 STACKTRACE: $stackTrace");

      Get.snackbar(
        "Error",
        "Login failed",
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    } finally {
      isLoading.value = false;
    }
  }
}
