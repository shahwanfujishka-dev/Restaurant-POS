import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:restaurant_pos/app/data/services/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('refresh and an older sync response preserve an offline sale', () async {
    final directory = await Directory.systemTemp.createTemp('pos_orders_');
    addTearDown(() => directory.delete(recursive: true));
    final key = List.filled(64, 'a').join();
    FlutterSecureStorage.setMockInitialValues({'pos_app_database_key_v1': key});
    sqfliteFfiInit();
    DatabaseHelper.configureDatabasesDirectory(directory.path);
    final storage = DatabaseHelper.instance;
    final db = await storage.database;

    await storage.saveOrderOffline({
      'uuid': 'ORD-local',
      'server_id': '42',
      'status': 'pending',
      'payload': '{"sale_items":[{"salesub_qty":2}]}',
      'is_synced': 0,
    }, [
      {'product_id': '7', 'quantity': 2},
    ]);
    await storage.saveOrderOffline({
      'uuid': '42',
      'server_id': '42',
      'status': 'pending',
      'payload': '{"sale_items":[{"salesub_qty":3}]}',
      'is_synced': 0,
    }, [
      {'product_id': '7', 'quantity': 3},
    ]);
    final uploading = (await storage.getUnsyncedOrders()).single;
    expect(uploading['uuid'], 'ORD-local');

    await storage.saveOfflinePayment({
      'order_uuid': '42',
      'amount': 35.0,
      'method': 'cash',
      'discount_amount': 0.0,
      'is_synced': 0,
    }, roundOff: 0, payType: 2);

    expect(
      await storage.acknowledgeOrderUpload(uploading, serverId: '42'),
      isFalse,
    );
    await storage.cacheSoldOrders([
      {'sales_odr_id': 42, 'sales_odr_total': 10.0},
    ]);
    await storage.pruneSyncedActiveOrders({});
    expect(
      await storage.updateOrderStatusByUuid(
        '42',
        'pending',
        isSynced: 1,
        refreshingCache: true,
      ),
      0,
    );
    expect((await storage.getUnsyncedOrders()).single['status'], 'paid');
    expect((await storage.getUnsyncedPayments()).single['order_uuid'], 'ORD-local');

    // Open the same encrypted file independently after closing the app's handle.
    await db.close();
    final reopened = await databaseFactoryFfi.openDatabase(
      join(directory.path, 'pos_app.db'),
      options: OpenDatabaseOptions(
        readOnly: true,
        onConfigure: (db) => db.execute("PRAGMA key = \"x'$key'\""),
      ),
    );
    addTearDown(reopened.close);
    final order = (await reopened.query('orders')).single;
    expect(order['uuid'], 'ORD-local');
    expect(order['is_synced'], 0);
    expect(order['total_amount'], 35.0);
    expect((await reopened.query('order_items')).single['quantity'], 3);
    expect((await reopened.query('payments')).single['is_synced'], 0);
  });
}
