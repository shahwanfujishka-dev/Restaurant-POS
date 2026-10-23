import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';
import 'package:collection/collection.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:get/get_instance/src/extension_instance.dart';
import 'package:get/get_navigation/src/extension_navigation.dart';
import 'package:get/get_navigation/src/root/parse_route.dart';
import 'package:get/get_rx/src/rx_types/rx_types.dart';
import 'package:get/get_state_manager/src/simple/get_controllers.dart';
import 'package:get_storage/get_storage.dart';
import 'package:intl/intl.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:restaurant_pos/helper/snackbar_helper.dart';
import 'package:windows_printer/windows_printer.dart';
import '../../../data/Device_Roles/device_roles.dart';
import '../../../data/models/order_model.dart';
import '../../../data/services/database_helper.dart';
import '../../../data/services/local_hub_client.dart';
import '../../../data/services/local_hub_order_service.dart';
import '../../../data/utils/AppState.dart';
import '../views/dashoard/models/dashboard_models.dart';
import 'dashboard_controller.dart';


class PrintIssue {
  final String kind;      // 'KOT' | 'RECEIPT'
  final String target;    // printer name, or item names if unrouted
  final String message;
  final DateTime at;
  final String? type;
  final String? address;
  final List<int>? bytes; // null = nothing to resend (no printer assigned)

  PrintIssue({
    required this.kind,
    required this.target,
    required this.message,
    required this.at,
    this.type,
    this.address,
    this.bytes,
  });

  bool get canRetry => bytes != null && address != null && type != null;
}

class PrinterModel {
  String name;
  final String address;
  final String type;
  final dynamic device;
  final bool isLikelyPrinter;

  PrinterModel({
    required this.name,
    required this.address,
    required this.type,
    this.device,
    this.isLikelyPrinter = false,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is PrinterModel &&
              runtimeType == other.runtimeType &&
              address == other.address;

  @override
  int get hashCode => address.hashCode;
}

class TokenPrinterAssignment {
  final int tokenPrinterId;
  final RxString printerAddress = "".obs;
  final RxString printerName = "".obs;
  final RxString printerType = "".obs;
  final RxString lastSeen = "".obs;
  final RxBool isOnline = true.obs;

  TokenPrinterAssignment({
    required this.tokenPrinterId,
    String address = "",
    String name = "",
    String type = "",
  }) {
    printerAddress.value = address;
    printerName.value = name;
    printerType.value = type;
  }
}

class PrinterController extends GetxController {
  // ──────────────────────────────────────────────────────────────────────
  // State
  // ──────────────────────────────────────────────────────────────────────
  var bluetoothPrinters = <PrinterModel>[].obs;
  var wifiPrinters = <PrinterModel>[].obs;
  var windowsPrinters = <PrinterModel>[].obs;

  List<PrinterModel> get allPrinters {
    final printers = <PrinterModel>[
      ...bluetoothPrinters,
      ...wifiPrinters,
      ...windowsPrinters,
    ];
    final uniquePrinters = <String, PrinterModel>{};
    for (final printer in printers) {
      uniquePrinters[printer.address] = printer;
    }
    return uniquePrinters.values.toList();
  }

  var scanningBluetooth = false.obs;
  var scanningWifi = false.obs;
  var showOnlyPrinters = false.obs;
  var currentWifiName = "".obs;
  var selectedBluetoothPrinter = Rxn<PrinterModel>();
  var selectedPrinter = Rxn<PrinterModel>();
  var selectedWifiPrinter = Rxn<PrinterModel>();
  var isCheckingConnection = false.obs;
  var isBluetoothPermissionGranted = true.obs;
  var tokenPrinterAssignments = <TokenPrinterAssignment>[].obs;
  final receiptPrinter = Rxn<TokenPrinterAssignment>();
  final printIssues = <String, List<PrintIssue>>{}.obs;
  final isRetryingPrint = false.obs;

  final NetworkInfo _networkInfo = NetworkInfo();

  List<PrinterModel> get filteredBluetoothDevices {
    if (!showOnlyPrinters.value) return bluetoothPrinters;
    return bluetoothPrinters.where((d) => d.isLikelyPrinter).toList();
  }

  String? _btConnectedAddress;
  String _btError = "";

  /// KOT de-duplication (must live on the class, not inside printKOT).
  final Map<String, DateTime> _lastKotPrint = {};

  /// Serialises every Bluetooth print so two jobs never interleave on the
  /// single RFCOMM connection.
  Future<void> _btChain = Future.value();

  // Paper width. 80mm = 48 cols (default), 58mm = 32 cols.
  // Set DB setting 'receipt_paper_width' to '58' for 58mm printers.
  PaperSize _paperSize = PaperSize.mm80;
  int _cols = 48;
  String get _hr => '-' * _cols;
  String get _dbl => '=' * _cols;

  // ──────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ──────────────────────────────────────────────────────────────────────
  @override
  void onInit() {
    super.onInit();

    _initWifi();
    _loadPaperSetting();
    _loadSavedMappings();
    _loadReceiptPrinter();
    checkPermissions().then((granted) {
      if (granted) {
        scanBluetoothPrinters();
        scanWifiPrinters();
        scanWindowsPrinters();
      }
    });
  }

  @override
  void onClose() {
    super.onClose();
  }

  bool hasPrintIssue(String orderId) =>
      printIssues[orderId]?.isNotEmpty ?? false;

  void _addIssue(String orderId, PrintIssue issue) {
    final list = [...(printIssues[orderId] ?? <PrintIssue>[])];
    if (issue.kind == 'RECEIPT') list.removeWhere((i) => i.kind == 'RECEIPT');
    list.add(issue);
    printIssues[orderId] = list;
  }

  void _dropKind(String orderId, String kind) {
    final list = (printIssues[orderId] ?? <PrintIssue>[])
        .where((i) => i.kind != kind)
        .toList();
    if (list.isEmpty) {
      printIssues.remove(orderId);
    } else {
      printIssues[orderId] = list;
    }
  }

  void clearPrintIssues(String orderId) => printIssues.remove(orderId);

  /// Empty list = everything printed.
  Future<List<({String target, String error})>> retryPrintIssues(
      String orderId) async {
    isRetryingPrint.value = true;
    final failures = <({String target, String error})>[];
    try {
      final remaining = <PrintIssue>[];
      for (final i in List.of(printIssues[orderId] ?? <PrintIssue>[])) {
        if (!i.canRetry) {
          remaining.add(i);
          continue;
        }
        final r = await _sendBytesDetailed(
          type: i.type!,
          address: i.address!,
          bytes: i.bytes!,
          tag: 'RETRY ${i.kind}',
        );
        if (!r.ok) {
          failures.add((target: i.target, error: r.error));
          // keep the latest reason on the issue itself
          remaining.add(PrintIssue(
            kind: i.kind,
            target: i.target,
            message: "${i.target}: ${r.error}",
            at: DateTime.now(),
            type: i.type,
            address: i.address,
            bytes: i.bytes,
          ));
        }
      }
      if (remaining.isEmpty) {
        printIssues.remove(orderId);
      } else {
        printIssues[orderId] = remaining;
      }
    } finally {
      isRetryingPrint.value = false;
    }
    return failures;
  }

  void _trackJob({
    required String orderId,
    required String kind,
    required bool ok,
    required String type,
    required String address,
    required String name,
    required List<int> bytes,
    bool clearOnSuccess = false,
  }) {
    if (ok) {
      if (clearOnSuccess) _dropKind(orderId, kind);
      return;
    }
    final target = name.isNotEmpty ? name : address;
    _addIssue(
      orderId,
      PrintIssue(
        kind: kind,
        target: target,
        message: "Could not reach $target",
        at: DateTime.now(),
        type: type,
        address: address,
        bytes: bytes,
      ),
    );
  }

  Future<void> _loadPaperSetting() async {
    try {
      final v = await DatabaseHelper.instance.getSetting('receipt_paper_width');
      if (v == '58') {
        _paperSize = PaperSize.mm58;
        _cols = 32;
      } else {
        _paperSize = PaperSize.mm80;
        _cols = 48;
      }
    } catch (_) {}
  }

  Future<void> _initWifi() async {
    try {
      String? wifiName = await _networkInfo.getWifiName();
      currentWifiName.value = wifiName ?? "WiFi";
    } catch (e) {
      debugPrint("Error getting WiFi name: $e");
    }
  }

  // ──────────────────────────────────────────────────────────────────────
  // Permissions
  // ──────────────────────────────────────────────────────────────────────
  Future<bool> checkPermissions() async {
    if (!Platform.isAndroid) return true;
    final scan = await Permission.bluetoothScan.isGranted;
    final connect = await Permission.bluetoothConnect.isGranted;
    isBluetoothPermissionGranted.value = scan && connect;
    return isBluetoothPermissionGranted.value;
  }

  Future<void> requestBluetoothPermissions() async {
    if (!Platform.isAndroid) return;

    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    bool granted = (statuses[Permission.bluetoothScan]?.isGranted ?? false) &&
        (statuses[Permission.bluetoothConnect]?.isGranted ?? false);

    isBluetoothPermissionGranted.value = granted;

    if (granted) {
      scanBluetoothPrinters();
    } else {
      if (statuses[Permission.bluetoothScan]?.isPermanentlyDenied ?? false) {
        Get.defaultDialog(
          title: "Permissions Required",
          middleText:
          "Bluetooth permissions are required to scan for printers. Please enable them in app settings.",
          confirm: TextButton(
            onPressed: () => openAppSettings(),
            child: const Text("Settings"),
          ),
          cancel: TextButton(
            onPressed: () => Get.back(),
            child: const Text("Cancel"),
          ),
        );
      }
    }
  }

  // ──────────────────────────────────────────────────────────────────────
  // Bluetooth connection
  // ──────────────────────────────────────────────────────────────────────
  Future<bool> ensureBluetoothConnected(String address,
      {int retries = 2}) async {
    _btError = "";
    try {
      final connected = await PrintBluetoothThermal.connectionStatus;
      if (connected && _btConnectedAddress == address) return true;
      if (connected) await PrintBluetoothThermal.disconnect;
      _btConnectedAddress = null;

      // Only Android uses MAC bonding. macOS/iOS use a CoreBluetooth UUID.
      if (Platform.isAndroid) {
        final paired = await PrintBluetoothThermal.pairedBluetooths;
        final isPaired = paired.any(
              (d) => d.macAdress.toUpperCase() == address.toUpperCase(),
        );
        if (!isPaired) {
          _btError = "Pair this printer in Android Bluetooth settings first.";
          return false;
        }
      }

      for (var i = 0; i < retries; i++) {
        final ok =
        await PrintBluetoothThermal.connect(macPrinterAddress: address);
        if (ok) {
          _btConnectedAddress = address;
          return true;
        }
        await Future.delayed(const Duration(milliseconds: 800));
      }
      _btError = "Connect failed for $address";
      return false;
    } catch (e) {
      _btError = "$e";
      debugPrint("BT ensure connect error: $e");
      _btConnectedAddress = null;
      return false;
    }
  }

  /// Runs [action] only after every previously queued Bluetooth job finished.
  Future<T> _withBtLock<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    final prev = _btChain;
    _btChain = completer.future.then((_) {}, onError: (_) {});
    prev.then((_) async {
      try {
        completer.complete(await action());
      } catch (e, s) {
        completer.completeError(e, s);
      }
    });
    return completer.future;
  }

  // ──────────────────────────────────────────────────────────────────────
  // Printer selection / lookup
  // ──────────────────────────────────────────────────────────────────────
  PrinterModel? getPrinterByAddress(String address) {
    return allPrinters.firstWhereOrNull(
          (printer) => printer.address == address,
    );
  }

  void selectPrinter(PrinterModel? printer) {
    selectedPrinter.value = printer;

    if (printer == null) {
      selectedBluetoothPrinter.value = null;
      selectedWifiPrinter.value = null;
      return;
    }

    if (printer.type == "bluetooth") {
      selectedBluetoothPrinter.value = printer;
      selectedWifiPrinter.value = null;
    } else if (printer.type == "wifi") {
      selectedWifiPrinter.value = printer;
      selectedBluetoothPrinter.value = null;
    }
  }

  Future<void> _loadSavedMappings() async {
    final savedMappings =
    await DatabaseHelper.instance.getAllTokenPrinterAssignments();

    tokenPrinterAssignments.assignAll(
      savedMappings.map(
            (m) => TokenPrinterAssignment(
          tokenPrinterId: (m['token_printer_id'] as num).toInt(),
          address: (m['printer_address'] ?? '').toString(),
          name: (m['printer_name'] ?? '').toString(),
          type: (m['printer_type'] ?? '').toString(),
        ),
      ),
    );

    if (Get.isRegistered<DashboardController>()) {
      final dashboardController = Get.find<DashboardController>();
      await dashboardController.fetchAllCategoriesForPrinters();

      final legacyMappings =
      await DatabaseHelper.instance.getAllCategoryPrinters();
      for (var mapping in legacyMappings) {
        final category = dashboardController.allCategoriesForPrinters
            .firstWhereOrNull((c) => c.id == mapping['category_id']);
        if (category != null) {
          category.printerAddress.value =
              (mapping['printer_address'] ?? '').toString();
        }
      }
    }
  }

  // ──────────────────────────────────────────────────────────────────────
  // Invoice / order helpers
  // ──────────────────────────────────────────────────────────────────────
  Future<String> _resolveInvoiceLabel(OrderModel order) async {
    // Prefer the real branch invoice number (host-assigned, e.g. "M-MPM0007")
    // — this is exactly what the Orders page displays, so print must match it.
    if (order.branchInv != null &&
        order.branchInv!.isNotEmpty &&
        order.branchInv != "null") {
      return order.branchInv!;
    }

    final branch = AppState.branchDisName.isNotEmpty
        ? AppState.branchDisName
        : AppState.branchName;
    final existingSeq = await DatabaseHelper.instance.getOfflineSeqForOrder(
      order.id,
    );
    if (existingSeq != null) {
      return "$branch ${existingSeq.toString().padLeft(3, '0')}";
    }
    if (order.invNo.isNotEmpty &&
        order.invNo != "LOCAL" &&
        order.invNo != "OFFLINE") {
      return order.invNo.toString();
    }
    final seq = await DatabaseHelper.instance.assignOfflineSeqForOrder(
      order.id,
    );
    return "$branch ${seq.toString().padLeft(3, '0')}";
  }

  Map<String, double> _splitTaxShare(OrderModel order, double splitAmount) {
    final double orderCgst =
    order.totalCgst > 0 ? order.totalCgst : (order.totalTax / 2);
    final double orderSgst =
    order.totalSgst > 0 ? order.totalSgst : (order.totalTax / 2);
    final double denom = order.finalTotal > 0 ? order.finalTotal : 1;
    final double ratio = (splitAmount / denom).clamp(0, 1);
    return {"cgst": orderCgst * ratio, "sgst": orderSgst * ratio};
  }

  String _tokenLabel(OrderModel order, String fallback) {
    final t = order.tokenNo?.trim() ?? '';
    return (t.isNotEmpty && t != 'null' && t != '0')
        ? t.toUpperCase()
        : fallback;
  }

  String? _receiptToken(OrderModel order) {
    final t = order.tokenNo?.trim() ?? '';
    return (t.isEmpty || t == 'null' || t == '0') ? null : t.toUpperCase();
  }

  // Single place that decides the order type for every print job.
  // NOTE: still reads the UI-selected type (same behaviour as before).
  // If you later trust order.sales_odr_order_type in all flows, change
  // ONLY this method.
  int? _orderTypeId(OrderModel order) {
    final v = GetStorage().read('selected_order_type_id');
    return v is int ? v : null;
  }

  String _orderTypeLabel(OrderModel order) {
    switch (_orderTypeId(order)) {
      case 0:
        return 'Dine In';
      case 1:
        return 'Delivery';
      case 2:
        return 'Pick Up';
      default:
        return '';
    }
  }

  bool _isDineIn(OrderModel order) => _orderTypeId(order) == 0;

  String _fmtPct(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  // ──────────────────────────────────────────────────────────────────────
  // Token printer routing
  // ──────────────────────────────────────────────────────────────────────
  int? _resolveTokenIdForProduct(FoodItemModel p) {
    if ((p.tokenPrinterId ?? 0) > 0) return p.tokenPrinterId;
    if (Get.isRegistered<DashboardController>()) {
      final cat = Get.find<DashboardController>()
          .allCategoriesForPrinters
          .firstWhereOrNull((c) => c.id.toString() == p.categoryId.toString());
      if (cat != null && cat.tokenPrinterId != 0) return cat.tokenPrinterId;
    }
    return tokenPrinterAssignments
        .firstWhereOrNull((a) => a.printerAddress.value.isNotEmpty)
        ?.tokenPrinterId;
  }

  int? _resolveTokenPrinterId(OrderItem item) {
    log(
      "🖨️ RESOLVE DEBUG START: product=${item.product.name} "
          "prdId=${item.product.id} categoryId=${item.product.categoryId} "
          "item.tokenPrinterId=${item.tokenPrinterId} "
          "item.product.tokenPrinterId=${item.product.tokenPrinterId}",
    );

    if (item.tokenPrinterId != null && item.tokenPrinterId! > 0) {
      log("🖨️ RESOLVE DEBUG → step1 matched: ${item.tokenPrinterId}");
      return item.tokenPrinterId;
    }

    if (item.product.tokenPrinterId != null &&
        item.product.tokenPrinterId! > 0) {
      log("🖨️ RESOLVE DEBUG → step2 matched: ${item.product.tokenPrinterId}");
      return item.product.tokenPrinterId;
    }

    if (!Get.isRegistered<DashboardController>()) {
      log("🖨️ RESOLVE DEBUG → DashboardController not registered");
      return null;
    }
    final dash = Get.find<DashboardController>();

    final cat = dash.allCategoriesForPrinters.firstWhereOrNull(
          (c) => c.id.toString() == item.product.categoryId.toString(),
    );
    log(
      "🖨️ RESOLVE DEBUG → step3 category: found=${cat != null} "
          "catId=${cat?.id} catTokenPrinterId=${cat?.tokenPrinterId} "
          "count=${dash.allCategoriesForPrinters.length}",
    );
    if (cat != null && cat.tokenPrinterId != 0) return cat.tokenPrinterId;

    // Last resort: first assigned printer. This can send an item to the
    // wrong kitchen, so make sure every category has a token printer.
    final firstAssigned = tokenPrinterAssignments.firstWhereOrNull(
          (a) => a.printerAddress.value.isNotEmpty,
    );
    log(
      "🖨️ RESOLVE DEBUG → step4 fallback: found=${firstAssigned != null} "
          "tokenPrinterId=${firstAssigned?.tokenPrinterId}",
    );
    return firstAssigned?.tokenPrinterId;
  }

  /// Returns problems. Empty list = all printers reachable.
  Future<List<String>> getUnreachablePrinters(
      List<FoodItemModel> products) async {
    final tokenIds = <int>{};
    for (final p in products) {
      final id = _resolveTokenIdForProduct(p);
      if (id != null && id != 0) tokenIds.add(id);
    }

    final problems = <String>[];
    final checked = <String, bool>{}; // address -> result, avoid double connect

    for (final id in tokenIds) {
      final a = tokenPrinterAssignments
          .firstWhereOrNull((a) => a.tokenPrinterId == id);
      if (a == null || a.printerAddress.value.isEmpty) {
        problems.add("Token Printer $id (not assigned)");
        continue;
      }
      final addr = a.printerAddress.value;
      final ok = checked[addr] ??= await checkPrinterConnection(PrinterModel(
        name: a.printerName.value,
        address: addr,
        type: a.printerType.value,
      ));
      if (!ok) {
        problems.add(a.printerName.value.isNotEmpty ? a.printerName.value : addr);
      }
    }
    return problems;
  }

  Future<bool> checkPrinterConnection(PrinterModel printer) async {
    isCheckingConnection.value = true;
    bool isConnected = false;
    try {
      if (printer.type == 'wifi') {
        try {
          final socket = await Socket.connect(
            printer.address,
            9100,
            timeout: const Duration(seconds: 3),
          );
          socket.destroy();
          isConnected = true;
        } catch (_) {
          isConnected = false;
        }
      } else if (printer.type == 'windows') {
        // Windows printers are installed in the OS; if it was listed, it exists.
        isConnected = windowsPrinters.any((p) => p.address == printer.address);
      } else {
        isConnected = await _withBtLock(
                () => ensureBluetoothConnected(printer.address));
      }
    } catch (e) {
      debugPrint("Connection check error: $e");
      isConnected = false;
    } finally {
      isCheckingConnection.value = false;
    }
    return isConnected;
  }

  Future<({bool saved, bool connected, String message})> updateTokenPrinter(
      int tokenPrinterId,
      PrinterModel printer,
      ) async {
    selectPrinter(printer);

    if (printer.type == 'bluetooth' && Platform.isAndroid) {
      try {
        final paired = await PrintBluetoothThermal.pairedBluetooths;
        final isPaired = paired.any(
              (d) => d.macAdress.toUpperCase() == printer.address.toUpperCase(),
        );
        if (!isPaired) {
          return (
          saved: false,
          connected: false,
          message: "Pair ${printer.name} in Android Bluetooth settings first.",
          );
        }
      } catch (e) {
        debugPrint("Paired check error: $e");
        return (
        saved: false,
        connected: false,
        message: "Could not read paired Bluetooth devices.",
        );
      }
    }

    final bool isConnected = await checkPrinterConnection(printer);
    if (!isConnected) {
      final reason = (printer.type == 'bluetooth' && _btError.isNotEmpty)
          ? _btError
          : "Turn the printer on, keep it in range, and try again.";
      return (
      saved: false,
      connected: false,
      message: "Could not connect to ${printer.name}. $reason",
      );
    }

    var assignment = tokenPrinterAssignments.firstWhereOrNull(
          (a) => a.tokenPrinterId == tokenPrinterId,
    );

    if (assignment == null) {
      assignment = TokenPrinterAssignment(tokenPrinterId: tokenPrinterId);
      tokenPrinterAssignments.add(assignment);
    }

    assignment.printerAddress.value = printer.address;
    assignment.printerName.value = printer.name;
    assignment.printerType.value = printer.type;

    await DatabaseHelper.instance.saveTokenPrinterAssignment(
      tokenPrinterId,
      printer.address,
      printer.name,
      printer.type,
    );

    // Keep category -> printer mapping in sync
    if (Get.isRegistered<DashboardController>()) {
      final dashboardController = Get.find<DashboardController>();
      for (var cat in dashboardController.allCategoriesForPrinters) {
        if (cat.tokenPrinterId == tokenPrinterId) {
          cat.printerAddress.value = printer.address;
        }
      }
    }

    return (
    saved: true,
    connected: true,
    message:
    "Token Printer $tokenPrinterId linked to ${printer.name} (${printer.type})",
    );
  }

  Future<void> removeTokenPrinterAssignment(int tokenPrinterId) async {
    tokenPrinterAssignments.removeWhere(
          (a) => a.tokenPrinterId == tokenPrinterId,
    );
    await DatabaseHelper.instance.deleteTokenPrinterAssignment(tokenPrinterId);

    if (Get.isRegistered<DashboardController>()) {
      final dashboardController = Get.find<DashboardController>();
      for (var cat in dashboardController.allCategoriesForPrinters) {
        if (cat.tokenPrinterId == tokenPrinterId) {
          cat.printerAddress.value = "";
        }
      }
    }
  }

  // ──────────────────────────────────────────────────────────────────────
  // Scanning
  // ──────────────────────────────────────────────────────────────────────
  Future<void> refreshPrinters() async {
    bluetoothPrinters.clear();
    wifiPrinters.clear();
    windowsPrinters.clear();

    await _initWifi();

    await scanBluetoothPrinters();
    await scanWifiPrinters();
    await scanWindowsPrinters();
  }

  Future<void> scanBluetoothPrinters() async {
    if (scanningBluetooth.value) return;

    if (Platform.isAndroid || Platform.isIOS) {
      if (!await checkPermissions()) {
        await requestBluetoothPermissions();
        return;
      }
    }

    scanningBluetooth.value = true;
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        if (await FlutterBluePlus.adapterState.first !=
            BluetoothAdapterState.on) {
          showSafeSnackbar("Bluetooth Off", "Please enable Bluetooth");
          return;
        }
      }

      // Only bonded devices can be printed to via RFCOMM
      final paired = await PrintBluetoothThermal.pairedBluetooths;
      bluetoothPrinters.assignAll(
        paired.map((d) => PrinterModel(
          name: d.name,
          address: d.macAdress,
          type: "bluetooth",
          isLikelyPrinter: _checkIfPrinter(d.name),
        )),
      );
    } catch (e) {
      debugPrint("❌ Bluetooth Scan Error: $e");
    } finally {
      scanningBluetooth.value = false;
    }
  }

  bool _checkIfPrinter(String name) {
    if (name.isEmpty) return false;
    final n = name.toLowerCase();
    return n.contains("printer") ||
        n.contains("pos") ||
        n.contains("thermal") ||
        n.contains("tm-") ||
        n.contains("mpt") ||
        n.contains("rd-") ||
        n.contains("innerprinter") ||
        n.contains("bluetooth") ||
        n.contains("58") ||
        n.contains("80");
  }

  Future<void> scanWindowsPrinters() async {
    if (!Platform.isWindows) return;

    try {
      debugPrint("🖨️ Scanning Windows printers...");
      final printers = await WindowsPrinter.getAvailablePrinters();
      final List<PrinterModel> foundPrinters = [];

      for (final printerName in printers) {
        final name = printerName.trim();
        if (name.isEmpty) continue;

        if (!foundPrinters.any((p) => p.address == name)) {
          foundPrinters.add(PrinterModel(
            name: name,
            address: name,
            type: "windows",
            isLikelyPrinter: _checkIfPrinter(name),
          ));
        }
      }

      windowsPrinters.assignAll(foundPrinters);
      debugPrint("🖨️ Windows printers found: ${windowsPrinters.length}");
    } catch (e) {
      debugPrint("❌ Windows printer scan error: $e");
    }
  }

  Future<void> scanWifiPrinters() async {
    if (scanningWifi.value) return;
    debugPrint("🔍 Starting WiFi scan...");
    scanningWifi.value = true;
    final List<PrinterModel> foundPrinters = [];
    try {
      String? ip = await _getLocalIPv4();
      debugPrint("📡 Device IP: $ip");

      if (ip == null || ip.isEmpty || ip == "0.0.0.0") {
        debugPrint(
          "⚠️ No WiFi IP found. Device might not be connected to WiFi or Location is OFF.",
        );
        return;
      }

      final String subnet = ip.substring(0, ip.lastIndexOf('.'));
      final List<int> printerPorts = [9100, 515, 631, 80, 8008, 8009];
      const int batchSize = 20;
      for (int i = 1; i < 255; i += batchSize) {
        final List<Future> batch = [];
        for (int j = i; j < i + batchSize && j < 255; j++) {
          final targetIp = "$subnet.$j";
          for (int port in printerPorts) {
            batch.add(_checkIp(targetIp, port, foundPrinters));
          }
        }
        await Future.wait(batch);
      }
      wifiPrinters.assignAll(foundPrinters);
      debugPrint("📍 WiFi scan complete. Found: ${foundPrinters.length}");
    } catch (e) {
      debugPrint("❌ WiFi Scan Error: $e");
    } finally {
      scanningWifi.value = false;
    }
  }

  Future<String?> _getLocalIPv4() async {
    try {
      final ip = await _networkInfo.getWifiIP();
      if (ip != null && ip.isNotEmpty && ip != "0.0.0.0") return ip;
    } catch (_) {}

    try {
      final ifaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final i in ifaces) {
        for (final a in i.addresses) {
          final ip = a.address;
          final isPrivate = ip.startsWith('192.168.') ||
              ip.startsWith('10.') ||
              RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(ip);
          if (isPrivate) return ip;
        }
      }
    } catch (e) {
      debugPrint("NetworkInterface error: $e");
    }
    return null;
  }

  Future<void> _checkIp(
      String ip,
      int port,
      List<PrinterModel> foundPrinters,
      ) async {
    try {
      final socket = await Socket.connect(
        ip,
        port,
        timeout: const Duration(milliseconds: 1500),
      );
      socket.destroy();

      final isPrinterPort =
          port == 9100 || port == 515 || port == 8008 || port == 8009;
      final printer = PrinterModel(
        name: isPrinterPort ? "Printer ($ip)" : "Device ($ip)",
        address: ip,
        type: "wifi",
        isLikelyPrinter: isPrinterPort,
      );

      // If a non-printer port answered first, upgrade it when a printer
      // port answers later (otherwise real printers vanish under
      // "show only printers").
      final idx = foundPrinters.indexWhere((p) => p.address == ip);
      if (idx == -1) {
        foundPrinters.add(printer);
        debugPrint("✅ Found potential printer at $ip:$port");
      } else if (isPrinterPort && !foundPrinters[idx].isLikelyPrinter) {
        foundPrinters[idx] = printer;
      }
    } catch (_) {}
  }

  void addManualWifiPrinter(String ip) {
    final newPrinter = PrinterModel(
      name: "Manual Printer ($ip)",
      address: ip,
      type: "wifi",
      isLikelyPrinter: true,
    );
    if (!wifiPrinters.any((p) => p.address == newPrinter.address)) {
      wifiPrinters.add(newPrinter);
    }
    selectedWifiPrinter.value = newPrinter;
  }

  void stopScan() {
    if (Platform.isAndroid || Platform.isIOS) {
      FlutterBluePlus.stopScan();
    }
    scanningBluetooth.value = false;
    scanningWifi.value = false;
  }

  // ──────────────────────────────────────────────────────────────────────
  // Hub sync
  // ──────────────────────────────────────────────────────────────────────
  Future<void> syncPrinterAssignmentsFromHub() async {
    if (!(DeviceConfig.isLocal && DeviceConfig.role == DeviceRole.client)) {
      return;
    }
    final hostIp = DeviceConfig.hostIp;
    if (hostIp == null || hostIp.trim().isEmpty || !DeviceConfig.hasAuthToken) {
      return;
    }

    try {
      final result = await LocalHubClient.instance.fetchPrinterAssignments(
        hostIp: hostIp,
        port: DeviceConfig.hostPort,
      );
      if (result['success'] == true) {
        final List<dynamic> data = result['data'] ?? [];
        await DatabaseHelper.instance.mergeTokenPrinterAssignments(
          data.cast<Map<String, dynamic>>(),
        );
        await _loadSavedMappings(); // refresh in-memory Rx list from the DB
        debugPrint(
            "✅ Printer assignments synced from hub (${data.length} entries)");
      }
    } catch (e) {
      debugPrint("Printer assignment sync from hub failed: $e");
    }
  }

  // ──────────────────────────────────────────────────────────────────────
  // Receipt printer setting
  // ──────────────────────────────────────────────────────────────────────
  Future<void> _loadReceiptPrinter() async {
    final db = DatabaseHelper.instance;
    final addr = await db.getSetting('receipt_printer_address') ?? '';
    if (addr.isEmpty) return;
    receiptPrinter.value = TokenPrinterAssignment(
      tokenPrinterId: -1,
      address: addr,
      name: await db.getSetting('receipt_printer_name') ?? '',
      type: await db.getSetting('receipt_printer_type') ?? 'bluetooth',
    );
  }

  Future<({bool saved, String message})> setReceiptPrinter(
      PrinterModel p) async {
    final ok = await checkPrinterConnection(p);
    if (!ok) {
      return (saved: false, message: "Could not connect to ${p.name}.");
    }
    final db = DatabaseHelper.instance;
    await db.saveSetting('receipt_printer_address', p.address);
    await db.saveSetting('receipt_printer_name', p.name);
    await db.saveSetting('receipt_printer_type', p.type);
    receiptPrinter.value = TokenPrinterAssignment(
      tokenPrinterId: -1,
      address: p.address,
      name: p.name,
      type: p.type,
    );
    return (saved: true, message: "Receipt printer set to ${p.name}");
  }

  Future<void> clearReceiptPrinter() async {
    final db = DatabaseHelper.instance;
    await db.saveSetting('receipt_printer_address', '');
    await db.saveSetting('receipt_printer_name', '');
    await db.saveSetting('receipt_printer_type', '');
    receiptPrinter.value = null;
  }

  /// Explicit receipt printer, else the first token printer that actually
  /// has an address.
  TokenPrinterAssignment? _receiptAssignment() {
    final explicit = receiptPrinter.value;
    if (explicit != null && explicit.printerAddress.value.isNotEmpty) {
      return explicit;
    }
    return tokenPrinterAssignments
        .firstWhereOrNull((a) => a.printerAddress.value.isNotEmpty);
  }

  // ──────────────────────────────────────────────────────────────────────
  // Transport (one path for wifi / windows / bluetooth)
  // ──────────────────────────────────────────────────────────────────────
  Future<bool> _sendBytes({
    required String type,
    required String address,
    required List<int> bytes,
    String tag = 'PRINT',
  }) async =>
      (await _sendBytesDetailed(
          type: type, address: address, bytes: bytes, tag: tag))
          .ok;

  Future<({bool ok, String error})> _sendBytesDetailed({
    required String type,
    required String address,
    required List<int> bytes,
    String tag = 'PRINT',
  }) async {
    try {
      debugPrint("🖨️ [$tag] ${bytes.length} bytes → $type:$address");

      if (type == 'wifi') return await _sendWifi(address, bytes);

      if (type == 'windows') {
        await WindowsPrinter.printRawData(
          printerName: address,
          data: Uint8List.fromList(bytes),
        );
        return (ok: true, error: '');
      }

      // Bluetooth (default)
      return await _withBtLock<({bool ok, String error})>(() async {
        if (!await ensureBluetoothConnected(address)) {
          return (
          ok: false,
          error: _btError.isNotEmpty
              ? _btError
              : "Could not connect to the printer.",
          );
        }
        final ok = await PrintBluetoothThermal.writeBytes(bytes);
        return (
        ok: ok,
        error: ok ? '' : "Connected, but the printer did not accept the data.",
        );
      });
    } catch (e) {
      debugPrint("❌ [$tag] send error: $e");
      return (ok: false, error: "$e");
    }
  }

  Future<({bool ok, String error})> _sendWifi(String ip, List<int> bytes) async {
    Socket? socket;
    try {
      socket = await Socket.connect(
        ip,
        9100,
        timeout: const Duration(seconds: 5),
      );
      socket.add(bytes);
      await socket.flush();
      await Future.delayed(const Duration(milliseconds: 400));
      return (ok: true, error: '');
    } catch (e) {
      debugPrint("WiFi send error ($ip): $e");
      return (ok: false, error: "Could not reach $ip on port 9100.");
    } finally {
      socket?.destroy();
    }
  }

  // ──────────────────────────────────────────────────────────────────────
  // Byte-builder helpers
  // ──────────────────────────────────────────────────────────────────────
  /// Key / value row (value right aligned).
  List<int> _kv(Generator g, String k, String v,
      {int kw = 5, bool bold = false}) {
    return g.row([
      PosColumn(text: k, width: kw),
      PosColumn(
        text: v,
        width: 12 - kw,
        styles: PosStyles(align: PosAlign.right, bold: bold),
      ),
    ]);
  }

  List<int> _headerBytes(Generator g) {
    List<int> b = [];
    b += g.text(
      AppState.branchName,
      styles: const PosStyles(
        align: PosAlign.center,
        height: PosTextSize.size2,
        fontType: PosFontType.fontA,
        bold: false,
      ),
    );
    b += g.text(
      AppState.branchAddress,
      styles: const PosStyles(align: PosAlign.center),
    );
    b += g.text(
      "Ph:${AppState.branchPhNo}",
      styles: const PosStyles(align: PosAlign.center),
    );
    b += g.text(
      "MOB:${AppState.branchMob}",
      styles: const PosStyles(align: PosAlign.center),
    );
    b += g.text(
      AppState.cmpTaxType != 1
          ? "GST No: ${AppState.branchVat}"
          : "VAT No: ${AppState.branchVat}",
      styles: const PosStyles(align: PosAlign.center),
    );
    return b;
  }

  bool get _upiAvailable =>
      AppState.isUpiEnabled &&
          AppState.upiId.isNotEmpty &&
          AppState.cmpTaxType != 1;

  List<int> _upiQrBytes(
      Generator g, {
        required double amount,
        required String note,
      }) {
    final String link = "upi://pay"
        "?pa=${AppState.upiId}"
        "&pn=${Uri.encodeComponent(AppState.branchName)}"
        "&am=${amount.toStringAsFixed(2)}"
        "&cu=INR"
        "&tn=${Uri.encodeComponent(note)}";
    List<int> b = [];
    b += g.qrcode(link, size: QRSize.size5, cor: QRCorrection.L);
    b += g.emptyLines(1);
    return b;
  }

  // ──────────────────────────────────────────────────────────────────────
  // RECEIPT / BILL
  // ──────────────────────────────────────────────────────────────────────
  /// Returns true if the job was sent to the printer.
  /// [received] and [change] are kept for call-site compatibility.
  Future<bool> printReceipt(
      OrderModel order,
      double received,
      double change, {
        bool isBill = false,
        String? customerName,
        String? paymentMethod,
        double? discount,
        double? roundOff,
        bool? isSale,
      }) async {
    debugPrint("--- START ${isBill ? 'BILL' : 'RECEIPT'} PRINTING ---");

    final assignment = _receiptAssignment();
    final address = assignment?.printerAddress.value ?? "";
    if (assignment == null || address.isEmpty) {
      debugPrint("No printer assigned for receipt.");
      return false;
    }
    final type = assignment.printerType.value.isEmpty
        ? 'bluetooth'
        : assignment.printerType.value;

    final String finalCustomerName =
        customerName ?? order.customerName ?? order.tableName;
    final double finalDiscount = discount ?? order.discount;
    final double finalRoundOff = roundOff ?? order.roundOff;

    final profile = await CapabilityProfile.load();

    // Decide the label ONCE so we never burn an offline sequence number and
    // then overwrite it with a reserved one.
    final bool reserveNumber = isBill &&
        DeviceConfig.isLocal &&
        DeviceConfig.role == DeviceRole.server &&
        order.status.value != OrderStatus.paid;
    // NOTE: make sure reserveInvoiceNumber is idempotent per order,
    // otherwise every bill reprint consumes a new number.
    final String invoiceLabel = reserveNumber
        ? await LocalHubOrderService.instance.reserveInvoiceNumber(order.id)
        : await _resolveInvoiceLabel(order);

    final bool resolvedIsSale =
        isSale ?? (order.status.value == OrderStatus.paid);

    final bytes = _buildReceiptBytes(
      order,
      profile,
      invoiceLabel: invoiceLabel,
      isBill: isBill,
      isSale: resolvedIsSale,
      customerName: finalCustomerName,
      paymentMethod: paymentMethod,
      discount: finalDiscount,
      roundOff: finalRoundOff,
    );

    final ok = await _sendBytes(
      type: type,
      address: address,
      bytes: bytes,
      tag: isBill ? 'BILL' : 'RECEIPT',
    );
    _trackJob(
      orderId: order.id,
      kind: 'RECEIPT',
      ok: ok,
      type: type,
      address: address,
      name: assignment.printerName.value,
      bytes: bytes,
      clearOnSuccess: true,
    );
    return ok;
  }

  List<int> _buildReceiptBytes(
      OrderModel order,
      CapabilityProfile profile, {
        required String invoiceLabel,
        bool isBill = false,
        bool isSale = false,
        String? customerName,
        String? paymentMethod,
        double discount = 0,
        double roundOff = 0,
      }) {
    final dashboardController = Get.find<DashboardController>();
    final int vatType = dashboardController.vatType.value;
    final bool isVatDisabled = vatType == 1;
    final bool isCompliment = paymentMethod?.toLowerCase() == 'compliment';

    final g = Generator(_paperSize, profile);
    List<int> b = [];
    b += g.setGlobalFont(PosFontType.fontA);
    b += _headerBytes(g);
    b += g.text(_hr);

    final String cust = customerName ?? order.customerName ?? "Cash Customer";
    if (cust.trim().isNotEmpty) b += _kv(g, "Customer:", cust);

    b += _kv(g, isSale ? "Inv No:" : "Order No:", invoiceLabel);

    final tok = _receiptToken(order);
    if (tok != null) b += _kv(g, "Token No:", tok);

    if (order.captainName != null && order.captainName!.isNotEmpty) {
      b += _kv(g, "Captain:", order.captainName!);
    }

    b += _kv(g, "Order type:", _orderTypeLabel(order));

    if (!isBill && !isCompliment) {
      b += _kv(g, "Pay type:", paymentMethod ?? "Cash");
    }
    b += _kv(g, "Date:", DateFormat('dd/MM/yyyy').format(order.createdAt));
    b += _kv(g, "Time:", DateFormat('HH:mm:ss').format(order.createdAt));
    if (_isDineIn(order)) b += _kv(g, "Table:", order.tableName);

    b += g.text(_hr);

    // Column titles
    b += g.row([
      PosColumn(text: "Item", width: 6),
      PosColumn(text: "Qty", width: 1),
      PosColumn(
        text: "Price",
        width: 2,
        styles: const PosStyles(align: PosAlign.right),
      ),
      PosColumn(
        text: "Amount",
        width: 3,
        styles: const PosStyles(align: PosAlign.right),
      ),
    ]);
    b += g.text(_hr);

    double calculatedSubTotal = 0;
    double calculatedTax = 0;
    final Set<double> taxRates = {};

    for (var item in order.items.where((i) => !i.isRemoved)) {
      final double taxPer = item.product.taxPer;
      final double baseQty = item.unit.unitBaseQty.toDouble();
      final double qty = item.quantity.toDouble();
      final double price = order.isUnsynced
          ? item.priceAtOrder.toDouble()
          : item.product.price * (baseQty > 1.0 ? baseQty : 1.0);

      final double lineSubTotal = price * qty;
      final double vatAmount =
      vatType == 1 ? 0.0 : (lineSubTotal * taxPer) / 100;

      taxRates.add(taxPer);
      calculatedSubTotal += lineSubTotal;
      calculatedTax += vatAmount;

      b += g.row([
        PosColumn(text: item.product.name, width: 6),
        PosColumn(text: item.quantity.toString(), width: 1),
        PosColumn(
          text: price.toStringAsFixed(2),
          width: 2,
          styles: const PosStyles(align: PosAlign.right),
        ),
        PosColumn(
          text: lineSubTotal.toStringAsFixed(2),
          width: 3,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);

      for (var addon in item.selectedAddons) {
        final double addonTotal = addon.price * addon.quantity.value;
        calculatedSubTotal += addonTotal;

        if (addon.price > 0) {
          b += g.row([
            PosColumn(text: " + ${addon.name}", width: 7),
            PosColumn(
              text: addon.price.toStringAsFixed(2),
              width: 2,
              styles: const PosStyles(align: PosAlign.right),
            ),
            PosColumn(
              text: addonTotal.toStringAsFixed(2),
              width: 3,
              styles: const PosStyles(align: PosAlign.right),
            ),
          ]);
        }
      }
    }

    final double finalSubTotal =
    (order.subTotal > 0) ? order.subTotal : calculatedSubTotal;
    final double finalVat =
    vatType == 1 ? 0.0 : ((order.totalTax > 0) ? order.totalTax : calculatedTax);

    b += g.text(_hr);
    b += _kv(g, "Sub Total", finalSubTotal.toStringAsFixed(2), kw: 6);

    if (AppState.cmpTaxType == 1) {
      b += _kv(g, "VAT", finalVat.toStringAsFixed(2), kw: 6);
    } else if (!isVatDisabled) {
      final double finalCgst =
      order.totalCgst > 0 ? order.totalCgst : (finalVat / 2);
      final double finalSgst =
      order.totalSgst > 0 ? order.totalSgst : (finalVat / 2);
      // Show a % only when every line has the same rate.
      final String pct =
      taxRates.length == 1 ? "(${_fmtPct(taxRates.first / 2)}%)" : "";
      b += _kv(g, "CGST$pct", finalCgst.toStringAsFixed(2), kw: 6);
      b += _kv(g, "SGST$pct", finalSgst.toStringAsFixed(2), kw: 6);
    }

    if (discount > 0) {
      b += _kv(g, "Discount", "-${discount.toStringAsFixed(2)}", kw: 6);
    }
    if (roundOff != 0) {
      b += _kv(g, "Round Off", roundOff.toStringAsFixed(2), kw: 6);
    }

    final bool isOnlineOrPaid =
        !order.isUnsynced || order.status.value == OrderStatus.paid;

    double netTotal;
    if (isCompliment) {
      netTotal = 0.0;
    } else if (vatType == 0) {
      // Tax-exclusive
      netTotal = (finalSubTotal + finalVat - discount + roundOff)
          .clamp(0, double.infinity)
          .toDouble();
    } else if (isOnlineOrPaid) {
      // Tax-inclusive, discount already baked into totalAmount
      netTotal =
          (order.totalAmount + roundOff).clamp(0, double.infinity).toDouble();
    } else {
      netTotal = (order.totalAmount - discount + roundOff)
          .clamp(0, double.infinity)
          .toDouble();
    }

    b += _kv(g, "NET TOTAL", netTotal.toStringAsFixed(2), kw: 6);
    b += g.text(_hr);

    if (!isCompliment && _upiAvailable) {
      b += _upiQrBytes(g, amount: netTotal, note: invoiceLabel);
    }

    b += g.text(
      "Thank You!",
      styles: const PosStyles(align: PosAlign.center),
    );
    b += g.feed(1);
    b += g.cut();
    return b;
  }

  // ──────────────────────────────────────────────────────────────────────
  // SPLIT RECEIPTS
  // ──────────────────────────────────────────────────────────────────────
  Future<bool> printSplitReceipts(
      OrderModel order,
      List<Map<String, dynamic>> splits,
      int totalSplits, {
        String? customerName,
        String? paymentMethod,
      }) async {
    debugPrint("--- START SPLIT RECEIPT PRINTING ($totalSplits splits) ---");

    final assignment = _receiptAssignment();
    final address = assignment?.printerAddress.value ?? "";
    if (assignment == null || address.isEmpty) {
      debugPrint("No printer assigned for split receipts.");
      return false;
    }
    final type = assignment.printerType.value.isEmpty
        ? 'bluetooth'
        : assignment.printerType.value;

    final profile = await CapabilityProfile.load();
    final invoiceLabel = await _resolveInvoiceLabel(order);

    bool allOk = true;
    for (var split in splits) {
      final int splitNo = split['ps_split_no'] as int;
      final double splitAmount = (split['ps_split_amnt'] as num).toDouble();
      final String splitLabel = "$splitNo/$totalSplits";
      debugPrint("🖨️ Printing split $splitLabel - Amount: $splitAmount");

      final bytes = _buildSplitReceiptBytes(
        order,
        splitLabel,
        splitAmount,
        profile,
        invoiceLabel: invoiceLabel,
        customerName: customerName,
        paymentMethod: paymentMethod,
      );

      final ok = await _sendBytes(
        type: type,
        address: address,
        bytes: bytes,
        tag: 'SPLIT $splitLabel',
      );
      _trackJob(
        orderId: order.id,
        kind: 'RECEIPT',
        ok: ok,
        type: type,
        address: address,
        name: assignment.printerName.value,
        bytes: bytes,
      );
      if (!ok) allOk = false;

      await Future.delayed(const Duration(milliseconds: 500));
    }
    return allOk;
  }

  List<int> _buildSplitReceiptBytes(
      OrderModel order,
      String splitLabel,
      double splitAmount,
      CapabilityProfile profile, {
        required String invoiceLabel,
        String? customerName,
        String? paymentMethod,
      }) {
    final dashboardController = Get.find<DashboardController>();
    final bool isVatDisabled = dashboardController.vatType.value == 1;
    final bool isCompliment = paymentMethod?.toLowerCase() == 'compliment';

    final g = Generator(_paperSize, profile);
    List<int> b = [];
    b += g.setGlobalFont(PosFontType.fontA);
    b += _headerBytes(g);
    b += g.text(
      "SPLIT BILL",
      styles: const PosStyles(align: PosAlign.center, bold: true),
    );
    b += g.text(
      "Bill $splitLabel",
      styles: const PosStyles(align: PosAlign.center, bold: true),
    );
    b += g.text(_hr);

    final String cust = customerName ?? order.customerName ?? "Cash Customer";
    if (cust.trim().isNotEmpty) b += _kv(g, "Customer:", cust);

    b += _kv(g, "Order No:", invoiceLabel, kw: 6);

    final tok = _receiptToken(order);
    if (tok != null) b += _kv(g, "Token No:", tok, kw: 6);

    b += _kv(g, "Order type:", _orderTypeLabel(order));

    if (!isCompliment) {
      b += _kv(g, "Pay type:", paymentMethod ?? "Cash");
    }
    if (_isDineIn(order)) b += _kv(g, "Table:", order.tableName, kw: 6);

    b += _kv(g, "Date:", DateFormat('dd/MM/yyyy').format(order.createdAt));
    b += _kv(g, "Time:", DateFormat('HH:mm:ss').format(order.createdAt));
    b += g.text(_hr);

    for (var item in order.items.where((i) => !i.isRemoved)) {
      b += g.row([
        PosColumn(text: "${item.quantity}x ${item.product.name}", width: 9),
        PosColumn(
          text: (item.priceAtOrder * item.quantity).toStringAsFixed(2),
          width: 3,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);
    }

    b += g.text(_hr);

    if (AppState.cmpTaxType != 1) {
      if (!isVatDisabled) {
        final taxShare = _splitTaxShare(order, splitAmount);
        b += _kv(g, "CGST", taxShare["cgst"]!.toStringAsFixed(2), kw: 6);
        b += _kv(g, "SGST", taxShare["sgst"]!.toStringAsFixed(2), kw: 6);
      }
      b += g.text(_hr);
    }

    b += g.text(
      "SPLIT AMOUNT",
      styles: const PosStyles(align: PosAlign.center, bold: true),
    );
    b += g.row([
      PosColumn(
        text: "Bill $splitLabel",
        width: 6,
        styles: const PosStyles(bold: true),
      ),
      PosColumn(
        text: splitAmount.toStringAsFixed(2),
        width: 6,
        styles: const PosStyles(
          align: PosAlign.right,
          bold: true,
          height: PosTextSize.size2,
        ),
      ),
    ]);
    b += g.text(_hr);

    if (!isCompliment && _upiAvailable) {
      b += _upiQrBytes(g, amount: splitAmount, note: "Split Bill $splitLabel");
    }

    b += g.text(
      "Thank You!",
      styles: const PosStyles(align: PosAlign.center),
    );
    b += g.feed(2);
    b += g.cut();
    return b;
  }

  // ──────────────────────────────────────────────────────────────────────
  // KOT
  // ──────────────────────────────────────────────────────────────────────
  OrderItem _copyItem(OrderItem i, {int? quantity, bool? isRemoved}) {
    return OrderItem(
      subId: i.subId,
      product: i.product,
      unit: i.unit,
      selectedAddons: i.selectedAddons,
      addonParentPrdId: i.addonParentPrdId,
      addonParentUnitId: i.addonParentUnitId,
      unitId: i.unitId,
      tokenPrinterId: i.tokenPrinterId,
      isRemoved: isRemoved ?? i.isRemoved,
      addonSubIdMap: i.addonSubIdMap,
      quantity: quantity ?? i.quantity,
      priceAtOrder: i.priceAtOrder,
      isKotModified: i.isKotModified,
      cgstRate: i.cgstRate,
      sgstRate: i.sgstRate,
      notes: i.notes,
    );
  }

  String _addonSig(List<AddonModel> addons) {
    final parts = addons.map((a) => '${a.prdId}:${a.quantity.value}').toList()
      ..sort();
    return parts.join(',');
  }

  /// product + unit + addon set. Different addon sets = different kitchen
  /// lines, so a changed addon shows as "remove old / add new".
  String _lineKey(OrderItem i) =>
      '${i.product.id}_${i.unitId ?? i.unit.unitId}_${_addonSig(i.selectedAddons)}';

  /// Merges duplicate lines (same key) by summing quantity so none is lost.
  Map<String, OrderItem> _mergeByKey(Iterable<OrderItem> items) {
    final map = <String, OrderItem>{};
    for (final i in items) {
      final k = _lineKey(i);
      final existing = map[k];
      map[k] = existing == null
          ? i
          : _copyItem(existing, quantity: existing.quantity + i.quantity);
    }
    return map;
  }

  Future<void> printKOT(OrderModel order, {List<OrderItem>? oldItems}) async {
    debugPrint("--- START KOT PRINTING ---");

    final List<OrderItem> itemsToPrint = [];
    final bool isUpdate = oldItems != null && oldItems.isNotEmpty;

    if (!isUpdate) {
      itemsToPrint.addAll(
        order.items.where((item) => !item.isRemoved && item.quantity > 0),
      );
    } else {
      final oldMap = _mergeByKey(
        oldItems.where((i) => !i.isRemoved && i.quantity > 0),
      );
      final newMap = _mergeByKey(
        order.items.where((i) => !i.isRemoved && i.quantity > 0),
      );

      debugPrint("OLD KEYS: ${oldMap.keys.toList()}");
      debugPrint("NEW KEYS: ${newMap.keys.toList()}");

      for (final key in {...oldMap.keys, ...newMap.keys}) {
        final oldItem = oldMap[key];
        final newItem = newMap[key];

        if (oldItem == null && newItem != null) {
          // Brand new line (also covers changed unit / changed addons)
          itemsToPrint.add(newItem);
          debugPrint("🆕 NEW: ${newItem.product.name} x${newItem.quantity}");
        } else if (newItem == null && oldItem != null) {
          // Line gone entirely (also covers changed unit / changed addons)
          itemsToPrint.add(_copyItem(oldItem, isRemoved: true));
          debugPrint("❌ REMOVED: ${oldItem.product.name} x${oldItem.quantity}");
        } else if (oldItem != null && newItem != null) {
          final int diff = newItem.quantity - oldItem.quantity;

          if (diff > 0) {
            itemsToPrint.add(_copyItem(newItem, quantity: diff));
            debugPrint("⬆️ +$diff ${newItem.product.name}");
          } else if (diff < 0) {
            itemsToPrint.add(
              _copyItem(oldItem, quantity: -diff, isRemoved: true),
            );
            debugPrint("⬇️ ${-diff} removed ${oldItem.product.name}");
          } else if (newItem.notes != oldItem.notes) {
            // Same qty, only the note changed
            itemsToPrint.add(newItem);
            debugPrint("📝 NOTE CHANGED: ${newItem.product.name}");
          }
        }
      }
    }

    if (itemsToPrint.isEmpty) {
      debugPrint("No new items or changes to print.");
      return;
    }

    // Duplicate-call guard (map is a class field so it actually persists)
    final now = DateTime.now();
    _lastKotPrint.removeWhere(
          (_, t) => now.difference(t) > const Duration(minutes: 1),
    );
    final sig = '${order.id}|${order.invNo}|'
        '${itemsToPrint.map((i) => '${i.product.id}:${i.quantity}:${i.isRemoved}').join(',')}';
    final last = _lastKotPrint[sig];
    if (last != null &&
        now.difference(last) < const Duration(seconds: 3)) {
      debugPrint("⚠️ Duplicate KOT call suppressed: $sig");
      return;
    }
    _lastKotPrint[sig] = now;

    debugPrint("📋 Total items to print: ${itemsToPrint.length}");
    await _distributeToPrinters(
      order,
      itemsToPrint,
      status: isUpdate ? "Modified" : "Original",
    );
  }

  Future<void> printCancelledOrder(OrderModel order) async {
    debugPrint("--- PRINTING CANCELLED ORDER ---");
    final cancelledItems =
    order.items.map((i) => _copyItem(i, isRemoved: true)).toList();
    await _distributeToPrinters(order, cancelledItems, status: "CANCELLED");
  }

  Future<void> _distributeToPrinters(
      OrderModel order,
      List<OrderItem> items, {
        required String status,
      }) async {
    debugPrint(
      "📍 DISTRIBUTING - Status: $status, Items: ${items.length}",
    );
    final invoiceLabel = await _resolveInvoiceLabel(order);

    final groups = <String, List<OrderItem>>{};
    final assignmentByAddress = <String, TokenPrinterAssignment>{};
    final unrouted = <String>{};

    for (final item in items) {
      final int? tokenId = _resolveTokenPrinterId(item);
      if (tokenId == null || tokenId == 0) {
        debugPrint("  ⚠️ No token printer ID for item: ${item.product.name}");
        unrouted.add(item.product.name);
        continue;
      }

      final assignment = tokenPrinterAssignments.firstWhereOrNull(
            (a) => a.tokenPrinterId == tokenId,
      );
      final address = assignment?.printerAddress.value ?? "";
      if (assignment == null || address.isEmpty) {
        debugPrint("  ❌ No printer assigned for token $tokenId");
        unrouted.add("${item.product.name} (token $tokenId)");
        continue;
      }

      groups.putIfAbsent(address, () => []).add(item);
      assignmentByAddress[address] = assignment;
    }

    final failedPrinters = <String>[];

    if (groups.isNotEmpty) {
      final profile = await CapabilityProfile.load();

      // Different printers print in parallel; Bluetooth jobs are serialised
      // by the lock inside _sendBytes.
      await Future.wait(groups.entries.map((entry) async {
        final address = entry.key;
        final a = assignmentByAddress[address]!;
        final type =
        a.printerType.value.isEmpty ? 'bluetooth' : a.printerType.value;

        _logKOTData(order, entry.value, status, type, address);

        final bytes = _buildKotBytes(
          order,
          entry.value,
          profile,
          status: status,
          invoiceLabel: invoiceLabel,
        );

        final ok = await _sendBytes(
          type: type,
          address: address,
          bytes: bytes,
          tag: 'KOT',
        );
        if (!ok) {
          failedPrinters.add(
            a.printerName.value.isNotEmpty ? a.printerName.value : address,
          );
          _trackJob(
            orderId: order.id,
            kind: 'KOT',
            ok: false,
            type: type,
            address: address,
            name: a.printerName.value,
            bytes: bytes,
          );
        }
      }));
    }

    if (unrouted.isNotEmpty || failedPrinters.isNotEmpty) {
      if (unrouted.isNotEmpty) {
        _addIssue(
          order.id,
          PrintIssue(
            kind: 'KOT',
            target: unrouted.join(', '),
            message: "No printer assigned for: ${unrouted.join(', ')}",
            at: DateTime.now(),
          ),
        );
      }
      final msg = [
        if (unrouted.isNotEmpty) "No printer for: ${unrouted.join(', ')}",
        if (failedPrinters.isNotEmpty)
          "Failed to print on: ${failedPrinters.join(', ')}",
      ].join('\n');
      showSafeSnackbar("KOT not fully printed", msg);
    }
  }

  List<int> _buildKotBytes(
      OrderModel order,
      List<OrderItem> items,
      CapabilityProfile profile, {
        required String status,
        required String invoiceLabel,
      }) {
    final g = Generator(_paperSize, profile);
    List<int> b = [];

    final removedItems = items.where((i) => i.isRemoved).toList();
    final newItems = items.where((i) => !i.isRemoved).toList();

    b += g.setGlobalFont(PosFontType.fontA);

    // HEADER
    b += g.text(
      "Token No : ${_tokenLabel(order, invoiceLabel)}",
      styles: const PosStyles(
        align: PosAlign.center,
        height: PosTextSize.size2,
        fontType: PosFontType.fontA,
        bold: false,
      ),
    );
    b += g.text(
      "KITCHEN ORDER",
      styles: const PosStyles(align: PosAlign.center),
    );
    b += g.text(_hr);

    // ORDER INFO
    b += _kv(g, "Order No:", invoiceLabel, kw: 6);
    b += _kv(g, "Order type:", _orderTypeLabel(order), kw: 6);

    if (order.captainName != null && order.captainName!.isNotEmpty) {
      b += _kv(g, "Captain:", order.captainName!, kw: 6);
    }
    if (_isDineIn(order)) {
      b += _kv(g, "Table:", "${order.tableName} (${order.chairNumber} Seats)",
          kw: 6);
    }

    void section(List<OrderItem> list, {required bool removed}) {
      if (list.isEmpty) return;

      final String title = removed
          ? (status == "CANCELLED"
          ? "ORDER CANCELLED"
          : "QUANTITY DECREASED / REMOVED")
          : (status == "Modified" ? "QUANTITY INCREASED / NEW" : "ORDER ITEMS");
      final String qtyTitle = removed
          ? (status == "CANCELLED" ? "Qty" : "Qty Removed")
          : (status == "Modified" ? "Qty Added" : "Qty");

      b += g.text(_dbl, styles: const PosStyles(bold: true));
      b += g.text(
        title,
        styles: PosStyles(
          align: PosAlign.center,
          bold: removed,
          height: PosTextSize.size2,
        ),
      );
      b += g.text(_dbl, styles: const PosStyles(bold: true));
      b += g.row([
        PosColumn(
            text: "Item", width: 8, styles: PosStyles(bold: removed)),
        PosColumn(
          text: qtyTitle,
          width: 4,
          styles: PosStyles(align: PosAlign.right, bold: removed),
        ),
      ]);
      b += g.text(_hr);

      for (final item in list) {
        b += g.row([
          PosColumn(
            text: item.product.name,
            width: 8,
            styles: PosStyles(bold: removed),
          ),
          PosColumn(
            text: "${item.quantity} ${item.unit.unitDisplay}",
            width: 4,
            styles: PosStyles(align: PosAlign.right, bold: removed),
          ),
        ]);
        if (item.notes.isNotEmpty) {
          b += g.text(
            "   NOTE: ${item.notes}",
            styles: PosStyles(bold: removed),
          );
        }
        for (final addon in item.selectedAddons) {
          b += g.row([
            PosColumn(
              text: "  ${removed ? '-' : '+'} ${addon.name}",
              width: 8,
            ),
            PosColumn(
              text: "${addon.quantity.value} ${addon.unitDisplay}",
              width: 4,
              styles: const PosStyles(align: PosAlign.right),
            ),
          ]);
        }
      }
    }

    section(removedItems, removed: true);
    section(newItems, removed: false);

    // FOOTER
    b += g.text(_dbl, styles: const PosStyles(bold: true));
    b += g.text(
      "*** Kitchen Copy ***",
      styles: const PosStyles(align: PosAlign.center),
    );
    b += g.feed(2);
    b += g.cut();
    return b;
  }

  void _logKOTData(
      OrderModel order,
      List<OrderItem> items,
      String status,
      String printerType,
      String address,
      ) {
    final buffer = StringBuffer();
    buffer.writeln("🖨️ ===== KOT PRINT START =====");
    buffer.writeln("Printer Type : $printerType");
    buffer.writeln("Printer Addr : $address");
    buffer.writeln("Status       : $status");
    buffer.writeln("Inv No       : ${order.invNo}");
    buffer.writeln("Token No     : ${order.tokenNo}");
    buffer.writeln("Order Type   : ${_orderTypeLabel(order)}");
    if (_isDineIn(order)) {
      buffer.writeln(
        "Table        : ${order.tableName} (${order.chairNumber} Seats)",
      );
    }
    buffer.writeln(
      "Date         : ${DateFormat('dd/MM/yyyy HH:mm:ss').format(order.createdAt)}",
    );
    buffer.writeln("------------------------------------------");

    for (var item in items) {
      final itemName =
      item.isRemoved ? "[REMOVED] ${item.product.name}" : item.product.name;
      buffer.writeln("$itemName  -> ${item.quantity} ${item.unit.unitDisplay}");
      if (item.notes.isNotEmpty) buffer.writeln("   NOTE: ${item.notes}");
      for (var addon in item.selectedAddons) {
        buffer.writeln(
          "   + ${addon.name} -> ${addon.quantity.value} ${addon.unitDisplay}",
        );
      }
    }

    buffer.writeln("------------------------------------------");
    buffer.writeln("🖨️ ===== KOT PRINT END =====");
    debugPrint(buffer.toString());
  }
}