import 'dart:convert';
import 'dart:developer';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart'hide ScreenType;
import 'package:restaurant_pos/app/modules/home/controller/printer_controller.dart';
import 'package:restaurant_pos/helper/screen_type.dart';
import 'package:restaurant_pos/helper/snackbar_helper.dart';
import '../../../data/models/order_model.dart';
import '../../../data/services/api_services.dart';
import '../../../data/services/database_helper.dart';
import '../../../data/utils/AppState.dart';
import '../../cart/controller/cart_controller.dart';
import 'dashboard_controller.dart';
import 'order_controller.dart';

class CashierController extends GetxController {
  final ApiService _apiService = Get.find<ApiService>();
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  final OrderModel order = Get.arguments;

  /// ─────────────────────────────────────────────
  /// 🔹 Scroll Handling
  /// ─────────────────────────────────────────────
  final ScrollController scrollController = ScrollController();

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
  final splitControllers = <TextEditingController>[].obs;

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
  double get tax {
    if (Get.isRegistered<DashboardController>() && Get.find<DashboardController>().vatType.value == 1) {
      return 0.0;
    }
    return order.totalTax * discountedRatio;
  }
  double get totalToPay {
    final double base = order.totalAmount - discountAmount.value + roundOffAmount.value;

    if (Get.isRegistered<DashboardController>() &&
        Get.find<DashboardController>().vatType.value == 1) {
      return (base - order.totalTax).clamp(0, double.infinity);
    }

    return base.clamp(0, double.infinity);
  }

  double get changeAmount =>
      (receivedAmount.value - totalToPay).clamp(0, double.infinity);


  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      amountController.text = totalToPay.toStringAsFixed(2);
      receivedAmount.value = totalToPay;
      bankAmountController.text = totalToPay.toStringAsFixed(2);
      bankReceivedAmount.value = totalToPay;
      _generateSplitAmounts(splitCount.value);
    });
    selectedCashLedgerId.value = int.tryParse(AppState.cashLedgerId) ?? 0;
    selectedBankLedgerId.value = int.tryParse(AppState.bankLedgerId) ?? 0;
    discountController.text = "";
    roundOffController.text = "";
    splitCountController.text = "1";
    _generateSplitAmounts(1);
    fetchAccounts();
    fetchCustomers();
    ever(isCustomerSelectEnabled, (bool enabled) {
      if (!enabled) {
        onCustomerSelected(null);
      }
    });
  }

  @override
  void onClose() {
    scrollController.dispose();
    for (var controller in splitControllers) {
      controller.dispose();
    }
    super.onClose();
  }

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
            }
          }
        }
      } catch (e) {
        final localCash = await _dbHelper.getLedgers('cash');
        cashAccounts.assignAll(localCash);
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
          if (selectedBankLedgerId.value == 0) {
            final defaultLedger = bankResponse.data['defaultLedger'];
            if (defaultLedger != null) {
              selectedBankLedgerId.value = (defaultLedger['ledger_id'] as num).toInt();
            }
          }
        }
      } catch (e) {
        final localBank = await _dbHelper.getLedgers('bank');
        bankAccounts.assignAll(localBank);
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
      customerAddressController.text = customer['address'] ?? customer['cust_home_addr'] ?? "";
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
    double cash = double.tryParse(value) ?? 0.0;
    if (cash > totalToPay) {
      cash = totalToPay;
      multiCashController.text = cash.toStringAsFixed(2);
      multiCashController.selection = TextSelection.fromPosition(TextPosition(offset: multiCashController.text.length));
    }
    multiCashAmount.value = cash;
    multiBankAmount.value = totalToPay - cash;
    multiBankController.text = multiBankAmount.value.toStringAsFixed(2);
  }

  void updateMultiBankAmount(String value) {
    double bank = double.tryParse(value) ?? 0.0;
    if (bank > totalToPay) {
      bank = totalToPay;
      multiBankController.text = bank.toStringAsFixed(2);
      multiBankController.selection = TextSelection.fromPosition(TextPosition(offset: multiBankController.text.length));
    }
    multiBankAmount.value = bank;
    multiCashAmount.value = totalToPay - bank;
    multiCashController.text = multiCashAmount.value.toStringAsFixed(2);
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
      double half = totalToPay / 2;
      multiCashAmount.value = half;
      multiBankAmount.value = totalToPay - half;
      multiCashController.text = multiCashAmount.value.toStringAsFixed(2);
      multiBankController.text = multiBankAmount.value.toStringAsFixed(2);
    }
  }

  void toggleSplit(bool value) {
    isSplit.value = value;
    if (isSplit.value) {
      _generateSplitAmounts(splitCount.value);

      // Auto-scroll to bottom on mobile
      if (ScreenType.isMobile()) {
        Future.delayed(const Duration(milliseconds: 300), () {
          if (scrollController.hasClients) {
            scrollController.animateTo(
              scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOut,
            );
          }
        });
      }
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
      discountController.text = "";
      showSafeSnackbar(
        "Invalid Discount",
        "Discount amount cannot be greater than the total amount of ${order.totalAmount.toStringAsFixed(2)}",
      );
    } else {
      discountAmount.value = val;
    }

    _recalculatePaymentAmounts();
    if (isSplit.value) _generateSplitAmounts(splitCount.value);
  }

  void updateRoundOffAmount(String value) {
    roundOffAmount.value = double.tryParse(value) ?? 0.0;
    _recalculatePaymentAmounts();
    if (isSplit.value) _generateSplitAmounts(splitCount.value);
  }

  void incrementRoundOff() {
    // Treat the current value as a positive addition
    double currentVal = double.tryParse(roundOffController.text) ?? 0.0;
    roundOffAmount.value = currentVal.abs();
    roundOffController.text = roundOffAmount.value.toStringAsFixed(2);
    _recalculatePaymentAmounts();
    if (isSplit.value) _generateSplitAmounts(splitCount.value);
  }

  void decrementRoundOff() {
    // Treat the current value as a subtraction (negative)
    double currentVal = double.tryParse(roundOffController.text) ?? 0.0;
    roundOffAmount.value = -currentVal.abs();
    roundOffController.text = roundOffAmount.value.toStringAsFixed(2);
    _recalculatePaymentAmounts();
    if (isSplit.value) _generateSplitAmounts(splitCount.value);
  }

  void _recalculatePaymentAmounts() {
    final method = paymentMethod.value;
    if (method == 'Cash') {
      amountController.text = totalToPay.toStringAsFixed(2);
      receivedAmount.value = totalToPay;
    } else if (method == 'Card' || method == 'Bank') {
      bankAmountController.text = totalToPay.toStringAsFixed(2);
      bankReceivedAmount.value = totalToPay;
    } else if (method == 'Multiple') {
      if (multiCashAmount.value > totalToPay) {
        multiCashAmount.value = totalToPay;
        multiCashController.text = multiCashAmount.value.toStringAsFixed(2);
      }
      multiBankAmount.value = totalToPay - multiCashAmount.value;
      multiBankController.text = multiBankAmount.value.toStringAsFixed(2);
    }
  }

  void updateSplitCount(String value) {
    final count = int.tryParse(value) ?? 1;
    splitCount.value = count <= 0 ? 1 : count;
    _generateSplitAmounts(splitCount.value);
  }

  void updateSplitAmount(int index, String value) {
    double val = double.tryParse(value) ?? 0.0;
    splitAmounts[index] = val;
  }

  void _generateSplitAmounts(int count) {
    final total = totalToPay;
    double perPerson = total / count;

    // Dispose old controllers
    for (var controller in splitControllers) {
      controller.dispose();
    }
    splitControllers.clear();

    splitAmounts.value = List.generate(count, (index) {
      double amount = (index == count - 1)
          ? total - (perPerson * (count - 1))
          : perPerson;

      splitControllers.add(TextEditingController(text: amount.toStringAsFixed(2)));
      return amount;
    });
  }

  double get currentSplitTotal => splitAmounts.fold(0, (sum, val) => sum + val);
  double get splitDifference => totalToPay - currentSplitTotal;

  Future<void> handleCompliment() async {
    await settleOrder(isComp: true);
  }

  Future<void> settleOrder({bool isComp = false}) async {
    if (!isComp && paymentMethod.value == 'Cash' && receivedAmount.value < totalToPay) {
      showSafeSnackbar("Invalid Amount", "Received amount is less than total.");
      return;
    }

    if (!isComp && paymentMethod.value == 'Multiple') {
      if (multiCashAmount.value <= 0) {
        showSafeSnackbar("Invalid Amount", "For Multipayment Cash Amount Must be greater than 0");
        return;
      }
      if (multiBankAmount.value <= 0) {
        showSafeSnackbar("Invalid Amount", "For Multipayment Card Amount Must be greater than 0");
        return;
      }
    }

    if (!isComp && isSplit.value) {
      if (splitDifference.abs() > 0.01) {
        showSafeSnackbar("Invalid Split", "Split amounts must equal the total to pay: ${totalToPay.toStringAsFixed(2)} (Current difference: ${splitDifference.toStringAsFixed(2)})");
        return;
      }
    }

    if (!isComp && paymentMethod.value == 'Credit' && selectedCustomer.value == null) {
      showSafeSnackbar("Customer Required", "Please Select a Registered Customer");
      return;
    }

    // Account validation
    if (!isComp) {
      if (paymentMethod.value == 'Cash' && selectedCashLedgerId.value == 0) {
        showSafeSnackbar("Account Required", "Please select a Cash Account");
        return;
      }
      if ((paymentMethod.value == 'Card' || paymentMethod.value == 'Bank') && selectedBankLedgerId.value == 0) {
        showSafeSnackbar("Account Required", "Please select a Bank Account");
        return;
      }
      if (paymentMethod.value == 'Multiple') {
        if (multiCashAmount.value > 0 && selectedCashLedgerId.value == 0) {
          showSafeSnackbar("Account Required", "Please select a Cash Account for the cash portion");
          return;
        }
        if (multiBankAmount.value > 0 && selectedBankLedgerId.value == 0) {
          showSafeSnackbar("Account Required", "Please select a Bank Account for the card portion");
          return;
        }
      }
    }

    try {
      isProcessing.value = true;

      // ✅ Save customer locally if details are provided (Store for offline cases)
      if (customerMobileController.text.isNotEmpty && customerNameController.text.isNotEmpty && customerNameController.text != "Cash Customer") {
        await _dbHelper.upsertCustomerByMobile({
          'name': customerNameController.text,
          'mobile': customerMobileController.text,
          'address': customerAddressController.text,
          'vat_no': customerVatController.text,
        });
        fetchCustomers(); // Refresh the local customers list
      }

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
      log("settleOrder: isComp=$isComp, payType=$payType, totalToPay=$totalToPay");

      final cartController = Get.find<CartController>();
      final result = cartController.isEditing
          ? await cartController.updateOrder(
        isDraft: false,
        payType: payType,
        cashAmt: cashAmt,
        cardAmt: cardAmt,
        cashLedgerId: cashLedgerId,
        bankLedgerId: bankLedgerId,
        registerCustEnabled: isCustomerSelectEnabled.value == true,
        isCompliment: isComp,
        discountAmount: isComp ? order.totalAmount : discountAmount.value,
        roundOffAmount: isComp ? 0 : roundOffAmount.value,
        customerData: isCustomerSelectEnabled.value ? selectedCustomer.value : null,
        customerName: customerNameController.text,
        customerMobile: customerMobileController.text,
        customerAddress: customerAddressController.text,
        customerVat: customerVatController.text,
        isSplit: isSplit.value,
        splitCount: isSplit.value ? splitCount.value : null,
        splitAmounts: isSplit.value ? splitAmounts.toList() : [],
      )
    : await cartController.placeOrder(
        isDraft: false,
        payType: payType,
        cashAmt: cashAmt,
        cardAmt: cardAmt,
        cashLedgerId: cashLedgerId,
        registerCustEnabled: isCustomerSelectEnabled.value == true,
        bankLedgerId: bankLedgerId,
        isCompliment: isComp,
        discountAmount: isComp ? order.totalAmount : discountAmount.value,
        roundOffAmount: isComp ? 0 : roundOffAmount.value,
        customerData: isCustomerSelectEnabled.value
            ? selectedCustomer.value
            : null,
        customerName: customerNameController.text,
        customerMobile: customerMobileController.text,
        customerAddress: customerAddressController.text,
        customerVat: customerVatController.text,
        isSplit: isSplit.value,
        splitCount: isSplit.value ? splitCount.value : null,
        splitAmounts: isSplit.value ? splitAmounts.toList() : [],
      );

      if (result != null && result['no_change'] != true) {
        final bool isOffline = result['offline'] == true;

        if (isOffline) {
          final String? localUuid = result['preview']?['local_uuid']?.toString();
          await _savePaymentLocally(isComp: isComp, localUuid: localUuid, result: result);
          return;
        }

        final messageMap = result['message'] is Map ? result['message'] as Map : null;
        if (messageMap != null && messageMap.containsKey('status') && messageMap['status'] == 0) {
          showSafeSnackbar("Error", messageMap['msg'] ?? "An error occurred");
          return;
        }

        final preview = messageMap?['preview'] is Map ? messageMap!['preview'] as Map : null;

        final String? serverId =
            preview?['sq_id']?.toString() ??
                preview?['sales_odr_id']?.toString() ??
                result['id']?.toString();

        final String? newLocalUuid = result['_local_uuid']?.toString();

        await _dbHelper.deleteOrder(order.id);

        if (newLocalUuid != null && newLocalUuid.isNotEmpty) {
          await _dbHelper.deleteOrder(newLocalUuid);
        }

        if (serverId != null && serverId.isNotEmpty) {
          await _dbHelper.updateOrderStatusByServerId(serverId, 'paid', isSynced: 1);
        }

        _printReceipt(result: result, isComp: isComp);
        cartController.stopEditing();

        Get.find<OrdersController>().fetchOrders();
        Get.back();
        showSafeSnackbar(
          "Success",
          isComp ? "Order complimented successfully." : "Order settled successfully.",
        );
      } else if (result != null && result['no_change'] == true) {
        showSafeSnackbar("No Changes", "No changes detected in the order.");
      } else {
        showSafeSnackbar("Error", "Failed to process order.");
      }
    } catch (e) {
      log("Settle Error: $e");
      await _savePaymentLocally(isComp: isComp);
    } finally {
      isProcessing.value = false;
    }
  }

  Future<void> _savePaymentLocally({bool isComp = false, String? localUuid,Map<String, dynamic>? result,}) async {
    try {
      int cashId = selectedCashLedgerId.value != 0
          ? selectedCashLedgerId.value
          : (int.tryParse(AppState.cashLedgerId) ?? 0);
      int bankId = selectedBankLedgerId.value != 0
          ? selectedBankLedgerId.value
          : (int.tryParse(AppState.bankLedgerId) ?? 0);

      final cartController = Get.find<CartController>();
      
      // ✅ Prioritize the explicitly passed localUuid (crucial for new offline orders)
      final String orderIdForDb = localUuid ?? (cartController.isEditing
          ? cartController.editingOrderId.value
          : order.id);

      log("Saving payment locally for Order ID: $orderIdForDb");

      final double finalDiscount = isComp ? order.totalAmount : discountAmount.value;
      final double finalRoundOff = isComp ? 0 : roundOffAmount.value;
      final double finalTotal = isComp ? 0 : totalToPay;

      await _dbHelper.insertPayment({
        "order_uuid": orderIdForDb,
        "amount": finalTotal,
        "method": isComp
            ? "compliment"
            : (isSplit.value ? "split" : paymentMethod.value.toLowerCase()),
        "is_synced": 0,
        "created_at": DateTime.now().toIso8601String(),
        "cash_ledger_id": cashId,
        "bank_ledger_id": bankId,
        "discount_amount": finalDiscount,
      });

      // Update order's payload with final payment details so the "Paid" tab shows correct breakdown
      final db = await _dbHelper.database;
      final orderRows = await db.query('orders', where: 'uuid = ? OR server_id = ?', whereArgs: [orderIdForDb, orderIdForDb], limit: 1);
      String? updatedPayload;
      if (orderRows.isNotEmpty) {
        final String? existingPayloadStr = orderRows.first['payload'] as String?;
        if (existingPayloadStr != null) {
          final Map<String, dynamic> p = jsonDecode(existingPayloadStr);
          p['tot_disc'] = finalDiscount;
          p['sales_odr_roundoff'] = finalRoundOff;
          p['tot_amount'] = finalTotal;
          p['sales_odr_total'] = finalTotal;
          updatedPayload = jsonEncode(p);
        }
      }

      await _dbHelper.updateOrderStatusByUuid(
        orderIdForDb,
        'paid',
        payload: updatedPayload,
        total: finalTotal,
      );

      if (isSplit.value && result != null) {
        result['message'] = {
          'pos_split_count': splitCount.value,
          'pos_split': List.generate(splitAmounts.length, (index) {
            return {
              'ps_split_no': index + 1,
              'ps_split_amnt': splitAmounts[index],
            };
          }),
          'preview': result['preview'],
        };
      }

      _printReceipt(result: result, isComp: isComp);

      cartController.stopEditing();

      if (Get.isRegistered<OrdersController>()) {
        final ordersController = Get.find<OrdersController>();
        // Ensure the local state in the controller is updated
        ordersController.markOrderAsPaidLocally(orderIdForDb);
        // Refresh the list to move the order from 'Pending' to 'Paid'
        await ordersController.fetchOrders();
      }

      Get.back();
      showSafeSnackbar(
        isComp ? "Compliment" : "Offline",
        isComp
            ? "Order complimented (saved locally)."
            : "Payment saved locally. It will sync automatically.",
      );
    } catch (e) {
      log("Local Settle Error: $e");
    }
  }

  void _printReceipt({Map<String, dynamic>? result, bool isComp = false}) {
    try {
      Map<String, dynamic>? messageMap;

      if (result != null) {
        if (result['message'] is Map) {
          messageMap = result['message'];
        } else if (isSplit.value) {
          // 🔥 Construct split manually for offline
          messageMap = {
            'pos_split_count': splitCount.value,
            'pos_split': List.generate(splitAmounts.length, (index) {
              return {
                'ps_split_no': index + 1,
                'ps_split_amnt': splitAmounts[index],
              };
            }),
            'preview': result['preview'],
          };
        }
      }
      OrderModel orderToPrint = order;
      if (result != null) {
        try {
          // ✅ Normalize: hoist preview to top level so parseOrderResponse finds it
          Map<String, dynamic> normalizedResult = Map<String, dynamic>.from(result);

          if (result['preview'] == null && messageMap?['preview'] is Map) {
            normalizedResult['preview'] = messageMap!['preview'];
          }

          orderToPrint = Get.find<OrdersController>().parseOrderResponse(
            normalizedResult,
            fallbackTableName: order.tableName,
            fallbackChairCount: order.chairNumber,
          );
        } catch (e) {
          log("Error parsing final order for print: $e");
        }
      }

      final posSplit = messageMap?['pos_split'] as List?;
      final splitCountResult = messageMap?['pos_split_count'] as int?;

      if (posSplit != null && posSplit.isNotEmpty && splitCountResult != null) {
        Get.find<PrinterController>().printSplitReceipts(
          orderToPrint,
          posSplit.map((e) => e as Map<String, dynamic>).toList(),
          splitCountResult,
        );
      } else {

        final double printDiscount = isComp
            ? (orderToPrint.totalAmount != 0 ? orderToPrint.totalAmount : order.totalAmount)
            : (result != null && result['offline'] != true)
            ? orderToPrint.discount
            : discountAmount.value;
        final double printRoundOff = isComp ? 0 : roundOffAmount.value;

        final OrderModel orderForPrint = isComp
            ? orderToPrint.copyWith(totalAmount: 0)
            : orderToPrint;

        Get.find<PrinterController>().printReceipt(
          orderForPrint,
          isComp ? 0 : receivedAmount.value,
          isComp ? 0 : changeAmount,
          customerName: customerNameController.text,
          paymentMethod: isComp ? "Compliment" : paymentMethod.value,
          discount: printDiscount,
          roundOff: printRoundOff,
        );
      }
    } catch (e) {
      log("Receipt Print Error: $e");
    }
  }

  // void _printReceipt({Map<String, dynamic>? result, bool isComp = false}) {
  //   try {
  //     final messageMap = result?['message'] is Map ? result!['message'] as Map : null;
  //     OrderModel orderToPrint = order;
  //
  //     if (result != null) {
  //       try {
  //         // ✅ Build preview-wrapped map so parseOrderResponse always finds
  //         // preview at top level — preserving correct rates AND getting items.
  //         Map<String, dynamic> normalizedResult;
  //
  //         final dynamic msgBlock = result['message'];
  //         if (result['preview'] is Map) {
  //           // Offline shape: preview already at top level
  //           normalizedResult = result;
  //         } else if (msgBlock is Map && msgBlock['preview'] is Map) {
  //           // Online shape: hoist preview to top level so parseOrderResponse
  //           // finds it directly — this is what gave correct rates in old code
  //           normalizedResult = {
  //             ...result,
  //             'preview': msgBlock['preview'],
  //             'offline': result['offline'] ?? false,
  //           };
  //         } else {
  //           normalizedResult = result;
  //         }
  //
  //         orderToPrint = Get.find<OrdersController>().parseOrderResponse(normalizedResult);
  //       } catch (e) {
  //         log("Error parsing final order for print: $e");
  //       }
  //     }
  //
  //     final posSplit = messageMap?['pos_split'] as List?;
  //     final splitCountResult = messageMap?['pos_split_count'] as int?;
  //
  //     if (posSplit != null && posSplit.isNotEmpty && splitCountResult != null) {
  //       Get.find<PrinterController>().printSplitReceipts(
  //         orderToPrint,
  //         posSplit.map((e) => e as Map<String, dynamic>).toList(),
  //         splitCountResult,
  //       );
  //     } else {
  //       final double printDiscount = isComp
  //           ? (orderToPrint.totalAmount != 0 ? orderToPrint.totalAmount : order.totalAmount)
  //           : discountAmount.value;
  //       final double printRoundOff = isComp ? 0 : roundOffAmount.value;
  //
  //       final OrderModel orderForPrint = isComp
  //           ? orderToPrint.copyWith(totalAmount: 0)
  //           : orderToPrint;
  //
  //       Get.find<PrinterController>().printReceipt(
  //         orderForPrint,
  //         isComp ? 0 : receivedAmount.value,
  //         isComp ? 0 : changeAmount,
  //         customerName: customerNameController.text,
  //         paymentMethod: isComp ? "Compliment" : paymentMethod.value,
  //         discount: printDiscount,
  //         roundOff: printRoundOff,
  //       );
  //     }
  //   } catch (e) {
  //     log("Receipt Print Error: $e");
  //   }
  // }
}
