import 'dart:developer';

import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import 'package:restaurant_pos/app/modules/home/controller/printer_controller.dart';

import '../../../data/models/order_model.dart';
import '../../../data/services/api_services.dart';
import '../../../data/services/database_helper.dart';
import '../../../data/utils/AppState.dart';
import 'order_controller.dart';

class CashierController extends GetxController {
  final ApiService _apiService = Get.find<ApiService>();
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  final OrderModel order = Get.arguments;

  /// ─────────────────────────────────────────────
  /// 🔹 Payment Types
  /// ─────────────────────────────────────────────
  final paymentMethod = 'Cash'.obs;

  final paymentMethods = [
    'Cash',
    'Card',
    'Credit',
    'Multiple',
    'Split',
  ];

  /// ─────────────────────────────────────────────
  /// 🔹 Cash Handling
  /// ─────────────────────────────────────────────
  final receivedAmount = 0.0.obs;
  final TextEditingController amountController = TextEditingController();

  /// ─────────────────────────────────────────────
  /// 🔹 Split Handling
  /// ─────────────────────────────────────────────
  final TextEditingController splitCountController = TextEditingController();

  final splitCount = 1.obs;
  final splitAmounts = <double>[].obs;

  /// ─────────────────────────────────────────────
  /// 🔹 States
  /// ─────────────────────────────────────────────
  final isProcessing = false.obs;

  double get totalToPay => order.totalAmount;

  double get changeAmount =>
      (receivedAmount.value - totalToPay).clamp(0, double.infinity);

  /// ─────────────────────────────────────────────
  /// 🔹 Init
  /// ─────────────────────────────────────────────
  @override
  void onInit() {
    super.onInit();

    /// Default values
    amountController.text = totalToPay.toStringAsFixed(2);
    receivedAmount.value = totalToPay;

    splitCountController.text = "1";
    _generateSplitAmounts(1);
  }

  /// ─────────────────────────────────────────────
  /// 🔹 Payment Method Change
  /// ─────────────────────────────────────────────
  void setPaymentMethod(String method) {
    paymentMethod.value = method;

    /// Reset when switching
    if (method == 'Cash') {
      amountController.text = totalToPay.toStringAsFixed(2);
      receivedAmount.value = totalToPay;
    }

    if (method == 'Split') {
      splitCountController.text = "1";
      _generateSplitAmounts(1);
    }
  }

  /// ─────────────────────────────────────────────
  /// 🔹 Cash Input
  /// ─────────────────────────────────────────────
  void updateReceivedAmount(String value) {
    receivedAmount.value = double.tryParse(value) ?? 0.0;
  }

  /// ─────────────────────────────────────────────
  /// 🔹 Split Logic
  /// ─────────────────────────────────────────────
  void updateSplitCount(String value) {
    final count = int.tryParse(value) ?? 1;
    splitCount.value = count <= 0 ? 1 : count;

    _generateSplitAmounts(splitCount.value);
  }

  void _generateSplitAmounts(int count) {
    final total = totalToPay;

    double perPerson = total / count;

    splitAmounts.value = List.generate(count, (index) {
      /// Fix rounding issue for last person
      if (index == count - 1) {
        return total -
            (perPerson * (count - 1)); // ensures exact total match
      }
      return perPerson;
    });
  }

  /// ─────────────────────────────────────────────
  /// 🔹 Settlement
  /// ─────────────────────────────────────────────
  Future<void> settleOrder() async {
    /// ✅ Validation
    if (paymentMethod.value == 'Cash' &&
        receivedAmount.value < totalToPay) {
      Get.snackbar("Invalid Amount", "Received amount is less than total.");
      return;
    }

    if (paymentMethod.value == 'Split' && splitCount.value <= 0) {
      Get.snackbar("Invalid Split", "Split count must be at least 1.");
      return;
    }

    try {
      isProcessing.value = true;

      final now = DateTime.now();
      final dateStr = DateFormat('yyyy-MM-dd').format(now);

      final body = {
        "usr_id": int.tryParse(AppState.userId) ?? 0,
        "sales_odr_id": int.tryParse(order.id),
        "sales_odr_inv_no": int.tryParse(order.invNo),
        "payment_method": paymentMethod.value.toLowerCase(),
        "amount_paid": totalToPay,
        "received_amount": receivedAmount.value,
        "change_given": changeAmount,
        "settle_date": dateStr,

        /// 🔥 Optional: send split info
        "split_count":
        paymentMethod.value == 'Split' ? splitCount.value : null,
      };

      log("Settling Order: ${order.invNo} with body: $body");

      final response = await _apiService.post(
        "mobileapp/pos/settle_sales_order",
        data: body,
      );

      if (response.statusCode == 200) {
        await _dbHelper.updateOrderStatusByServerId(
          order.id,
          'paid',
          isSynced: 1,
        );

        Get.find<OrdersController>().fetchOrders();
        Get.back();

        Get.snackbar(
            "Success", "Order #${order.invNo} settled successfully.");

        _printReceipt();
      } else {
        Get.snackbar("Error", "Failed to settle order on server.");
      }
    } catch (e) {
      log("Settle Error: $e. Saving locally...");
      await _savePaymentLocally();
    } finally {
      isProcessing.value = false;
    }
  }

  /// ─────────────────────────────────────────────
  /// 🔹 Offline Save
  /// ─────────────────────────────────────────────
  Future<void> _savePaymentLocally() async {
    try {
      final now = DateTime.now();

      await _dbHelper.insertPayment({
        "order_uuid": order.id,
        "amount": totalToPay,
        "method": paymentMethod.value.toLowerCase(),
        "is_synced": 0,
        "created_at": now.toIso8601String(),
      });

      if (order.isUnsynced) {
        await _dbHelper.updateOrderStatusByUuid(
          order.id,
          'paid',
          isSynced: 0,
        );
      } else {
        await _dbHelper.updateOrderStatusByServerId(
          order.id,
          'paid',
          isSynced: 0,
        );
      }

      Get.find<OrdersController>().fetchOrders();
      Get.back();

      Get.snackbar(
        "Offline",
        "Payment saved locally. It will sync automatically.",
      );

      _printReceipt();
    } catch (e) {
      log("Local Settle Error: $e");
    }
  }

  /// ─────────────────────────────────────────────
  /// 🔹 Printing
  /// ─────────────────────────────────────────────
  void _printReceipt() {
    try {
      final printerController = Get.find<PrinterController>();
      printerController.printReceipt(
        order,
        receivedAmount.value,
        changeAmount,
      );
    } catch (e) {
      log("Receipt Print Error: $e");
    }
  }
}