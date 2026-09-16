import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'package:esc_pos_printer_plus/esc_pos_printer_plus.dart';
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
import '../../../data/models/order_model.dart';
import '../../../data/models/order_type.dart';
import '../../../data/services/database_helper.dart';
import '../../../data/utils/AppState.dart';
import '../views/dashoard/models/dashboard_models.dart';
import 'dashboard_controller.dart';

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
  var bluetoothPrinters = <PrinterModel>[].obs;
  var wifiPrinters = <PrinterModel>[].obs;
  var scanningBluetooth = false.obs;
  var scanningWifi = false.obs;
  var showOnlyPrinters = false.obs;
  var currentWifiName = "".obs;
  var selectedBluetoothPrinter = Rxn<PrinterModel>();
  var selectedWifiPrinter = Rxn<PrinterModel>();
  var isCheckingConnection = false.obs;
  var isBluetoothPermissionGranted = true.obs;
  var tokenPrinterAssignments = <TokenPrinterAssignment>[].obs;
  final NetworkInfo _networkInfo = NetworkInfo();
  StreamSubscription? _scanSubscription;
  List<PrinterModel> get filteredBluetoothDevices {
    if (!showOnlyPrinters.value) return bluetoothPrinters;
    return bluetoothPrinters.where((d) => d.isLikelyPrinter).toList();
  }

  // double calculatedCgst = 0;
  // double calculatedSgst = 0;
  @override
  void onInit() {
    super.onInit();
    _initWifi();
    _loadSavedMappings();
    _listenToBleScan();
    checkPermissions().then((granted) {
      if (granted) {
        scanBluetoothPrinters();
        scanWifiPrinters();
      }
    });
  }

  void _listenToBleScan() {
    _scanSubscription = FlutterBluePlus.onScanResults.listen((results) {
      for (ScanResult r in results) {
        String name = r.device.platformName.isNotEmpty
            ? r.device.platformName
            : r.advertisementData.advName;
        if (name.isNotEmpty) {
          final printer = PrinterModel(
            name: name,
            address: r.device.remoteId.str,
            type: "bluetooth",
            device: r.device,
            isLikelyPrinter: _checkIfPrinter(name),
          );
          if (!bluetoothPrinters.any((p) => p.address == printer.address)) {
            bluetoothPrinters.add(printer);
          }
        }
      }
    });
  }

  Future<void> _initWifi() async {
    try {
      String? wifiName = await _networkInfo.getWifiName();
      currentWifiName.value = wifiName ?? "WiFi";
    } catch (e) {
      debugPrint("Error getting WiFi name: $e");
    }
  }

  Future<bool> checkPermissions() async {
    if (!Platform.isAndroid) return true;

    bool scan = await Permission.bluetoothScan.isGranted;
    bool connect = await Permission.bluetoothConnect.isGranted;
    bool location = await Permission.location.isGranted;

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

    bool granted =
        (statuses[Permission.bluetoothScan]?.isGranted ?? false) &&
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

  Future<void> _loadSavedMappings() async {
    final savedMappings = await DatabaseHelper.instance
        .getAllTokenPrinterAssignments();

    tokenPrinterAssignments.assignAll(
      savedMappings.map(
        (m) => TokenPrinterAssignment(
          tokenPrinterId: m['token_printer_id'],
          address: m['printer_address'],
          name: m['printer_name'],
          type: m['printer_type'],
        ),
      ),
    );

    if (Get.isRegistered<DashboardController>()) {
      final dashboardController = Get.find<DashboardController>();
      await dashboardController.fetchAllCategoriesForPrinters();

      final legacyMappings = await DatabaseHelper.instance
          .getAllCategoryPrinters();
      for (var mapping in legacyMappings) {
        final category = dashboardController.allCategoriesForPrinters
            .firstWhereOrNull((c) => c.id == mapping['category_id']);
        if (category != null) {
          category.printerAddress.value = mapping['printer_address'];
        }
      }
    }
  }

  Future<String> _resolveInvoiceLabel(OrderModel order) async {
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
      return order.branchInv.toString();
    }
    final seq = await DatabaseHelper.instance.assignOfflineSeqForOrder(
      order.id,
    );
    return "$branch ${seq.toString().padLeft(3, '0')}";
  }

  Map<String, double> _splitTaxShare(OrderModel order, double splitAmount) {
    final double orderCgst = order.totalCgst > 0
        ? order.totalCgst
        : (order.totalTax / 2);
    final double orderSgst = order.totalSgst > 0
        ? order.totalSgst
        : (order.totalTax / 2);
    final double denom = order.finalTotal > 0 ? order.finalTotal : 1;
    final double ratio = (splitAmount / denom).clamp(0, 1);
    return {"cgst": orderCgst * ratio, "sgst": orderSgst * ratio};
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
      } else {
        isConnected = await PrintBluetoothThermal.connect(
          macPrinterAddress: printer.address,
        );
      }
    } catch (e) {
      debugPrint("Connection check error: $e");
      isConnected = false;
    } finally {
      isCheckingConnection.value = false;
    }
    return isConnected;
  }

  Future<void> updateTokenPrinter(
    int tokenPrinterId,
    PrinterModel printer,
  ) async {
    bool isConnected = await checkPrinterConnection(printer);
    if (!isConnected) {
      showSafeSnackbar(
        "Connection Warning",
        "Could not connect to ${printer.name}. The assignment will be saved, but printing may fail if it remains unreachable.",
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

    if (Get.isRegistered<DashboardController>()) {
      final dashboardController = Get.find<DashboardController>();
      for (var cat in dashboardController.allCategoriesForPrinters) {
        if (cat.tokenPrinterId == tokenPrinterId) {
          cat.printerAddress.value = printer.address;
        }
      }
    }

    if (isConnected) {
      showSafeSnackbar(
        "Saved",
        "Token Printer $tokenPrinterId linked to ${printer.name} (Connected)",
      );
    }
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

  Future<void> refreshPrinters() async {
    bluetoothPrinters.clear();
    wifiPrinters.clear();
    await _initWifi();
    await scanBluetoothPrinters();
    await scanWifiPrinters();
  }

  Future<void> scanBluetoothPrinters() async {
    if (scanningBluetooth.value) return;

    bool hasPermission = await checkPermissions();
    if (!hasPermission) {
      await requestBluetoothPermissions();
      return;
    }

    debugPrint("🔍 Starting Bluetooth scan...");
    scanningBluetooth.value = true;

    try {
      if (await FlutterBluePlus.adapterState.first !=
          BluetoothAdapterState.on) {
        showSafeSnackbar(
          "Bluetooth Off",
          "Please enable Bluetooth",
          // backgroundColor: Colors.orange,
          // colorText: Colors.white,
        );
        scanningBluetooth.value = false;
        return;
      }

      bluetoothPrinters.clear();

      final List<BluetoothInfo> pairedDevices =
          await PrintBluetoothThermal.pairedBluetooths;
      for (var d in pairedDevices) {
        bluetoothPrinters.add(
          PrinterModel(
            name: d.name,
            address: d.macAdress,
            type: "bluetooth",
            isLikelyPrinter: _checkIfPrinter(d.name),
          ),
        );
      }

      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 5),
        androidUsesFineLocation: true,
      );
    } catch (e) {
      debugPrint("❌ Bluetooth Scan Error: $e");
    } finally {
      Future.delayed(const Duration(seconds: 5), () {
        scanningBluetooth.value = false;
      });
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

  Future<void> scanWifiPrinters() async {
    if (scanningWifi.value) return;
    debugPrint("🔍 Starting WiFi scan...");
    scanningWifi.value = true;
    List<PrinterModel> foundPrinters = [];
    try {
      String? ip = await _networkInfo.getWifiIP();
      debugPrint("📡 Device IP: $ip");

      if (ip == null || ip.isEmpty || ip == "0.0.0.0") {
        debugPrint(
          "⚠️ No WiFi IP found. Device might not be connected to WiFi or Location is OFF.",
        );
        scanningWifi.value = false;
        return;
      }

      final String subnet = ip.substring(0, ip.lastIndexOf('.'));
      final List<int> printerPorts = [9100, 515, 631, 80, 8008, 8009];
      const int batchSize = 15;
      for (int i = 1; i < 255; i += batchSize) {
        List<Future> batch = [];
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

  Future<void> _checkIp(
    String ip,
    int port,
    List<PrinterModel> foundPrinters,
  ) async {
    try {
      final socket = await Socket.connect(
        ip,
        port,
        timeout: const Duration(milliseconds: 2000),
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

      if (!foundPrinters.any((p) => p.address == printer.address)) {
        foundPrinters.add(printer);
        debugPrint("✅ Found potential printer at $ip:$port");
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
    FlutterBluePlus.stopScan();
    scanningBluetooth.value = false;
    scanningWifi.value = false;
  }

  Future<void> printReceipt(
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
    final String finalCustomerName =
        customerName ?? order.customerName ?? order.tableName;
    final double finalDiscount = discount ?? order.discount;
    final double finalRoundOff = roundOff ?? order.roundOff;
    final assignment = tokenPrinterAssignments.isNotEmpty
        ? tokenPrinterAssignments.first
        : null;
    final address = assignment?.printerAddress.value ?? "";
    final type = assignment?.printerType.value ?? "bluetooth";

    if (address.isEmpty) {
      debugPrint("No printer assigned for receipt.");
      return;
    }

    final profile = await CapabilityProfile.load();
    final invoiceLabel = await _resolveInvoiceLabel(order);
    final bool resolvedIsSale = isSale ?? (order.status.value == OrderStatus.paid);

    if (type == 'wifi') {
      await _printWifiReceipt(
        address,
        invoiceLabel: invoiceLabel,
        order,
        received,
        change,
        profile,
        isBill: isBill,
        isSale: resolvedIsSale,
        customerName: finalCustomerName,
        paymentMethod: paymentMethod,
        discount: finalDiscount,
        roundOff: finalRoundOff,
      );
    } else {
      final printerInfo = PrinterModel(
        name: assignment!.printerName.value,
        address: address,
        type: 'bluetooth',
      );
      await _printBluetoothReceipt(
        printerInfo,
        order,
        received,
        change,
        profile,
        invoiceLabel: invoiceLabel,
        isBill: isBill,
        isSale: resolvedIsSale,
        customerName: finalCustomerName,
        paymentMethod: paymentMethod,
        discount: finalDiscount,
        roundOff: finalRoundOff,
      );
    }
  }

  Future<void> printSplitReceipts(
    OrderModel order,
    List<Map<String, dynamic>> splits,
    int totalSplits, {
    String? customerName,
    String? paymentMethod,
  }) async {
    debugPrint("--- START SPLIT RECEIPT PRINTING ($totalSplits splits) ---");

    final assignment = tokenPrinterAssignments.isNotEmpty
        ? tokenPrinterAssignments.first
        : null;
    final address = assignment?.printerAddress.value ?? "";
    final type = assignment?.printerType.value ?? "bluetooth";

    if (address.isEmpty) {
      debugPrint("No printer assigned for split receipts.");
      return;
    }

    final profile = await CapabilityProfile.load();
    final invoiceLabel = await _resolveInvoiceLabel(order);

    for (var split in splits) {
      final int splitNo = split['ps_split_no'] as int;
      final double splitAmount = (split['ps_split_amnt'] as num).toDouble();
      final String splitLabel = "$splitNo/$totalSplits";

      debugPrint("🖨️ Printing split $splitLabel - Amount: $splitAmount");

      if (type == 'wifi') {
        await _printWifiSplitReceipt(
          address,
          order,
          split,
          splitLabel,
          splitAmount,
          profile,
          invoiceLabel: invoiceLabel,
          customerName: customerName,
          paymentMethod: paymentMethod,
        );
      } else {
        final printerInfo = PrinterModel(
          name: assignment!.printerName.value,
          address: address,
          type: 'bluetooth',
        );
        await _printBluetoothSplitReceipt(
          printerInfo,
          order,
          split,
          splitLabel,
          splitAmount,
          profile,
          invoiceLabel: invoiceLabel,
          customerName: customerName,
          paymentMethod: paymentMethod,
        );
      }

      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  Future<void> _printWifiSplitReceipt(
    String ip,
    OrderModel order,
    Map<String, dynamic> split,
    String splitLabel,
    double splitAmount,
    CapabilityProfile profile, {
    required String invoiceLabel,
    String? customerName,
    String? paymentMethod,
  }) async {
    try {
      final printer = NetworkPrinter(PaperSize.mm80, profile);
      final res = await printer.connect(ip, port: 9100);
      if (res == PosPrintResult.success) {
        _generateSplitReceiptTicket(
          printer,
          order,
          split,
          splitLabel,
          splitAmount,
          invoiceLabel: invoiceLabel,
          customerName: customerName,
          paymentMethod: paymentMethod,
        );
        await Future.delayed(const Duration(milliseconds: 500));
        printer.disconnect();
      }
    } catch (e) {
      debugPrint("WiFi Split Receipt Error: $e");
    }
  }

  Future<void> _printBluetoothSplitReceipt(
    PrinterModel printer,
    OrderModel order,
    Map<String, dynamic> split,
    String splitLabel,
    double splitAmount,
    CapabilityProfile profile, {
    required String invoiceLabel,
    String? customerName,
    String? paymentMethod,
  }) async {
    try {
      bool connected = await PrintBluetoothThermal.connectionStatus;
      if (!connected) {
        await PrintBluetoothThermal.connect(macPrinterAddress: printer.address);
      }

      final generator = Generator(PaperSize.mm80, profile);
      final dashboardController = Get.find<DashboardController>();
      final isVatDisabled = dashboardController.vatType.value == 1;
      List<int> bytes = [];
      bytes += generator.setGlobalFont(PosFontType.fontA);
      bytes += generator.text(
        AppState.branchName,
        styles: const PosStyles(
          align: PosAlign.center,
          height: PosTextSize.size2,
          fontType: PosFontType.fontA,
          bold: false,
        ),
      );
      bytes += generator.text(
        AppState.branchAddress,
        styles: const PosStyles(align: PosAlign.center),
      );
      bytes += generator.text(
        "Ph:${AppState.branchPhNo}",
        styles: const PosStyles(align: PosAlign.center),
      );
      bytes += generator.text(
        "MOB:${AppState.branchMob}",
        styles: const PosStyles(align: PosAlign.center),
      );
      if (AppState.cmpTaxType != 1) {
        bytes += generator.text(
          "GST No: ${AppState.branchVat}",
          styles: const PosStyles(align: PosAlign.center),
        );
      } else {
        bytes += generator.text(
          "VAT No: ${AppState.branchVat}",
          styles: const PosStyles(align: PosAlign.center),
        );
      }
      bytes += generator.text(
        "SPLIT BILL",
        styles: const PosStyles(align: PosAlign.center, bold: true),
      );
      bytes += generator.text(
        "Bill $splitLabel",
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size1,
          width: PosTextSize.size1,
        ),
      );
      bytes += generator.text('-' * 48);
      final String? effectiveCustomerName = customerName ?? order.customerName ?? "Cash Customer";
      if (effectiveCustomerName != null && effectiveCustomerName.trim().isNotEmpty) {
  bytes += generator.row([
    PosColumn(text: "Customer:", width: 5),
    PosColumn(
      text: effectiveCustomerName,
      width: 7,
      styles: const PosStyles(align: PosAlign.right),
    ),
  ]);
}
      bytes += generator.row([
        PosColumn(text: "Order No:", width: 6),
        PosColumn(
          text: invoiceLabel,
          width: 6,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);
      bytes += generator.row([
        PosColumn(text: "Order type:", width: 5),
        PosColumn(
          // text: OrderType.values
          //     .firstWhere(
          //       (e) => e.id == order.sales_odr_order_type,
          //       orElse: () => OrderType.dineIn,
          //     )
          //     .displayName,
          text: (GetStorage().read('selected_order_type_id') == 0
              ? 'Dine In'
              : GetStorage().read('selected_order_type_id') == 1
              ? 'Delivery'
              : GetStorage().read('selected_order_type_id') == 2
              ? 'Pick Up'
              : ''),
          width: 7,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);
      if (paymentMethod?.toLowerCase() != 'compliment') {
        bytes += generator.row([
          PosColumn(text: "Pay type:", width: 5),
          PosColumn(
            text: paymentMethod ?? "Cash",
            width: 7,
            styles: const PosStyles(align: PosAlign.right),
          ),
        ]);
      }

      if (GetStorage().read('selected_order_type_id') == 0) {
        bytes += generator.row([
          PosColumn(text: "Table:", width: 6),
          PosColumn(
            text: order.tableName,
            width: 6,
            styles: const PosStyles(align: PosAlign.right),
          ),
        ]);
      }
      bytes += generator.row([
        PosColumn(text: "Date:", width: 5),
        PosColumn(
          text: DateFormat('dd/MM/yyyy').format(order.createdAt),
          width: 7,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);
      bytes += generator.row([
        PosColumn(text: "Time:", width: 5),
        PosColumn(
          text: DateFormat('HH:mm:ss').format(order.createdAt),
          width: 7,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);
      bytes += generator.text('-' * 48);

      for (var item in order.items.where((i) => !i.isRemoved)) {
        bytes += generator.row([
          PosColumn(text: "${item.quantity}x ${item.product.name}", width: 9),
          PosColumn(
            text: (item.priceAtOrder * item.quantity).toStringAsFixed(2),
            width: 3,
            styles: const PosStyles(align: PosAlign.right),
          ),
        ]);
      }

      bytes += generator.text('-' * 48);
      final taxShare = _splitTaxShare(order, splitAmount);
      bytes += generator.text('-' * 48);
      if (AppState.cmpTaxType != 1) {
        isVatDisabled
            ? SizedBox.shrink()
            : bytes += generator.row([
                PosColumn(text: "CGST", width: 6),
                PosColumn(
                  text: taxShare["cgst"]!.toStringAsFixed(2),
                  width: 6,
                  styles: const PosStyles(align: PosAlign.right),
                ),
              ]);
        isVatDisabled
            ? SizedBox.shrink()
            : bytes += generator.row([
                PosColumn(text: "SGST", width: 6),
                PosColumn(
                  text: taxShare["sgst"]!.toStringAsFixed(2),
                  width: 6,
                  styles: const PosStyles(align: PosAlign.right),
                ),
              ]);
        bytes += generator.text('-' * 48);
      }
      bytes += generator.text(
        "SPLIT AMOUNT",
        styles: const PosStyles(align: PosAlign.center, bold: true),
      );
      bytes += generator.row([
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

      bytes += generator.text('-' * 48);
      if ((paymentMethod?.toLowerCase() != 'compliment') &&
          AppState.isUpiEnabled &&
          AppState.upiId.isNotEmpty &&
          AppState.cmpTaxType != 1) {

        final String upiLink = "upi://pay"
            "?pa=${AppState.upiId}"
            "&pn=${Uri.encodeComponent(AppState.branchName)}"
            "&am=${splitAmount.toStringAsFixed(2)}"
            "&cu=INR"
            "&tn=${Uri.encodeComponent("Split Bill $splitLabel")}";

        bytes += generator.qrcode(
          upiLink,
          size: QRSize.size5,
          cor: QRCorrection.L,
        );

        bytes += generator.emptyLines(1);
      }

      bytes += generator.text(
        "Thank You!",
        styles: const PosStyles(align: PosAlign.center),
      );
      bytes += generator.feed(2);
      bytes += generator.cut();

      await PrintBluetoothThermal.writeBytes(bytes);
      debugPrint("✅ Split receipt $splitLabel printed successfully");
    } catch (e) {
      debugPrint("BT Split Receipt Error: $e");
    }
  }

  void _generateSplitReceiptTicket(
    NetworkPrinter printer,
    OrderModel order,
    Map<String, dynamic> split,
    String splitLabel,
    double splitAmount, {
    required String invoiceLabel,
    String? customerName,
    String? paymentMethod,
  }) {
    final dashboardController = Get.find<DashboardController>();
    final isVatDisabled = dashboardController.vatType.value == 1;
    printer.text(
      AppState.branchName,
      styles: const PosStyles(
        align: PosAlign.center,
        height: PosTextSize.size2,
        fontType: PosFontType.fontA,
        bold: false,
      ),
    );
    printer.text(
      AppState.branchAddress,
      styles: const PosStyles(align: PosAlign.center),
    );
    printer.text(
      "Ph:${AppState.branchPhNo}",
      styles: const PosStyles(align: PosAlign.center),
    );
    printer.text(
      "MOB:${AppState.branchMob}",
      styles: const PosStyles(align: PosAlign.center),
    );
    if (AppState.cmpTaxType != 1) {
      printer.text(
        "GST No: ${AppState.branchVat}",
        styles: const PosStyles(align: PosAlign.center),
      );
    } else {
      printer.text(
        "VAT No: ${AppState.branchVat}",
        styles: const PosStyles(align: PosAlign.center),
      );
    }
    printer.text(
      "SPLIT BILL",
      styles: const PosStyles(align: PosAlign.center, bold: true),
    );
    printer.text(
      "Bill $splitLabel",
      styles: const PosStyles(
        align: PosAlign.center,
        bold: true,
        height: PosTextSize.size2,
      ),
    );
    printer.hr();
    final String? effectiveCustomerName = customerName ?? order.customerName ?? "Cash Customer";
if (effectiveCustomerName != null && effectiveCustomerName.trim().isNotEmpty) {
  printer.row([
    PosColumn(text: "Customer:", width: 5),
    PosColumn(
      text: effectiveCustomerName,
      width: 7,
      styles: const PosStyles(align: PosAlign.right),
    ),
  ]);
}
    printer.row([
      PosColumn(text: "Order No:", width: 6),
      PosColumn(
        text: invoiceLabel,
        width: 6,
        styles: const PosStyles(align: PosAlign.right),
      ),
    ]);

    printer.row([
      PosColumn(text: "Order type:", width: 5),
      PosColumn(
        // text: OrderType.values
        //     .firstWhere(
        //       (e) => e.id == order.sales_odr_order_type,
        //       orElse: () => OrderType.dineIn,
        //     )
        //     .displayName,
        text: (GetStorage().read('selected_order_type_id') == 0
            ? 'Dine In'
            : GetStorage().read('selected_order_type_id') == 1
            ? 'Delivery'
            : GetStorage().read('selected_order_type_id') == 2
            ? 'Pick Up'
            : ''),
        width: 7,
        styles: const PosStyles(align: PosAlign.right),
      ),
    ]);

    if (paymentMethod?.toLowerCase() != 'compliment') {
      printer.row([
        PosColumn(text: "Pay type:", width: 5),
        PosColumn(
          text: paymentMethod ?? "Cash",
          width: 7,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);
    }

    if (GetStorage().read('selected_order_type_id') == 0) {
      printer.row([
        PosColumn(text: "Table:", width: 6),
        PosColumn(
          text: "${order.tableName} (${order.chairNumber} Seats)",
          width: 6,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);
    }
    printer.row([
      PosColumn(text: "Date:", width: 5),
      PosColumn(
        text: DateFormat('dd/MM/yyyy').format(order.createdAt),
        width: 7,
        styles: const PosStyles(align: PosAlign.right),
      ),
    ]);
    printer.row([
      PosColumn(text: "Time:", width: 5),
      PosColumn(
        text: DateFormat('HH:mm:ss').format(order.createdAt),
        width: 7,
        styles: const PosStyles(align: PosAlign.right),
      ),
    ]);
    printer.hr();

    for (var item in order.items.where((i) => !i.isRemoved)) {
      printer.row([
        PosColumn(text: "${item.quantity}x ${item.product.name}", width: 9),
        PosColumn(
          text: (item.priceAtOrder * item.quantity).toStringAsFixed(2),
          width: 3,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);
    }

    printer.hr();
    final taxShare = _splitTaxShare(order, splitAmount);
    printer.hr();
    if (AppState.cmpTaxType != 1) {
      isVatDisabled
          ? SizedBox.shrink()
          : printer.row([
              PosColumn(text: "CGST", width: 6),
              PosColumn(
                text: taxShare["cgst"]!.toStringAsFixed(2),
                width: 6,
                styles: const PosStyles(align: PosAlign.right),
              ),
            ]);
      isVatDisabled
          ? SizedBox.shrink()
          : printer.row([
              PosColumn(text: "SGST", width: 6),
              PosColumn(
                text: taxShare["sgst"]!.toStringAsFixed(2),
                width: 6,
                styles: const PosStyles(align: PosAlign.right),
              ),
            ]);
      printer.hr();
    }
    printer.text(
      "SPLIT AMOUNT",
      styles: const PosStyles(align: PosAlign.center, bold: true),
    );
    printer.row([
      PosColumn(
        text: "Bill $splitLabel",
        width: 6,
        styles: const PosStyles(bold: true),
      ),
      PosColumn(
        text: splitAmount.toStringAsFixed(2),
        width: 6,
        styles: const PosStyles(align: PosAlign.right, bold: true),
      ),
    ]);
    printer.hr();

    if ((paymentMethod?.toLowerCase() != 'compliment') &&
        AppState.isUpiEnabled &&
        AppState.upiId.isNotEmpty &&
        AppState.cmpTaxType != 1) {

      final String upiLink = "upi://pay"
          "?pa=${AppState.upiId}"
          "&pn=${Uri.encodeComponent(AppState.branchName)}"
          "&am=${splitAmount.toStringAsFixed(2)}"
          "&cu=INR"
          "&tn=${Uri.encodeComponent("Split Bill $splitLabel")}";

      printer.qrcode(
        upiLink,
        size: QRSize.size5,
        cor: QRCorrection.L,
      );

      printer.feed(1);
    }
    printer.text("Thank You!", styles: const PosStyles(align: PosAlign.center));
    printer.feed(3);
    printer.cut();
  }

  Future<void> _printWifiReceipt(
    String ip,
    OrderModel order,
    double received,
    double change,
    CapabilityProfile profile, {
    bool isBill = false,
        bool isSale = false,
    String? customerName,
    String? paymentMethod,
    String? invoiceLabel,
    double discount = 0,
    double roundOff = 0,
  }) async {
    try {
      final printer = NetworkPrinter(PaperSize.mm80, profile);
      final res = await printer.connect(ip, port: 9100);
      if (res == PosPrintResult.success) {
        _generateReceiptTicket(
          printer,
          order,
          received,
          change,
          isSale: isSale,
          isBill: isBill,
          customerName: customerName,
          paymentMethod: paymentMethod,
          discount: discount,
          roundOff: roundOff,
        );
        await Future.delayed(const Duration(milliseconds: 500));
        printer.disconnect();
      }
    } catch (e) {
      debugPrint("WiFi Receipt Error: $e");
    }
  }

  Future<void> _printBluetoothReceipt(
    PrinterModel printer,
    OrderModel order,
    double received,
    double change,
    CapabilityProfile profile, {
    bool isBill = false,
        bool isSale = false,
    String? customerName,
    String? invoiceLabel,
    String? paymentMethod,
    double discount = 0,
    double roundOff = 0,
  }) async {
    try {
      final DashboardController dashboardController =
          Get.find<DashboardController>();
      final bool isVatDisabled = dashboardController.vatType.value == 1;
      bool connected = await PrintBluetoothThermal.connectionStatus;
      if (!connected) {
        await PrintBluetoothThermal.connect(macPrinterAddress: printer.address);
      }
      final generator = Generator(PaperSize.mm80, profile);
      List<int> bytes = [];
      bytes += generator.setGlobalFont(PosFontType.fontA);

      // Header
      // bytes += generator.text(
      //   "REST POS",
      //   styles: const PosStyles(
      //     align: PosAlign.center,
      //     bold: false,
      //     height: PosTextSize.size2,
      //   ),
      // );
      // bytes += generator.text(
      //   isBill ? "ORDER BILL" : "Final Receipt",
      //   styles: const PosStyles(align: PosAlign.center),
      // );
      bytes += generator.text(
        AppState.branchName,
        styles: const PosStyles(
          align: PosAlign.center,
          height: PosTextSize.size2,
          fontType: PosFontType.fontA,
          bold: false,
        ),
      );
      bytes += generator.text(
        AppState.branchAddress,
        styles: const PosStyles(align: PosAlign.center),
      );
      bytes += generator.text(
        "Ph:${AppState.branchPhNo}",
        styles: const PosStyles(align: PosAlign.center),
      );
      bytes += generator.text(
        "MOB:${AppState.branchMob}",
        styles: const PosStyles(align: PosAlign.center),
      );
      if (AppState.cmpTaxType != 1) {
        bytes += generator.text(
          "GST No: ${AppState.branchVat}",
          styles: const PosStyles(align: PosAlign.center),
        );
      } else {
        bytes += generator.text(
          "VAT No: ${AppState.branchVat}",
          styles: const PosStyles(align: PosAlign.center),
        );
      }
      bytes += generator.text("-" * 48);
      final String? effectiveCustomerName = customerName ?? order.customerName ?? "Cash Customer";
      if (effectiveCustomerName != null && effectiveCustomerName.trim().isNotEmpty) {
        bytes += generator.row([
          PosColumn(text: "Customer:", width: 5),
          PosColumn(
            text: effectiveCustomerName,
            width: 7,
            styles: const PosStyles(align: PosAlign.right),
          ),
        ]);
      }
      final bool isInvoiced = order.status.value == OrderStatus.paid;

      bytes += generator.row([
        PosColumn(text: isSale ? "Inv No:" : "Order No:", width: 5),
        PosColumn(
          text: invoiceLabel.toString(),
          width: 7,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);
      // bytes += generator.row([
      //   PosColumn(text: "Captain:", width: 5),
      //   PosColumn(
      //     text: order.captainName.toString(),
      //     width: 7,
      //     styles: const PosStyles(align: PosAlign.right),
      //   ),
      // ]);
      bytes += generator.row([
        PosColumn(text: "Order type:", width: 5),
        PosColumn(
          // text: OrderType.values
          //     .firstWhere(
          //       (e) => e.id == order.sales_odr_order_type,
          //       orElse: () => OrderType.dineIn,
          //     )
          //     .displayName,
          text: (GetStorage().read('selected_order_type_id') == 0
              ? 'Dine In'
              : GetStorage().read('selected_order_type_id') == 1
              ? 'Delivery'
              : GetStorage().read('selected_order_type_id') == 2
              ? 'Pick Up'
              : ''),
          width: 7,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);
      if (!isBill && paymentMethod?.toLowerCase() != 'compliment') {
        bytes += generator.row([
          PosColumn(text: "Pay type:", width: 5),
          PosColumn(
            text: paymentMethod ?? "Cash",
            width: 7,
            styles: const PosStyles(align: PosAlign.right),
          ),
        ]);
      }
      bytes += generator.row([
        PosColumn(text: "Date:", width: 5),
        PosColumn(
          text: DateFormat('dd/MM/yyyy').format(order.createdAt),
          width: 7,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);
      bytes += generator.row([
        PosColumn(text: "Time:", width: 5),
        PosColumn(
          text: DateFormat('HH:mm:ss').format(order.createdAt),
          width: 7,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);
      if (GetStorage().read('selected_order_type_id') == 0) {
        bytes += generator.row([
          PosColumn(text: "Table:", width: 5),
          PosColumn(
            text: order.tableName,
            width: 7,
            styles: const PosStyles(align: PosAlign.right),
          ),
        ]);
      }

      bytes += generator.text("-" * 48);

      // Column Titles
      bytes += generator.row([
        PosColumn(
          text: "Item",
          width: 6, // 👈 increase when no VAT
        ),
        PosColumn(text: "Qty", width: 1),
        PosColumn(
          text: "Price",
          width: 2,
          styles: const PosStyles(align: PosAlign.right),
        ),
        // if (AppState.cmpTaxType == 1)
        //   PosColumn(
        //     text: "Vat",
        //     width: 2,
        //     styles: const PosStyles(align: PosAlign.right),
        //   ),
        PosColumn(
          text: "Amount",
          width: 3,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);
      bytes += generator.text("-" * 48);
      double calculatedSubTotal = 0;
      double calculatedTax = 0;
      double calculatedCgst = 0;
      double calculatedSgst = 0;
      final double itemCgst = (order.Taxpercentage / 2);
      final double itemSgst = (order.Taxpercentage / 2);
      for (var item in order.items.where((i) => !i.isRemoved)) {
        //   final double itemCgst = (item.cgstRate > 0) ? item.cgstRate : (item.product.taxPer/ 2);
        // final double itemSgst = (item.sgstRate > 0) ? item.sgstRate : itemCgst;
        double taxPer = item.product.taxPer;

        // double qty = item.quantity.toDouble();
        double baseqty = item.unit.unitBaseQty.toDouble();
        double qty;
        double price;
        if (order.isUnsynced) {
          price = item.priceAtOrder.toDouble();
          qty = item.quantity.toDouble();
        } else {
          price = item.product.price * (baseqty > 1.0 ? baseqty : 1.0);
          qty = item.quantity.toDouble();
        }

        double vatAmount;
        double lineTotal;
        double lineSubTotal;

        if (Get.isRegistered<DashboardController>() &&
            Get.find<DashboardController>().vatType.value == 1) {
          // Price includes tax (VAT Disabled for offline/special cases as per requirement)
          lineTotal = price * qty;
          vatAmount = 0.0;
          lineSubTotal = lineTotal;
        } else {
          // Price excludes tax
          lineSubTotal = price * qty;
          vatAmount = (lineSubTotal * taxPer) / 100;
          lineTotal = lineSubTotal;
        }
        final double lineCgst = taxPer / 2;
        final double lineSgst = taxPer / 2;
        calculatedCgst += lineCgst;
        calculatedSgst += lineSgst;
        calculatedSubTotal += lineSubTotal;
        calculatedTax += vatAmount;
        // calculatedCgst += lineCgstAmt;
        // calculatedSgst += lineSgstAmt;

        // final hasVat = AppState.cmpTaxType == 1;

        bytes += generator.row([
          PosColumn(
            text: item.product.name,
            width: 6, // 👈 expand when no VAT
          ),
          PosColumn(text: item.quantity.toString(), width: 1),
          PosColumn(
            text: price.toStringAsFixed(2),
            width: 2,
            styles: const PosStyles(align: PosAlign.right),
          ),

          // if (hasVat)
          //   PosColumn(
          //     text: vatAmount.toStringAsFixed(2),
          //     width: 2,
          //     styles: const PosStyles(align: PosAlign.right),
          //   ),
          PosColumn(
            text: lineTotal.toStringAsFixed(2),
            width: 3,
            styles: const PosStyles(align: PosAlign.right),
          ),
        ]);

        for (var addon in item.selectedAddons) {
          double addonTotal = addon.price * addon.quantity.value;
          calculatedSubTotal += addonTotal;
          bytes += generator.row([
            PosColumn(text: "", width: 1),
            PosColumn(text: " + ${addon.name}", width: 4),
            PosColumn(
              text: addon.price.toStringAsFixed(2),
              width: 2,
              styles: const PosStyles(align: PosAlign.right),
            ),
            PosColumn(
              text: "0.00",
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

      final double finalSubTotal = (order.subTotal > 0)
          ? order.subTotal
          : calculatedSubTotal;
      final double finalVat =
          (Get.isRegistered<DashboardController>() &&
              Get.find<DashboardController>().vatType.value == 1)
          ? 0.0
          : ((order.totalTax > 0) ? order.totalTax : calculatedTax);

      bytes += generator.text("-" * 48);
      bytes += generator.row([
        PosColumn(text: "Sub Total", width: 6),
        PosColumn(
          text: finalSubTotal.toStringAsFixed(2),
          width: 6,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);
      if (AppState.cmpTaxType == 1) {
        bytes += generator.row([
          PosColumn(text: "VAT", width: 6),
          PosColumn(
            text: finalVat.toStringAsFixed(2),
            width: 6,
            styles: const PosStyles(align: PosAlign.right),
          ),
        ]);
      } else {
        final double finalCgst = order.totalCgst > 0
            ? order.totalCgst
            : (finalVat / 2);
        final double finalSgst = order.totalSgst > 0
            ? order.totalSgst
            : (finalVat / 2);
        (isVatDisabled)
            ? ""
            : bytes += generator.row([
                PosColumn(text: "CGST(${calculatedCgst}%)", width: 6),
                PosColumn(
                  text: finalCgst.toStringAsFixed(2),
                  width: 6,
                  styles: const PosStyles(align: PosAlign.right),
                ),
              ]);
        (isVatDisabled)
            ? ""
            : bytes += generator.row([
                PosColumn(text: "SGST(${calculatedSgst}%)", width: 6),
                PosColumn(
                  text: finalSgst.toStringAsFixed(2),
                  width: 6,
                  styles: const PosStyles(align: PosAlign.right),
                ),
              ]);
      }
      if (discount > 0) {
        bytes += generator.row([
          PosColumn(text: "Discount", width: 6),
          PosColumn(
            text: "${discount.toStringAsFixed(2)}",
            width: 6,
            styles: const PosStyles(align: PosAlign.right),
          ),
        ]);
      }

      if (roundOff != 0) {
        bytes += generator.row([
          PosColumn(text: "Round Off", width: 6),
          PosColumn(
            text: roundOff.toStringAsFixed(2),
            width: 6,
            styles: const PosStyles(align: PosAlign.right),
          ),
        ]);
      }
      final int vatType = dashboardController.vatType.value;

      bool isCompliment = paymentMethod?.toLowerCase() == 'compliment';
      bool isOnlineOrPaid =
          !order.isUnsynced || order.status.value == OrderStatus.paid;

      double finalTotal;
      double netTotal;

      if (isCompliment) {
        netTotal = 0.0;
      } else {
        if (vatType == 0) {
          // Tax-exclusive: subtotal + VAT - discount + roundOff
          netTotal = (finalSubTotal + finalVat - discount + roundOff).clamp(
            0,
            double.infinity,
          );
        } else {
          // Tax-inclusive
          if (isOnlineOrPaid) {
            // order.totalAmount from server already has discount baked in
            netTotal = (order.totalAmount + roundOff).clamp(0, double.infinity);
          } else {
            // Offline totalAmount is pre-discount
            netTotal = (order.totalAmount - discount + roundOff).clamp(
              0,
              double.infinity,
            );
          }
        }
      }
      bytes += generator.row([
        PosColumn(
          text: "NET TOTAL",
          width: 6,
          styles: const PosStyles(height: PosTextSize.size1),
        ),
        PosColumn(
          text: netTotal.toStringAsFixed(2),
          width: 6,
          styles: const PosStyles(
            align: PosAlign.right,
            height: PosTextSize.size1,
          ),
        ),
      ]);

      // if (!isBill) {
      //   bytes += generator.row([
      //     PosColumn(text: "Received", width: 6),
      //     PosColumn(text: received.toStringAsFixed(2), width: 6, styles: const PosStyles(align: PosAlign.right)),
      //   ]);
      //   bytes += generator.row([
      //     PosColumn(text: "Change", width: 6),
      //     PosColumn(text: change.toStringAsFixed(2), width: 6, styles: const PosStyles(align: PosAlign.right)),
      //   ]);
      // }

      bytes += generator.text("-" * 48);

      if (!isCompliment &&
          AppState.isUpiEnabled &&
          AppState.upiId.isNotEmpty &&
          AppState.cmpTaxType != 1) {
        final String upiLink =
            "upi://pay"
            "?pa=${AppState.upiId}"
            "&pn=${Uri.encodeComponent(AppState.branchName)}"
            "&am=${netTotal.toStringAsFixed(2)}"
            "&cu=INR"
            "&tn=${Uri.encodeComponent(invoiceLabel.toString())}";

        bytes += generator.qrcode(
          upiLink,
          size: QRSize.size5,
          cor: QRCorrection.L,
        );
        bytes += generator.emptyLines(1);
      }

      bytes += generator.text(
        "Thank You!",
        styles: const PosStyles(align: PosAlign.center),
      );
      bytes += generator.feed(1);
      bytes += generator.cut();
      await PrintBluetoothThermal.writeBytes(bytes);
    } catch (e) {
      debugPrint("BT Receipt Error: $e");
    }
  }

  void _generateReceiptTicket(
    NetworkPrinter printer,
    OrderModel order,
    double received,
    double change, {
    bool isBill = false,
        bool isSale = false,
    String? customerName,
    String? paymentMethod,
    double discount = 0,
    double roundOff = 0,
  }) {
    printer.text(
      "REST POS",
      styles: const PosStyles(
        align: PosAlign.center,
        bold: true,
        height: PosTextSize.size2,
      ),
    );
    printer.text(
      "SPLIT BILL",
      styles: const PosStyles(align: PosAlign.center, bold: true),
    );
    printer.text("-" * 48);
    printer.hr();
    final String? effectiveCustomerName = customerName ?? order.customerName?? "Cash Customer";
if (effectiveCustomerName != null && effectiveCustomerName.trim().isNotEmpty) {
    printer.row([
      PosColumn(text: "Customer:", width: 5),
      PosColumn(
        text: effectiveCustomerName,
        width: 7,
        styles: const PosStyles(align: PosAlign.right),
      ),
    ]);}

    final bool isInvoiced = order.status.value == OrderStatus.paid;

    printer.row([
      PosColumn(text: isSale ? "Inv No:" : "Order No:", width: 5),
      PosColumn(
        text: order.branchInv.toString(),
        width: 7,
        styles: const PosStyles(align: PosAlign.right),
      ),
    ]);
    printer.row([
      PosColumn(text: "Captain:", width: 5),
      PosColumn(
        text: order.captainName.toString(),
        width: 7,
        styles: const PosStyles(align: PosAlign.right),
      ),
    ]);
    printer.row([
      PosColumn(text: "Order type:", width: 5),
      PosColumn(
        // text: OrderType.values
        //     .firstWhere(
        //       (e) => e.id == order.sales_odr_order_type,
        //   orElse: () => OrderType.dineIn,
        // )
        //     .displayName,
        text: (GetStorage().read('selected_order_type_id') == 0
            ? 'Dine In'
            : GetStorage().read('selected_order_type_id') == 1
            ? 'Delivery'
            : GetStorage().read('selected_order_type_id') == 2
            ? 'Pick Up'
            : ''),
        width: 7,
        styles: const PosStyles(align: PosAlign.right),
      ),
    ]);
    if (!isBill && paymentMethod?.toLowerCase() != 'compliment') {
      printer.row([
        PosColumn(text: "Pay type:", width: 5),
        PosColumn(
          text: paymentMethod ?? "Cash",
          width: 7,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);
    }
    printer.row([
      PosColumn(text: "Date:", width: 5),
      PosColumn(
        text: DateFormat('dd/MM/yyyy').format(order.createdAt),
        width: 7,
        styles: const PosStyles(align: PosAlign.right),
      ),
    ]);
    printer.row([
      PosColumn(text: "Time:", width: 5),
      PosColumn(
        text: DateFormat('HH:mm:ss').format(order.createdAt),
        width: 7,
        styles: const PosStyles(align: PosAlign.right),
      ),
    ]);
    if (GetStorage().read('selected_order_type_id') == 0) {
      printer.row([
        PosColumn(text: "Table:", width: 5),
        PosColumn(
          text: order.tableName,
          width: 7,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);
    }

    printer.hr();

    // Column headers
    printer.row([
      PosColumn(text: "Qty", width: 1, styles: const PosStyles(bold: true)),
      PosColumn(text: "Item", width: 4, styles: const PosStyles(bold: true)),
      PosColumn(
        text: "Rate",
        width: 2,
        styles: const PosStyles(align: PosAlign.right, bold: true),
      ),
      if (AppState.cmpTaxType == 1) ...[
        PosColumn(
          text: "Vat",
          width: 2,
          styles: const PosStyles(align: PosAlign.right, bold: true),
        ),
      ] else ...[
        PosColumn(
          text: "Gst Total",
          width: 2,
          styles: const PosStyles(align: PosAlign.right, bold: true),
        ),
      ],
      PosColumn(
        text: "Amount",
        width: 3,
        styles: const PosStyles(align: PosAlign.right, bold: true),
      ),
    ]);
    printer.hr();

    double calculatedSubTotal = 0;
    double calculatedTax = 0;

    final dashboardController = Get.find<DashboardController>();
    final int vatType = dashboardController.vatType.value;

    for (var item in order.items.where((i) => !i.isRemoved)) {
      // ✅ Match BT: use item.product.price, not item.priceAtOrder
      double price = item.product.price;
      double taxPer = item.product.taxPer;
      double qty = item.quantity.toDouble();
      print("Price: ${item.priceAtOrder}");
      double vatAmount;
      double lineTotal;
      double lineSubTotal;

      if (vatType == 1) {
        // Tax-inclusive
        lineTotal = price * qty;
        vatAmount = 0.0;
        lineSubTotal = lineTotal;
      } else {
        // Tax-exclusive
        lineSubTotal = price * qty;
        vatAmount = (lineSubTotal * taxPer) / 100;
        lineTotal = lineSubTotal + vatAmount;
      }

      calculatedSubTotal += lineSubTotal;
      calculatedTax += vatAmount;

      printer.row([
        PosColumn(text: item.quantity.toString(), width: 1),
        PosColumn(text: item.product.name, width: 4),
        PosColumn(
          text: price.toStringAsFixed(2),
          width: 2,
          styles: const PosStyles(align: PosAlign.right),
        ),
        PosColumn(
          text: vatAmount.toStringAsFixed(2),
          width: 2,
          styles: const PosStyles(align: PosAlign.right),
        ),
        PosColumn(
          text: lineTotal.toStringAsFixed(2),
          width: 3,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);

      for (var addon in item.selectedAddons) {
        double addonTotal = addon.price * addon.quantity.value;
        calculatedSubTotal += addonTotal;
        printer.row([
          PosColumn(text: "", width: 1),
          PosColumn(text: " + ${addon.name}", width: 4),
          PosColumn(
            text: addon.price.toStringAsFixed(2),
            width: 2,
            styles: const PosStyles(align: PosAlign.right),
          ),
          PosColumn(
            text: "0.00",
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

    final double finalSubTotal = (order.subTotal > 0)
        ? order.subTotal
        : calculatedSubTotal;
    final double finalVat = (vatType == 1)
        ? 0.0
        : ((order.totalTax > 0) ? order.totalTax : calculatedTax);

    printer.hr();

    printer.row([
      PosColumn(text: "Sub Total", width: 6),
      PosColumn(
        text: finalSubTotal.toStringAsFixed(2),
        width: 6,
        styles: const PosStyles(align: PosAlign.right),
      ),
    ]);
    if (AppState.cmpTaxType == 1) {
      printer.row([
        PosColumn(text: "VAT", width: 6),
        PosColumn(
          text: finalVat.toStringAsFixed(2),
          width: 6,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);
    } else {
      final double finalCgst = order.totalCgst > 0
          ? order.totalCgst
          : (finalVat / 2);
      final double finalSgst = order.totalSgst > 0
          ? order.totalSgst
          : (finalVat / 2);

      (vatType == 1)
          ? SizedBox.shrink()
          : printer.row([
              PosColumn(text: "CGST", width: 6),
              PosColumn(
                text: finalCgst.toStringAsFixed(2),
                width: 6,
                styles: const PosStyles(align: PosAlign.right),
              ),
            ]);
      (vatType == 1)
          ? SizedBox.shrink()
          : printer.row([
              PosColumn(text: "SGST", width: 6),
              PosColumn(
                text: finalSgst.toStringAsFixed(2),
                width: 6,
                styles: const PosStyles(align: PosAlign.right),
              ),
            ]);
    }

    if (discount > 0) {
      printer.row([
        PosColumn(text: "Discount", width: 6),
        PosColumn(
          text: "-${discount.toStringAsFixed(2)}",
          width: 6,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);
    }

    if (roundOff != 0) {
      printer.row([
        PosColumn(text: "Round Off", width: 6),
        PosColumn(
          text: roundOff.toStringAsFixed(2),
          width: 6,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);
    }

    // ✅ Match BT: full netTotal logic
    bool isCompliment = paymentMethod?.toLowerCase() == 'compliment';
    bool isOnlineOrPaid =
        !order.isUnsynced || order.status.value == OrderStatus.paid;

    double netTotal;
    if (isCompliment) {
      netTotal = 0.0;
    } else {
      if (vatType == 0) {
        // Tax-exclusive: build total from parts
        netTotal = (finalSubTotal + finalVat - discount + roundOff).clamp(
          0,
          double.infinity,
        );
      } else {
        // Tax-inclusive: order.totalAmount already has discount baked in for online/paid
        if (isOnlineOrPaid) {
          netTotal = (order.totalAmount + roundOff).clamp(0, double.infinity);
        } else {
          netTotal = (order.totalAmount - discount + roundOff).clamp(
            0,
            double.infinity,
          );
        }
      }
    }

    printer.row([
      PosColumn(
        text: "NET TOTAL",
        width: 6,
        styles: const PosStyles(bold: true),
      ),
      PosColumn(
        text: netTotal.toStringAsFixed(2),
        width: 6,
        styles: const PosStyles(align: PosAlign.right, bold: true),
      ),
    ]);

    // ✅ Match BT: Received/Change removed (commented out to match BT behaviour)
    // if (!isBill) {
    //   printer.row([...Received...]);
    //   printer.row([...Change...]);
    // }

    printer.hr();

    if (!isCompliment &&
        AppState.isUpiEnabled &&
        AppState.upiId.isNotEmpty &&
        AppState.cmpTaxType != 1) {
      final String upiLink =
          "upi://pay"
          "?pa=${AppState.upiId}"
          "&pn=${Uri.encodeComponent(AppState.branchDisName)}"
          "&am=${netTotal.toStringAsFixed(2)}"
          "&cu=INR"
          "&tn=${Uri.encodeComponent(order.branchInv.toString())}";

      printer.qrcode(
        upiLink,
        align: PosAlign.center,
        size: QRSize.size6,
        cor: QRCorrection.L,
      );
      printer.feed(1);
    }

    printer.text("Thank You!", styles: const PosStyles(align: PosAlign.center));
    printer.feed(3);
    printer.cut();
  }

  Future<void> printKOT(OrderModel order, {List<OrderItem>? oldItems}) async {
    debugPrint("--- START KOT PRINTING ---");

    List<OrderItem> itemsToPrint = [];
    bool isUpdate = false;

    if (oldItems == null || oldItems.isEmpty) {
      isUpdate = false;
      itemsToPrint = order.items
          .where((item) => !item.isRemoved && item.quantity > 0)
          .toList();
    } else {
      isUpdate = true;

      String itemKey(OrderItem item) =>
          "${item.product.id}_${item.unitId ?? item.unit.unitId}";

      final newMap = {
        for (var item in order.items)
          if (!item.isRemoved) itemKey(item): item,
      };

      final oldMap = {for (var item in oldItems) itemKey(item): item};

      Set<String> allKeys = {...oldMap.keys, ...newMap.keys};

      for (var key in allKeys) {
        final oldItem = oldMap[key];
        final newItem = newMap[key];

        if (oldItem == null && newItem != null && !newItem.isRemoved) {
          // ✅ Completely new item
          itemsToPrint.add(newItem);
          debugPrint(
            "🆕 NEW ITEM: ${newItem.product.name} x${newItem.quantity}",
          );
        } else if (newItem == null && oldItem != null) {
          // ✅ Item removed entirely
          itemsToPrint.add(
            OrderItem(
              subId: oldItem.subId,
              product: oldItem.product,
              quantity: oldItem.quantity,
              priceAtOrder: oldItem.priceAtOrder,
              unit: oldItem.unit,
              unitId: oldItem.unitId,
              tokenPrinterId: oldItem.tokenPrinterId,
              selectedAddons: oldItem.selectedAddons,
              isRemoved: true,
              notes: oldItem.notes,
            ),
          );
          debugPrint(
            "❌ REMOVED ITEM: ${oldItem.product.name} x${oldItem.quantity}",
          );
        } else if (oldItem != null && newItem != null) {
          // ✅ Item exists in both - check for changes

          final int qtyDifference = newItem.quantity - oldItem.quantity;
          final bool qtyIncreased = qtyDifference > 0;
          final bool qtyDecreased = qtyDifference < 0;
          final bool notesChanged = newItem.notes != oldItem.notes;

          // Check addon changes
          final oldAddonMap = {
            for (var a in oldItem.selectedAddons) a.prdId: a,
          };
          final newAddonMap = {
            for (var a in newItem.selectedAddons) a.prdId: a,
          };
          Set<int> allAddonIds = {...oldAddonMap.keys, ...newAddonMap.keys};
          bool addonsChanged = false;
          List<AddonModel> addedAddons = [];
          List<AddonModel> removedAddons = [];
          List<AddonModel> modifiedAddons = [];

          for (var addonId in allAddonIds) {
            final oldAddon = oldAddonMap[addonId];
            final newAddon = newAddonMap[addonId];

            if (oldAddon == null && newAddon != null) {
              addonsChanged = true;
              addedAddons.add(newAddon);
              debugPrint(
                "➕ ADDED ADDON: ${newAddon.name} x${newAddon.quantity.value}",
              );
            } else if (newAddon == null && oldAddon != null) {
              addonsChanged = true;
              removedAddons.add(oldAddon);
              debugPrint("➖ REMOVED ADDON: ${oldAddon.name}");
            } else if (oldAddon != null &&
                newAddon != null &&
                oldAddon.quantity.value != newAddon.quantity.value) {
              addonsChanged = true;
              modifiedAddons.add(newAddon);
              debugPrint(
                "🔄 MODIFIED ADDON: ${newAddon.name} ${oldAddon.quantity.value} → ${newAddon.quantity.value}",
              );
            }
          }

          // ✅ Handle quantity changes - print as a single change item
          if (qtyIncreased) {
            // Print Increased quantity
            itemsToPrint.add(
              OrderItem(
                subId: newItem.subId,
                product: newItem.product,
                quantity: qtyDifference, // Only the increased amount
                priceAtOrder: newItem.priceAtOrder,
                unit: newItem.unit,
                unitId: newItem.unitId,
                tokenPrinterId: newItem.tokenPrinterId,
                selectedAddons: newItem.selectedAddons,
                isRemoved: false,
                notes: newItem.notes,
              ),
            );
            debugPrint(
              "⬆️ INCREASED QTY: ${newItem.product.name} +$qtyDifference (${oldItem.quantity} → ${newItem.quantity})",
            );
          } else if (qtyDecreased) {
            // Print Decreased quantity (as removed)
            itemsToPrint.add(
              OrderItem(
                subId: oldItem.subId,
                product: oldItem.product,
                quantity: -qtyDifference, // Positive number of units removed
                priceAtOrder: oldItem.priceAtOrder,
                unit: oldItem.unit,
                unitId: oldItem.unitId,
                tokenPrinterId: oldItem.tokenPrinterId,
                selectedAddons: oldItem.selectedAddons,
                isRemoved: true,
                notes: oldItem.notes,
              ),
            );
            debugPrint(
              "⬇️ DECREASED QTY: ${oldItem.product.name} -${-qtyDifference} (${oldItem.quantity} → ${newItem.quantity})",
            );
          }

          // ✅ Handle addon or notes changes separately (if no quantity change)
          if (!qtyIncreased && !qtyDecreased && (addonsChanged || notesChanged)) {
            // Print modified item with addon changes or notes changes
            itemsToPrint.add(
              OrderItem(
                subId: newItem.subId,
                product: newItem.product,
                quantity: newItem.quantity,
                priceAtOrder: newItem.priceAtOrder,
                unit: newItem.unit,
                unitId: newItem.unitId,
                tokenPrinterId: newItem.tokenPrinterId,
                selectedAddons: newItem.selectedAddons,
                isRemoved: false,
                notes: newItem.notes,
              ),
            );
            debugPrint("🔄 ADDON OR NOTES CHANGES ONLY: ${newItem.product.name}");
          }
        }
      }
    }

    if (itemsToPrint.isEmpty) {
      debugPrint("No new items or changes to print.");
      return;
    }

    debugPrint("📋 Total items to print: ${itemsToPrint.length}");
    await _distributeToPrinters(
      order,
      itemsToPrint,
      status: isUpdate ? "Modified" : "Original",
    );
  }

  Future<void> printCancelledOrder(OrderModel order) async {
    debugPrint("--- PRINTING CANCELLED ORDER ---");
    final cancelledItems = order.items
        .map(
          (item) => OrderItem(
            product: item.product,
            unit: item.unit,
            quantity: item.quantity,
            priceAtOrder: item.priceAtOrder,
            selectedAddons: item.selectedAddons,
            tokenPrinterId: item.tokenPrinterId,
            isRemoved: true,
            notes: item.notes,
          ),
        )
        .toList();

    await _distributeToPrinters(order, cancelledItems, status: "CANCELLED");
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
      log(
        "🖨️ RESOLVE DEBUG → DashboardController not registered, returning null",
      );
      return null;
    }
    final dash = Get.find<DashboardController>();

    final cat = dash.allCategoriesForPrinters.firstWhereOrNull(
      (c) => c.id.toString() == item.product.categoryId.toString(),
    );
    log(
      "🖨️ RESOLVE DEBUG → step3 category lookup: "
      "categoryFound=${cat != null} catId=${cat?.id} catTokenPrinterId=${cat?.tokenPrinterId} "
      "allCategoriesForPrintersCount=${dash.allCategoriesForPrinters.length}",
    );
    if (cat != null && cat.tokenPrinterId != 0) return cat.tokenPrinterId;

    final firstAssigned = tokenPrinterAssignments.firstWhereOrNull(
      (a) => a.printerAddress.value.isNotEmpty,
    );
    log(
      "🖨️ RESOLVE DEBUG → step4 fallback assignment: "
      "found=${firstAssigned != null} tokenPrinterId=${firstAssigned?.tokenPrinterId} "
      "totalAssignments=${tokenPrinterAssignments.length}",
    );
    return firstAssigned?.tokenPrinterId;
  }

  Future<void> _distributeToPrinters(
    OrderModel order,
    List<OrderItem> items, {
    required String status,
  }) async {
    debugPrint(
      "📍 DISTRIBUTING TO PRINTERS - Status: $status, Items: ${items.length}",
    );
    final invoiceLabel = await _resolveInvoiceLabel(order);
    Map<String, List<OrderItem>> printerGroups = {};

    for (var item in items) {
      debugPrint(
        "  📦 Processing item: ${item.product.name}, qty: ${item.quantity}, isRemoved: ${item.isRemoved}",
      );

      int? tokenId = _resolveTokenPrinterId(item);
      debugPrint("  📌 Resolved Token ID: $tokenId");

      if (tokenId == null || tokenId == 0) {
        debugPrint("  ⚠️ No token printer ID for item: ${item.product.name}");
        continue;
      }
      final assignment = tokenPrinterAssignments.firstWhereOrNull(
        (a) => a.tokenPrinterId == tokenId,
      );
      final address = assignment?.printerAddress.value ?? "";
      debugPrint("  🖨️ Token $tokenId → Printer address: $address");

      if (address.isNotEmpty) {
        if (!printerGroups.containsKey(address)) printerGroups[address] = [];
        printerGroups[address]!.add(item);
        debugPrint("  ✅ Added to printer group: $address");
      } else {
        debugPrint("  ❌ No printer assigned for token $tokenId");
      }
    }

    if (printerGroups.isEmpty) {
      debugPrint("❌ No printer groups found - nothing to print!");
      return;
    }

    debugPrint("📋 Printer groups: ${printerGroups.keys}");

    final profile = await CapabilityProfile.load();

    for (var entry in printerGroups.entries) {
      final address = entry.key;
      final groupItems = entry.value;

      debugPrint("🖨️ Printing to $address (${groupItems.length} items)");

      final allPrinters = [...bluetoothPrinters, ...wifiPrinters];
      var printerInfo = allPrinters.firstWhereOrNull(
        (p) => p.address == address,
      );

      if (printerInfo == null) {
        final assignment = tokenPrinterAssignments.firstWhereOrNull(
          (a) => a.printerAddress.value == address,
        );
        if (assignment != null) {
          printerInfo = PrinterModel(
            name: assignment.printerName.value,
            address: assignment.printerAddress.value,
            type: assignment.printerType.value,
          );
          debugPrint("  📌 Using printer from assignment: ${printerInfo.name}");
        }
      }

      if (printerInfo == null) {
        debugPrint("  ❌ Printer info not found for address: $address");
        continue;
      }

      _logKOTData(order, groupItems, status, printerInfo.type, address);

      if (printerInfo.type == 'wifi') {
        debugPrint("  📡 Sending to WiFi printer...");
        await _printWifiKOT(
          address,
          order,
          groupItems,
          profile,
          status: status,
          invoiceLabel: invoiceLabel,
        );
      } else {
        debugPrint("  📡 Sending to Bluetooth printer...");
        await _printBluetoothKOT(
          printerInfo,
          order,
          groupItems,
          profile,
          status: status,
          invoiceLabel: invoiceLabel,
        );
      }
    }
  }

  String centerTextDynamic(String text, {bool isDouble = false}) {
    int width = isDouble ? 24 : 48;

    if (text.length >= width) return text;

    int spaces = ((width - text.length) / 2).floor();
    return ' ' * spaces + text;
  }

  Future<void> _printWifiKOT(
    String ip,
    OrderModel order,
    List<OrderItem> items,
    CapabilityProfile profile, {
    required String status,
    required String invoiceLabel,
  }) async {
    try {
      final printer = NetworkPrinter(PaperSize.mm80, profile);
      final res = await printer.connect(ip, port: 9100);

      if (res == PosPrintResult.success) {
        _generateKOTTicket(
          printer,
          order,
          items,
          status: status,
          invoiceLabel: invoiceLabel,
        );

        await Future.delayed(const Duration(milliseconds: 300));

        printer.disconnect();
      }
    } catch (e) {
      debugPrint("WiFi Print Error: $e");
    }
  }

  Future<void> _printBluetoothKOT(
    PrinterModel printer,
    OrderModel order,
    List<OrderItem> items,
    CapabilityProfile profile, {
    required String status,
    required String invoiceLabel,
  }) async {
    try {
      debugPrint("🔵 _printBluetoothKOT called for ${printer.name}");

      bool connected = await PrintBluetoothThermal.connectionStatus;
      if (!connected) {
        debugPrint(
          "🔵 Not connected, attempting to connect to ${printer.address}",
        );
        bool res = await PrintBluetoothThermal.connect(
          macPrinterAddress: printer.address,
        );
        if (!res) {
          debugPrint("❌ Failed to connect to Bluetooth printer");
          return;
        }
        debugPrint("✅ Connected to Bluetooth printer");
      }

      final generator = Generator(PaperSize.mm80, profile);
      List<int> bytes = [];

      final removedItems = items.where((i) => i.isRemoved).toList();
      final newItems = items.where((i) => !i.isRemoved).toList();

      debugPrint(
        "🔵 Removed items: ${removedItems.length}, New items: ${newItems.length}",
      );

      // Always print header
      bytes += generator.setGlobalFont(PosFontType.fontA);
      bytes += generator.text(
        "Token No : $invoiceLabel", // was ${order.invNo}
        styles: const PosStyles(
          align: PosAlign.center,
          height: PosTextSize.size2,
          fontType: PosFontType.fontA,
          bold: false,
        ),
      );
      bytes += generator.text(
        "KITCHEN ORDER",
        styles: const PosStyles(align: PosAlign.center),
      );
      bytes += generator.text('-' * 48);

      // Order info
      bytes += generator.row([
        PosColumn(text: "Order No:", width: 6),
        PosColumn(
          text: invoiceLabel, // was order.invNo
          width: 6,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);

      bytes += generator.row([
        PosColumn(text: "Order type:", width: 6),
        PosColumn(
          // text: OrderType.values
          //     .firstWhere(
          //       (e) => e.id == order.sales_odr_order_type,
          //       orElse: () => OrderType.dineIn,
          //     )
          //     .displayName,
          text: (GetStorage().read('selected_order_type_id') == 0
              ? 'Dine In'
              : GetStorage().read('selected_order_type_id') == 1
              ? 'Delivery'
              : GetStorage().read('selected_order_type_id') == 2
              ? 'Pick Up'
              : ''),
          width: 6,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);
      if (order.captainName != null && order.captainName!.isNotEmpty) {
        bytes += generator.row([
          PosColumn(text: "Captain:", width: 6),
          PosColumn(
            text: order.captainName!,
            width: 6,
            styles: const PosStyles(align: PosAlign.right),
          ),
        ]);
      }

      if (GetStorage().read('selected_order_type_id') == 0) {
        bytes += generator.row([
          PosColumn(text: "Table:", width: 6),
          PosColumn(
            text: "${order.tableName} (${order.chairNumber} Seats)",
            width: 6,
            styles: const PosStyles(align: PosAlign.right),
          ),
        ]);
      }

      // ─── CANCELLED / REMOVED SECTION ───
      if (removedItems.isNotEmpty) {
        debugPrint("🔵 Printing ${removedItems.length} removed items");
        bytes += generator.text('=' * 48, styles: const PosStyles(bold: true));

        String sectionTitle = status == "CANCELLED"
            ? "ORDER CANCELLED"
            : "QUANTITY DECREASED / REMOVED";

        bytes += generator.text(
          sectionTitle,
          styles: const PosStyles(
            align: PosAlign.center,
            bold: true,
            height: PosTextSize.size2,
          ),
        );
        bytes += generator.text('=' * 48, styles: const PosStyles(bold: true));
        bytes += generator.row([
          PosColumn(
            text: "Item",
            width: 8,
            styles: const PosStyles(bold: true),
          ),
          PosColumn(
            text: status == "CANCELLED" ? "Qty" : "Qty Removed",
            width: 4,
            styles: const PosStyles(align: PosAlign.right, bold: true),
          ),
        ]);
        bytes += generator.text('-' * 48);

        for (var item in removedItems) {
          debugPrint(
            "🔵 Printing removed: ${item.product.name} x${item.quantity}",
          );
          bytes += generator.row([
            PosColumn(
              text: status == "CANCELLED"
                  ? item.product.name
                  : "${item.product.name}",
              width: 8,
              styles: const PosStyles(bold: true),
            ),
            PosColumn(
              text: "${item.quantity} ${item.unit.unitDisplay}",
              width: 4,
              styles: const PosStyles(align: PosAlign.right, bold: true),
            ),
          ]);

          // PRINT NOTES
          if (item.notes.isNotEmpty) {
            bytes += generator.text(
              "   NOTE: ${item.notes}",
              styles: const PosStyles( bold: true),
            );
          }

          for (var addon in item.selectedAddons) {
            bytes += generator.row([
              PosColumn(text: "  - ${addon.name}", width: 8),
              PosColumn(
                text: "${addon.quantity.value} ${addon.unitDisplay}",
                width: 4,
                styles: const PosStyles(align: PosAlign.right),
              ),
            ]);
          }
        }
      }

      // ─── NEW / UPDATED SECTION ───
      if (newItems.isNotEmpty) {
        debugPrint("🔵 Printing ${newItems.length} new/updated items");
        bytes += generator.text('=' * 48, styles: const PosStyles(bold: true));

        String sectionTitle = status == "Modified"
            ? "QUANTITY INCREASED / NEW"
            : "ORDER ITEMS";

        bytes += generator.text(
          sectionTitle,
          styles: const PosStyles(
            align: PosAlign.center,
            // bold: true,
            height: PosTextSize.size2,
          ),
        );
        bytes += generator.text('=' * 48, styles: const PosStyles(bold: true));
        bytes += generator.row([
          PosColumn(
            text: "Item",
            width: 8,
            // styles: const PosStyles(bold: true),
          ),
          PosColumn(
            text: status == "Modified" ? "Qty Added" : "Qty",
            width: 4,
            styles: const PosStyles(align: PosAlign.right),
          ),
        ]);
        bytes += generator.text('-' * 48);

        for (var item in newItems) {
          debugPrint("🔵 Printing new: ${item.product.name} x${item.quantity}");
          bytes += generator.row([
            PosColumn(
              text: "${item.product.name}",
              width: 8,
              // styles: const PosStyles(bold: true),
            ),
            PosColumn(
              text: "${item.quantity} ${item.unit.unitDisplay}",
              width: 4,
              styles: const PosStyles(align: PosAlign.right),
            ),
          ]);

          // PRINT NOTES
          if (item.notes.isNotEmpty) {
            bytes += generator.text(
              "   NOTE: ${item.notes}",
              // styles: const PosStyles(bold: true),
            );
          }

          for (var addon in item.selectedAddons) {
            bytes += generator.row([
              PosColumn(text: "  + ${addon.name}", width: 8),
              PosColumn(
                text: "${addon.quantity.value} ${addon.unitDisplay}",
                width: 4,
                styles: const PosStyles(align: PosAlign.right),
              ),
            ]);
          }
        }
      }

      bytes += generator.text('=' * 48, styles: const PosStyles(bold: true));
      bytes += generator.text("*** Kitchen Copy ***", styles: const PosStyles(align: PosAlign.center));
      bytes += generator.feed(2);
      bytes += generator.cut();

      debugPrint("🔵 Writing ${bytes.length} bytes to printer");
      await PrintBluetoothThermal.writeBytes(bytes);
      debugPrint("✅ KOT printed successfully to Bluetooth printer");
    } catch (e) {
      debugPrint("❌ Bluetooth Print Error: $e");
      // debugPrint("Stack trace: ${StackTrace.current}");
    }
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

    buffer.writeln("Token No     : ${order.invNo}");
    buffer.writeln(
      "Order Type   : ${OrderType.values.firstWhere((e) => e.id == order.sales_odr_order_type, orElse: () => OrderType.dineIn).displayName}",
    );
    if (GetStorage().read('selected_order_type_id') == 0) {
      buffer.writeln(
        "Table        : ${order.tableName} (${order.chairNumber} Seats)",
      );
    }
    buffer.writeln(
      "Date         : ${DateFormat('dd/MM/yyyy HH:mm:ss').format(order.createdAt)}",
    );

    buffer.writeln("------------------------------------------");

    for (var item in items) {
      String itemName = item.product.name;

      if (item.isRemoved) {
        itemName = "[REMOVED] $itemName";
      }

      buffer.writeln(
        "${itemName}  -> ${item.quantity} ${item.unit.unitDisplay}",
      );

      if (item.notes.isNotEmpty) {
        buffer.writeln("   NOTE: ${item.notes}");
      }

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

  void _generateKOTTicket(
    NetworkPrinter printer,
    OrderModel order,
    List<OrderItem> items, {
    required String status,
    required String invoiceLabel,
  }) {
    final removedItems = items.where((i) => i.isRemoved).toList();
    final newItems = items.where((i) => !i.isRemoved).toList();

    printer.text(
      "Token No : $invoiceLabel",
      styles: const PosStyles(
        align: PosAlign.center,
        bold: true,
        height: PosTextSize.size2,
      ),
    );
    printer.text(
      "KITCHEN ORDER",
      styles: const PosStyles(align: PosAlign.center, bold: true),
    );
    printer.hr();

    // Status badge with change type
    if (status == "Modified") {
      printer.text(
        "*** ORDER MODIFIED ***",
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
        ),
      );
    } else if (status == "CANCELLED") {
      printer.text(
        "*** ORDER CANCELLED ***",
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
        ),
      );
    } else {
      printer.text(
        "*** NEW ORDER ***",
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
        ),
      );
    }

    printer.row([
      PosColumn(text: "Order No:", width: 6),
      PosColumn(
        text: invoiceLabel,
        width: 6,
        styles: const PosStyles(align: PosAlign.right),
      ),
    ]);

    printer.row([
      PosColumn(text: "Order type:", width: 6),
      PosColumn(
        // text: OrderType.values
        //     .firstWhere(
        //       (e) => e.id == order.sales_odr_order_type,
        //       orElse: () => OrderType.dineIn,
        //     )
        //     .displayName,
        text: (GetStorage().read('selected_order_type_id') == 0
            ? 'Dine In'
            : GetStorage().read('selected_order_type_id') == 1
            ? 'Delivery'
            : GetStorage().read('selected_order_type_id') == 2
            ? 'Pick Up'
            : ''),
        width: 6,
        styles: const PosStyles(align: PosAlign.right),
      ),
    ]);

    if (order.captainName != null && order.captainName!.isNotEmpty) {
      printer.row([
        PosColumn(text: "Captain:", width: 6),
        PosColumn(
          text: order.captainName!,
          width: 6,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);
    }

    if (GetStorage().read('selected_order_type_id') == 0) {
      printer.row([
        PosColumn(text: "Table:", width: 6),
        PosColumn(
          text: "${order.tableName} (${order.chairNumber} Seats)",
          width: 6,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);
    }

    printer.row([
      PosColumn(text: "Date:", width: 6),
      PosColumn(
        text: DateFormat('dd/MM/yyyy').format(order.createdAt),
        width: 6,
        styles: const PosStyles(align: PosAlign.right),
      ),
    ]);
    printer.row([
      PosColumn(text: "Time:", width: 6),
      PosColumn(
        text: DateFormat('HH:mm:ss').format(order.createdAt),
        width: 6,
        styles: const PosStyles(align: PosAlign.right),
      ),
    ]);

    // ─── QUANTITY DECREASES / REMOVED SECTION ───
    if (removedItems.isNotEmpty) {
      printer.hr();
      String sectionTitle = status == "CANCELLED"
          ? "CANCELLED ITEMS"
          : "QUANTITY DECREASED / REMOVED";
      printer.text(
        sectionTitle,
        styles: const PosStyles(align: PosAlign.center, bold: true),
      );
      printer.hr();
      printer.row([
        PosColumn(text: "Item", width: 8, styles: const PosStyles(bold: true)),
        PosColumn(
          text: status == "CANCELLED" ? "Qty" : "Qty Removed",
          width: 4,
          styles: const PosStyles(align: PosAlign.right, bold: true),
        ),
      ]);
      printer.text('-' * 42);

      for (var item in removedItems) {
        printer.row([
          PosColumn(
            text: status == "CANCELLED"
                ? item.product.name
                : "${item.product.name}",
            width: 8,
            styles: const PosStyles(bold: true),
          ),
          PosColumn(
            text: "${item.quantity} ${item.unit.unitDisplay}",
            width: 4,
            styles: const PosStyles(align: PosAlign.right, bold: true),
          ),
        ]);

        if (item.notes.isNotEmpty) {
          printer.text(
            "   NOTE: ${item.notes}",
            styles: const PosStyles(bold: true),
          );
        }

        for (var addon in item.selectedAddons) {
          printer.row([
            PosColumn(text: "  - ${addon.name}", width: 8),
            PosColumn(
              text: "${addon.quantity.value} ${addon.unitDisplay}",
              width: 4,
              styles: const PosStyles(align: PosAlign.right),
            ),
          ]);
        }
      }
    }

    // ─── QUANTITY INCREASES / NEW SECTION ───
    if (newItems.isNotEmpty) {
      printer.hr();
      String sectionTitle = status == "Modified"
          ? "QUANTITY INCREASED / NEW"
          : "ORDER ITEMS";
      printer.text(
        sectionTitle,
        styles: const PosStyles(align: PosAlign.center, bold: true),
      );
      printer.hr();
      printer.row([
        PosColumn(text: "Item", width: 8),
        PosColumn(
          text: status == "Modified" ? "Qty Added" : "Qty",
          width: 4,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);
      printer.text('-' * 42);

      for (var item in newItems) {
        // Show if this is a partial increase
        String qtyDisplay = item.quantity.toString();
        printer.row([
          PosColumn(
            text: "${item.product.name}",
            width: 8,
            // styles: const PosStyles(bold: true),
          ),
          PosColumn(
            text: "$qtyDisplay ${item.unit.unitDisplay}",
            width: 4,
            styles: const PosStyles(align: PosAlign.right),
          ),
        ]);

        if (item.notes.isNotEmpty) {
          printer.text(
            "   NOTE: ${item.notes}",
            styles: const PosStyles(bold: true),
          );
        }

        for (var addon in item.selectedAddons) {
          printer.row([
            PosColumn(text: "  + ${addon.name}", width: 8),
            PosColumn(
              text: "${addon.quantity.value} ${addon.unitDisplay}",
              width: 4,
              styles: const PosStyles(align: PosAlign.right),
            ),
          ]);
        }
      }
    }

    printer.hr();
    printer.text(
      "*** Kitchen Copy ***",
      styles: const PosStyles(align: PosAlign.center),
    );
    printer.feed(3);
    printer.cut();
  }

  @override
  void onClose() {
    _scanSubscription?.cancel();
    super.onClose();
  }
}
