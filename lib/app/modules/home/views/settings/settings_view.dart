import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../../../../data/utils/AppState.dart';
import '../../../../theme/app_theme.dart';
import '../../../../theme/app_typography.dart';
import '../../controller/settings_controller.dart';

class SettingsView extends GetView<SettingsController> {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      backgroundColor: colors.bg,
      body: ListView(
        padding: EdgeInsets.all(16.w),
        children: [
          Text(
            "Sync Preferences",
            style: AppTypography.cardTitle.copyWith(fontWeight: FontWeight.bold, color: colors.text),
          ),
          SizedBox(height: 12.h),
          Container(
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(12.r),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(colors.isDark ? 0.2 : 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                Obx(() => ListTile(
                  leading: CircleAvatar(
                    backgroundColor: controller.isBackgroundSync.value
                        ? AppTheme.primaryGreen.withOpacity(0.1)
                        : colors.textField,
                    child: Icon(
                        Icons.sync,
                        color: controller.isBackgroundSync.value
                            ? AppTheme.primaryGreen
                            : colors.subtext
                    ),
                  ),
                  title: Text("Background Sync", style: TextStyle(color: colors.text)),
                  subtitle: Text(
                      controller.isBackgroundSync.value
                          ? "Orders sync automatically as soon as possible."
                          : "Orders will only sync when you press the sync button.",
                      style: TextStyle(color: colors.subtext)
                  ),
                  trailing: Switch(
                    value: controller.isBackgroundSync.value,
                    onChanged: controller.toggleBackgroundSync,
                    activeColor: AppTheme.primaryGreen,
                  ),
                )),
                Divider(height: 1, color: colors.border),
                Obx(() => ListTile(
                  onTap: controller.isMasterSyncing.value 
                      ? null 
                      : controller.performManualMasterSync,
                  leading: CircleAvatar(
                    backgroundColor: AppTheme.primaryGreen.withOpacity(0.1),
                    child: controller.isMasterSyncing.value
                        ? SizedBox(
                            width: 20.w,
                            height: 20.w,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.primaryGreen,
                              value: controller.masterSyncProgress.value > 0 
                                  ? controller.masterSyncProgress.value 
                                  : null,
                            ),
                          )
                        : const Icon(Icons.cloud_download_outlined, color: AppTheme.primaryGreen),
                  ),
                  title: Text("Manual Data Sync", style: TextStyle(color: colors.text)),
                  subtitle: Text(
                      controller.isMasterSyncing.value
                          ? "Updating restaurant data... ${(controller.masterSyncProgress.value * 100).toInt()}%"
                          : "Download latest categories, products, and tables.",
                      style: TextStyle(color: colors.subtext)
                  ),
                  trailing: Icon(Icons.chevron_right, color: colors.subtext),
                )),
              ],
            ),
          ),
          
          SizedBox(height: 24.h),
          Text(
            "Account",
            style: AppTypography.cardTitle.copyWith(fontWeight: FontWeight.bold, color: colors.text),
          ),
          SizedBox(height: 12.h),
          Container(
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(12.r),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(colors.isDark ? 0.2 : 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFFEE2E2),
                    child: Icon(Icons.logout, color: Colors.red),
                  ),
                  title: const Text("Logout", style: TextStyle(color: Colors.red)),
                  subtitle: Text("Clear all local data and sign out.", style: TextStyle(color: colors.subtext)),
                  onTap: () => _showLogoutDialog(context),
                ),
              ],
            ),
          ),

          SizedBox(height: 24.h),
          Text(
            "About App",
            style: AppTypography.cardTitle.copyWith(fontWeight: FontWeight.bold, color: colors.text),
          ),
          SizedBox(height: 12.h),
          _buildInfoTile(context, Icons.info_outline, "Version", "1.0.0 (Build 3)"),
          _buildInfoTile(context, Icons.person_outline, "User ID", AppState.userId),
          _buildInfoTile(context, Icons.business_outlined, "Branch", AppState.username),
        ],
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    final colors = AppColors.of(context);
    Get.dialog(
      CupertinoAlertDialog(
        title: const Text("Logout"),
        content: const Text("Are you sure you want to logout? All unsynced orders will be lost."),
        actions: [
          CupertinoDialogAction(
            child: const Text("Cancel"),
            onPressed: () => Get.back(),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => AppState.logout(),
            child: const Text("Logout"),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoTile(BuildContext context, IconData icon, String title, String value) {
    final colors = AppColors.of(context);
    return Container(
      margin: EdgeInsets.only(bottom: 8.h),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: ListTile(
        leading: Icon(icon, color: colors.subtext),
        title: Text(title, style: TextStyle(color: colors.text)),
        trailing: Text(
          value,
          style: TextStyle(fontWeight: FontWeight.bold, color: colors.subtext),
        ),
      ),
    );
  }
}
