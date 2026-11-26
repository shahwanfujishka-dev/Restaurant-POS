import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../helper/network_helper.dart';
import '../../helper/snackbar_helper.dart';
import '../data/Device_Roles/device_roles.dart';
import '../data/models/order_model.dart';
import '../data/models/order_type.dart';
import '../data/services/order_submission.dart';
import '../data/utils/AppState.dart';
import '../modules/cart/controller/cart_controller.dart';
import '../modules/home/controller/dashboard_controller.dart';
import '../modules/home/controller/order_controller.dart';
import '../modules/home/controller/printer_controller.dart';
import '../modules/home/controller/table_controller.dart';

Future<void> submitCartOrder({
  required CartController controller,
  required String destination,
  bool requireCaptain = false,
  int? cashLedgerId,
  bool isDraft = false,
  int? payType,
  double? cashAmt,
  double? cardAmt,
  bool isCompliment = false,
  bool shouldPrintReceipt = false,
  bool validateClient = false,
}) async {
  if (controller.cartItems.isEmpty || controller.isProcessing.value) return;

  if (AppState.orderType == OrderType.dineIn && !controller.hasSelectedTable) {
    if (requireCaptain) {
      Get.find<DashboardController>().showError(
        'table_required'.tr,
        'select_table_msg'.tr,
      );
    } else {
      showSafeSnackbar('table_required'.tr, 'select_table_msg'.tr);
    }
    return;
  }

  final hasValidItems = controller.cartItems.any(
    (item) => !item.isDeleted.value && item.quantity.value > 0,
  );

  if (!hasValidItems) {
    showSafeSnackbar('empty_order'.tr, 'empty_order_msg'.tr);
    return;
  }

  if (requireCaptain && controller.selectedCaptainId.value == null) {
    showSafeSnackbar('captain_required'.tr, 'captain_required_msg'.tr);
    return;
  }

  final submission = OrderSubmission(controller);
  if (!submission.tryBegin()) return;
  try {
    final timing = Stopwatch()..start();
    if (!await submission.checkReady(validateClient: validateClient)) return;
    final readinessMs = timing.elapsedMilliseconds;
    final printedBeforeSave =
        DeviceConfig.requireOrderPrinting && DeviceConfig.isLocal;
    final responseData = await submission.save(
      isDraft: isDraft,
      printBill: shouldPrintReceipt,
      payType: payType,
      cashAmt: cashAmt,
      cardAmt: cardAmt,
      cashLedgerId: controller.isEditing ? null : cashLedgerId,
      isCompliment: isCompliment,
    );

    debugPrint(
      '[Checkout timing] readiness=${readinessMs}ms '
      'save with required printing=${timing.elapsedMilliseconds - readinessMs}ms',
    );
    if (responseData?['print_blocked'] == true) return;
    if (responseData == null) {
      if (DeviceConfig.isOnline &&
          !await NetworkHelper.hasInternetConnection()) {
        showSafeSnackbar('no_internet'.tr, 'check_network_msg'.tr);
      } else {
        showSafeSnackbar('error'.tr, 'unexpected_error'.tr);
      }
      return;
    }

    final message = responseData['message'];
    final status = message is Map ? message['status'] : responseData['status'];
    if (status == 0) {
      final details = message is Map ? message['msg'] : message;
      final errorMessage = details?.toString() ?? 'Order processing failed';
      final normalized = errorMessage.toLowerCase();
      if (normalized.contains('seat') || normalized.contains('available')) {
        try {
          if (Get.isRegistered<TablesController>()) {
            await Get.find<TablesController>().fetchTables(silent: true);
          }
        } catch (_) {}
        showSafeSnackbar("Table Seat Notice", errorMessage);
      } else {
        showSafeSnackbar('error'.tr, errorMessage);
      }
      return;
    }

    if (responseData['no_change'] == true) {
      controller.stopEditing();
      showSafeSnackbar('no_change'.tr, 'no_change_msg'.tr);
      return;
    }

    final ordersController = Get.find<OrdersController>();
    final bool wasEditing = controller.isEditing;
    final bool wasDraftVal = controller.wasDraft.value;
    final List<OrderItem> originalItemsCopy = List<OrderItem>.from(
      controller.originalItems,
    );

    final String snapshotTableName = controller.selectedTableName.value;
    final int snapshotChairCount = controller.selectedChairCount.value;
    OrderModel? liveOrder;
    try {
      liveOrder = ordersController.parseOrderResponse(
        responseData,
        fallbackTableName: snapshotTableName,
        fallbackChairCount: snapshotChairCount,
      );
      if (DeviceConfig.isLocal) ordersController.updateExistingOrder(liveOrder);
    } catch (e) {
      debugPrint("Pre-clear parse failed: $e");
    }
    if (wasEditing) {
      showSafeSnackbar(
        isDraft ? 'draft_updated'.tr : 'order_updated'.tr,
        isDraft ? 'draft_updated_msg'.tr : 'order_updated_msg'.tr,
      );
      controller.stopEditing();
    } else {
      showSafeSnackbar(
        isDraft ? 'draft_saved'.tr : 'order_placed'.tr,
        isDraft ? 'draft_saved_msg'.tr : 'order_placed_msg'.tr,
      );
      controller.clearCart();
      controller.clearTable();
    }

    Get.offAllNamed(destination);

    unawaited(
      _runOrderFollowUp(
        liveOrder: liveOrder,
        responseData: responseData,
        isDraft: isDraft,
        wasEditing: wasEditing,
        wasDraft: wasDraftVal,
        originalItems: originalItemsCopy,
        ordersController: ordersController,
        snapshotTableName: snapshotTableName,
        snapshotChairCount: snapshotChairCount,
        shouldPrintReceipt: shouldPrintReceipt,
        printedBeforeSave: printedBeforeSave,
      ),
    );
  } catch (e) {
    debugPrint("Order processing error: $e");
    showSafeSnackbar('error'.tr, 'unexpected_error'.tr);
  } finally {
    submission.finish();
  }
}

Future<void> _runOrderFollowUp({
  required Map<String, dynamic> responseData,
  required bool isDraft,
  required bool wasEditing,
  required bool wasDraft,
  required List<OrderItem> originalItems,
  required OrdersController ordersController,
  String snapshotTableName = "",
  int snapshotChairCount = 0,
  bool shouldPrintReceipt = false,
  OrderModel? liveOrder,
  required bool printedBeforeSave,
}) async {
  if (!isDraft && !printedBeforeSave) {
    try {
      final printerController = Get.find<PrinterController>();
      final OrderModel order =
          liveOrder ??
          ordersController.parseOrderResponse(
            responseData,
            fallbackTableName: snapshotTableName,
            fallbackChairCount: snapshotChairCount,
          );
      final oldItemsForKOT = (wasEditing && !wasDraft) ? originalItems : null;

      try {
        String? missingAssignment;
        final kotSuccess = await printerController.printKOT(
          order,
          oldItems: oldItemsForKOT,
          onMissingAssignment: (message) => missingAssignment = message,
        );
        if (!kotSuccess) {
          final ctx = Get.overlayContext;
          if (ctx != null && ctx.mounted) {
            await showDialog(
              context: ctx,
              builder: (d) => AlertDialog(
                icon: const Icon(
                  Icons.print_disabled,
                  color: Colors.red,
                  size: 36,
                ),
                title: const Text('KOT Print Failed'),
                content: Text(
                  missingAssignment == null
                      ? 'The order was saved, but the kitchen ticket did not print. '
                            'Check the printer connection and paper before retrying.'
                      : 'The order was saved.\n\n$missingAssignment',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(d),
                    child: const Text('Close'),
                  ),
                  FilledButton(
                    onPressed: () {
                      Navigator.pop(d);
                      printerController.printKOT(
                        order,
                        oldItems: oldItemsForKOT,
                      );
                    },
                    child: const Text('Retry KOT Print'),
                  ),
                ],
              ),
            );
          }
        }
      } catch (e) {
        debugPrint("KOT print failed: $e");
        showSafeSnackbar('KOT not printed', '$e');
      }

      if (shouldPrintReceipt) {
        await Future.delayed(
          const Duration(milliseconds: 600),
        ); // BT printer switch gap
        try {
          final receiptSuccess = await printerController.printReceipt(
            order,
            0,
            0,
            isBill: true,
          );
          if (!receiptSuccess) {
            showSafeSnackbar(
              'Bill Print Failed',
              'Bill printing failed. Check printer connection or paper and retry.',
            );
            final ctx = Get.context;
            if (ctx != null && ctx.mounted) {
              await showDialog(
                context: ctx,
                builder: (d) => AlertDialog(
                  icon: const Icon(
                    Icons.print_disabled,
                    color: Colors.red,
                    size: 36,
                  ),
                  title: const Text('Bill Print Failed'),
                  content: const Text(
                    'Bill failed to print because the printer is unavailable, disconnected, or out of paper.\n\nPlease check printer connection or paper and retry.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(d),
                      child: const Text('Close'),
                    ),
                    FilledButton(
                      onPressed: () {
                        Navigator.pop(d);
                        printerController.printReceipt(
                          order,
                          0,
                          0,
                          isBill: true,
                        );
                      },
                      child: const Text('Retry Bill Print'),
                    ),
                  ],
                ),
              );
            }
          }
        } catch (e) {
          debugPrint("Receipt print failed: $e");
          showSafeSnackbar('Receipt not printed', '$e');
        }
      }
    } catch (e) {
      debugPrint("Background Printing failed: $e");
      showSafeSnackbar('Print failed', '$e');
    }
  }

  try {
    if (DeviceConfig.operationMode != OperationMode.local) {
      await ordersController.fetchOrdersSafely();
    }
  } catch (e) {
    debugPrint("Background Fetch Orders failed: $e");
  }
}
