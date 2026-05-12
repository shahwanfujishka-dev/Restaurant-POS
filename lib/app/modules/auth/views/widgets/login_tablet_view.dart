import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:get/get_navigation/src/extension_navigation.dart';
import 'package:get/get_state_manager/src/rx_flutter/rx_obx_widget.dart';
import 'package:get/get_state_manager/src/simple/get_view.dart';

import '../../../../theme/app_theme.dart';
import '../../../../theme/app_typography.dart';
import '../../controllers/auth_controller.dart';

class LoginTabletView extends GetView<AuthController> {
  const LoginTabletView({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      backgroundColor: colors.bg,
      body: Row(
        children: [
          // Side Panel with Branding
          Expanded(
            flex: 2,
            child: Container(
              color: AppTheme.primaryGreen.withOpacity(0.1),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.fastfood, size: 50.sp, color: AppTheme.primaryGreen),
                    SizedBox(height: 16.h),
                    Text(
                      'Restaurant POS',
                      style: AppTypography.headline1.copyWith(color: AppTheme.primaryGreen),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Login Form
          Expanded(
            flex: 3,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 64.w),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Welcome Back!',
                      style: AppTypography.headline1.copyWith(color: colors.text),
                    ),
                    SizedBox(height: 8.h),
                    Column(
                      children: [
                        Obx(() => Column(
                          children: [
                            GestureDetector(
                              onTap: () async {
                                final result = await Get.toNamed('/qr-scanner');

                                if (result != null && result is Map<String, dynamic>) {
                                  controller.updateBranchConfig(result);
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryGreen.withOpacity(0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.qr_code_scanner,
                                    size: 32.sp, color: AppTheme.primaryGreen),
                              ),
                            ),

                            SizedBox(height: 12.h),

                            /// ✅ Verification Status Banner
                            if (controller.isVerified.value)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  "✓ ${controller.getBranchInfo()}",
                                  style: const TextStyle(color: Colors.green),
                                ),
                              )
                            else
                              const Text(
                                "Scan QR to verify branch",
                                style: TextStyle(color: Colors.red),
                              ),
                          ],
                        )),

                        SizedBox(height: 20.h),
                      ],
                    ),
                    Text(
                      'Login to your account',
                      style: AppTypography.subtitle.copyWith(color: colors.subtext),
                    ),
                    SizedBox(height: 40.h),
                    TextField(
                      controller: controller.usernameController,
                      style: TextStyle(color: colors.text),
                      decoration: InputDecoration(
                        labelText: 'Username',
                        labelStyle: TextStyle(color: colors.subtext),
                        filled: true,
                        fillColor: colors.textField,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8.r),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8.r),
                          borderSide: BorderSide(color: colors.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8.r),
                          borderSide: const BorderSide(color: AppTheme.primaryGreen),
                        ),
                      ),
                    ),
                    SizedBox(height: 16.h),
                    Obx(() => TextField(
                      controller: controller.passwordController,
                      obscureText: !controller.isPasswordVisible.value,
                      style: TextStyle(color: colors.text),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        labelStyle: TextStyle(color: colors.subtext),
                        filled: true,
                        fillColor: colors.textField,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8.r),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8.r),
                          borderSide: BorderSide(color: colors.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8.r),
                          borderSide: const BorderSide(color: AppTheme.primaryGreen),
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            controller.isPasswordVisible.value
                                ? Icons.visibility
                                : Icons.visibility_off,
                            color: colors.subtext,
                          ),
                          onPressed: () {
                            controller.togglePasswordVisibility();
                          },
                        ),
                      ),
                    )),
                    SizedBox(height: 30.h),
                    Obx(() => ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: controller.isVerified.value
                            ? AppTheme.primaryGreen
                            : colors.subtext.withOpacity(0.5),
                        minimumSize: Size(double.infinity, 50.h),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8.r),
                        ),
                      ),
                      onPressed: controller.isVerified.value
                          ? () {
                        controller.login();
                      }
                          : null, // disables button
                      child: controller.isLoading.value
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Text('Login', style: AppTypography.button),
                    ))
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}