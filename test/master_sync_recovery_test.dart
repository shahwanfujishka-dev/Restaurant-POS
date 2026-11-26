import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:restaurant_pos/app/data/services/api_services.dart';
import 'package:restaurant_pos/app/data/services/database_helper.dart';
import 'package:restaurant_pos/app/data/services/sync_service.dart';
import 'package:restaurant_pos/app/data/utils/AppState.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('failed refresh still requires sync after a previous success', () async {
    final directory = await Directory.systemTemp.createTemp('pos_master_sync_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => directory.path,
        );
    FlutterSecureStorage.setMockInitialValues({});
    sqfliteFfiInit();
    DatabaseHelper.configureDatabasesDirectory(directory.path);
    await GetStorage.init();
    final db = await DatabaseHelper.instance.database;
    addTearDown(() async {
      Get.reset();
      await db.close();
      await directory.delete(recursive: true);
    });

    Get.put(ApiService());
    final service = SyncService();
    await AppState.updateSession(profile: {'usr_id': 42});
    expect(await AppState.requiresMasterSync(), isTrue);

    await service.runMasterSync(() async {});
    expect(await AppState.requiresMasterSync(), isFalse);

    final storage = DatabaseHelper.instance;
    await storage.insertCategories([
      {'id': 'old', 'name': 'Previous menu', 'sort_order': 0},
    ]);
    await storage.saveSetting('unrelated', 'preserved');

    final started = Completer<void>();
    final download = Completer<void>();
    final refresh = service.runMasterSync(
      () => service.refreshMasterCatalog((staging) async {
        await staging.insertCategories([
          {'id': 'failed', 'name': 'Incomplete menu', 'sort_order': 0},
        ]);
        started.complete();
        await download.future;
      }, fullRefresh: true),
    );
    final failure = expectLater(refresh, throwsStateError);
    await started.future;
    expect((await storage.getCategories()).single['id'], 'old');
    expect(await AppState.requiresMasterSync(), isTrue);

    download.completeError(StateError('Connection lost'));
    await failure;
    expect(await AppState.requiresMasterSync(), isTrue);
    expect((await storage.getCategories()).single['id'], 'old');

    await service.runMasterSync(
      () => service.refreshMasterCatalog(
        (staging) => staging.insertCategories([
          {'id': 'new', 'name': 'Complete menu', 'sort_order': 0},
        ]),
        fullRefresh: true,
      ),
    );
    expect(await AppState.requiresMasterSync(), isFalse);
    expect((await storage.getCategories()).single['id'], 'new');
    expect(await storage.getSetting('unrelated'), 'preserved');
  });
}
