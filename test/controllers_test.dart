import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:restaurant_pos/app/data/Device_Roles/device_roles.dart';
import 'package:restaurant_pos/app/data/models/order_model.dart';
import 'package:restaurant_pos/app/data/models/order_type.dart';
import 'package:restaurant_pos/app/data/services/api_services.dart';
import 'package:restaurant_pos/app/data/services/order_submission.dart';
import 'package:restaurant_pos/app/data/services/sync_service.dart';
import 'package:restaurant_pos/app/data/utils/AppState.dart';
import 'package:restaurant_pos/app/modules/auth/controllers/auth_controller.dart';
import 'package:restaurant_pos/app/modules/cart/controller/cart_controller.dart';
import 'package:restaurant_pos/app/modules/home/controller/cashier_controller.dart';
import 'package:restaurant_pos/app/modules/home/controller/dashboard_controller.dart';
import 'package:restaurant_pos/app/modules/home/controller/home_controller.dart';
import 'package:restaurant_pos/app/modules/home/controller/order_controller.dart';
import 'package:restaurant_pos/app/modules/home/controller/printer_controller.dart';
import 'package:restaurant_pos/app/modules/home/controller/settings_controller.dart';
import 'package:restaurant_pos/app/modules/home/controller/table_controller.dart';
import 'package:restaurant_pos/app/modules/home/views/dashoard/models/dashboard_models.dart';
import 'package:restaurant_pos/app/modules/order_type/controller/order_type_controller.dart';
import 'package:restaurant_pos/app/theme/theme_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  late Directory storageDirectory;

  setUpAll(() async {
    storageDirectory = await Directory.systemTemp.createTemp(
      'pos_controllers_',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          pathProvider,
          (_) async => storageDirectory.path,
        );
    await GetStorage.init();
  });

  setUp(() {
    Get.testMode = true;
    Get.put(ApiService());
  });

  tearDown(() async {
    Get.reset();
    Get.testMode = false;
    await GetStorage().erase();
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    await storageDirectory.delete(recursive: true);
  });

  test('order submission guard is shared across entry points', () {
    final cart = CartController();
    final first = OrderSubmission(cart);
    final second = OrderSubmission(cart);

    expect(first.tryBegin(), isTrue);
    expect(second.tryBegin(), isFalse);
    first.finish();
    expect(second.tryBegin(), isTrue);
    second.finish();
    expect(cart.isProcessing.value, isFalse);
  });

  group('CartController', () {
    test('preserves paid add-on quantity when free allowance grows', () {
      final cart = CartController();
      final addon = AddonModel(
        id: 1,
        prdId: 2,
        prdaddon_flags: 0,
        name: 'Sauce',
        price: 4,
        unitDisplay: 'each',
        taxPer: 5,
        initialQty: 2,
        freeQty: 1,
      );
      final item = CartItem(
        product: _product(),
        unit: _unit(),
        selectedAddons: [addon],
      );
      cart.cartItems.add(item);

      cart.updateQuantity(item, 3);

      expect(addon.quantity.value, 4);
      expect(cart.totalItemsCount, 3);
      expect(cart.totalAmount, 64);
      expect(cart.totalTaxAmount, closeTo(6.2, 0.001));
      expect(cart.grandTotal, closeTo(70.2, 0.001));
    });

    test(
      'retains removed order lines for editing and excludes them from totals',
      () {
        final cart = CartController();
        final saved = CartItem(
          subId: 7,
          product: _product(),
          unit: _unit(),
          qty: 2,
        );
        final unsaved = CartItem(product: _product(), unit: _unit());
        cart.editingOrderId.value = '42';
        cart.cartItems.addAll([saved, unsaved]);

        cart.removeItem(saved);
        expect(cart.cartItems, contains(saved));
        expect(saved.isDeleted.value, isTrue);
        expect(saved.quantity.value, 0);
        expect(cart.totalItemsCount, 1);
        expect(cart.totalAmount, 20);

        cart.removeItem(unsaved);
        expect(cart.cartItems, [saved]);
        expect(cart.grandTotal, 0);
      },
    );
  });

  group('OrdersController', () {
    test('resolves details by invoice across active and sold orders', () {
      final controller = OrdersController();
      final summary = _order(id: 'local', invoice: 'INV-42');
      final detail = _order(
        id: '42',
        invoice: 'INV-42',
        items: [
          OrderItem(
            product: _product(),
            unit: _unit(),
            quantity: 1,
            priceAtOrder: 20,
          ),
        ],
      );
      controller.orders.add(summary);
      controller.soldOrders.add(detail);

      expect(controller.resolveOrder(summary), same(detail));
      expect(controller.detailsState(summary), OrderDetailsState.loaded);
    });

    test(
      'keeps separate offline orders distinct and prioritizes a retry in progress',
      () {
        final controller = OrdersController();
        final first = _order(id: 'first', invoice: 'OFFLINE');
        final second = _order(id: 'second', invoice: 'OFFLINE');
        controller.orders.add(first);
        controller.detailsFailedIds.add(second.id);

        expect(controller.resolveOrder(second), same(second));
        expect(controller.detailsState(second), OrderDetailsState.failed);
        controller.loadingOrderDetailsIds.add(second.id);
        expect(controller.detailsState(second), OrderDetailsState.loading);
      },
    );

    test('formats elapsed time using the current clock value', () {
      final controller = OrdersController();
      final now = DateTime(2026, 11, 25, 12);
      controller.currentTime.value = now;

      expect(
        controller.getElapsedTime(now.add(const Duration(seconds: 1))),
        '00:00',
      );
      expect(
        controller.getElapsedTime(
          now.subtract(const Duration(minutes: 2, seconds: 5)),
        ),
        '02:05',
      );
      expect(
        controller.getElapsedTime(
          now.subtract(const Duration(hours: 1, seconds: 5)),
        ),
        '01:00:05',
      );
    });
  });

  test(
    'TablesController counts local replacements and excludes the edited order',
    () {
      final cart = Get.put<CartController>(_CartWithoutCaptainLoad());
      final controller = TablesController();
      final table = TableModel(
        id: 4,
        name: 'Table 4',
        chairCount: 10,
        availableSeatCount: 8,
        processingTable: [
          {'sales_odr_id': 1, 'sales_odr_no_seats': 2},
          {'sales_odr_id': 2, 'sales_odr_no_seats': 3},
          {'sales_odr_id': 3, 'sales_odr_no_seats': '1'},
        ],
      );
      cart.editingOrderId.value = '1';
      cart.selectedTableId.value = '4';
      cart.selectedChairCount.value = 4;
      controller.pendingUpdateIds.add('2');
      controller.localOrdersOccupancy[4] = 2;

      expect(
        controller.getOccupiedCountForTable(
          table,
          includeCurrentSelection: false,
        ),
        3,
      );
      expect(controller.getOccupiedCountForTable(table), 7);
    },
  );

  test('HomeController updates the page title with the selected tab', () {
    final controller = HomeController();
    expect(controller.pageTitle, 'dashboard');

    controller.changeIndex(2);
    expect(controller.selectedIndex.value, 2);
    expect(controller.pageTitle, 'orders');
  });

  test(
    'OrderTypeController routes dine-in to table selection and clears the table for pickup',
    () async {
      final home = Get.put(HomeController());
      final cart = Get.put<CartController>(_CartWithoutCaptainLoad());
      final controller = OrderTypeController();

      await controller.selectOrderType(OrderType.dineIn, navigate: false);
      expect(home.pageTitle, 'tables');

      cart.selectedTableId.value = '4';
      cart.selectedChairCount.value = 2;
      await controller.selectOrderType(OrderType.dineIn, navigate: false);
      expect(home.pageTitle, 'dashboard');
      expect(cart.selectedTableId.value, '4');

      await controller.selectOrderType(OrderType.pickUp, navigate: false);
      expect(controller.selectedType.value, OrderType.pickUp);
      expect(AppState.orderType, OrderType.pickUp);
      expect(cart.selectedTableId.value, isEmpty);
      expect(cart.selectedChairCount.value, 0);
    },
  );

  test(
    'DashboardController refreshes on category changes and favorite toggles',
    () {
      Get.put<CartController>(_CartWithoutCaptainLoad());
      Get.put<SyncService>(_SyncWithoutPolling());
      final controller = _DashboardWithoutProductFetch();

      controller.selectCategory('drinks');
      controller.selectCategory('drinks');
      expect(controller.selectedCategoryId.value, 'drinks');
      expect(controller.fetchCount, 1);

      controller.setFavorite(5);
      expect(controller.selectedFavoriteId.value, 5);
      controller.setFavorite(5);
      expect(controller.selectedFavoriteId.value, isNull);
      expect(controller.fetchCount, 3);
    },
  );

  test(
    'PrinterController filters Bluetooth devices and deduplicates addresses',
    () {
      final controller = PrinterController();
      final kitchen = PrinterModel(
        name: 'Kitchen',
        address: '1',
        type: 'bluetooth',
        isLikelyPrinter: true,
      );
      final headset = PrinterModel(
        name: 'Headset',
        address: '2',
        type: 'bluetooth',
      );
      final rediscovered = PrinterModel(
        name: 'Kitchen',
        address: '1',
        type: 'wifi',
      );
      controller.bluetoothPrinters.assignAll([kitchen, headset]);
      controller.wifiPrinters.add(rediscovered);

      expect(controller.filteredBluetoothDevices, [kitchen, headset]);
      controller.showOnlyPrinters.value = true;
      expect(controller.filteredBluetoothDevices, [kitchen]);
      expect(controller.allPrinters, hasLength(2));
      expect(controller.getPrinterByAddress('1'), same(rediscovered));
      expect(controller.getPrinterByAddress('missing'), isNull);
    },
  );

  testWidgets('macOS discovery can finish after nine seconds and reuse the link',
      (tester) async {
    const channel = MethodChannel('groons.web.app/print');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const address = 'ABCD1234-1234-1234-1234-ABCDEFABCDEF';
    var connected = false;
    var scans = 0;
    var connects = 0;
    var disconnects = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'connectionstatus':
          return connected;
        case 'pairedbluetooths':
          scans++;
          await Future<void>.delayed(const Duration(seconds: 5));
          return ['Kitchen#$address'];
        case 'connect':
          connects++;
          if (connects == 1) return false;
          await Future<void>.delayed(const Duration(seconds: 5));
          connected = true;
          return true;
        case 'disconnect':
          disconnects++;
          connected = false;
          return true;
        default:
          throw MissingPluginException(call.method);
      }
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final printer = PrinterController();
    final firstCheck = printer.checkPrinterConnection(
      PrinterModel(name: 'Kitchen', address: address, type: 'bluetooth'),
      forOrder: true,
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 4));
    expect(printer.isCheckingConnection.value, isTrue);
    await tester.pump(const Duration(seconds: 1));
    expect(await firstCheck, isTrue);

    final assignment = PrinterModel(
      name: 'Kitchen',
      address: address.toLowerCase(),
      type: 'bluetooth',
    );
    expect(await printer.checkPrinterConnection(assignment, forOrder: true), isTrue);
    expect(await printer.checkPrinterConnection(assignment, forOrder: true), isTrue);
    expect(scans, 1);
    expect(connects, 2);
    expect(disconnects, 0);
  }, skip: !Platform.isMacOS);

  test(
    'SettingsController clears connection state when no host is configured',
    () async {
      Get.put<SyncService>(_SyncWithoutPolling());
      final controller = SettingsController();
      controller.hostIp.value = '192.0.2.10';
      controller.hostPort.value = 8081;
      expect(controller.hubUrl, 'http://192.0.2.10:8081');

      controller.hostIp.value = '';
      controller.isHubConnected.value = true;
      expect(await controller.verifyConnection(), isFalse);
      expect(controller.isHubConnected.value, isFalse);
      expect(controller.hostAddress, 'Not configured');
    },
  );

  test(
    'SettingsController updates and persists the order printing preference',
    () async {
      Get.put<SyncService>(_SyncWithoutPolling());
      final controller = SettingsController();

      await controller.setRequireOrderPrinting(false);
      expect(controller.requireOrderPrinting.value, isFalse);
      expect(DeviceConfig.requireOrderPrinting, isFalse);
      await controller.setRequireOrderPrinting(true);
      expect(controller.requireOrderPrinting.value, isTrue);
      expect(DeviceConfig.requireOrderPrinting, isTrue);
    },
  );

  test(
    'AuthController ignores blank and file-path QR scanner values',
    () async {
      final controller = AuthController();
      controller.companyCode.value = 'BR42';
      controller.isVerified.value = true;

      await controller.processQrValue('  ');
      await controller.processQrValue('/tmp/example.png');
      await controller.processQrValue(r'C:\example.png');

      expect(controller.companyCode.value, 'BR42');
      expect(controller.isVerified.value, isTrue);
      expect(controller.isLoading.value, isFalse);
    },
  );

  testWidgets('ThemeController restores and updates the saved preference', (
    tester,
  ) async {
    await tester.runAsync(() => GetStorage().write('is_dark_mode', true));
    await tester.pumpWidget(GetMaterialApp(home: const SizedBox.shrink()));
    final controller = Get.put(ThemeController());
    expect(controller.isDark.value, isTrue);

    controller.toggleTheme();
    await tester.pumpAndSettle();
    expect(controller.isDark.value, isFalse);
    expect(GetStorage().read<bool>('is_dark_mode'), isFalse);
    await tester.runAsync(() => GetStorage().save());
  });

  testWidgets(
    'CashierController recalculates payment and tracks split differences',
    (tester) async {
      late CashierController controller;
      await tester.pumpWidget(
        GetMaterialApp(
          home: const SizedBox.shrink(),
          getPages: [
            GetPage(
              name: '/cashier-test',
              page: () {
                controller = CashierController();
                return const SizedBox.shrink();
              },
            ),
          ],
        ),
      );
      Get.toNamed(
        '/cashier-test',
        arguments: _order(id: '42', invoice: 'INV-42'),
      );
      await tester.pumpAndSettle();
      addTearDown(controller.onClose);

      controller.updateDiscountAmount('10');
      controller.roundOffController.text = '0.50';
      controller.setRoundOffSign(true);
      expect(controller.totalToPay, 89.5);
      expect(controller.receivedAmount.value, 89.5);

      controller.updateReceivedAmount('100');
      expect(controller.changeAmount, 10.5);
      controller.updateReceivedAmount('80');
      expect(controller.changeAmount, 0);

      controller.updateSplitCount('3');
      expect(controller.splitAmounts, [29.84, 29.83, 29.83]);
      expect(controller.currentSplitTotal, closeTo(89.5, 0.001));
      expect(controller.currentSplitVatTotal, closeTo(9, 0.001));
      controller.updateSplitAmount(0, '20');
      expect(controller.splitDifference, 9.84);
      controller.updateSplitCount('0');
      expect(controller.splitAmounts, [89.5]);
    },
  );
}

class _CartWithoutCaptainLoad extends CartController {
  @override
  Future<void> loadCaptains() async {}
}

class _SyncWithoutPolling extends SyncService {
  @override
  // The test drives sync explicitly without starting timers or network calls.
  // ignore: must_call_super
  void onInit() {}

  @override
  void onClose() => super.onClose();
}

class _DashboardWithoutProductFetch extends DashboardController {
  int fetchCount = 0;

  @override
  Future<void> fetchProducts() async {
    fetchCount++;
  }
}

FoodItemModel _product() => FoodItemModel(
  id: '1',
  name: 'Sandwich',
  categoryId: 'food',
  price: 20,
  prd_tax: 10,
  image: '',
  unitDisplay: 'each',
);

ProductUnit _unit() => ProductUnit(
  unitId: 1,
  unitName: 'Each',
  unitDisplay: 'each',
  rate: 20,
  unitBaseQty: 1,
  existAddOns: [],
);

OrderModel _order({
  required String id,
  required String invoice,
  List<OrderItem> items = const [],
}) {
  final createdAt = DateTime(2026, 11, 25);
  return OrderModel(
    id: id,
    invNo: invoice,
    tableId: '',
    tableName: '',
    chairNumber: 0,
    sales_odr_pos_status: 0,
    items: items,
    status: OrderStatus.pending,
    createdAt: createdAt,
    orderTime: createdAt,
    totalAmount: 100,
    totalTax: 10,
  );
}
