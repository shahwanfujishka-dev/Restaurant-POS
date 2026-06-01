import 'dart:developer';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:restaurant_pos/app/modules/home/controller/printer_controller.dart';
import 'package:restaurant_pos/helper/snackbar_helper.dart';
import '../../../data/models/order_model.dart';
import '../../../data/services/api_services.dart';
import '../../../data/services/database_helper.dart';
import '../../../data/utils/AppState.dart';
import '../../cart/controller/cart_controller.dart';
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
    'Bank',
    'Credit',
    'Multiple',
  ];

  /// ─────────────────────────────────────────────
  /// 🔹 Customer Handling
  /// ─────────────────────────────────────────────
  final isCustomerSelectEnabled = false.obs;
  final customers = <Map<String, dynamic>>[].obs;
  final selectedCustomer = Rxn<Map<String, dynamic>>();

  final TextEditingController customerNameController = TextEditingController(text: "Cash Customer");
  final TextEditingController customerMobileController = TextEditingController();
  final TextEditingController customerAddressController = TextEditingController();
  final TextEditingController customerVatController = TextEditingController();

  /// ─────────────────────────────────────────────
  /// 🔹 Accounts Handling
  /// ─────────────────────────────────────────────
  final cashAccounts = <Map<String, dynamic>>[].obs;
  final bankAccounts = <Map<String, dynamic>>[].obs;
  final bankReceivedAmount = 0.0.obs;
  final TextEditingController bankAmountController = TextEditingController();

  final multiCashAmount = 0.0.obs;
  final multiBankAmount = 0.0.obs;
  final TextEditingController multiCashController = TextEditingController();
  final TextEditingController multiBankController = TextEditingController();
  final selectedCashLedgerId = 0.obs;
  final selectedBankLedgerId = 0.obs;

  final isLoadingAccounts = false.obs;

  /// ─────────────────────────────────────────────
  /// 🔹 Cash Handling
  /// ─────────────────────────────────────────────
  final receivedAmount = 0.0.obs;
  final TextEditingController amountController = TextEditingController();

  /// ─────────────────────────────────────────────
  /// 🔹 Discount Handling
  /// ─────────────────────────────────────────────
  final discountAmount = 0.0.obs;
  final TextEditingController discountController = TextEditingController();

  /// ─────────────────────────────────────────────
  /// 🔹 Round Off Handling
  /// ─────────────────────────────────────────────
  final roundOffAmount = 0.0.obs;
  final TextEditingController roundOffController = TextEditingController();

  /// ─────────────────────────────────────────────
  /// 🔹 Split Handling
  /// ─────────────────────────────────────────────
  final isSplit = false.obs;
  final TextEditingController splitCountController = TextEditingController();

  final splitCount = 1.obs;
  final splitAmounts = <double>[].obs;

  /// ─────────────────────────────────────────────
  /// 🔹 States
  /// ─────────────────────────────────────────────
  final isProcessing = false.obs;

  /// Helper to calculate the proportion of the total after discount is applied
  double get discountedRatio {
    if (order.totalAmount <= 0) return 1.0;
    return (order.totalAmount - discountAmount.value) / order.totalAmount;
  }

  /// Subtotal and Tax decrease according to the discounting amount
  double get subtotal => (order.totalAmount - order.totalTax) * discountedRatio;
  double get tax => order.totalTax * discountedRatio;

  double get totalToPay => (order.totalAmount - discountAmount.value + roundOffAmount.value).clamp(0, double.infinity);

  double get changeAmount =>
      (receivedAmount.value - totalToPay).clamp(0, double.infinity);

  /// ─────────────────────────────────────────────
  /// 🔹 Init
  /// ─────────────────────────────────────────────
  @override
  void onInit() {
    super.onInit();

    // 1. Pre-populate defaults from AppState (stored during login)
    selectedCashLedgerId.value = int.tryParse(AppState.cashLedgerId) ?? 0;
    selectedBankLedgerId.value = int.tryParse(AppState.bankLedgerId) ?? 0;

    /// Default values for amount
    amountController.text = totalToPay.toStringAsFixed(2);
    receivedAmount.value = totalToPay;

    discountController.text = "0.00";
    roundOffController.text = "0.00";

    splitCountController.text = "1";
    _generateSplitAmounts(1);

    // 2. Fetch fresh lists from API or Local
    fetchAccounts();
    fetchCustomers();

    // Listen for toggle changes
    ever(isCustomerSelectEnabled, (bool enabled) {
      if (!enabled) {
        onCustomerSelected(null);
      }
    });
  }

  /// ─────────────────────────────────────────────
  /// 🔹 Fetch Data
  /// ─────────────────────────────────────────────
  Future<void> fetchAccounts() async {
    try {
      isLoadingAccounts.value = true;
      try {
        final cashResponse = await _apiService.post('mobileapp/sales/get_branch_all_cash_account', data: {
          "usr_id": int.tryParse(AppState.userId) ?? 0,
        });
        if (cashResponse.statusCode == 200) {
          final List<dynamic> data = cashResponse.data['data'] ?? [];
          final list = data.map((e) => e as Map<String, dynamic>).toList();
          cashAccounts.assignAll(list);
          await _dbHelper.insertLedgers(list, 'cash');
          if (selectedCashLedgerId.value == 0) {
            final defaultLedger = cashResponse.data['defaultLedger'];
            if (defaultLedger != null) {
              selectedCashLedgerId.value = (defaultLedger['ledger_id'] as num).toInt();
            } else if (cashAccounts.isNotEmpty) {
              selectedCashLedgerId.value = (cashAccounts[0]['ledger_id'] as num).toInt();
            }
          }
        }
      } catch (e) {
        final localCash = await _dbHelper.getLedgers('cash');
        cashAccounts.assignAll(localCash);
        if (selectedCashLedgerId.value == 0 && cashAccounts.isNotEmpty) {
          selectedCashLedgerId.value = (cashAccounts[0]['ledger_id'] as num).toInt();
        }
      }

      try {
        final bankResponse = await _apiService.post('mobileapp/sales/get_branch_bank_account', data: {
          "usr_id": int.tryParse(AppState.userId) ?? 0,
        });
        if (bankResponse.statusCode == 200) {
          final List<dynamic> data = bankResponse.data['data'] ?? [];
          final list = data.map((e) => e as Map<String, dynamic>).toList();
          bankAccounts.assignAll(list);
          await _dbHelper.insertLedgers(list, 'bank');
          if (selectedBankLedgerId.value == 0 && bankAccounts.isNotEmpty) {
            selectedBankLedgerId.value = (bankAccounts[0]['ledger_id'] as num).toInt();
          }
        }
      } catch (e) {
        final localBank = await _dbHelper.getLedgers('bank');
        bankAccounts.assignAll(localBank);
        if (selectedBankLedgerId.value == 0 && bankAccounts.isNotEmpty) {
          selectedBankLedgerId.value = (bankAccounts[0]['ledger_id'] as num).toInt();
        }
      }
    } catch (e) {
      log("Critical Error in fetchAccounts: $e");
    } finally {
      isLoadingAccounts.value = false;
    }
  }

  Future<void> fetchCustomers() async {
    try {
      final localCustomers = await _dbHelper.getCustomers();
      customers.assignAll(localCustomers);

      final response = await _apiService.post('mobileapp/customer/download', data: {
        "part_no": 0,
        "limit": 1000,
        "sync_time": "",
      });

      if (response.statusCode == 200) {
        final List<dynamic> data = response.data['data'] ?? [];
        final list = data.map((e) => e as Map<String, dynamic>).toList();
        await _dbHelper.insertCustomers(list);
        customers.assignAll(list);
      }
    } catch (e) {
      log("Error fetching customers: $e");
    }
  }

  void onCustomerSelected(Map<String, dynamic>? customer) {
    selectedCustomer.value = customer;
    if (customer != null) {
      customerNameController.text = customer['name'] ?? "";
      customerMobileController.text = customer['mobile'] ?? "";
      customerAddressController.text = customer['cust_home_addr'] ?? "";
      customerVatController.text = customer['vat_no'] ?? "";
    } else {
      customerNameController.text = "Cash Customer";
      customerMobileController.clear();
      customerAddressController.clear();
      customerVatController.clear();
    }
  }

  void updateBankReceivedAmount(String value) {
    bankReceivedAmount.value = double.tryParse(value) ?? 0.0;
  }

  void updateMultiCashAmount(String value) {
    multiCashAmount.value = double.tryParse(value) ?? 0.0;
  }

  void updateMultiBankAmount(String value) {
    multiBankAmount.value = double.tryParse(value) ?? 0.0;
  }

  void setPaymentMethod(String method) {
    paymentMethod.value = method;
    if (method == 'Cash') {
      amountController.text = totalToPay.toStringAsFixed(2);
      receivedAmount.value = totalToPay;
    } else if (method == 'Card' || method == 'Bank') {
      bankAmountController.text = totalToPay.toStringAsFixed(2);
      bankReceivedAmount.value = totalToPay;
    } else if (method == 'Multiple') {
      multiCashController.text = '';
      multiBankController.text = '';
      multiCashAmount.value = 0.0;
      multiBankAmount.value = 0.0;
    }
  }

  void toggleSplit(bool value) {
    isSplit.value = value;
    if (isSplit.value) {
      _generateSplitAmounts(splitCount.value);
    }
  }

  void updateReceivedAmount(String value) {
    receivedAmount.value = double.tryParse(value) ?? 0.0;
  }

  void updateDiscountAmount(String value) {
    double val = double.tryParse(value) ?? 0.0;

    // Validation: Discount cannot exceed total amount
    if (val > order.totalAmount) {
      discountAmount.value = 0.0;
      discountController.text = "0.00";
      showSafeSnackbar(
        "Invalid Discount",
        "Discount amount cannot be greater than the total amount of ${order.totalAmount.toStringAsFixed(2)}",
        // backgroundColor: Colors.red,
        // colorText: Colors.white,
        // snackPosition: SnackPosition.BOTTOM,
      );
    } else {
      discountAmount.value = val;
    }

    if (paymentMethod.value == 'Cash') {
      amountController.text = totalToPay.toStringAsFixed(2);
      receivedAmount.value = totalToPay;
    } else if (paymentMethod.value == 'Card' || paymentMethod.value == 'Bank') {
      bankAmountController.text = totalToPay.toStringAsFixed(2);
      bankReceivedAmount.value = totalToPay;
    }
    if (isSplit.value) _generateSplitAmounts(splitCount.value);
  }

  void updateRoundOffAmount(String value) {
    roundOffAmount.value = double.tryParse(value) ?? 0.0;
    if (paymentMethod.value == 'Cash') {
      amountController.text = totalToPay.toStringAsFixed(2);
      receivedAmount.value = totalToPay;
    }
    if (isSplit.value) _generateSplitAmounts(splitCount.value);
  }

  void updateSplitCount(String value) {
    final count = int.tryParse(value) ?? 1;
    splitCount.value = count <= 0 ? 1 : count;
    _generateSplitAmounts(splitCount.value);
  }

  void _generateSplitAmounts(int count) {
    final total = totalToPay;
    double perPerson = total / count;
    splitAmounts.value = List.generate(count, (index) {
      if (index == count - 1) return total - (perPerson * (count - 1));
      return perPerson;
    });
  }

  Future<void> handleCompliment() async {
    await settleOrder(isComp: true);
  }

  Future<void> settleOrder({bool isComp = false}) async {
    if (!isComp && paymentMethod.value == 'Cash' && receivedAmount.value < totalToPay) {
      showSafeSnackbar("Invalid Amount", "Received amount is less than total.",
          // backgroundColor: Colors.red, colorText: Colors.white
      );
      return;
    }

    try {
      isProcessing.value = true;
      final Map<String, int> payTypeMap = {
        'Cash': 2, 'Card': 5, 'Bank': 3, 'Credit': 1, 'Multiple': 4,
      };
      final int payType = isComp ? 2 : (payTypeMap[paymentMethod.value] ?? 0);

      double? cashAmt;
      double? cardAmt;
      if (isComp) {
        cashAmt = 0; cardAmt = 0;
      } else if (paymentMethod.value == 'Cash') {
        cashAmt = totalToPay;
      } else if (paymentMethod.value == 'Card' || paymentMethod.value == 'Bank') {
        cardAmt = totalToPay;
      } else if (paymentMethod.value == 'Multiple') {
        cashAmt = multiCashAmount.value;
        cardAmt = multiBankAmount.value;
      }

      int? cashLedgerId;
      int? bankLedgerId;
      if (isComp || paymentMethod.value == 'Cash' || paymentMethod.value == 'Multiple') {
        cashLedgerId = selectedCashLedgerId.value != 0 ? selectedCashLedgerId.value : (int.tryParse(AppState.cashLedgerId) ?? 0);
        if (cashLedgerId == 0) cashLedgerId = null;
      }
      if (paymentMethod.value == 'Card' || paymentMethod.value == 'Bank' || paymentMethod.value == 'Multiple') {
        bankLedgerId = selectedBankLedgerId.value != 0 ? selectedBankLedgerId.value : (int.tryParse(AppState.bankLedgerId) ?? 0);
        if (bankLedgerId == 0) bankLedgerId = null;
      }

      final cartController = Get.find<CartController>();
      final result = cartController.isEditing
          ? await cartController.updateOrder(
        isDraft: false,
        payType: payType,
        cashAmt: cashAmt,
        cardAmt: cardAmt,
        cashLedgerId: cashLedgerId,
        bankLedgerId: bankLedgerId,
        isCompliment: isComp,
        discountAmount: discountAmount.value,
        roundOffAmount: roundOffAmount.value,
        customerData: isCustomerSelectEnabled.value   // ← replaces customerId
            ? selectedCustomer.value
            : null,
        customerName: customerNameController.text,
        customerMobile: customerMobileController.text,
        customerAddress: customerAddressController.text,
        customerVat: customerVatController.text,
      )
          : await cartController.placeOrder(
        isDraft: false,
        payType: payType,
        cashAmt: cashAmt,
        cardAmt: cardAmt,
        cashLedgerId: cashLedgerId,
        bankLedgerId: bankLedgerId,
        isCompliment: isComp,
        discountAmount: discountAmount.value,
        roundOffAmount: roundOffAmount.value,
        customerData: isCustomerSelectEnabled.value   // ← replaces customerId
            ? selectedCustomer.value
            : null,
        customerName: customerNameController.text,
        customerMobile: customerMobileController.text,
        customerAddress: customerAddressController.text,
        customerVat: customerVatController.text,
      );

      if (result != null && result['no_change'] != true) {
        final bool isOffline = result['offline'] == true;

        if (isOffline) {
          await _savePaymentLocally(isComp: isComp);
          return;
        }

        // ✅ Correct path matching actual response shape
        final messageMap = result['message'] is Map ? result['message'] as Map : null;
        final preview = messageMap?['preview'] is Map ? messageMap!['preview'] as Map : null;

        final String? serverId =
            preview?['sq_id']?.toString() ??
                preview?['sales_odr_id']?.toString() ??
                result['id']?.toString();

        // ✅ The new local uuid injected by placeOrder
        final String? newLocalUuid = result['_local_uuid']?.toString();

        // ✅ Delete original pending order
        await _dbHelper.deleteOrder(order.id);

        // ✅ Delete the new local paid record placeOrder created
        if (newLocalUuid != null && newLocalUuid.isNotEmpty) {
          await _dbHelper.deleteOrder(newLocalUuid);
        }

        // ✅ Mark server record as paid
        if (serverId != null && serverId.isNotEmpty) {
          await _dbHelper.updateOrderStatusByServerId(serverId, 'paid', isSynced: 1);
        }

        _printReceipt();
        cartController.stopEditing();
        Get.find<OrdersController>().fetchOrders();
        Get.back();
        showSafeSnackbar(
          "Success",
          isComp ? "Order complimented successfully." : "Order settled successfully.",
          // backgroundColor: Colors.green,
          // colorText: Colors.white,
        );
      } else if (result != null && result['no_change'] == true) {
        showSafeSnackbar("No Changes", "No changes detected in the order.",
            // backgroundColor: Colors.orange, colorText: Colors.white
        );
      } else {
        showSafeSnackbar("Error", "Failed to process order.",
            // backgroundColor: Colors.red, colorText: Colors.white
        );
      }
    } catch (e) {
      log("Settle Error: $e");
      await _savePaymentLocally(isComp: isComp);
    } finally {
      isProcessing.value = false;
    }
  }

  Future<void> _savePaymentLocally({bool isComp = false}) async {
    try {
      int cashId = selectedCashLedgerId.value != 0 ? selectedCashLedgerId.value : (int.tryParse(AppState.cashLedgerId) ?? 0);
      int bankId = selectedBankLedgerId.value != 0 ? selectedBankLedgerId.value : (int.tryParse(AppState.bankLedgerId) ?? 0);
      await _dbHelper.insertPayment({
        "order_uuid": order.id,
        "amount": isComp ? 0 : totalToPay,
        "method": isComp ? "compliment" : (isSplit.value ? "split" : paymentMethod.value.toLowerCase()),
        "is_synced": 0,
        "created_at": DateTime.now().toIso8601String(),
        "cash_ledger_id": cashId,
        "bank_ledger_id": bankId,
        "discount_amount": isComp ? order.totalAmount : discountAmount.value,
      });
      await _dbHelper.updateOrderStatusByServerId(order.id, 'paid', isSynced: 0);
      _printReceipt();
      Get.find<CartController>().stopEditing();
      Get.find<OrdersController>().fetchOrders();
      Get.back();
      showSafeSnackbar("Offline", "Payment saved locally. It will sync automatically.",
          // backgroundColor: Colors.orange, colorText: Colors.white
      );
    } catch (e) { log("Local Settle Error: $e"); }
  }

  void _printReceipt() {
    try {
      Get.find<PrinterController>().printReceipt(order, receivedAmount.value, changeAmount);
    } catch (e) { log("Receipt Print Error: $e"); }
  }
}
