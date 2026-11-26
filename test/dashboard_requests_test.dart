import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:get_storage/get_storage.dart';
import 'package:restaurant_pos/app/data/services/api_services.dart';
import 'package:restaurant_pos/app/data/services/database_helper.dart';
import 'package:restaurant_pos/app/data/services/sync_service.dart';
import 'package:restaurant_pos/app/modules/cart/controller/cart_controller.dart';
import 'package:restaurant_pos/app/modules/home/controller/dashboard_controller.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('an older product response cannot replace the current search', () async {
    final directory = await Directory.systemTemp.createTemp('pos_dashboard_');
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      pathProvider,
      (_) async => directory.path,
    );
    addTearDown(() => messenger.setMockMethodCallHandler(pathProvider, null));
    await GetStorage.init();
    FlutterSecureStorage.setMockInitialValues({});
    sqfliteFfiInit();
    DatabaseHelper.configureDatabasesDirectory(directory.path);
    final db = await DatabaseHelper.instance.database;
    addTearDown(() async {
      Get.reset();
      await db.close();
      await directory.delete(recursive: true);
    });

    final api = _PendingProductApi();
    Get.put<ApiService>(api);
    Get.put<CartController>(_CartWithoutCaptainLoad());
    Get.put<SyncService>(_SyncWithoutPolling());
    final dashboard = DashboardController();

    dashboard.searchKeyword.value = 'Soup';
    final older = dashboard.fetchProducts();
    await api.called('Soup');

    dashboard.searchKeyword.value = 'Rice';
    final newer = dashboard.fetchProducts();
    await api.called('Rice');

    api.complete('Rice', 2);
    await newer;
    expect(dashboard.filteredFoodItems.single.name, 'Rice');
    expect(dashboard.isLoadingProducts.value, isFalse);

    api.complete('Soup', 1);
    await older;
    expect(dashboard.filteredFoodItems.single.name, 'Rice');

    dashboard.searchKeyword.value = 'Salad';
    final superseded = dashboard.fetchProducts();
    await api.called('Salad');
    dashboard.searchKeyword.value = 'Pasta';
    final current = dashboard.fetchProducts();
    await api.called('Pasta');

    api.complete('Salad', 3);
    await superseded;
    expect(dashboard.isLoadingProducts.value, isTrue);

    api.complete('Pasta', 4);
    await current;
    expect(dashboard.filteredFoodItems.single.name, 'Pasta');
    expect(dashboard.isLoadingProducts.value, isFalse);
  });
}

class _PendingProductApi extends ApiService {
  final _requests = <String, Completer<Response>>{};
  final _calls = <String, Completer<void>>{};

  Future<void> called(String keyword) =>
      _calls.putIfAbsent(keyword, Completer<void>.new).future;

  @override
  Future<Response> post(
    String path, {
    dynamic data,
    Options? options,
    CancelToken? cancelToken,
  }) {
    final keyword = data['keyword'] as String;
    final request = _requests[keyword] = Completer<Response>();
    _calls.putIfAbsent(keyword, Completer<void>.new).complete();
    return request.future;
  }

  void complete(String keyword, int id) {
    _requests[keyword]!.complete(
      Response(
        requestOptions: RequestOptions(),
        statusCode: 200,
        data: {
          'data': [
            {'prd_id': id, 'prd_name': keyword, 'sale_rate': 10},
          ],
        },
      ),
    );
  }
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
