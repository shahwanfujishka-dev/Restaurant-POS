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
      appBar: AppBar(
        title: Text('settings'.tr),
        backgroundColor: colors.isDark ? Colors.black : Colors.white,
      ),
      body: ListView(
        padding: EdgeInsets.all(8.w),
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
          // ORDER VISIBILITY
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
                  "Order Visibility",
                  style: AppTypography.cardTitle.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colors.text,
                  ),
                ),
                SizedBox(height: 12.h),
                _buildOrderVisibilityCard(context),
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
            ListTile(
              onTap: () => controller.changeOperationMode(false),
              leading: CircleAvatar(
                backgroundColor: !controller.isLocalMode
                    ? AppTheme.primaryGreen.withOpacity(0.1)
                    : colors.textField,
                child: Icon(
                  Icons.cloud_outlined,
                  color: !controller.isLocalMode ? AppTheme.primaryGreen : colors.subtext,
                ),
              ),
              title: Text("Online Mode", style: TextStyle(color: colors.text, fontWeight: FontWeight.w600)),
              subtitle: Text("Use the cloud server directly.", style: TextStyle(color: colors.subtext)),
              trailing: Radio<bool>(
                value: false,
                groupValue: controller.isLocalMode,
                onChanged: (_) => controller.changeOperationMode(false),
                activeColor: AppTheme.primaryGreen,
              ),
            ),
            Divider(height: 1, color: colors.border),
            ListTile(
              onTap: () => controller.changeOperationMode(true),
              leading: CircleAvatar(
                backgroundColor: controller.isLocalMode
                    ? AppTheme.primaryGreen.withOpacity(0.1)
                    : colors.textField,
                child: Icon(
                  Icons.wifi,
                  color: controller.isLocalMode ? AppTheme.primaryGreen : colors.subtext,
                ),
              ),
              title: Text("Local Hub Mode", style: TextStyle(color: colors.text, fontWeight: FontWeight.w600)),
              subtitle: Text("Use the restaurant's local network hub.", style: TextStyle(color: colors.subtext)),
              trailing: Radio<bool>(
                value: true,
                groupValue: controller.isLocalMode,
                onChanged: (_) => controller.changeOperationMode(true),
                activeColor: AppTheme.primaryGreen,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectedDevicesTile(BuildContext context) {
    final colors = AppColors.of(context);
    return Obx(() {
      final devices = controller.connectedDevices;
      return ExpansionTile(
        leading: Icon(Icons.devices_other, color: colors.subtext),
        title: Text("Connected Devices", style: TextStyle(color: colors.text)),
        subtitle: Text(
          devices.isEmpty ? "No clients connected" : "${devices.length} client(s) connected",
          style: TextStyle(color: colors.subtext),
        ),
        children: devices.isEmpty
            ? [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
            child: Text("Waiting for client devices to connect...", style: TextStyle(color: colors.subtext)),
          ),
        ]
            : devices.map((d) {
          return ListTile(
            dense: true,
            leading: Icon(Icons.smartphone, color: colors.subtext, size: 20.sp),
            title: Text(d['deviceName']?.toString() ?? 'Unnamed Device', style: TextStyle(color: colors.text)),
            subtitle: (d['userName']?.toString().isNotEmpty ?? false)
                ? Text(d['userName'].toString(), style: TextStyle(color: colors.subtext))
                : null,
          );
        }).toList(),
      );
    });
  }

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
            // ROLE PICKER — new
            // ----------------------------------------------------------
            ListTile(
              onTap: controller.isChangingRole.value ? null : () => controller.becomeHost(),
              leading: CircleAvatar(
                backgroundColor: controller.isHost
                    ? AppTheme.primaryGreen.withOpacity(0.1)
                    : colors.textField,
                child: Icon(
                  Icons.dns_outlined,
                  color: controller.isHost ? AppTheme.primaryGreen : colors.subtext,
                ),
              ),
              title: Text("Host This Device", style: TextStyle(color: colors.text, fontWeight: FontWeight.w600)),
              subtitle: Text("This device becomes the Main Cashier for the network.", style: TextStyle(color: colors.subtext)),
              trailing: controller.isChangingRole.value
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Radio<bool>(
                value: true,
                groupValue: controller.isHost,
                onChanged: (_) => controller.becomeHost(),
                activeColor: AppTheme.primaryGreen,
              ),
            ),
            Divider(height: 1, color: colors.border),
            ListTile(
              onTap: controller.isChangingRole.value ? null : () => controller.becomeClient(),
              leading: CircleAvatar(
                backgroundColor: controller.isClient
                    ? AppTheme.primaryGreen.withOpacity(0.1)
                    : colors.textField,
                child: Icon(
                  Icons.smartphone,
                  color: controller.isClient ? AppTheme.primaryGreen : colors.subtext,
                ),
              ),
              title: Text("Connect as Client", style: TextStyle(color: colors.text, fontWeight: FontWeight.w600)),
              subtitle: Text("Connect to another device acting as Main Cashier.", style: TextStyle(color: colors.subtext)),
              trailing: controller.isChangingRole.value
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Radio<bool>(
                value: true,
                groupValue: controller.isClient,
                onChanged: (_) => controller.becomeClient(),
                activeColor: AppTheme.primaryGreen,
              ),
            ),
            Divider(height: 1, color: colors.border),

            // ----------------------------------------------------------
            // DEVICE ID — unchanged
            // ----------------------------------------------------------
            ListTile(
              leading: Icon(Icons.fingerprint, color: colors.subtext),
              title: Text("Device ID", style: TextStyle(color: colors.text)),
              subtitle: Text(
                controller.deviceId.value.isEmpty ? "Not configured" : controller.deviceId.value,
                style: TextStyle(color: colors.subtext),
              ),
            ),

            // ----------------------------------------------------------
            // HOST INFORMATION
            // ----------------------------------------------------------
            if (controller.isHost) ...[
              Divider(height: 1, color: colors.border),
              ListTile(
                leading: Icon(Icons.router_outlined, color: colors.subtext),
                title: Text("Hub Address", style: TextStyle(color: colors.text)),
                subtitle: Text(controller.hubUrl, style: TextStyle(color: colors.subtext, fontWeight: FontWeight.w500)),
                trailing: IconButton(
                  icon: Icon(Icons.copy_outlined, color: colors.subtext),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: controller.hubUrl));
                    Get.snackbar("Copied", "Hub address copied to clipboard.", snackPosition: SnackPosition.BOTTOM);
                  },
                ),
              ),
              Divider(height: 1, color: colors.border),
              ListTile(
                leading: Icon(Icons.settings_ethernet, color: colors.subtext),
                title: Text("Server Port", style: TextStyle(color: colors.text)),
                subtitle: Text(controller.hostPort.value.toString(), style: TextStyle(color: colors.subtext)),
              ),
              Divider(height: 1, color: colors.border),
              _buildHubStatusTile(context, isHost: true),
              Divider(height: 1, color: colors.border),
              _buildConnectedDevicesTile(context),
            ],

            // ----------------------------------------------------------
            // CLIENT INFORMATION
            // ----------------------------------------------------------
            if (controller.isClient) ...[
              Divider(height: 1, color: colors.border),
              ListTile(
                leading: Icon(Icons.router_outlined, color: colors.subtext),
                title: Text("Main Cashier IP", style: TextStyle(color: colors.text)),
                subtitle: Text(controller.hostIp.value ?? "Not set", style: TextStyle(color: colors.subtext)),
                trailing: Icon(Icons.edit_outlined, color: colors.subtext),
                onTap: () => _showHostIpDialog(context),
              ),
              Divider(height: 1, color: colors.border),
              ListTile(
                leading: Icon(Icons.settings_ethernet, color: colors.subtext),
                title: Text("Hub Port", style: TextStyle(color: colors.text)),
                subtitle: Text(controller.hostPort.value.toString(), style: TextStyle(color: colors.subtext)),
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

  Widget _buildHubStatusTile(BuildContext context, {required bool isHost}) {
    final colors = AppColors.of(context);
    return ListTile(
      leading: Obx(() {
        final bool connected = isHost ? controller.isHubServerRunning.value : controller.isHubConnected.value;
        return CircleAvatar(
          backgroundColor: connected ? AppTheme.primaryGreen.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
          child: Icon(
            connected ? Icons.check_circle_outline : Icons.wifi_off,
            color: connected ? AppTheme.primaryGreen : Colors.orange,
          ),
        );
      }),
      title: Text("Hub Status", style: TextStyle(color: colors.text)),
      subtitle: Obx(() => Text(
        isHost
            ? (controller.isHubServerRunning.value ? "Server Running" : "Server Stopped")
            : (controller.isHubConnected.value ? "Connected" : "Not connected"),
        style: TextStyle(color: colors.subtext),
      )),
      trailing: isHost
          ? IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => controller.startLocalServer(),
            )
          : Obx(() => TextButton(
                onPressed: controller.isTestingHubConnection.value ? null : () => controller.testHubConnection(),
                child: controller.isTestingHubConnection.value
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Connect'),
              )),
    );
  }

  Widget _buildOrderVisibilityCard(BuildContext context) {
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
            ListTile(
              onTap: () => controller.toggleOrderVisibility(false),
              leading: CircleAvatar(
                backgroundColor: !controller.showMyOrdersOnly.value
                    ? AppTheme.primaryGreen.withOpacity(0.1)
                    : colors.textField,
                child: Icon(
                  Icons.groups_outlined,
                  color: !controller.showMyOrdersOnly.value ? AppTheme.primaryGreen : colors.subtext,
                ),
              ),
              title: Text("All Orders", style: TextStyle(color: colors.text, fontWeight: FontWeight.w600)),
              subtitle: Text("Show orders placed by every device.", style: TextStyle(color: colors.subtext)),
              trailing: Radio<bool>(
                value: false,
                groupValue: controller.showMyOrdersOnly.value,
                onChanged: (_) => controller.toggleOrderVisibility(false),
                activeColor: AppTheme.primaryGreen,
              ),
            ),
            Divider(height: 1, color: colors.border),
            ListTile(
              onTap: () => controller.toggleOrderVisibility(true),
              leading: CircleAvatar(
                backgroundColor: controller.showMyOrdersOnly.value
                    ? AppTheme.primaryGreen.withOpacity(0.1)
                    : colors.textField,
                child: Icon(
                  Icons.person_outline,
                  color: controller.showMyOrdersOnly.value ? AppTheme.primaryGreen : colors.subtext,
                ),
              ),
              title: Text("My Orders Only", style: TextStyle(color: colors.text, fontWeight: FontWeight.w600)),
              subtitle: Text("Show only orders placed on this device.", style: TextStyle(color: colors.subtext)),
              trailing: Radio<bool>(
                value: true,
                groupValue: controller.showMyOrdersOnly.value,
                onChanged: (_) => controller.toggleOrderVisibility(true),
                activeColor: AppTheme.primaryGreen,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSyncPreferencesCard(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Column(
        children: [
          Obx(() => ListTile(
            leading: CircleAvatar(
              backgroundColor: controller.isBackgroundSync.value ? AppTheme.primaryGreen.withOpacity(0.1) : colors.textField,
              child: Icon(Icons.sync, color: controller.isBackgroundSync.value ? AppTheme.primaryGreen : colors.subtext),
            ),
            title: Text("Background Sync", style: TextStyle(color: colors.text)),
            subtitle: Text(
              controller.isBackgroundSync.value ? "Orders sync automatically." : "Orders sync manually.",
              style: TextStyle(color: colors.subtext),
            ),
            trailing: Switch(
              value: controller.isBackgroundSync.value,
              onChanged: controller.toggleBackgroundSync,
              activeColor: AppTheme.primaryGreen,
            ),
          )),
          Divider(height: 1, color: colors.border),
          Obx(() => ListTile(
            onTap: controller.isMasterSyncing.value ? null : controller.performManualMasterSync,
            leading: CircleAvatar(
              backgroundColor: AppTheme.primaryGreen.withOpacity(0.1),
              child: controller.isMasterSyncing.value
                  ? CircularProgressIndicator(strokeWidth: 2, value: controller.masterSyncProgress.value > 0 ? controller.masterSyncProgress.value : null)
                  : const Icon(Icons.cloud_download_outlined, color: AppTheme.primaryGreen),
            ),
            title: Text("Manual Data Sync", style: TextStyle(color: colors.text)),
            subtitle: Text(
              controller.isMasterSyncing.value ? "Syncing..." : "Download latest data.",
              style: TextStyle(color: colors.subtext),
            ),
          )),
        ],
      ),
    );
  }

  void _showHostIpDialog(BuildContext context) {
    final colors = AppColors.of(context);
    final textController = TextEditingController(text: controller.hostIp.value ?? '');
    Get.dialog(
      AlertDialog(
        title: const Text("Main Cashier IP"),
        content: TextField(
          controller: textController,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(hintText: "192.168.x.x", labelText: "Host IP", filled: true, fillColor: colors.textField),
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text("Cancel")),
          ElevatedButton(onPressed: () { controller.setHostIp(textController.text); Get.back(); }, child: const Text("Save")),
        ],
      ),
    );
  }

  void _showHostPortDialog(BuildContext context) {
    final colors = AppColors.of(context);
    final textController = TextEditingController(text: controller.hostPort.value.toString());
    Get.dialog(
      AlertDialog(
        title: const Text("Hub Port"),
        content: TextField(
          controller: textController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(hintText: "8080", labelText: "Port", filled: true, fillColor: colors.textField),
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text("Cancel")),
          ElevatedButton(onPressed: () {
            final port = int.tryParse(textController.text.trim());
            if (port != null) { controller.setHostPort(port); Get.back(); }
          }, child: const Text("Save")),
        ],
      ),
    );
  }

  Widget _buildInfoTile(BuildContext context, IconData icon, String title, String value) {
    final colors = AppColors.of(context);
    return Container(
      margin: EdgeInsets.only(bottom: 8.h),
      decoration: BoxDecoration(color: colors.card, borderRadius: BorderRadius.circular(12.r)),
      child: ListTile(
        leading: Icon(icon, color: colors.subtext),
        title: Text(title, style: TextStyle(color: colors.text)),
        trailing: Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: colors.subtext)),
      ),
    );
  }

  Widget _buildAccountCard(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      decoration: BoxDecoration(color: colors.card, borderRadius: BorderRadius.circular(12.r)),
      child: ListTile(
        leading: const CircleAvatar(backgroundColor: Color(0xFFFEE2E2), child: Icon(Icons.logout, color: Colors.red)),
        title: const Text("Logout", style: TextStyle(color: Colors.red)),
        onTap: () => _showLogoutDialog(context),
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    Get.dialog(
      CupertinoAlertDialog(
        title: const Text("Logout"),
        content: const Text("Are you sure? Unsynced orders may be lost."),
        actions: [
          CupertinoDialogAction(child: const Text("Cancel"), onPressed: () => Get.back()),
          CupertinoDialogAction(isDestructiveAction: true, onPressed: () => AppState.logout(), child: const Text("Logout")),
        ],
      ),
    );
  }
}
