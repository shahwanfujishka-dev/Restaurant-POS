import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../../../../data/Device_Roles/device_roles.dart';
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
      appBar: AppBar(title: Text('settings'.tr),backgroundColor: colors.isDark?Colors.black:Colors.white,),
      body: ListView(
        padding: EdgeInsets.all(16.w),
        children: [
          // ============================================================
          // OPERATION MODE
          // ============================================================
          Text(
            "Operation Mode",
            style: AppTypography.cardTitle.copyWith(
              fontWeight: FontWeight.bold,
              color: colors.text,
            ),
          ),

          SizedBox(height: 12.h),

          _buildOperationModeCard(context),

          // ============================================================
          // LOCAL HUB
          // ============================================================
          Obx(() {
            if (!controller.isLocalMode) {
              return const SizedBox.shrink();
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: 24.h),

                Text(
                  "Local Hub",
                  style: AppTypography.cardTitle.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colors.text,
                  ),
                ),

                SizedBox(height: 12.h),

                _buildLocalHubCard(context),
              ],
            );
          }),

          // ============================================================
          // SYNC PREFERENCES
          // ============================================================
          SizedBox(height: 24.h),

          Text(
            "Sync Preferences",
            style: AppTypography.cardTitle.copyWith(
              fontWeight: FontWeight.bold,
              color: colors.text,
            ),
          ),

          SizedBox(height: 12.h),

          _buildSyncPreferencesCard(context),

          // ============================================================
          // ABOUT APP
          // ============================================================
          SizedBox(height: 24.h),

          Text(
            "About App",
            style: AppTypography.cardTitle.copyWith(
              fontWeight: FontWeight.bold,
              color: colors.text,
            ),
          ),

          SizedBox(height: 12.h),

          _buildInfoTile(context, Icons.info_outline, "Version", "1.3.1"),

          _buildInfoTile(
            context,
            Icons.business_outlined,
            "Branch",
            AppState.branchDisName,
          ),

          // ============================================================
          // ACCOUNT
          // ============================================================
          SizedBox(height: 24.h),

          Text(
            "Account",
            style: AppTypography.cardTitle.copyWith(
              fontWeight: FontWeight.bold,
              color: colors.text,
            ),
          ),

          SizedBox(height: 12.h),

          _buildAccountCard(context),
        ],
      ),
    );
  }

  // ========================================================================
  // OPERATION MODE CARD
  // ========================================================================

  Widget _buildOperationModeCard(BuildContext context) {
    final colors = AppColors.of(context);

    return Container(
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
      child: Obx(
        () => Column(
          children: [
            // ONLINE MODE
            ListTile(
              onTap: () {
                if (!controller.isOnlineMode) {
                  controller.changeOperationMode(false);
                }
              },
              leading: CircleAvatar(
                backgroundColor: !controller.isLocalMode
                    ? AppTheme.primaryGreen.withOpacity(0.1)
                    : colors.textField,
                child: Icon(
                  Icons.cloud_outlined,
                  color: !controller.isLocalMode
                      ? AppTheme.primaryGreen
                      : colors.subtext,
                ),
              ),
              title: Text(
                "Online Mode",
                style: TextStyle(
                  color: colors.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                "Use the cloud server directly.",
                style: TextStyle(color: colors.subtext),
              ),
              trailing: Radio<bool>(
                value: false,
                groupValue: controller.isLocalMode,
                onChanged: (_) {
                  controller.changeOperationMode(false);
                },
                activeColor: AppTheme.primaryGreen,
              ),
            ),

            Divider(height: 1, color: colors.border),

            // LOCAL HUB MODE
            ListTile(
              onTap: () {
                if (!controller.isLocalMode) {
                  controller.changeOperationMode(true);
                }
              },
              leading: CircleAvatar(
                backgroundColor: controller.isLocalMode
                    ? AppTheme.primaryGreen.withOpacity(0.1)
                    : colors.textField,
                child: Icon(
                  Icons.wifi,
                  color: controller.isLocalMode
                      ? AppTheme.primaryGreen
                      : colors.subtext,
                ),
              ),
              title: Text(
                "Local Hub Mode",
                style: TextStyle(
                  color: colors.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                "Use the restaurant's local network hub.",
                style: TextStyle(color: colors.subtext),
              ),
              trailing: Radio<bool>(
                value: true,
                groupValue: controller.isLocalMode,
                onChanged: (_) {
                  controller.changeOperationMode(true);
                },
                activeColor: AppTheme.primaryGreen,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ========================================================================
  // LOCAL HUB CARD
  // ========================================================================

  Widget _buildLocalHubCard(BuildContext context) {
    final colors = AppColors.of(context);

    return Container(
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
      child: Obx(
        () => Column(
          children: [
            // ----------------------------------------------------------
            // DEVICE ROLE
            // ----------------------------------------------------------
            ListTile(
              leading: CircleAvatar(
                backgroundColor: AppTheme.primaryGreen.withOpacity(0.1),
                child: const Icon(
                  Icons.devices_outlined,
                  color: AppTheme.primaryGreen,
                ),
              ),
              title: Text("Device Role", style: TextStyle(color: colors.text)),
              subtitle: Text(
                controller.deviceRoleLabel,
                style: TextStyle(color: colors.subtext),
              ),
              trailing: Icon(Icons.chevron_right, color: colors.subtext),
              onTap: () => _showDeviceRoleDialog(context),
            ),

            Divider(height: 1, color: colors.border),

            // ----------------------------------------------------------
            // DEVICE ID
            // ----------------------------------------------------------
            ListTile(
              leading: Icon(Icons.fingerprint, color: colors.subtext),
              title: Text("Device ID", style: TextStyle(color: colors.text)),
              subtitle: Text(
                controller.deviceId.value.isEmpty
                    ? "Not configured"
                    : controller.deviceId.value,
                style: TextStyle(color: colors.subtext),
              ),
            ),

            // ----------------------------------------------------------
            // HOST INFORMATION
            // ----------------------------------------------------------
            if (controller.isHost) ...[
              Divider(
                height: 1,
                color: colors.border,
              ),

              ListTile(
                leading: Icon(
                  Icons.router_outlined,
                  color: colors.subtext,
                ),
                title: Text(
                  "Hub Address",
                  style: TextStyle(
                    color: colors.text,
                  ),
                ),
                subtitle: Text(
                  controller.hubUrl,
                  style: TextStyle(
                    color: colors.subtext,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                trailing: IconButton(
                  icon: Icon(
                    Icons.copy_outlined,
                    color: colors.subtext,
                  ),
                  onPressed: () {
                    Clipboard.setData(
                      ClipboardData(
                        text: controller.hubUrl,
                      ),
                    );

                    Get.snackbar(
                      "Copied",
                      "Hub address copied to clipboard.",
                      snackPosition: SnackPosition.BOTTOM,
                    );
                  },
                ),
              ),

              Divider(
                height: 1,
                color: colors.border,
              ),

              ListTile(
                leading: Icon(
                  Icons.settings_ethernet,
                  color: colors.subtext,
                ),
                title: Text(
                  "Server Port",
                  style: TextStyle(
                    color: colors.text,
                  ),
                ),
                subtitle: Text(
                  controller.hostPort.value.toString(),
                  style: TextStyle(
                    color: colors.subtext,
                  ),
                ),
              ),

              Divider(
                height: 1,
                color: colors.border,
              ),

              _buildHubStatusTile(
                context,
                isHost: true,
              ),
            ],

            // ----------------------------------------------------------
            // CLIENT INFORMATION
            // ----------------------------------------------------------
            if (controller.isClient) ...[
              Divider(height: 1, color: colors.border),

              ListTile(
                leading: Icon(Icons.router_outlined, color: colors.subtext),
                title: Text(
                  "Main Cashier",
                  style: TextStyle(color: colors.text),
                ),
                subtitle: Text(
                  controller.hostAddress,
                  style: TextStyle(color: colors.subtext),
                ),
                trailing: Icon(Icons.edit_outlined, color: colors.subtext),
                onTap: () => _showHostIpDialog(context),
              ),

              Divider(height: 1, color: colors.border),

              ListTile(
                leading: Icon(Icons.settings_ethernet, color: colors.subtext),
                title: Text("Hub Port", style: TextStyle(color: colors.text)),
                subtitle: Text(
                  controller.hostPort.value.toString(),
                  style: TextStyle(color: colors.subtext),
                ),
                trailing: Icon(Icons.edit_outlined, color: colors.subtext),
                onTap: () => _showHostPortDialog(context),
              ),

              Divider(height: 1, color: colors.border),

              _buildHubStatusTile(context, isHost: false),
            ],
          ],
        ),
      ),
    );
  }

  // ========================================================================
  // HUB STATUS
  // ========================================================================

  Widget _buildHubStatusTile(BuildContext context, {required bool isHost}) {
    final colors = AppColors.of(context);

    return ListTile(
      leading: Obx(() {
        final bool connected = isHost
            ? controller.isHubServerRunning.value
            : controller.isHubConnected.value;

        return CircleAvatar(
          backgroundColor: connected
              ? AppTheme.primaryGreen.withOpacity(0.1)
              : Colors.orange.withOpacity(0.1),
          child: Icon(
            connected ? Icons.check_circle_outline : Icons.wifi_find,
            color: connected ? AppTheme.primaryGreen : Colors.orange,
          ),
        );
      }),
      title: Text("Hub Status", style: TextStyle(color: colors.text)),
      subtitle: Obx(
        () => Text(
          isHost
              ? controller.isHubServerRunning.value
                    ? "Server Running"
                    : "Server Stopped"
              : controller.isHubConnected.value
              ? "Connected"
              : "Not connected",
          style: TextStyle(color: colors.subtext),
        ),
      ),
      trailing: isHost
          ? null
          : Obx(
              () => TextButton(
                onPressed: controller.isTestingHubConnection.value
                    ? null
                    : controller.testHubConnection,
                child: controller.isTestingHubConnection.value
                    ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                  ),
                )
                    : const Text('Test'),
              )
            ),
    );
  }

  // ========================================================================
  // SYNC PREFERENCES CARD
  // ========================================================================

  Widget _buildSyncPreferencesCard(BuildContext context) {
    final colors = AppColors.of(context);

    return Container(
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
          Obx(
            () => ListTile(
              leading: CircleAvatar(
                backgroundColor: controller.isBackgroundSync.value
                    ? AppTheme.primaryGreen.withOpacity(0.1)
                    : colors.textField,
                child: Icon(
                  Icons.sync,
                  color: controller.isBackgroundSync.value
                      ? AppTheme.primaryGreen
                      : colors.subtext,
                ),
              ),
              title: Text(
                "Background Sync",
                style: TextStyle(color: colors.text),
              ),
              subtitle: Text(
                controller.isBackgroundSync.value
                    ? "Orders sync automatically as soon as possible."
                    : "Orders will only sync when you press the sync button.",
                style: TextStyle(color: colors.subtext),
              ),
              trailing: Switch(
                value: controller.isBackgroundSync.value,
                onChanged: controller.toggleBackgroundSync,
                activeColor: AppTheme.primaryGreen,
              ),
            ),
          ),

          Divider(height: 1, color: colors.border),

          Obx(
            () => ListTile(
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
                    : const Icon(
                        Icons.cloud_download_outlined,
                        color: AppTheme.primaryGreen,
                      ),
              ),
              title: Text(
                "Manual Data Sync",
                style: TextStyle(color: colors.text),
              ),
              subtitle: Text(
                controller.isMasterSyncing.value
                    ? "Updating restaurant data... "
                          "${(controller.masterSyncProgress.value * 100).toInt()}%"
                    : "Download latest categories, products, and tables.",
                style: TextStyle(color: colors.subtext),
              ),
              trailing: Icon(Icons.chevron_right, color: colors.subtext),
            ),
          ),
        ],
      ),
    );
  }

  // ========================================================================
  // DEVICE ROLE DIALOG
  // ========================================================================

  void _showDeviceRoleDialog(BuildContext context) {
    final colors = AppColors.of(context);

    Get.dialog(
      AlertDialog(
        title: const Text("Select Device Role"),
        content: Obx(
          () => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _roleOption(
                context,
                DeviceRole.host,
                "Main Cashier / Host",
                "Runs the local server and controls the restaurant network.",
                Icons.dns_outlined,
              ),
              _roleOption(
                context,
                DeviceRole.client,
                "Client",
                "Connects to the Main Cashier over the local network.",
                Icons.tablet_android_outlined,
              ),
              _roleOption(
                context,
                DeviceRole.solo,
                "Standalone",
                "Works independently using the normal online flow.",
                Icons.phone_android_outlined,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _roleOption(
    BuildContext context,
    DeviceRole role,
    String title,
    String subtitle,
    IconData icon,
  ) {
    final colors = AppColors.of(context);

    final selected = controller.deviceRole.value == role;

    return InkWell(
      borderRadius: BorderRadius.circular(10.r),
      onTap: () async {
        await controller.changeDeviceRole(role);
        Get.back();
      },
      child: Container(
        margin: EdgeInsets.only(bottom: 8.h),
        padding: EdgeInsets.all(10.w),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primaryGreen.withOpacity(0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10.r),
          border: Border.all(
            color: selected ? AppTheme.primaryGreen : colors.border,
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: selected
                  ? AppTheme.primaryGreen.withOpacity(0.1)
                  : colors.textField,
              child: Icon(
                icon,
                color: selected ? AppTheme.primaryGreen : colors.subtext,
              ),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: colors.text,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 3.h),
                  Text(
                    subtitle,
                    style: TextStyle(color: colors.subtext, fontSize: 12.sp),
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle, color: AppTheme.primaryGreen),
          ],
        ),
      ),
    );
  }

  // ========================================================================
  // HOST IP DIALOG
  // ========================================================================

  void _showHostIpDialog(BuildContext context) {
    final colors = AppColors.of(context);

    final textController = TextEditingController(
      text: controller.hostIp.value ?? '',
    );

    Get.dialog(
      AlertDialog(
        title: const Text("Main Cashier IP"),
        content: TextField(
          controller: textController,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            hintText: "192.168.68.136",
            labelText: "Host IP Address",
            filled: true,
            fillColor: colors.textField,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10.r),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              await controller.setHostIp(textController.text);

              Get.back();
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  // ========================================================================
  // HOST PORT DIALOG
  // ========================================================================

  void _showHostPortDialog(BuildContext context) {
    final colors = AppColors.of(context);

    final textController = TextEditingController(
      text: controller.hostPort.value.toString(),
    );

    Get.dialog(
      AlertDialog(
        title: const Text("Hub Port"),
        content: TextField(
          controller: textController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: "8080",
            labelText: "Port",
            filled: true,
            fillColor: colors.textField,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10.r),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              final port = int.tryParse(textController.text.trim());

              if (port == null) {
                Get.snackbar(
                  "Invalid Port",
                  "Please enter a valid port.",
                  backgroundColor: Colors.red,
                  colorText: Colors.white,
                  snackPosition: SnackPosition.BOTTOM,
                );
                return;
              }

              await controller.setHostPort(port);

              Get.back();
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  // ========================================================================
  // ABOUT INFO TILE
  // ========================================================================

  Widget _buildInfoTile(
    BuildContext context,
    IconData icon,
    String title,
    String value,
  ) {
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

  // ========================================================================
  // ACCOUNT CARD
  // ========================================================================

  Widget _buildAccountCard(BuildContext context) {
    final colors = AppColors.of(context);

    return Container(
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
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: Color(0xFFFEE2E2),
          child: Icon(Icons.logout, color: Colors.red),
        ),
        title: const Text("Logout", style: TextStyle(color: Colors.red)),
        subtitle: Text(
          "Clear local data and sign out.",
          style: TextStyle(color: colors.subtext),
        ),
        onTap: () => _showLogoutDialog(context),
      ),
    );
  }

  // ========================================================================
  // LOGOUT
  // ========================================================================

  void _showLogoutDialog(BuildContext context) {
    Get.dialog(
      CupertinoAlertDialog(
        title: const Text("Logout"),
        content: const Text(
          "Are you sure you want to logout? "
          "All unsynced orders will be lost.",
        ),
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
}
