import 'dart:async';
import 'dart:io';
import 'package:esc_pos_printer_plus/esc_pos_printer_plus.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:get/get_instance/src/extension_instance.dart';
import 'package:get/get_navigation/src/extension_navigation.dart';
import 'package:get/get_navigation/src/root/parse_route.dart';
import 'package:get/get_navigation/src/snackbar/snackbar.dart';
import 'package:get/get_rx/src/rx_types/rx_types.dart';
import 'package:get/get_state_manager/src/simple/get_controllers.dart';
import 'package:intl/intl.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import '../../../data/models/order_model.dart';
import '../../../data/services/database_helper.dart';
import '../views/dashoard/models/dashboard_models.dart';
import 'dashboard_controller.dart';

class PrinterModel {
  String name;
  final String address;
  final String type; // bluetooth or wifi
  final dynamic device; // Original device object
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

  // Permission state
  var isBluetoothPermissionGranted = true.obs;

  var tokenPrinterAssignments = <TokenPrinterAssignment>[].obs;

  final NetworkInfo _networkInfo = NetworkInfo();
  StreamSubscription? _scanSubscription;

  List<PrinterModel> get filteredBluetoothDevices {
    if (!showOnlyPrinters.value) return bluetoothPrinters;
    return bluetoothPrinters.where((d) => d.isLikelyPrinter).toList();
  }

  @override
  void onInit() {
    super.onInit();
    _initWifi();
    _loadSavedMappings();
    _listenToBleScan();

    // Initial scan with permission check
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

      // ✅ Corrected: Fetch ALL categories in the background specifically for mapping
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

  Future<void> updateTokenPrinter(
      int tokenPrinterId,
      PrinterModel printer,
      ) async {
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

    Get.snackbar(
      "Saved",
      "Token Printer $tokenPrinterId linked to ${printer.name}",
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: Colors.green,
      colorText: Colors.white,
      duration: const Duration(seconds: 1),
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
        Get.snackbar(
          "Bluetooth Off",
          "Please enable Bluetooth",
          backgroundColor: Colors.orange,
          colorText: Colors.white,
        );
        scanningBluetooth.value = false;
        return;
      }

      bluetoothPrinters.clear();

      // 1. Get Paired Devices (Classic Bluetooth)
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

      // 2. Start Live BLE Scan
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
      // Added more common printer ports (9100=RAW, 515=LPD, 631=IPP, 80=Web, 8008/8009=Epson ePOS)
      final List<int> printerPorts = [9100, 515, 631, 80, 8008, 8009];

      // Scanning the full subnet in batches
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
      // Slightly longer timeout for better reliability across different router types
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

  // --- RECEIPT PRINTING LOGIC ---
  Future<void> printReceipt(OrderModel order, double received, double change) async {
    debugPrint("--- START RECEIPT PRINTING ---");
    // For receipts, we usually print to the "Main" or "Cashier" printer.
    // Let's assume the first printer in assignments is the default.
    final assignment = tokenPrinterAssignments.isNotEmpty ? tokenPrinterAssignments.first : null;
    final address = assignment?.printerAddress.value ?? "";
    final type = assignment?.printerType.value ?? "bluetooth";

    if (address.isEmpty) {
      debugPrint("No printer assigned for receipt.");
      return;
    }

    final profile = await CapabilityProfile.load();
    if (type == 'wifi') {
      await _printWifiReceipt(address, order, received, change, profile);
    } else {
      final printerInfo = PrinterModel(name: assignment!.printerName.value, address: address, type: 'bluetooth');
      await _printBluetoothReceipt(printerInfo, order, received, change, profile);
    }
  }

  Future<void> _printWifiReceipt(String ip, OrderModel order, double received, double change, CapabilityProfile profile) async {
    try {
      final printer = NetworkPrinter(PaperSize.mm80, profile);
      final res = await printer.connect(ip, port: 9100);
      if (res == PosPrintResult.success) {
        _generateReceiptTicket(printer, order, received, change);
        await Future.delayed(const Duration(milliseconds: 500));
        printer.disconnect();
      }
    } catch (e) { debugPrint("WiFi Receipt Error: $e"); }
  }

  Future<void> _printBluetoothReceipt(PrinterModel printer, OrderModel order, double received, double change, CapabilityProfile profile) async {
    try {
      bool connected = await PrintBluetoothThermal.connectionStatus;
      if (!connected) {
        await PrintBluetoothThermal.connect(macPrinterAddress: printer.address);
      }
      final generator = Generator(PaperSize.mm80, profile);
      List<int> bytes = [];
      bytes += generator.setGlobalFont(PosFontType.fontA);

      // Header
      bytes += generator.text("REST POS", styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2));
      bytes += generator.text("Final Receipt", styles: const PosStyles(align: PosAlign.center));
      bytes += generator.text("-" * 48);

      bytes += generator.row([
        PosColumn(text: "Order: ${order.invNo}", width: 6),
        PosColumn(text: DateFormat('dd/MM/yy HH:mm').format(order.createdAt), width: 6, styles: const PosStyles(align: PosAlign.right)),
      ]);
      
      // ✅ Added Table and Chair count for Bluetooth Receipt
      bytes += generator.text(
        "Table: ${order.tableName}",
        styles: const PosStyles(align: PosAlign.center),
      );
      
      bytes += generator.text("-" * 48);

      for (var item in order.items.where((i) => !i.isRemoved)) {
        bytes += generator.row([
          PosColumn(text: "${item.quantity}x ${item.product.name}", width: 9),
          PosColumn(text: (item.priceAtOrder * item.quantity).toStringAsFixed(2), width: 3, styles: const PosStyles(align: PosAlign.right)),
        ]);
      }

      bytes += generator.text("-" * 48);
      bytes += generator.row([
        PosColumn(text: "TOTAL", width: 6, styles: const PosStyles(bold: true)),
        PosColumn(text: order.totalAmount.toStringAsFixed(2), width: 6, styles: const PosStyles(align: PosAlign.right, bold: true)),
      ]);
      bytes += generator.row([
        PosColumn(text: "Received", width: 6),
        PosColumn(text: received.toStringAsFixed(2), width: 6, styles: const PosStyles(align: PosAlign.right)),
      ]);
      bytes += generator.row([
        PosColumn(text: "Change", width: 6),
        PosColumn(text: change.toStringAsFixed(2), width: 6, styles: const PosStyles(align: PosAlign.right)),
      ]);

      bytes += generator.text("-" * 48);
      bytes += generator.text("Thank You!", styles: const PosStyles(align: PosAlign.center));
      bytes += generator.feed(2);
      bytes += generator.cut();

      await PrintBluetoothThermal.writeBytes(bytes);
    } catch (e) { debugPrint("BT Receipt Error: $e"); }
  }

  void _generateReceiptTicket(NetworkPrinter printer, OrderModel order, double received, double change) {
    printer.text("REST POS", styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2));
    printer.hr();
    printer.text("Invoice: ${order.invNo}", styles: const PosStyles(align: PosAlign.center));
    printer.text("Table: ${order.tableName} (Seats: ${order.chairNumber})", styles: const PosStyles(align: PosAlign.center));
    printer.hr();
    for (var item in order.items.where((i) => !i.isRemoved)) {
      printer.row([
        PosColumn(text: "${item.quantity}x ${item.product.name}", width: 9),
        PosColumn(text: (item.priceAtOrder * item.quantity).toStringAsFixed(2), width: 3, styles: const PosStyles(align: PosAlign.right)),
      ]);
    }
    printer.hr();
    printer.row([
      PosColumn(text: "TOTAL", width: 6, styles: const PosStyles(bold: true)),
      PosColumn(text: order.totalAmount.toStringAsFixed(2), width: 6, styles: const PosStyles(align: PosAlign.right, bold: true)),
    ]);
    printer.row([
      PosColumn(text: "Received", width: 6),
      PosColumn(text: received.toStringAsFixed(2), width: 6, styles: const PosStyles(align: PosAlign.right)),
    ]);
    printer.row([
      PosColumn(text: "Change", width: 6),
      PosColumn(text: change.toStringAsFixed(2), width: 6, styles: const PosStyles(align: PosAlign.right)),
    ]);
    printer.hr();
    printer.text("Thank You!", styles: const PosStyles(align: PosAlign.center));
    printer.feed(3);
    printer.cut();
  }

  // --- KOT PRINTING LOGIC ---
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
          if (!item.isRemoved) itemKey(item): item
      };

      final oldMap = {for (var item in oldItems) itemKey(item): item};

      Set<String> allKeys = {...oldMap.keys, ...newMap.keys};

      for (var key in allKeys) {
        final oldItem = oldMap[key];
        final newItem = newMap[key];

        if (oldItem == null && newItem != null && !newItem.isRemoved) {
          // ✅ Completely new item
          itemsToPrint.add(newItem);
          debugPrint("🆕 NEW ITEM: ${newItem.product.name} x${newItem.quantity}");

        } else if (newItem == null && oldItem != null) {
          // ✅ Item removed entirely
          itemsToPrint.add(OrderItem(
            subId: oldItem.subId,
            product: oldItem.product,
            quantity: oldItem.quantity,
            priceAtOrder: oldItem.priceAtOrder,
            unit: oldItem.unit,
            unitId: oldItem.unitId,
            tokenPrinterId: oldItem.tokenPrinterId,
            selectedAddons: oldItem.selectedAddons,
            isRemoved: true,
          ));
          debugPrint("❌ REMOVED ITEM: ${oldItem.product.name} x${oldItem.quantity}");

        } else if (oldItem != null && newItem != null) {
          // ✅ Item exists in both - check for changes

          final int qtyDifference = newItem.quantity - oldItem.quantity;
          final bool qtyIncreased = qtyDifference > 0;
          final bool qtyDecreased = qtyDifference < 0;

          // Check addon changes
          final oldAddonMap = {for (var a in oldItem.selectedAddons) a.prdId: a};
          final newAddonMap = {for (var a in newItem.selectedAddons) a.prdId: a};
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
              debugPrint("➕ ADDED ADDON: ${newAddon.name} x${newAddon.quantity.value}");
            } else if (newAddon == null && oldAddon != null) {
              addonsChanged = true;
              removedAddons.add(oldAddon);
              debugPrint("➖ REMOVED ADDON: ${oldAddon.name}");
            } else if (oldAddon != null && newAddon != null &&
                oldAddon.quantity.value != newAddon.quantity.value) {
              addonsChanged = true;
              modifiedAddons.add(newAddon);
              debugPrint("🔄 MODIFIED ADDON: ${newAddon.name} ${oldAddon.quantity.value} → ${newAddon.quantity.value}");
            }
          }

          // ✅ Handle quantity changes - print as a single change item
          if (qtyIncreased) {
            // Print Increased quantity
            itemsToPrint.add(OrderItem(
              subId: newItem.subId,
              product: newItem.product,
              quantity: qtyDifference,  // Only the increased amount
              priceAtOrder: newItem.priceAtOrder,
              unit: newItem.unit,
              unitId: newItem.unitId,
              tokenPrinterId: newItem.tokenPrinterId,
              selectedAddons: newItem.selectedAddons,
              isRemoved: false,
            ));
            debugPrint("⬆️ INCREASED QTY: ${newItem.product.name} +$qtyDifference (${oldItem.quantity} → ${newItem.quantity})");

          } else if (qtyDecreased) {
            // Print Decreased quantity (as removed)
            itemsToPrint.add(OrderItem(
              subId: oldItem.subId,
              product: oldItem.product,
              quantity: -qtyDifference,  // Positive number of units removed
              priceAtOrder: oldItem.priceAtOrder,
              unit: oldItem.unit,
              unitId: oldItem.unitId,
              tokenPrinterId: oldItem.tokenPrinterId,
              selectedAddons: oldItem.selectedAddons,
              isRemoved: true,
            ));
            debugPrint("⬇️ DECREASED QTY: ${oldItem.product.name} -${-qtyDifference} (${oldItem.quantity} → ${newItem.quantity})");
          }

          // ✅ Handle addon changes separately (if no quantity change)
          if (!qtyIncreased && !qtyDecreased && addonsChanged) {
            // Print modified item with addon changes
            itemsToPrint.add(OrderItem(
              subId: newItem.subId,
              product: newItem.product,
              quantity: newItem.quantity,
              priceAtOrder: newItem.priceAtOrder,
              unit: newItem.unit,
              unitId: newItem.unitId,
              tokenPrinterId: newItem.tokenPrinterId,
              selectedAddons: newItem.selectedAddons,
              isRemoved: false,
            ));
            debugPrint("🔄 ADDON CHANGES ONLY: ${newItem.product.name}");
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
    final cancelledItems = order.items.map((item) => OrderItem(
      product: item.product,
      unit: item.unit,
      quantity: item.quantity,
      priceAtOrder: item.priceAtOrder,
      selectedAddons: item.selectedAddons,
      tokenPrinterId: item.tokenPrinterId,
      isRemoved: true,
    )).toList();

    await _distributeToPrinters(order, cancelledItems, status: "CANCELLED");
  }

  /// ✅ Helper to resolve the correct Token Printer ID for an item
  int? _resolveTokenPrinterId(OrderItem item) {
    if (!Get.isRegistered<DashboardController>()) return item.tokenPrinterId;
    final dashboardController = Get.find<DashboardController>();

    // 1. Try directly from OrderItem (might be populated from Cart)
    if (item.tokenPrinterId != null && item.tokenPrinterId != 0) {
      return item.tokenPrinterId;
    }

    // 2. Try from FoodItemModel (often populated from cat_token_printer in DB)
    if (item.product.tokenPrinterId != null && item.product.tokenPrinterId != 0) {
      return item.product.tokenPrinterId;
    }

    // 3. Fallback: Lookup in the full category list (allCategoriesForPrinters)
    // This is important for items in categories not explicitly shown in POS view
    final category = dashboardController.allCategoriesForPrinters.firstWhereOrNull(
          (c) => c.id == item.product.categoryId,
    );
    if (category != null && category.tokenPrinterId != 0) {
      return category.tokenPrinterId;
    }

    // 4. Final Fallback: Check the standard categories list
    final mainCategory = dashboardController.categories.firstWhereOrNull(
          (c) => c.id == item.product.categoryId,
    );
    return mainCategory?.tokenPrinterId;
  }

  Future<void> _distributeToPrinters(OrderModel order, List<OrderItem> items, {required String status}) async {
    debugPrint("📍 DISTRIBUTING TO PRINTERS - Status: $status, Items: ${items.length}");

    Map<String, List<OrderItem>> printerGroups = {};

    for (var item in items) {
      debugPrint("  📦 Processing item: ${item.product.name}, qty: ${item.quantity}, isRemoved: ${item.isRemoved}");

      int? tokenId = _resolveTokenPrinterId(item);
      debugPrint("  📌 Resolved Token ID: $tokenId");

      if (tokenId == null || tokenId == 0) {
        debugPrint("  ⚠️ No token printer ID for item: ${item.product.name}");
        continue;
      }

      final assignment = tokenPrinterAssignments.firstWhereOrNull((a) => a.tokenPrinterId == tokenId);
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
      var printerInfo = allPrinters.firstWhereOrNull((p) => p.address == address);

      if (printerInfo == null) {
        final assignment = tokenPrinterAssignments.firstWhereOrNull((a) => a.printerAddress.value == address);
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
        await _printWifiKOT(address, order, groupItems, profile, status: status);
      } else {
        debugPrint("  📡 Sending to Bluetooth printer...");
        await _printBluetoothKOT(printerInfo, order, groupItems, profile, status: status);
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
      }) async {
    try {
      final printer = NetworkPrinter(PaperSize.mm80, profile);
      final res = await printer.connect(ip, port: 9100);

      if (res == PosPrintResult.success) {
        _generateKOTTicket(printer, order, items, status: status);

        await Future.delayed(const Duration(milliseconds: 300));

        printer.disconnect();
      }
    } catch (e) {
      debugPrint("WiFi Print Error: $e");
    }
  }

  Future<void> _printBluetoothKOT(PrinterModel printer, OrderModel order, List<OrderItem> items, CapabilityProfile profile, {required String status}) async {
    try {
      debugPrint("🔵 _printBluetoothKOT called for ${printer.name}");

      bool connected = await PrintBluetoothThermal.connectionStatus;
      if (!connected) {
        debugPrint("🔵 Not connected, attempting to connect to ${printer.address}");
        bool res = await PrintBluetoothThermal.connect(macPrinterAddress: printer.address);
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

      debugPrint("🔵 Removed items: ${removedItems.length}, New items: ${newItems.length}");

      // Always print header
      bytes += generator.setGlobalFont(PosFontType.fontA);
      bytes += generator.text(
        "Token No : ${order.invNo}",
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        ),
      );
      bytes += generator.text(
        "SIMPLIFIED TAX INVOICE",
        styles: const PosStyles(align: PosAlign.center, bold: true),
      );
      bytes += generator.text('-' * 48);

      // Order info
      bytes += generator.row([
        PosColumn(text: "Order No:", width: 6),
        PosColumn(text: order.invNo, width: 6, styles: const PosStyles(align: PosAlign.right)),
      ]);
      bytes += generator.row([
        PosColumn(text: "Table:", width: 6),
        PosColumn(
          text: "${order.tableName} (${order.chairNumber} Seats)",
          width: 6,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);

      // ─── CANCELLED / REMOVED SECTION ───
      if (removedItems.isNotEmpty) {
        debugPrint("🔵 Printing ${removedItems.length} removed items");
        bytes += generator.text('=' * 48, styles: const PosStyles(bold: true));
        bytes += generator.text(
          "QUANTITY DECREASED / REMOVED",
          styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2),
        );
        bytes += generator.text('=' * 48, styles: const PosStyles(bold: true));
        bytes += generator.row([
          PosColumn(text: "Item", width: 8, styles: const PosStyles(bold: true)),
          PosColumn(text: "Qty Removed", width: 4, styles: const PosStyles(align: PosAlign.right, bold: true)),
        ]);
        bytes += generator.text('-' * 48);

        for (var item in removedItems) {
          debugPrint("🔵 Printing removed: ${item.product.name} x${item.quantity}");
          bytes += generator.row([
            PosColumn(text: "✗ ${item.product.name}", width: 8, styles: const PosStyles(bold: true)),
            PosColumn(text: "${item.quantity} ${item.unit.unitDisplay}", width: 4,
                styles: const PosStyles(align: PosAlign.right, bold: true)),
          ]);
          for (var addon in item.selectedAddons) {
            bytes += generator.row([
              PosColumn(text: "  - ${addon.name}", width: 8),
              PosColumn(text: "${addon.quantity.value} ${addon.unitDisplay}", width: 4,
                  styles: const PosStyles(align: PosAlign.right)),
            ]);
          }
        }
      }

      // ─── NEW / UPDATED SECTION ───
      if (newItems.isNotEmpty) {
        debugPrint("🔵 Printing ${newItems.length} new/updated items");
        bytes += generator.text('=' * 48, styles: const PosStyles(bold: true));
        bytes += generator.text(
          "QUANTITY INCREASED / NEW",
          styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2),
        );
        bytes += generator.text('=' * 48, styles: const PosStyles(bold: true));
        bytes += generator.row([
          PosColumn(text: "Item", width: 8, styles: const PosStyles(bold: true)),
          PosColumn(text: "Qty Added", width: 4, styles: const PosStyles(align: PosAlign.right, bold: true)),
        ]);
        bytes += generator.text('-' * 48);

        for (var item in newItems) {
          debugPrint("🔵 Printing new: ${item.product.name} x${item.quantity}");
          bytes += generator.row([
            PosColumn(text: "${item.product.name}", width: 8, styles: const PosStyles(bold: true)),
            PosColumn(text: "${item.quantity} ${item.unit.unitDisplay}", width: 4,
                styles: const PosStyles(align: PosAlign.right, bold: true)),
          ]);
          for (var addon in item.selectedAddons) {
            bytes += generator.row([
              PosColumn(text: "  + ${addon.name}", width: 8),
              PosColumn(text: "${addon.quantity.value} ${addon.unitDisplay}", width: 4,
                  styles: const PosStyles(align: PosAlign.right)),
            ]);
          }
        }
      }

      // Footer
      bytes += generator.text('=' * 48, styles: const PosStyles(bold: true));
      bytes += generator.text(
        "*** Kitchen Copy ***",
        styles: const PosStyles(align: PosAlign.center),
      );
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
  void _logKOTData(OrderModel order, List<OrderItem> items, String status, String printerType, String address) {
    final buffer = StringBuffer();

    buffer.writeln("🖨️ ===== KOT PRINT START =====");
    buffer.writeln("Printer Type : $printerType");
    buffer.writeln("Printer Addr : $address");
    buffer.writeln("Status       : $status");

    buffer.writeln("Token No     : ${order.invNo}");
    buffer.writeln("Table        : ${order.tableName} (${order.chairNumber} Seats)");
    buffer.writeln("Date         : ${DateFormat('dd/MM/yyyy HH:mm:ss').format(order.createdAt)}");

    buffer.writeln("------------------------------------------");

    for (var item in items) {
      String itemName = item.product.name;

      if (item.isRemoved) {
        itemName = "[REMOVED] $itemName";
      }

      buffer.writeln("${itemName}  -> ${item.quantity} ${item.unit.unitDisplay}");

      for (var addon in item.selectedAddons) {
        buffer.writeln("   + ${addon.name} -> ${addon.quantity.value} ${addon.unitDisplay}");
      }
    }

    buffer.writeln("------------------------------------------");
    buffer.writeln("🖨️ ===== KOT PRINT END =====");

    debugPrint(buffer.toString());
  }

  void _generateKOTTicket(NetworkPrinter printer, OrderModel order, List<OrderItem> items, {required String status}) {
    final removedItems = items.where((i) => i.isRemoved).toList();
    final newItems = items.where((i) => !i.isRemoved).toList();

    printer.text("Token No : ${order.invNo}",
        styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2));
    printer.text("SIMPLIFIED TAX INVOICE",
        styles: const PosStyles(align: PosAlign.center, bold: true));
    printer.hr();

    // Status badge with change type
    if (status == "Modified") {
      printer.text("*** ORDER MODIFIED ***",
          styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2));
    } else {
      printer.text("*** NEW ORDER ***",
          styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2));
    }

    printer.row([
      PosColumn(text: "Order No:", width: 6),
      PosColumn(text: order.invNo, width: 6, styles: const PosStyles(align: PosAlign.right)),
    ]);

    printer.row([
      PosColumn(text: "Table:", width: 6),
      PosColumn(
        text: "${order.tableName} (${order.chairNumber} Seats)",
        width: 6,
        styles: const PosStyles(align: PosAlign.right),
      ),
    ]);

    printer.row([
      PosColumn(text: "Date:", width: 6),
      PosColumn(text: DateFormat('dd/MM/yyyy').format(order.createdAt), width: 6, styles: const PosStyles(align: PosAlign.right)),
    ]);
    printer.row([
      PosColumn(text: "Time:", width: 6),
      PosColumn(text: DateFormat('HH:mm:ss').format(order.createdAt), width: 6, styles: const PosStyles(align: PosAlign.right)),
    ]);

    // ─── QUANTITY DECREASES / REMOVED SECTION ───
    if (removedItems.isNotEmpty) {
      printer.hr();
      printer.text("QUANTITY DECREASED / REMOVED",
          styles: const PosStyles(align: PosAlign.center, bold: true));
      printer.hr();
      printer.row([
        PosColumn(text: "Item", width: 8, styles: const PosStyles(bold: true)),
        PosColumn(text: "Qty Removed", width: 4, styles: const PosStyles(align: PosAlign.right, bold: true)),
      ]);
      printer.text('-' * 42);

      for (var item in removedItems) {
        printer.row([
          PosColumn(text: "✗ ${item.product.name}", width: 8, styles: const PosStyles(bold: true)),
          PosColumn(text: "${item.quantity} ${item.unit.unitDisplay}", width: 4,
              styles: const PosStyles(align: PosAlign.right, bold: true)),
        ]);
        for (var addon in item.selectedAddons) {
          printer.row([
            PosColumn(text: "  - ${addon.name}", width: 8),
            PosColumn(text: "${addon.quantity.value} ${addon.unitDisplay}", width: 4,
                styles: const PosStyles(align: PosAlign.right)),
          ]);
        }
      }
    }

    // ─── QUANTITY INCREASES / NEW SECTION ───
    if (newItems.isNotEmpty) {
      printer.hr();
      printer.text("QUANTITY INCREASED / NEW",
          styles: const PosStyles(align: PosAlign.center, bold: true));
      printer.hr();
      printer.row([
        PosColumn(text: "Item", width: 8, styles: const PosStyles(bold: true)),
        PosColumn(text: "Qty Added", width: 4, styles: const PosStyles(align: PosAlign.right, bold: true)),
      ]);
      printer.text('-' * 42);

      for (var item in newItems) {
        // Show if this is a partial increase
        String qtyDisplay = item.quantity.toString();
        printer.row([
          PosColumn(text: "✓ ${item.product.name}", width: 8, styles: const PosStyles(bold: true)),
          PosColumn(text: "$qtyDisplay ${item.unit.unitDisplay}", width: 4,
              styles: const PosStyles(align: PosAlign.right, bold: true)),
        ]);
        for (var addon in item.selectedAddons) {
          printer.row([
            PosColumn(text: "  + ${addon.name}", width: 8),
            PosColumn(text: "${addon.quantity.value} ${addon.unitDisplay}", width: 4,
                styles: const PosStyles(align: PosAlign.right)),
          ]);
        }
      }
    }

    printer.hr();
    printer.text("*** Kitchen Copy ***", styles: const PosStyles(align: PosAlign.center));
    printer.feed(3);
    printer.cut();
  }

  @override
  void onClose() {
    _scanSubscription?.cancel();
    super.onClose();
  }
}
