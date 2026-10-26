import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart' hide ScreenType;
import '../../../../../helper/screen_type.dart';
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
      appBar: ScreenType.isMobile()
          ? AppBar(
              title: Text('settings'.tr),
              backgroundColor: colors.isDark ? Colors.black : Colors.white,
            )
          : null,
      body: ListView(
        padding: EdgeInsets.all(8.w),
        children: [
          Text(
            'operation_mode'.tr,
            style: AppTypography.cardTitle.copyWith(
              fontWeight: FontWeight.bold,
              color: colors.text,
            ),
          ),
          SizedBox(height: 12.h),
          _buildOperationModeCard(context),
          Obx(() {
            if (!controller.isLocalMode) {
              return const SizedBox.shrink();
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: 24.h),
                Text(
                  'local_hub'.tr,
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
          Obx(() {
            if (!controller.isLocalMode) {
              return const SizedBox.shrink();
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: 24.h),
                Text(
                  'order_visibility'.tr,
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
          Obx(() {
            if (!controller.isLocalMode) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: 24.h),
                Text(
                  'token_reset'.tr,
                  style: AppTypography.cardTitle.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colors.text,
                  ),
                ),
                SizedBox(height: 12.h),
                _buildOpeningTimeCard(context),
              ],
            );
          }),
          Obx(() {
            if (controller.isLocalMode && controller.isClient ||
                controller.isOnlineMode) {
              return const SizedBox.shrink();
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: 24.h),
                Text(
                  'sync_preferences'.tr,
                  style: AppTypography.cardTitle.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colors.text,
                  ),
                ),
                SizedBox(height: 12.h),
                _buildSyncPreferencesCard(context),
              ],
            );
          }),
          SizedBox(height: 24.h),
          Text(
            'about_app'.tr,
            style: AppTypography.cardTitle.copyWith(
              fontWeight: FontWeight.bold,
              color: colors.text,
            ),
          ),
          SizedBox(height: 12.h),
          _buildInfoTile(context, Icons.info_outline, 'version'.tr, "1.1.8"),
          _buildInfoTile(
            context,
            Icons.business_outlined,
            'branch'.tr,
            AppState.branchDisName.toUpperCase(),
          ),
          SizedBox(height: 24.h),
          Text(
            'account'.tr,
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
                  color: !controller.isLocalMode
                      ? AppTheme.primaryGreen
                      : colors.subtext,
                ),
              ),
              title: Text(
                'online_mode'.tr,
                style: TextStyle(
                  color: colors.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                'online_mode_desc'.tr,
                style: TextStyle(color: colors.subtext),
              ),
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
                  color: controller.isLocalMode
                      ? AppTheme.primaryGreen
                      : colors.subtext,
                ),
              ),
              title: Text(
                'local_hub_mode'.tr,
                style: TextStyle(
                  color: colors.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                'local_hub_mode_desc'.tr,
                style: TextStyle(color: colors.subtext),
              ),
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

  Widget _buildOpeningTimeCard(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Obx(() {
        final t = controller.openingTime.value;
        return ListTile(
          onTap: () => controller.pickOpeningTime(context),
          leading: CircleAvatar(
            backgroundColor: AppTheme.primaryGreen.withOpacity(0.1),
            child: const Icon(Icons.access_time, color: AppTheme.primaryGreen),
          ),
          title: Text(
            'opening_time'.tr,
            style: TextStyle(color: colors.text, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            t == null
                ? 'opening_time_not_set'.tr
                : 'opening_time_desc'.trParams({'time': t.format(context)}),
            style: TextStyle(color: colors.subtext),
          ),
          trailing: t == null
              ? Icon(Icons.edit_outlined, color: colors.subtext)
              : IconButton(
                  icon: Icon(Icons.close, color: colors.subtext),
                  onPressed: controller.clearOpeningTime,
                ),
        );
      }),
    );
  }

  Widget _buildConnectedDevicesTile(BuildContext context) {
    final colors = AppColors.of(context);
    return Obx(() {
      final devices = controller.connectedDevices;
      return ExpansionTile(
        leading: Icon(Icons.devices_other, color: colors.subtext),
        title: Text('connected_devices'.tr, style: TextStyle(color: colors.text)),
        subtitle: Text(
          devices.isEmpty
              ? 'no_clients_connected'.tr
              : "${devices.length} client(s) connected",
        style: TextStyle(color: colors.subtext),
        ),
        children: devices.isEmpty
            ? [
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 16.w,
                    vertical: 8.h,
                  ),
                  child: Text(
                    'waiting_for_clients'.tr,
                    style: TextStyle(color: colors.subtext),
                  ),
                ),
              ]
            : devices.map((d) {
                return ListTile(
                  dense: true,
                  leading: Icon(
                    Icons.smartphone,
                    color: colors.subtext,
                    size: 20.sp,
                  ),
                  title: Text(
                    d['deviceName']?.toString() ?? 'unnamed_device'.tr,
                    style: TextStyle(color: colors.text),
                  ),
                  subtitle: (d['userName']?.toString().isNotEmpty ?? false)
                      ? Text(
                          d['userName'].toString(),
                          style: TextStyle(color: colors.subtext),
                        )
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
            ListTile(
              onTap: controller.isChangingRole.value
                  ? null
                  : () => controller.becomeHost(),
              leading: CircleAvatar(
                backgroundColor: controller.isHost
                    ? AppTheme.primaryGreen.withOpacity(0.1)
                    : colors.textField,
                child: Icon(
                  Icons.dns_outlined,
                  color: controller.isHost
                      ? AppTheme.primaryGreen
                      : colors.subtext,
                ),
              ),
              title: Text(
                'host_this_device'.tr,
                style: TextStyle(
                  color: colors.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                'host_desc'.tr,
                style: TextStyle(color: colors.subtext),
              ),
              trailing: controller.isChangingRole.value
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Radio<bool>(
                      value: true,
                      groupValue: controller.isHost,
                      onChanged: (_) => controller.becomeHost(),
                      activeColor: AppTheme.primaryGreen,
                    ),
            ),
            Divider(height: 1, color: colors.border),
            ListTile(
              onTap: controller.isChangingRole.value
                  ? null
                  : () => controller.becomeClient(),
              leading: CircleAvatar(
                backgroundColor: controller.isClient
                    ? AppTheme.primaryGreen.withOpacity(0.1)
                    : colors.textField,
                child: Icon(
                  Icons.smartphone,
                  color: controller.isClient
                      ? AppTheme.primaryGreen
                      : colors.subtext,
                ),
              ),
              title: Text(
                'connect_as_client'.tr,
                style: TextStyle(
                  color: colors.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                'client_desc'.tr,
                style: TextStyle(color: colors.subtext),
              ),
              trailing: controller.isChangingRole.value
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Radio<bool>(
                      value: true,
                      groupValue: controller.isClient,
                      onChanged: (_) => controller.becomeClient(),
                      activeColor: AppTheme.primaryGreen,
                    ),
            ),
            Divider(height: 1, color: colors.border),

            if (controller.isHost) ...[
              Divider(height: 1, color: colors.border),
              ListTile(
                leading: Icon(Icons.router_outlined, color: colors.subtext),
                title: Text(
                  'hub_address'.tr,
                  style: TextStyle(color: colors.text),
                ),
                subtitle: Text(
                  controller.hubUrl,
                  style: TextStyle(
                    color: colors.subtext,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                trailing: IconButton(
                  icon: Icon(Icons.copy_outlined, color: colors.subtext),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: controller.hubUrl));
                    Get.snackbar(
                      'copied'.tr,
                      'hub_address_copied'.tr,
                      snackPosition: SnackPosition.BOTTOM,
                    );
                  },
                ),
              ),
              Divider(height: 1, color: colors.border),
              ListTile(
                leading: Icon(Icons.settings_ethernet, color: colors.subtext),
                title: Text(
                  'server_port'.tr,
                  style: TextStyle(color: colors.text),
                ),
                subtitle: Text(
                  controller.hostPort.value.toString(),
                  style: TextStyle(color: colors.subtext),
                ),
              ),
              Divider(height: 1, color: colors.border),
              _buildHubStatusTile(context, isHost: true),
              Divider(height: 1, color: colors.border),
              _buildConnectedDevicesTile(context),
            ],

            if (controller.isClient) ...[
              Divider(height: 1, color: colors.border),
              ListTile(
                leading: Icon(Icons.router_outlined, color: colors.subtext),
                title: Text(
                  'main_cashier_ip'.tr,
                  style: TextStyle(color: colors.text),
                ),
                subtitle: Text(
                  controller.hostIp.value ?? 'opening_time_not_set'.tr,
                  style: TextStyle(color: colors.subtext),
                ),
                trailing: Icon(Icons.edit_outlined, color: colors.subtext),
                onTap: () => _showHostIpDialog(context),
              ),
              Divider(height: 1, color: colors.border),
              ListTile(
                leading: Icon(Icons.settings_ethernet, color: colors.subtext),
                title: Text('hub_port'.tr, style: TextStyle(color: colors.text)),
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
            connected ? Icons.check_circle_outline : Icons.wifi_off,
            color: connected ? AppTheme.primaryGreen : Colors.orange,
          ),
        );
      }),
      title: Text('hub_status'.tr, style: TextStyle(color: colors.text)),
      subtitle: Obx(
        () => Text(
          isHost
              ? (controller.isHubServerRunning.value
                    ? 'server_running'.tr
                    : 'server_stopped'.tr)
              : (controller.isHubConnected.value
                    ? 'connected'.tr
                    : 'not_connected'.tr),
          style: TextStyle(color: colors.subtext),
        ),
      ),
      trailing: isHost
          ? IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => controller.startLocalServer(),
            )
          : Obx(
              () => TextButton(
                onPressed: controller.isTestingHubConnection.value
                    ? null
                    : () => controller.testHubConnection(),
                child: controller.isTestingHubConnection.value
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text('confirm'.tr),
              ),
            ),
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
                  color: !controller.showMyOrdersOnly.value
                      ? AppTheme.primaryGreen
                      : colors.subtext,
                ),
              ),
              title: Text(
                'all_orders'.tr,
                style: TextStyle(
                  color: colors.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                'all_orders_desc'.tr,
                style: TextStyle(color: colors.subtext),
              ),
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
                  color: controller.showMyOrdersOnly.value
                      ? AppTheme.primaryGreen
                      : colors.subtext,
                ),
              ),
              title: Text(
                'my_orders_only'.tr,
                style: TextStyle(
                  color: colors.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                'my_orders_only_desc'.tr,
                style: TextStyle(color: colors.subtext),
              ),
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
          Obx(() {
            final count = controller.pendingCount.value;
            final isSyncing = controller.isSyncingOrders.value;
            return ListTile(
              onTap: (isSyncing || count == 0)
                  ? null
                  : () => controller.syncOrdersToLive(),
              leading: CircleAvatar(
                backgroundColor: Colors.blue.withOpacity(0.1),
                child: isSyncing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(
                        Icons.cloud_upload_outlined,
                        color: Colors.blue,
                      ),
              ),
              title: Text(
                'sync_pending_orders'.tr,
                style: TextStyle(color: colors.text),
              ),
              subtitle: Text(
                isSyncing
                    ? 'syncing_orders'.trParams({'count': count.toString()})
                    : 'pending_orders_msg'.trParams({'count': count.toString()}),
                style: TextStyle(color: colors.subtext),
              ),
            );
          }),
          Divider(height: 1, color: colors.border),
          Obx(
            () => ListTile(
              onTap: controller.isMasterSyncing.value
                  ? null
                  : controller.performManualMasterSync,
              leading: CircleAvatar(
                backgroundColor: AppTheme.primaryGreen.withOpacity(0.1),
                child: controller.isMasterSyncing.value
                    ? CircularProgressIndicator(
                        strokeWidth: 2,
                        value: controller.masterSyncProgress.value > 0
                            ? controller.masterSyncProgress.value
                            : null,
                      )
                    : const Icon(
                        Icons.cloud_download_outlined,
                        color: AppTheme.primaryGreen,
                      ),
              ),
              title: Text(
                'manual_data_sync'.tr,
                style: TextStyle(color: colors.text),
              ),
              subtitle: Text(
                controller.isMasterSyncing.value
                    ? 'syncing'.tr
                    : 'download_data'.tr,
                style: TextStyle(color: colors.subtext),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showHostIpDialog(BuildContext context) {
    final colors = AppColors.of(context);
    final textController = TextEditingController(
      text: controller.hostIp.value ?? '',
    );
    Get.dialog(
      AlertDialog(
        title: Text('main_cashier_ip'.tr),
        content: TextField(
          controller: textController,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            hintText: "192.168.x.x",
            labelText: 'host_ip'.tr,
            filled: true,
            fillColor: colors.textField,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: Text('cancel'.tr)),
          ElevatedButton(
            onPressed: () {
              controller.setHostIp(textController.text);
              Get.back();
            },
            child: Text('save'.tr),
          ),
        ],
      ),
    );
  }

  void _showHostPortDialog(BuildContext context) {
    final colors = AppColors.of(context);
    final textController = TextEditingController(
      text: controller.hostPort.value.toString(),
    );
    Get.dialog(
      AlertDialog(
        title: Text('hub_port'.tr),
        content: TextField(
          controller: textController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: "8080",
            labelText: 'port'.tr,
            filled: true,
            fillColor: colors.textField,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: Text('cancel'.tr)),
          ElevatedButton(
            onPressed: () {
              final port = int.tryParse(textController.text.trim());
              if (port != null) {
                controller.setHostPort(port);
                Get.back();
              }
            },
            child: Text('save'.tr),
          ),
        ],
      ),
    );
  }

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

  Widget _buildAccountCard(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: Color(0xFFFEE2E2),
          child: Icon(Icons.logout, color: Colors.red),
        ),
        title: Text('logout'.tr, style: const TextStyle(color: Colors.red)),
        onTap: () => _showLogoutDialog(context),
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    Get.dialog(
      CupertinoAlertDialog(
        title: Text('logout'.tr),
        content: Text('logout_warning'.tr),
        actions: [
          CupertinoDialogAction(
            child: Text('cancel'.tr),
            onPressed: () => Get.back(),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => AppState.logout(),
            child: Text('logout'.tr),
          ),
        ],
      ),
    );
  }
}
