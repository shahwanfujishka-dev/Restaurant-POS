import 'dart:async';
import 'dart:developer';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:restaurant_pos/app/data/services/order_submission.dart';
import 'package:get/get.dart' hide ScreenType;
import 'package:restaurant_pos/app/data/Device_Roles/device_roles.dart';
import 'package:restaurant_pos/app/modules/home/controller/printer_controller.dart';
import 'package:restaurant_pos/app/routes/app_pages.dart';
import 'package:restaurant_pos/helper/network_helper.dart';
import 'package:restaurant_pos/helper/screen_type.dart';
import 'package:restaurant_pos/helper/snackbar_helper.dart';
import '../../../data/models/order_model.dart';
import '../../../data/services/api_endpoints.dart';
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
  final ScrollController scrollController = ScrollController();
  final paymentMethod = 'Cash'.obs;
  final paymentMethods = ['Cash', 'Card', 'Bank', 'Credit', 'Multiple'];
  final isCustomerSelectEnabled = false.obs;
  final customers = <Map<String, dynamic>>[].obs;
  final selectedCustomer = Rxn<Map<String, dynamic>>();
  final TextEditingController customerNameController = TextEditingController(
    text: 'cash_customer'.tr,
  );
  final TextEditingController customerMobileController =
      TextEditingController();
  final TextEditingController customerAddressController =
      TextEditingController();
  final TextEditingController customerVatController = TextEditingController();
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
  final receivedAmount = 0.0.obs;
  final TextEditingController amountController = TextEditingController();
  final discountAmount = 0.0.obs;
  final TextEditingController discountController = TextEditingController();
  final roundOffAmount = 0.0.obs;
  final roundOffIsNegative = false.obs; // false = "+" (default)
  final TextEditingController roundOffController = TextEditingController();
  final isSplit = false.obs;
  final TextEditingController splitCountController = TextEditingController();
  final splitCount = 1.obs;
  final splitAmounts = <double>[].obs;
  final splitControllers = <TextEditingController>[].obs;
  final isProcessing = false.obs;
  double get discountedRatio {
    if (order.totalAmount <= 0) return 1.0;
    return (order.totalAmount - discountAmount.value) / order.totalAmount;
  }

  double get subtotal => (order.totalAmount - order.totalTax) * discountedRatio;
  double get tax {
    if (Get.isRegistered<DashboardController>() &&
        Get.find<DashboardController>().vatType.value == 1) {
      return 0.0;
    }
    return order.totalTax * discountedRatio;
  }

  double get totalToPay {
    final double base =
        order.totalAmount - discountAmount.value + roundOffAmount.value;
    final vatDisabled = Get.isRegistered<DashboardController>() &&
        Get.find<DashboardController>().vatType.value == 1;
    final amount = vatDisabled ? base - order.totalTax : base;
    return _minorUnits(amount.clamp(0, double.infinity)) / 100;
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
        final cashResponse = await _apiService.post(
          ApiEndpoints.getBranchCashAccounts,
          data: {"usr_id": int.tryParse(AppState.userId) ?? 0},
        );
        if (cashResponse.statusCode == 200) {
          final List<dynamic> data = cashResponse.data['data'] ?? [];
          final list = data.map((e) => e as Map<String, dynamic>).toList();
          cashAccounts.assignAll(list);
          await _dbHelper.insertLedgers(list, 'cash');
          if (selectedCashLedgerId.value == 0) {
            final defaultLedger = cashResponse.data['defaultLedger'];
            if (defaultLedger != null) {
              selectedCashLedgerId.value = (defaultLedger['ledger_id'] as num)
                  .toInt();
            }
          }
        }
      } catch (e) {
        final localCash = await _dbHelper.getLedgers('cash');
        cashAccounts.assignAll(localCash);
      }
      try {
        final bankResponse = await _apiService.post(
          ApiEndpoints.getBranchBankAccounts,
          data: {"usr_id": int.tryParse(AppState.userId) ?? 0},
        );
        if (bankResponse.statusCode == 200) {
          final List<dynamic> data = bankResponse.data['data'] ?? [];
          final list = data.map((e) => e as Map<String, dynamic>).toList();
          bankAccounts.assignAll(list);
          await _dbHelper.insertLedgers(list, 'bank');
          if (selectedBankLedgerId.value == 0) {
            final defaultLedger = bankResponse.data['defaultLedger'];
            if (defaultLedger != null) {
              selectedBankLedgerId.value = (defaultLedger['ledger_id'] as num)
                  .toInt();
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

      final response = await _apiService.post(
        ApiEndpoints.downloadCustomers,
        data: {"part_no": 0, "limit": 1000, "sync_time": ""},
      );

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
      customerAddressController.text =
          customer['address'] ?? customer['cust_home_addr'] ?? "";
      customerVatController.text = customer['vat_no'] ?? "";
    } else {
      customerNameController.text = 'cash_customer'.tr;
      customerMobileController.clear();
      customerAddressController.clear();
      customerVatController.clear();
    }
  }

  void updateBankReceivedAmount(String value) {
    bankReceivedAmount.value = double.tryParse(value) ?? 0.0;
  }

  void updateMultiCashAmount(String value) {
    double cash = _minorUnits(double.tryParse(value) ?? 0) / 100;
    if (cash > totalToPay) {
      cash = totalToPay;
      multiCashController.text = cash.toStringAsFixed(2);
      multiCashController.selection = TextSelection.fromPosition(
        TextPosition(offset: multiCashController.text.length),
      );
    }
    multiCashAmount.value = cash;
    multiBankAmount.value = (_minorUnits(totalToPay) - _minorUnits(cash)) / 100;
    multiBankController.text = multiBankAmount.value.toStringAsFixed(2);
  }

  void updateMultiBankAmount(String value) {
    double bank = _minorUnits(double.tryParse(value) ?? 0) / 100;
    if (bank > totalToPay) {
      bank = totalToPay;
      multiBankController.text = bank.toStringAsFixed(2);
      multiBankController.selection = TextSelection.fromPosition(
        TextPosition(offset: multiBankController.text.length),
      );
    }
    multiBankAmount.value = bank;
    multiCashAmount.value = (_minorUnits(totalToPay) - _minorUnits(bank)) / 100;
    multiCashController.text = multiCashAmount.value.toStringAsFixed(2);
  }

  void setPaymentMethod(String method) {
    if (paymentMethod.value == method) return;
    paymentMethod.value = method;

    if (method == 'Credit') {
      isCustomerSelectEnabled.value = true;
    } else if (method != 'Card') {
      isCustomerSelectEnabled.value = false;
    }

    if (method == 'Cash') {
      amountController.text = totalToPay.toStringAsFixed(2);
      receivedAmount.value = totalToPay;
    } else if (method == 'Card' || method == 'Bank') {
      bankAmountController.text = totalToPay.toStringAsFixed(2);
      bankReceivedAmount.value = totalToPay;
    } else if (method == 'Multiple') {
      final total = _minorUnits(totalToPay);
      final cash = (total + 1) ~/ 2;
      multiCashAmount.value = cash / 100;
      multiBankAmount.value = (total - cash) / 100;
      multiCashController.text = multiCashAmount.value.toStringAsFixed(2);
      multiBankController.text = multiBankAmount.value.toStringAsFixed(2);
    }
  }

  void toggleSplit(bool value) {
    isSplit.value = value;
    if (isSplit.value) {
      _generateSplitAmounts(splitCount.value);
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
    if (val > order.totalAmount) {
      discountAmount.value = 0.0;
      discountController.text = "";
      showSafeSnackbar(
        'invalid_discount_title'.tr,
        'invalid_discount_msg'.trParams({'total': order.totalAmount.toStringAsFixed(2)}),
      );
    } else {
      discountAmount.value = val;
    }
    _recalculatePaymentAmounts();
    if (isSplit.value) _generateSplitAmounts(splitCount.value);
  }

  void updateRoundOffAmount(String value) {
    final double mag = (double.tryParse(value) ?? 0.0).abs();
    final double val = roundOffIsNegative.value ? -mag : mag;
    final double netAmount = order.totalAmount - discountAmount.value;

    if (val.abs() > netAmount) {
      roundOffAmount.value = 0.0;
      roundOffController.text = "";
      showSafeSnackbar(
        'invalid_roundoff_title'.tr,
        'invalid_roundoff_msg'.trParams({'net': netAmount.toStringAsFixed(2)}),
      );
    } else {
      roundOffAmount.value = val;
    }
    _recalculatePaymentAmounts();
    if (isSplit.value) _generateSplitAmounts(splitCount.value);
  }

  void setRoundOffSign(bool negative) {
    roundOffIsNegative.value = negative;
    updateRoundOffAmount(roundOffController.text); // re-apply with new sign
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
      multiBankAmount.value =
          (_minorUnits(totalToPay) - _minorUnits(multiCashAmount.value)) / 100;
      multiBankController.text = multiBankAmount.value.toStringAsFixed(2);
    }
  }

  void updateSplitCount(String value) {
    final count = int.tryParse(value) ?? 1;
    splitCount.value = count <= 0 ? 1 : count;
    _generateSplitAmounts(splitCount.value);
  }

  void updateSplitAmount(int index, String value) {
    final amount = double.tryParse(value) ?? 0.0;
    splitAmounts[index] = amount.isFinite && amount >= 0
        ? _minorUnits(amount) / 100
        : 0.0;
  }

  void _generateSplitAmounts(int count) {
    final total = _minorUnits(totalToPay);
    final perPerson = total ~/ count;
    final remainder = total % count;
    for (var controller in splitControllers) {
      controller.dispose();
    }
    splitControllers.clear();
    splitAmounts.value = List.generate(count, (index) {
      final amount = (perPerson + (index < remainder ? 1 : 0)) / 100;
      splitControllers.add(
        TextEditingController(text: amount.toStringAsFixed(2)),
      );
      return amount;
    });
  }

  int _minorUnits(double amount) => amount.isFinite ? (amount * 100).round() : 0;

  int get _splitTotalMinorUnits =>
      splitAmounts.fold(0, (sum, amount) => sum + _minorUnits(amount));

  double get currentSplitTotal => _splitTotalMinorUnits / 100;
  double get splitDifference =>
      (_minorUnits(totalToPay) - _splitTotalMinorUnits) / 100;

  double getSplitVat(int index) {
    if (index < 0 || index >= splitAmounts.length) return 0.0;
    final amt = splitAmounts[index];
    if (totalToPay <= 0) return 0.0;
    return (tax * (amt / totalToPay));
  }

  double get currentSplitVatTotal {
    double totalVat = 0;
    for (int i = 0; i < splitAmounts.length; i++) {
      totalVat += getSplitVat(i);
    }
    return totalVat;
  }

  Future<void> handleCompliment() async {
    await settleOrder(isComp: true);
  }

  Future<void> settleOrder({bool isComp = false}) async {
    if (isProcessing.value) return;
    if (!isComp &&
        paymentMethod.value == 'Cash' &&
        receivedAmount.value < totalToPay) {
      showSafeSnackbar('invalid_amount'.tr, 'received_less_than_total'.tr);
      return;
    }
    if (!isComp && paymentMethod.value == 'Multiple') {
      if (multiCashAmount.value <= 0) {
        showSafeSnackbar(
          'invalid_amount'.tr,
          'multi_cash_min_error'.tr,
        );
        return;
      }
      if (multiBankAmount.value <= 0) {
        showSafeSnackbar(
          'invalid_amount'.tr,
          'multi_card_min_error'.tr,
        );
        return;
      }
    }
    if (!isComp && isSplit.value) {
      if (splitDifference != 0) {
        showSafeSnackbar(
          'invalid_split'.tr,
          'split_total_error'.trParams({
            'total': totalToPay.toStringAsFixed(2),
            'diff': splitDifference.toStringAsFixed(2)
          }),
        );
        return;
      }
    }
    if (!isComp &&
        paymentMethod.value == 'Credit' &&
        selectedCustomer.value == null) {
      showSafeSnackbar(
        'customer_required'.tr,
        'select_registered_customer'.tr,
      );
      return;
    }
    if (!isComp) {
      if (paymentMethod.value == 'Cash' && selectedCashLedgerId.value == 0) {
        showSafeSnackbar('account_required'.tr, 'select_cash_acc'.tr);
        return;
      }
      if ((paymentMethod.value == 'Card' || paymentMethod.value == 'Bank') &&
          selectedBankLedgerId.value == 0) {
        showSafeSnackbar('account_required'.tr, 'select_bank_acc'.tr);
        return;
      }
      if (paymentMethod.value == 'Multiple') {
        if (multiCashAmount.value > 0 && selectedCashLedgerId.value == 0) {
          showSafeSnackbar(
            'account_required'.tr,
            'select_cash_acc_multi'.tr,
          );
          return;
        }
        if (multiBankAmount.value > 0 && selectedBankLedgerId.value == 0) {
          showSafeSnackbar(
            'account_required'.tr,
            'select_bank_acc_multi'.tr,
          );
          return;
        }
      }
    }

    final cartController = Get.find<CartController>();
    final submission = OrderSubmission(cartController);
    if (!submission.tryBegin()) return;
    isProcessing.value = true;
    Map<String, dynamic>? result;
    final requiresPrinting = DeviceConfig.requireOrderPrinting;
    final receiptPrintedBeforeSave = requiresPrinting && DeviceConfig.isLocal;
    Future<bool> printPayment(Map<String, dynamic> preview) =>
        _printReceipt(result: preview, isComp: isComp, beforeSave: true);
    try {
      if (DeviceConfig.isOnline && !await NetworkHelper.hasInternetConnection()) {
        showSafeSnackbar('no_internet'.tr, 'check_network_msg'.tr);
        isProcessing.value = false;
        return;
      }

      if (customerMobileController.text.isNotEmpty &&
          customerNameController.text.isNotEmpty &&
          customerNameController.text != 'cash_customer'.tr) {
        await _dbHelper.upsertCustomerByMobile({
          'name': customerNameController.text,
          'mobile': customerMobileController.text,
          'address': customerAddressController.text,
          'vat_no': customerVatController.text,
        });
        fetchCustomers();
      }
      final Map<String, int> payTypeMap = {
        'Cash': 2,
        'Card': 5,
        'Bank': 3,
        'Credit': 1,
        'Multiple': 4,
      };
      final int payType = isComp ? 2 : (payTypeMap[paymentMethod.value] ?? 0);
      double? cashAmt;
      double? cardAmt;
      if (isComp) {
        cashAmt = 0;
        cardAmt = 0;
      } else if (paymentMethod.value == 'Cash') {
        cashAmt = totalToPay;
      } else if (paymentMethod.value == 'Card' ||
          paymentMethod.value == 'Bank') {
        cardAmt = totalToPay;
      } else if (paymentMethod.value == 'Multiple') {
        cashAmt = multiCashAmount.value;
        cardAmt = multiBankAmount.value;
      }
      int? cashLedgerId;
      int? bankLedgerId;
      if (isComp ||
          paymentMethod.value == 'Cash' ||
          paymentMethod.value == 'Multiple') {
        cashLedgerId = selectedCashLedgerId.value != 0
            ? selectedCashLedgerId.value
            : (int.tryParse(AppState.cashLedgerId) ?? 0);
        if (cashLedgerId == 0) cashLedgerId = null;
      }
      if (paymentMethod.value == 'Card' ||
          paymentMethod.value == 'Bank' ||
          paymentMethod.value == 'Multiple') {
        bankLedgerId = selectedBankLedgerId.value != 0
            ? selectedBankLedgerId.value
            : (int.tryParse(AppState.bankLedgerId) ?? 0);
        if (bankLedgerId == 0) bankLedgerId = null;
      }
      log(
        "settleOrder: isComp=$isComp, payType=$payType, totalToPay=$totalToPay",
      );
      result = await submission.save(
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
      printPayment: requiresPrinting ? printPayment : null,
      );

      if (result?['print_blocked'] == true) return;
      log("settleOrder result: $result");

      if (result != null && result['no_change'] != true) {
        final bool isOffline = result['offline'] == true;
        if (isOffline) {
          final String? localUuid = result['preview']?['local_uuid']
              ?.toString();
          await _savePaymentLocally(
            receiptAlreadyPrinted: receiptPrintedBeforeSave,
            isComp: isComp,
            localUuid: localUuid,
            result: result,
            payType: payType,
          );
          return;
        }
        final messageMap = result['message'] is Map
            ? result['message'] as Map
            : null;
        if (messageMap != null &&
            messageMap.containsKey('status') &&
            messageMap['status'] == 0) {
          showSafeSnackbar('error'.tr, messageMap['msg'] ?? 'unexpected_error'.tr);
          return;
        }
        final preview = messageMap?['preview'] is Map
            ? messageMap!['preview'] as Map
            : null;
        final String? serverId =
            preview?['sq_id']?.toString() ??
            preview?['sales_odr_id']?.toString() ??
            result['id']?.toString();
        final String? newLocalUuid = result['_local_uuid']?.toString();
        if (!receiptPrintedBeforeSave) {
          unawaited(_printReceipt(result: result, isComp: isComp));
        }
        try {
          await _dbHelper.deleteOrder(order.id);
          if (newLocalUuid != null && newLocalUuid.isNotEmpty) {
            await _dbHelper.deleteOrder(newLocalUuid);
          }
          if (serverId != null && serverId.isNotEmpty) {
            await _dbHelper.updateOrderStatusByServerId(serverId, 'paid', isSynced: 1);
          }
        } catch (e) {
          log("Post-settle DB cleanup failed: $e");
        }
        cartController.stopEditing();
        Get.find<OrdersController>().fetchOrdersSafely();
        Get.offAllNamed(
          ScreenType.isMobile() ? Routes.ORDER_TYPE : Routes.HOME,
        );

        final String? branchInv =
            preview?['sales_odr_sales_branch_inv']?.toString() ??
            preview?['sales_branch_inv']?.toString() ??
            preview?['sales_odr_branch_inv']?.toString();

        showSafeSnackbar(
          'success'.tr,
          isComp
              ? 'order_compliment_success'.tr
              : (branchInv != null 
                  ? 'order_settle_success_inv'.trParams({'inv': branchInv})
                  : 'order_settle_success'.tr),
        );
      } else if (result != null && result['no_change'] == true) {
        showSafeSnackbar('no_change'.tr, 'no_change_msg'.tr);
      } else {
        if (DeviceConfig.isOnline &&
            !await NetworkHelper.hasInternetConnection()) {
          showSafeSnackbar('no_internet'.tr, 'check_network_msg'.tr);
        } else {
          showSafeSnackbar('error'.tr, 'unexpected_error'.tr);
        }
      }
    } catch (e) {
      log("Settle Error: $e");
      if (result == null && !requiresPrinting) {
        await _savePaymentLocally(isComp: isComp);
      } else if (result == null) {
        showSafeSnackbar('error'.tr, 'unexpected_error'.tr);
      } else {
        log("Post-settle error, order already saved: $e");
      }
    } finally {
      submission.finish();
      isProcessing.value = false;
    }
  }

  Future<void> _savePaymentLocally({
    bool isComp = false,
    String? localUuid,
    Map<String, dynamic>? result,
    int? payType,
    bool receiptAlreadyPrinted = false,
  }) async {
    final cartController = Get.find<CartController>();
    final String orderIdForDb =
        localUuid ??
            (cartController.isEditing
                ? cartController.editingOrderId.value
                : order.id);

    try {
      log("Saving payment locally for Order ID: $orderIdForDb");

      final double finalDiscount = isComp
          ? order.totalAmount
          : discountAmount.value;
      final double finalRoundOff = isComp ? 0 : roundOffAmount.value;
      final double finalTotal = isComp ? 0 : totalToPay;

      // 1. Build the split message BEFORE printing (the printer reads it)
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

      final savedByHub = result != null &&
          DeviceConfig.isLocal && DeviceConfig.role == DeviceRole.client;
      if (!savedByHub) {
        try {
          final int cashId = selectedCashLedgerId.value != 0
              ? selectedCashLedgerId.value
              : (int.tryParse(AppState.cashLedgerId) ?? 0);
          final int bankId = selectedBankLedgerId.value != 0
              ? selectedBankLedgerId.value
              : (int.tryParse(AppState.bankLedgerId) ?? 0);

          await _dbHelper.saveOfflinePayment({
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
          },
            roundOff: finalRoundOff,
            payType: payType ?? (isComp ? 2 : 0),
          );
        } catch (e) {
          log("Local payment DB save failed: $e");
          showSafeSnackbar('error'.tr, 'unexpected_error'.tr);
          return;
        }
      }

      if (!receiptAlreadyPrinted) {
        unawaited(_printReceipt(result: result, isComp: isComp));
      }
      cartController.stopEditing();
      if (Get.isRegistered<OrdersController>()) {
        final ordersController = Get.find<OrdersController>();
        ordersController.markOrderAsPaidLocally(orderIdForDb);
        ordersController.fetchOrdersSafely();
      }
      Get.offAllNamed(ScreenType.isMobile() ? Routes.ORDER_TYPE : Routes.HOME);
      showSafeSnackbar(
        isComp ? 'compliment'.tr : 'paid'.tr,
        isComp ? 'compliment_offline_msg'.tr : 'payment_completed'.tr,
      );
    } catch (e) {
      log("Local Settle Error: $e");
    }
  }

  Future<bool> _printReceipt({
    Map<String, dynamic>? result,
    bool isComp = false,
    bool beforeSave = false,
  }) async {
    try {
      final received = isComp ? 0.0 : receivedAmount.value;
      final change = isComp ? 0.0 : changeAmount;
      final customerName = customerNameController.text;
      final method = isComp ? 'compliment'.tr : paymentMethod.value.tr;
      final discount = discountAmount.value;
      final roundOff = isComp ? 0.0 : roundOffAmount.value;
      final netTotal = beforeSave ? (isComp ? 0.0 : totalToPay) : null;
      final printerCtrl = Get.find<PrinterController>();
      Map<String, dynamic>? messageMap;

      if (result != null) {
        if (result['message'] is Map) {
          messageMap = result['message'];
        }
        if (isSplit.value && messageMap?['pos_split'] == null) {
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
          Map<String, dynamic> normalizedResult = Map<String, dynamic>.from(
            result,
          );
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
          if (beforeSave) return false;
        }
      }

      if (beforeSave && orderToPrint.items.isEmpty) return false;
      if (orderToPrint.items.isEmpty) {
        log("Print: parsed items empty, falling back to order.items (${order.items.length})");
        var src = order.items;
        if (src.isEmpty && Get.isRegistered<OrdersController>()) {
          final oc = Get.find<OrdersController>();
          await oc.fetchOrderDetails(order);
          src = (oc.orders + oc.soldOrders)
              .firstWhere((o) => o.invNo == order.invNo, orElse: () => order)
              .items;
        }
        orderToPrint = orderToPrint.copyWith(items: src);
      }

      final posSplit = messageMap?['pos_split'] as List?;
      final splitCountResult = messageMap?['pos_split_count'] as int?;
      final Future<bool> Function() send;

      if (posSplit != null && posSplit.isNotEmpty && splitCountResult != null) {
        final splits = posSplit.cast<Map<String, dynamic>>().toList();
        send = () => printerCtrl.printSplitReceipts(
          orderToPrint,
          splits,
          splitCountResult,
          stopOnFailure: beforeSave,
        );
      } else {
        final double printDiscount = isComp
            ? (orderToPrint.totalAmount != 0
                  ? orderToPrint.totalAmount
                  : order.totalAmount)
            : (result != null && result['offline'] != true)
            ? orderToPrint.discount
            : discount;
        final OrderModel orderForPrint = isComp
            ? orderToPrint.copyWith(totalAmount: 0)
            : orderToPrint;
        send = () => printerCtrl.printReceipt(
          orderForPrint,
          received,
          change,
          customerName: customerName,
          paymentMethod: method,
          discount: printDiscount,
          roundOff: roundOff,
          netTotalOverride: netTotal,
          isSale: true,
        );
      }

      Future<bool> sendWithFeedback() async {
        final printSuccess = await send().catchError((Object error) {
          log('Receipt print failed: $error');
          return false;
        });
        if (!printSuccess && !beforeSave) {
          showSafeSnackbar(
            "Receipt Print Failed",
            "Order settled successfully, but receipt printing failed. You can check printer/paper and retry.",
          );
          final ctx = Get.overlayContext;
          if (ctx != null && ctx.mounted) {
            await showDialog(
              context: ctx,
              builder: (d) => AlertDialog(
                icon: const Icon(Icons.print_disabled, color: Colors.red, size: 36),
                title: const Text("Receipt Print Failed"),
                content: const Text(
                  "Order settled successfully, but the receipt was not printed because the printer is unavailable, disconnected, or out of paper.\n\nPlease check printer connection or paper and retry.",
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(d),
                    child: const Text("Close"),
                  ),
                  FilledButton(
                    onPressed: () {
                      Navigator.pop(d);
                      unawaited(sendWithFeedback());
                    },
                    child: const Text("Retry Print"),
                  ),
                ],
              ),
            );
          }
        }
        return printSuccess;
      }

      return await sendWithFeedback();
    } catch (e) {
      log("Receipt Print Error: $e");
      if (beforeSave) return false;
      showSafeSnackbar(
        "Receipt Print Error",
        "Order settled successfully, but receipt printing encountered an error: $e",
      );
      return false;
    }
  }
}
