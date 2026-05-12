import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:get/get_instance/src/extension_instance.dart';
import 'package:get/get_navigation/src/extension_navigation.dart';
import 'package:get/get_state_manager/src/rx_flutter/rx_obx_widget.dart';
import 'package:get/get_state_manager/src/simple/get_view.dart';

import '../../../../../helper/screen_type.dart';
import '../../../../theme/app_theme.dart';
import '../../../../theme/app_typography.dart';
import '../../controller/dashboard_controller.dart';
import '../../controller/printer_controller.dart';

class PrintersPage extends GetView<PrinterController> {
  const PrintersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final dashboardController = Get.find<DashboardController>();
    final colors = AppColors.of(context);

    return Scaffold(
      backgroundColor: colors.bg,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddAssignmentDialog(context, dashboardController),
        backgroundColor: AppTheme.primaryGreen,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: Obx(() {
        if (!controller.isBluetoothPermissionGranted.value) {
          return _buildPermissionErrorState(context);
        }
        return ScreenType.isMobile()
            ? _buildMobileLayout(context, dashboardController)
            : _buildTabletLayout(context, dashboardController);
      }),
    );
  }

  Widget _buildPermissionErrorState(BuildContext context) {
    final colors = AppColors.of(context);
    return Center(
      child: Padding(
        padding: EdgeInsets.all(24.w),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bluetooth_disabled, size: 80.w, color: Colors.orange),
            SizedBox(height: 24.h),
            Text(
              "Bluetooth Permissions Required",
              style: AppTypography.cardTitle.copyWith(color: colors.text),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 12.h),
            Text(
              "To scan for printers on Android 12+, we need permission to find nearby devices.",
              style: AppTypography.bodyText.copyWith(color: colors.text),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 32.h),
            ElevatedButton.icon(
              onPressed: () => controller.requestBluetoothPermissions(),
              icon: const Icon(Icons.security, color: Colors.white),
              label: const Text("Grant Permissions", style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryGreen,
                padding: EdgeInsets.symmetric(horizontal: 32.w, vertical: 16.h),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- TABLET LAYOUT ---
  Widget _buildTabletLayout(BuildContext context, DashboardController dashboardController) {
    final colors = AppColors.of(context);
    return Padding(
      padding: EdgeInsets.all(16.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                  "Printer Configuration",
                  style: AppTypography.cardTitle.copyWith(color: colors.text)
              ),
              Row(
                children: [
                  _buildHeaderActionBtn(
                    context,
                    label: "Add Manual IP",
                    icon: Icons.add,
                    onPressed: () => _showManualIpDialog(context),
                    isPrimary: false,
                  ),
                  SizedBox(width: 12.w),
                  _buildHeaderActionBtn(
                    context,
                    label: "Scan for Devices",
                    icon: Icons.search,
                    onPressed: () {
                      controller.scanBluetoothPrinters();
                      controller.scanWifiPrinters();
                    },
                    isPrimary: true,
                  ),
                ],
              ),
            ],
          ),
          SizedBox(height: 24.h),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    children: [
                      _buildNetworkInfoCard(context),
                      SizedBox(height: 16.h),
                      _buildActivePrintersSummary(context),
                    ],
                  ),
                ),
                SizedBox(width: 24.w),

                Expanded(
                  flex: 7,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSectionHeader(context, "Token Printer Assignments", Icons.print),
                      Expanded(child: _buildTokenAssignmentsList(context)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- MOBILE LAYOUT ---
  Widget _buildMobileLayout(BuildContext context, DashboardController dashboardController) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(16.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildNetworkInfoCard(context),
          SizedBox(height: 24.h),
          _buildActivePrintersSummary(context),
          SizedBox(height: 24.h),
          _buildSectionHeader(context, "Token Printer Assignments", Icons.print),
          _buildTokenAssignmentsList(context),
          SizedBox(height: 80.h), // Space for FAB
        ],
      ),
    );
  }

  Widget _buildNetworkInfoCard(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      padding: EdgeInsets.all(10.w),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(12.r),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(colors.isDark ? 0.2 : 0.05), blurRadius: 10)],
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(6.w),
            decoration: BoxDecoration(
              color: AppTheme.primaryGreen.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.wifi, color: AppTheme.primaryGreen, size: AppTypography.sizeText),
          ),
          SizedBox(width: 6.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Current Network",
                    style: AppTypography.cardSubtitle.copyWith(color: colors.subtext)),
                Obx(() => Text(
                  controller.currentWifiName.value.replaceAll('"', ''),
                  style: AppTypography.cardTitle.copyWith(color: colors.text),
                )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivePrintersSummary(BuildContext context) {
    final colors = AppColors.of(context);
    return Obx(() {
      return Container(
        width: double.infinity,
        padding: EdgeInsets.all(10.w),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(10.r),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(colors.isDark ? 0.2 : 0.05), blurRadius: 10)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Available Printers",
                style: AppTypography.cardTitle.copyWith(color: colors.text)),
            SizedBox(height: 6.h),
            _buildPrinterStatusRow(context, "Bluetooth", controller.bluetoothPrinters.length, Colors.blue),
            SizedBox(height: 4.h),
            _buildPrinterStatusRow(context, "WiFi", controller.wifiPrinters.length, Colors.orange),
            if (controller.scanningBluetooth.value || controller.scanningWifi.value)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: LinearProgressIndicator(color: AppTheme.primaryGreen),
              ),
          ],
        ),
      );
    });
  }

  Widget _buildPrinterStatusRow(BuildContext context, String label, int count, Color color) {
    final colors = AppColors.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: colors.subtext, fontSize: AppTypography.sizeText)),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 4.h),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20.r),
          ),
          child: Text("$count Found",
              style: TextStyle(
                  color: color, fontSize: AppTypography.sizeText, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _buildTokenAssignmentsList(BuildContext context) {
    final colors = AppColors.of(context);
    return Obx(() {
      if (controller.tokenPrinterAssignments.isEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.print_disabled, size: AppTypography.foodIcon, color: colors.subtext.withOpacity(0.3)),
              SizedBox(height: 16.h),
              Text("No assignments yet", style: AppTypography.bodyText.copyWith(color: colors.text)),
              Text("Tap '+' to link a printer to a Token ID", style: AppTypography.bodyText.copyWith(color: colors.subtext)),
            ],
          ),
        );
      }

      return ListView.separated(
        shrinkWrap: true,
        physics: const BouncingScrollPhysics(),
        itemCount: controller.tokenPrinterAssignments.length,
        separatorBuilder: (_, __) => SizedBox(height: 12.h),
        itemBuilder: (context, index) {
          final assignment = controller.tokenPrinterAssignments[index];
          return Container(
            padding: EdgeInsets.all(16.w),
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(12.r),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(colors.isDark ? 0.2 : 0.03), blurRadius: 5)],
              border: Border.all(color: colors.border),
            ),
            child: Row(
              children: [
                Container(
                  width: AppTypography.iconXL,
                  height: AppTypography.iconXL,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryGreen.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      assignment.tokenPrinterId.toString(),
                      style: TextStyle(color: AppTheme.primaryGreen, fontWeight: FontWeight.bold, fontSize: AppTypography.sizeText),
                    ),
                  ),
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Token Printer ID", style: TextStyle(color: colors.subtext, fontSize: AppTypography.sizeText)),
                      Text("Printer: ${assignment.printerName.value}", style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTypography.sizeText, color: colors.text)),
                      Text("Address: ${assignment.printerAddress.value}", style: TextStyle(color: colors.subtext, fontSize: AppTypography.sizeText)),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                  onPressed: () => controller.removeTokenPrinterAssignment(assignment.tokenPrinterId),
                ),
              ],
            ),
          );
        },
      );
    });
  }

  void _showAddAssignmentDialog(BuildContext context, DashboardController dashboardController) {
    int? selectedTokenId;
    PrinterModel? selectedPrinter;
    final colors = AppColors.of(context);

    Get.dialog(
      Obx(() {
        // ✅ Calculate uniqueTokenIds INSIDE Obx to react to changes
        final uniqueTokenIds = dashboardController.allCategoriesForPrinters
            .map((c) => c.tokenPrinterId)
            .where((id) => id != 0)
            .toSet()
            .toList();
        uniqueTokenIds.sort();

        // If categories haven't loaded yet, show a loader
        if (dashboardController.isFetchingAllCategories.value && uniqueTokenIds.isEmpty) {
          return const Center(child: CircularProgressIndicator(color: AppTheme.primaryGreen));
        }

        // If no token IDs available, show a message
        if (uniqueTokenIds.isEmpty) {
          return AlertDialog(
            backgroundColor: colors.card,
            title: Text("Assign Printer to Token ID", style: TextStyle(color: colors.text)),
            content: Text("No Token Printer IDs available. Please check your categories configuration.", style: TextStyle(color: colors.text)),
            actions: [
              TextButton(
                  onPressed: () => Get.back(),
                  child: const Text("Close")
              ),
            ],
          );
        }

        return AlertDialog(
          backgroundColor: colors.card,
          title: Text("Assign Printer to Token ID", style: TextStyle(color: colors.text)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                dropdownColor: colors.card,
                decoration: InputDecoration(
                  labelText: "Choose Token Printer ID",
                  labelStyle: TextStyle(color: colors.subtext),
                ),
                style: TextStyle(color: colors.text),
                value: selectedTokenId,
                items: uniqueTokenIds.map((id) => DropdownMenuItem(
                  value: id,
                  child: Text("Token ID: $id", style: TextStyle(color: colors.text)),
                )).toList(),
                onChanged: (val) => selectedTokenId = val,
              ),
              SizedBox(height: 8.h),
              Obx(() {
                final allPrinters = [...controller.bluetoothPrinters, ...controller.wifiPrinters];
                return DropdownButtonFormField<PrinterModel>(
                  dropdownColor: colors.card,
                  decoration: InputDecoration(
                    labelText: "Choose Printer",
                    labelStyle: TextStyle(color: colors.subtext),
                  ),
                  style: TextStyle(color: colors.text),
                  value: selectedPrinter,
                  items: allPrinters.map((p) => DropdownMenuItem(
                    value: p,
                    child: Text("${p.name} (${p.type})", style: TextStyle(color: colors.text)),
                  )).toList(),
                  onChanged: (val) => selectedPrinter = val,
                );
              }),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Get.back(), child: const Text("Cancel")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGreen),
              onPressed: () {
                if (selectedTokenId != null && selectedPrinter != null) {
                  controller.updateTokenPrinter(selectedTokenId!, selectedPrinter!);
                  Get.back();
                } else {
                  Get.snackbar(
                      "Error",
                      "Please select both Token ID and Printer",
                      backgroundColor: Colors.red,
                      colorText: Colors.white
                  );
                }
              },
              child: const Text("Save Assignment", style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      }),
    );
  }

  void _showManualIpDialog(BuildContext context) {
    final ipController = TextEditingController();
    final colors = AppColors.of(context);
    Get.dialog(
      AlertDialog(
        backgroundColor: colors.card,
        title: Text("Add Manual WiFi Printer", style: TextStyle(color: colors.text)),
        content: TextField(
          controller: ipController,
          style: TextStyle(color: colors.text),
          decoration: InputDecoration(
            hintText: "Enter IP Address (e.g. 192.168.1.100)",
            hintStyle: TextStyle(color: colors.subtext),
          ),
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGreen),
            onPressed: () {
              if (ipController.text.isNotEmpty) {
                controller.addManualWifiPrinter(ipController.text);
                Get.back();
              }
            },
            child: const Text("Add", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title, IconData icon) {
    final colors = AppColors.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: 12.h),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.primaryGreen, size: AppTypography.iconXL),
          SizedBox(width: 8.w),
          Text(title, style: AppTypography.cardTitle.copyWith(color: colors.text)),
        ],
      ),
    );
  }

  Widget _buildHeaderActionBtn(
    BuildContext context, {
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
    required bool isPrimary,
  }) {
    final colors = AppColors.of(context);
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18.w, color: isPrimary ? Colors.white : AppTheme.primaryGreen),
      label: Text(label, style: TextStyle(color: isPrimary ? Colors.white : AppTheme.primaryGreen)),
      style: ElevatedButton.styleFrom(
        backgroundColor: isPrimary ? AppTheme.primaryGreen : colors.card,
        side: const BorderSide(color: AppTheme.primaryGreen),
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
      ),
    );
  }
}