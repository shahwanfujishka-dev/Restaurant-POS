import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart' hide ScreenType;
import '../../../../../helper/screen_type.dart';
import '../../../../../helper/snackbar_helper.dart';
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
            Icon(
              Icons.bluetooth_disabled,
              size: ScreenType.isMobile() ? 80.w : 40.w,
              color: Colors.orange,
            ),
            SizedBox(height: 24.h),
            Text(
              'permissions_required'.tr,
              style: AppTypography.cardTitle.copyWith(color: colors.text),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 12.h),
            Text(
              'bt_permission_desc'.tr,
              style: AppTypography.bodyText.copyWith(color: colors.text),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 32.h),
            ElevatedButton.icon(
              onPressed: () => controller.requestBluetoothPermissions(),
              icon: const Icon(Icons.security, color: Colors.white),
              label: Text(
                'grant_permissions'.tr,
                style: const TextStyle(color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryGreen,
                padding: EdgeInsets.symmetric(horizontal: 32.w, vertical: 16.h),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.r),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- TABLET LAYOUT ---
  Widget _buildTabletLayout(
    BuildContext context,
    DashboardController dashboardController,
  ) {
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
                'printer_configuration'.tr,
                style: AppTypography.cardTitle.copyWith(color: colors.text),
              ),
              Row(
                children: [
                  _buildHeaderActionBtn(
                    context,
                    label: 'add_manual_ip'.tr,
                    icon: Icons.add,
                    onPressed: () => _showManualIpDialog(context),
                    isPrimary: false,
                  ),
                  SizedBox(width: 6.w),
                  _buildHeaderActionBtn(
                    context,
                    label: 'scan_for_devices'.tr,
                    icon: Icons.search,
                    onPressed: () {
                      controller.scanBluetoothPrinters();
                      controller.scanWifiPrinters();
                      controller.scanWindowsPrinters();
                    },
                    isPrimary: true,
                  ),
                ],
              ),
            ],
          ),
          SizedBox(height: 12.h),
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
                      SizedBox(height: 16.h),
                      _buildReceiptPrinterCard(context),
                    ],
                  ),
                ),
                SizedBox(width: 12.w),

                Expanded(
                  flex: 6,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSectionHeader(
                        context,
                        'token_printer_assignments'.tr,
                        Icons.print,
                      ),
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
  Widget _buildMobileLayout(
    BuildContext context,
    DashboardController dashboardController,
  ) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(16.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildNetworkInfoCard(context),
          SizedBox(height: 24.h),
          _buildActivePrintersSummary(context),
          SizedBox(height: 16.h),
          _buildReceiptPrinterCard(context),
          SizedBox(height: 24.h),
          _buildSectionHeader(
            context,
            'token_printer_assignments'.tr,
            Icons.print,
          ),
          _buildTokenAssignmentsList(context),
          SizedBox(height: 80.h),
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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(colors.isDark ? 0.2 : 0.05),
            blurRadius: 10,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(6.w),
            decoration: BoxDecoration(
              color: AppTheme.primaryGreen.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.wifi,
              color: AppTheme.primaryGreen,
              size: AppTypography.sizeText,
            ),
          ),
          SizedBox(width: 6.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'current_network'.tr,
                  style: AppTypography.cardSubtitle.copyWith(
                    color: colors.subtext,
                  ),
                ),
                Obx(
                  () => Text(
                    controller.currentWifiName.value.replaceAll('"', ''),
                    style: AppTypography.cardTitle.copyWith(color: colors.text),
                  ),
                ),
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
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(colors.isDark ? 0.2 : 0.05),
              blurRadius: 10,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'available_printers'.tr,
                  style: AppTypography.cardTitle.copyWith(color: colors.text),
                ),
                IconButton(
                  icon: Icon(
                    Icons.refresh,
                    size: AppTypography.sizeText,
                    color: colors.subtext,
                  ),
                  onPressed: () => controller.refreshPrinters(),
                  tooltip: 'retry'.tr,
                ),
              ],
            ),
            SizedBox(height: 6.h),
            _buildPrinterStatusRow(
              context,
              'bluetooth'.tr,
              controller.bluetoothPrinters.length,
              Colors.blue,
            ),
            SizedBox(height: 4.h),
            _buildPrinterStatusRow(
              context,
              'wifi'.tr,
              controller.wifiPrinters.length,
              Colors.orange,
            ),
            SizedBox(height: 4.h),
            _buildPrinterStatusRow(
              context,
              'windows'.tr,
              controller.windowsPrinters.length,
              Colors.purple,
            ),
            if (controller.scanningBluetooth.value ||
                controller.scanningWifi.value)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: LinearProgressIndicator(color: AppTheme.primaryGreen),
              ),
          ],
        ),
      );
    });
  }

  Widget _buildPrinterStatusRow(
    BuildContext context,
    String label,
    int count,
    Color color,
  ) {
    final colors = AppColors.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: colors.subtext,
            fontSize: AppTypography.sizeText,
          ),
        ),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20.r),
          ),
          child: Text(
            'n_found'.trParams({'count': count.toString()}),
            style: TextStyle(
              color: color,
              fontSize: AppTypography.sizeText,
              fontWeight: FontWeight.bold,
            ),
          ),
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
              Icon(
                Icons.print_disabled,
                size: AppTypography.foodIcon,
                color: colors.subtext.withOpacity(0.3),
              ),
              SizedBox(height: 16.h),
              Text(
                'no_assignments_yet'.tr,
                style: AppTypography.bodyText.copyWith(color: colors.text),
              ),
              Text(
                'link_printer_msg'.tr,
                style: AppTypography.bodyText.copyWith(color: colors.subtext),
              ),
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
            padding: EdgeInsets.all(AppTypography.smallText),
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(12.r),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(colors.isDark ? 0.2 : 0.03),
                  blurRadius: 5,
                ),
              ],
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
                      style: TextStyle(
                        color: AppTheme.primaryGreen,
                        fontWeight: FontWeight.bold,
                        fontSize: AppTypography.sizeText,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'printer_label'.trParams({'name': assignment.printerName.value}),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: AppTypography.sizeText,
                          color: colors.text,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    color: Colors.redAccent,
                  ),
                  onPressed: () => controller.removeTokenPrinterAssignment(
                    assignment.tokenPrinterId,
                  ),
                ),
              ],
            ),
          );
        },
      );
    });
  }

  Widget _buildReceiptPrinterCard(BuildContext context) {
    final colors = AppColors.of(context);
    return Obx(() {
      final rp = controller.receiptPrinter.value;
      return Container(
        width: double.infinity,
        padding: EdgeInsets.all(AppTypography.smallText),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(10.r),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          children: [
            Icon(Icons.receipt_long, color: AppTheme.primaryGreen),
            SizedBox(width: 4.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'receipt_printer'.tr,
                    style: AppTypography.cardTitle.copyWith(color: colors.text),
                  ),
                  Text(
                    rp == null
                        ? 'receipt_printer_not_set'.tr
                        : rp.printerName.value,
                    style: TextStyle(color: colors.subtext),
                  ),
                ],
              ),
            ),
            if (rp != null)
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                onPressed: controller.clearReceiptPrinter,
              ),
            TextButton(
              onPressed: () => _showReceiptPrinterDialog(context),
              child: Text('choose'.tr),
            ),
          ],
        ),
      );
    });
  }

  void _showReceiptPrinterDialog(BuildContext context) {
    final colors = AppColors.of(context);
    Get.dialog(
      AlertDialog(
        backgroundColor: colors.card,
        title: Text(
          'select_receipt_printer'.tr,
          style: TextStyle(color: colors.text),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Obx(() {
            final printers = controller.allPrinters;
            return ListView(
              shrinkWrap: true,
              children: printers
                  .map(
                    (p) => ListTile(
                      leading: Icon(
                        p.type == "bluetooth"
                            ? Icons.bluetooth
                            : p.type == "windows"
                            ? Icons.usb
                            : Icons.wifi,
                      ),
                      title: Text(
                        "${p.name} (${p.type.toUpperCase()})",
                        style: TextStyle(color: colors.text),
                      ),
                      onTap: () async {
                        final r = await controller.setReceiptPrinter(p);
                        if (r.saved && Get.isDialogOpen == true) Get.back();
                        showSafeSnackbar(
                          r.saved ? 'saved'.tr : 'not_saved'.tr,
                          r.message,
                        );
                      },
                    ),
                  )
                  .toList(),
            );
          }),
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: Text('cancel'.tr)),
        ],
      ),
    );
  }

  void _showAddAssignmentDialog(
    BuildContext context,
    DashboardController dashboardController,
  ) {
    int? selectedTokenId;
    PrinterModel? selectedPrinter;
    final colors = AppColors.of(context);

    Get.dialog(
      Obx(() {
        final uniqueTokenIds = dashboardController.allCategoriesForPrinters
            .map((c) => c.tokenPrinterId)
            .where((id) => id != 0)
            .toSet()
            .toList();
        uniqueTokenIds.sort();

        if (dashboardController.isFetchingAllCategories.value &&
            uniqueTokenIds.isEmpty) {
          return const Center(
            child: CircularProgressIndicator(color: AppTheme.primaryGreen),
          );
        }

        if (uniqueTokenIds.isEmpty) {
          return AlertDialog(
            backgroundColor: colors.card,
            title: Text(
              'assign_printer_token'.tr,
              style: TextStyle(color: colors.text),
            ),
            content: Text(
              'no_token_ids_msg'.tr,
              style: TextStyle(color: colors.text),
            ),
            actions: [
              TextButton(
                onPressed: () => Get.back(),
                child: Text('close'.tr),
              ),
            ],
          );
        }

        return AlertDialog(
          backgroundColor: colors.card,
          scrollable: true,
          title: Text(
            'assign_printer_token'.tr,
            style: TextStyle(color: colors.text),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                dropdownColor: colors.card,
                decoration: InputDecoration(
                  labelText: 'choose_token_id'.tr,
                  labelStyle: TextStyle(color: colors.subtext),
                ),
                style: TextStyle(color: colors.text),
                value: selectedTokenId,
                items: uniqueTokenIds
                    .map(
                      (id) => DropdownMenuItem(
                        value: id,
                        child: Text(
                          'token_id_label'.trParams({'id': id.toString()}),
                          style: TextStyle(color: colors.text),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (val) => selectedTokenId = val,
              ),
              SizedBox(height: 8.h),

              Obx(() {
                final allPrinters = controller.allPrinters;
                String printerKey(PrinterModel printer) =>
                    '${printer.type}::${printer.address}';
                final selectedKey = selectedPrinter == null
                    ? null
                    : printerKey(selectedPrinter!);
                final validSelectedKey =
                    selectedKey != null &&
                        allPrinters.any((p) => printerKey(p) == selectedKey)
                    ? selectedKey
                    : null;

                return DropdownButtonFormField<String>(
                  isExpanded: true,
                  dropdownColor: colors.card,
                  value: validSelectedKey,
                  decoration: InputDecoration(
                    labelText: 'choose_printer'.tr,
                    labelStyle: TextStyle(color: colors.subtext),
                  ),
                  style: TextStyle(color: colors.text),
                  items: allPrinters.map((printer) {
                    return DropdownMenuItem<String>(
                      value: printerKey(printer),
                      child: Row(
                        children: [
                          Icon(
                            printer.type == "bluetooth"
                                ? Icons.bluetooth
                                : printer.type == "windows"
                                ? Icons.usb
                                : Icons.wifi,
                            size: 18,
                            color: printer.type == "bluetooth"
                                ? Colors.blue
                                : printer.type == "windows"
                                ? Colors.purple
                                : Colors.green,
                          ),
                          SizedBox(width: 8.w),
                          Expanded(
                            child: Text(
                              "${printer.name} (${printer.type.toUpperCase()})",
                              style: TextStyle(color: colors.text),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (key) {
                    if (key == null) {
                      selectedPrinter = null;
                      return;
                    }

                    final matches = allPrinters.where(
                      (printer) => printerKey(printer) == key,
                    );

                    if (matches.isEmpty) {
                      selectedPrinter = null;
                      return;
                    }

                    selectedPrinter = matches.first;
                    controller.selectPrinter(matches.first);
                  },
                );
              }),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Get.back(),
              child: Text('cancel'.tr),
            ),
            Obx(
              () => ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryGreen,
                ),
                onPressed: controller.isCheckingConnection.value
                    ? null
                    : () async {
                        if (selectedTokenId == null ||
                            selectedPrinter == null) {
                          Get.snackbar(
                            'error'.tr,
                            'select_both_msg'.tr,
                            backgroundColor: Colors.red,
                            colorText: Colors.white,
                          );
                          return;
                        }

                        final result = await controller.updateTokenPrinter(
                          selectedTokenId!,
                          selectedPrinter!,
                        );

                        if (!result.saved) {
                          showSafeSnackbar('not_saved'.tr, result.message);
                          return;
                        }

                        if (Get.isDialogOpen == true) Get.back();
                        showSafeSnackbar(
                          result.connected ? 'saved'.tr : 'connection_warning'.tr,
                          result.message,
                        );
                      },
                child: controller.isCheckingConnection.value
                    ? SizedBox(
                        width: 20.w,
                        height: 20.w,
                        child: const CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        'save_assignment'.tr,
                        style: const TextStyle(color: Colors.white),
                      ),
              ),
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
        title: Text(
          'add_manual_wifi_printer'.tr,
          style: TextStyle(color: colors.text),
        ),
        content: TextField(
          controller: ipController,
          style: TextStyle(color: colors.text),
          decoration: InputDecoration(
            hintText: 'enter_ip_hint'.tr,
            hintStyle: TextStyle(color: colors.subtext),
          ),
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: Text('cancel'.tr)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryGreen,
            ),
            onPressed: () {
              if (ipController.text.isNotEmpty) {
                controller.addManualWifiPrinter(ipController.text);
                Get.back();
              }
            },
            child: Text('add'.tr, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(
    BuildContext context,
    String title,
    IconData icon,
  ) {
    final colors = AppColors.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: 12.h),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.primaryGreen, size: AppTypography.iconXL),
          SizedBox(width: 8.w),
          Text(
            title,
            style: AppTypography.cardTitle.copyWith(color: colors.text),
          ),
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
      icon: Icon(
        icon,
        size: AppTypography.sizeText,
        color: isPrimary ? Colors.white : AppTheme.primaryGreen,
      ),
      label: Text(
        label,
        style: TextStyle(
          color: isPrimary ? Colors.white : AppTheme.primaryGreen,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: isPrimary ? AppTheme.primaryGreen : colors.card,
        side: const BorderSide(color: AppTheme.primaryGreen),
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
      ),
    );
  }
}
