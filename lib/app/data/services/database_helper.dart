import 'dart:convert';
import 'dart:developer';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('pos_app.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 9, // bumped to 9 to include inv_no column
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  // Robust Parsing Helpers
  double _toDouble(dynamic value, {double defaultValue = 0.0}) {
    if (value == null) return defaultValue;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? defaultValue;
  }

  int _toInt(dynamic value, {int defaultValue = 0}) {
    if (value == null) return defaultValue;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? defaultValue;
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS product_units (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          prd_id TEXT,
          price_group_id INTEGER,
          unit_id INTEGER,
          unit_name TEXT,
          unit_display TEXT,
          rate REAL,
          unit_base_qty REAL,
          exist_addons TEXT,
          UNIQUE(prd_id, price_group_id, unit_id)
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS common_addons (
          prd_id INTEGER PRIMARY KEY,
          name TEXT,
          price REAL,
          unit_id INTEGER,
          unit_display TEXT,
          tax_per REAL,
          tax_cat_id INTEGER,
          unit_base_qty REAL,
          prdaddon_flags INTEGER
        )
      ''');

      try {
        await db.execute('ALTER TABLE orders ADD COLUMN payload TEXT');
      } catch (e) {}
    }
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS favorites (
          id INTEGER PRIMARY KEY,
          name TEXT,
          image TEXT,
          sort_order INTEGER
        )
      ''');
    }
    if (oldVersion < 4) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS app_settings (
          key TEXT PRIMARY KEY,
          value TEXT
        )
      ''');
    }
    if (oldVersion < 5) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS bulk_product_units (
          produnit_id          INTEGER PRIMARY KEY,
          produnit_prod_id     INTEGER,
          produnit_unit_id     INTEGER,
          produnit_ean_barcode TEXT,
          produnit_flag        INTEGER,
          exist_addons         TEXT,
          common_addons        TEXT
        )
      ''');
    }
    if (oldVersion < 6) {
      await db.execute('ALTER TABLE bulk_product_units ADD COLUMN unit_name TEXT');
      await db.execute('ALTER TABLE bulk_product_units ADD COLUMN unit_display TEXT');
      await db.execute('ALTER TABLE bulk_product_units ADD COLUMN rate REAL');
      await db.execute('ALTER TABLE bulk_product_units ADD COLUMN unit_base_qty REAL');
    }
    if (oldVersion < 7) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS units (
          id INTEGER PRIMARY KEY,
          name TEXT,
          code TEXT,
          display TEXT,
          base_qty REAL
        )
      ''');
    }
    if (oldVersion < 8) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS stock_unit_rates (
          sur_id INTEGER PRIMARY KEY,
          branch_stock_id INTEGER,
          sur_prd_id INTEGER,
          sur_stock_id INTEGER,
          sur_unit_id INTEGER,
          sur_batch_id INTEGER,
          sur_unit_rate REAL,
          sur_unit_rate2 REAL,
          sur_branch_id INTEGER,
          sur_flag INTEGER,
          price_group_id INTEGER,
          server_sync_time INTEGER,
          created_at TEXT,
          updated_at TEXT
        )
      ''');
    }
    if (oldVersion < 9) {
      try {
        await db.execute('ALTER TABLE orders ADD COLUMN inv_no TEXT');
      } catch (e) {}
    }
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE categories (
        id TEXT PRIMARY KEY,
        name TEXT,
        cat_pos TEXT,
        token_printer_id INTEGER,
        sort_order INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE products (
        id TEXT,
        price_group_id INTEGER,
        name TEXT,
        category_id TEXT,
        price REAL,
        prd_tax REAL,
        image TEXT,
        unit_display TEXT,
        tax_cat_id INTEGER,
        tax_per REAL,
        sort_order INTEGER,
        PRIMARY KEY (id, price_group_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE product_units (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        prd_id TEXT,
        price_group_id INTEGER,
        unit_id INTEGER,
        unit_name TEXT,
        unit_display TEXT,
        rate REAL,
        unit_base_qty REAL,
        exist_addons TEXT,
        UNIQUE(prd_id, price_group_id, unit_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE common_addons (
        prd_id INTEGER PRIMARY KEY,
        name TEXT,
        price REAL,
        unit_id INTEGER,
        unit_display TEXT,
        tax_per REAL,
        tax_cat_id INTEGER,
        unit_base_qty REAL,
        prdaddon_flags INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE areas (
        id INTEGER PRIMARY KEY,
        name TEXT,
        is_default INTEGER,
        price_group_id INTEGER,
        sort_order INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE pos_tables (
        id INTEGER PRIMARY KEY,
        area_id INTEGER,
        name TEXT,
        chair_count INTEGER,
        processing_table TEXT,
        sort_order INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE favorites (
        id INTEGER PRIMARY KEY,
        name TEXT,
        image TEXT,
        sort_order INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE app_settings (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE token_printer_assignments (
        token_printer_id INTEGER PRIMARY KEY,
        printer_address TEXT,
        printer_name TEXT,
        printer_type TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE category_printers (
        category_id TEXT PRIMARY KEY,
        printer_address TEXT,
        printer_name TEXT,
        printer_type TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE orders (
        local_id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT UNIQUE,
        server_id TEXT,
        inv_no TEXT,
        order_type_id INTEGER,
        table_id INTEGER,
        customer_name TEXT,
        customer_phone TEXT,
        total_amount REAL,
        total_tax REAL,
        status TEXT, 
        is_synced INTEGER DEFAULT 0,
        payload TEXT,
        created_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE order_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        order_uuid TEXT,
        product_id TEXT,
        name TEXT,
        quantity REAL,
        price REAL,
        tax REAL,
        subtotal REAL,
        is_printed INTEGER DEFAULT 0,
        FOREIGN KEY (order_uuid) REFERENCES orders (uuid) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        order_uuid TEXT,
        amount REAL,
        method TEXT, 
        transaction_id TEXT,
        is_synced INTEGER DEFAULT 0,
        created_at TEXT,
        FOREIGN KEY (order_uuid) REFERENCES orders (uuid) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE bulk_product_units (
        produnit_id          INTEGER PRIMARY KEY,
        produnit_prod_id     INTEGER,
        produnit_unit_id     INTEGER,
        produnit_ean_barcode TEXT,
        produnit_flag        INTEGER,
        exist_addons         TEXT,
        common_addons        TEXT,
        unit_name            TEXT,
        unit_display         TEXT,
        rate                 REAL,
        unit_base_qty        REAL
      )
    ''');

    await db.execute('''
      CREATE TABLE units (
        id INTEGER PRIMARY KEY,
        name TEXT,
        code TEXT,
        display TEXT,
        base_qty REAL
      )
    ''');

    await db.execute('''
      CREATE TABLE stock_unit_rates (
        sur_id INTEGER PRIMARY KEY,
        branch_stock_id INTEGER,
        sur_prd_id INTEGER,
        sur_stock_id INTEGER,
        sur_unit_id INTEGER,
        sur_batch_id INTEGER,
        sur_unit_rate REAL,
        sur_unit_rate2 REAL,
        sur_branch_id INTEGER,
        sur_flag INTEGER,
        price_group_id INTEGER,
        server_sync_time INTEGER,
        created_at TEXT,
        updated_at TEXT
      )
    ''');
  }

  // --- App Settings ---
  Future<void> saveSetting(String key, String value) async {
    final db = await instance.database;
    await db.insert('app_settings', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> getSetting(String key) async {
    final db = await instance.database;
    final List<Map<String, dynamic>> maps = await db.query('app_settings', where: 'key = ?', whereArgs: [key]);
    if (maps.isNotEmpty) return maps.first['value'] as String;
    return null;
  }

  // --- Payments ---
  Future<void> insertPayment(Map<String, dynamic> payment) async {
    final db = await instance.database;
    await db.insert('payments', payment);
  }

  Future<List<Map<String, dynamic>>> getUnsyncedPayments() async {
    final db = await instance.database;
    return await db.query('payments', where: 'is_synced = ?', whereArgs: [0]);
  }

  Future<void> updatePaymentSyncStatus(int id, int isSynced) async {
    final db = await instance.database;
    await db.update('payments', {'is_synced': isSynced}, where: 'id = ?', whereArgs: [id]);
  }

  // --- Orders ---
  Future<void> insertOrder(Map<String, dynamic> order, List<Map<String, dynamic>> items) async {
    final db = await instance.database;
    await db.transaction((txn) async {
      await txn.insert('orders', order, conflictAlgorithm: ConflictAlgorithm.replace);
      final String uuid = order['uuid'];
      await txn.delete('order_items', where: 'order_uuid = ?', whereArgs: [uuid]);
      for (var item in items) {
        await txn.insert('order_items', item, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<List<Map<String, dynamic>>> getUnsyncedOrders() async {
    final db = await instance.database;
    // Removed the "status != 'draft'" filter to allow offline drafts to sync to the server
    return await db.query('orders', where: 'is_synced = ?', whereArgs: [0]);
  }

  Future<List<Map<String, dynamic>>> getAllLocalOrders() async {
    final db = await instance.database;
    return await db.query('orders', orderBy: 'created_at DESC');
  }

  Future<List<Map<String, dynamic>>> getOrderItemsByUuid(String uuid) async {
    final db = await instance.database;
    return await db.query('order_items', where: 'order_uuid = ?', whereArgs: [uuid]);
  }

  Future<int> updateOrderStatusByServerId(String serverId, String status, {int? isSynced, double? total, double? tax, String? payload, String? invNo}) async {
    final db = await instance.database;
    final Map<String, dynamic> values = {'status': status};
    if (isSynced != null) values['is_synced'] = isSynced;
    if (total != null) values['total_amount'] = total;
    if (tax != null) values['total_tax'] = tax;
    if (payload != null) values['payload'] = payload;
    if (invNo != null) values['inv_no'] = invNo;
    
    int count = await db.update('orders', values, where: 'server_id = ?', whereArgs: [serverId]);
    if (count == 0) {
      count = await db.update('orders', values, where: 'uuid = ?', whereArgs: [serverId]);
    }
    return count;
  }

  Future<void> saveOrderOffline(Map<String, dynamic> orderValues, List<Map<String, dynamic>> itemValues) async {
    final db = await instance.database;
    await db.transaction((txn) async {
      final String id = (orderValues['server_id'] ?? orderValues['uuid']).toString();
      
      // Try to find existing record to get its real UUID
      final List<Map<String, dynamic>> existing = await txn.query(
        'orders',
        columns: ['uuid'],
        where: 'uuid = ? OR server_id = ?',
        whereArgs: [id, id],
        limit: 1,
      );
      
      String targetUuid;
      if (existing.isNotEmpty) {
        targetUuid = existing.first['uuid'];
        await txn.update('orders', orderValues, where: 'uuid = ?', whereArgs: [targetUuid]);
      } else {
        targetUuid = orderValues['uuid'] ?? id;
        orderValues['uuid'] = targetUuid; // ensure uuid is set
        await txn.insert('orders', orderValues, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      
      // Sync items table
      await txn.delete('order_items', where: 'order_uuid = ?', whereArgs: [targetUuid]);
      for (var item in itemValues) {
        item['order_uuid'] = targetUuid;
        await txn.insert('order_items', item);
      }
    });
  }

  Future<void> updateOrderStatusByUuid(String uuid, String status, {int? isSynced, String? serverId, String? invNo}) async {
    final db = await instance.database;
    final Map<String, dynamic> values = {'status': status};
    if (isSynced != null) values['is_synced'] = isSynced;
    if (serverId != null) values['server_id'] = serverId;
    if (invNo != null) values['inv_no'] = invNo;
    await db.update('orders', values, where: 'uuid = ?', whereArgs: [uuid]);
  }

  Future<void> updateOrderOffline(String id, Map<String, dynamic> values) async {
    final db = await instance.database;
    int count = await db.update('orders', values, where: 'uuid = ?', whereArgs: [id]);
    if (count == 0) {
      await db.update('orders', values, where: 'server_id = ?', whereArgs: [id]);
    }
  }

  Future<void> deleteOrder(String id) async {
    final db = await instance.database;
    await db.transaction((txn) async {
      final List<Map<String, dynamic>> maps = await txn.query(
        'orders',
        columns: ['uuid'],
        where: 'uuid = ? OR server_id = ?',
        whereArgs: [id, id],
        limit: 1,
      );
      
      if (maps.isNotEmpty) {
        final String uuid = maps.first['uuid'];
        await txn.delete('order_items', where: 'order_uuid = ?', whereArgs: [uuid]);
        await txn.delete('payments', where: 'order_uuid = ?', whereArgs: [uuid]);
      }
      
      await txn.delete('orders', where: 'uuid = ? OR server_id = ?', whereArgs: [id, id]);
    });
  }

  Future<void> markItemAsPrinted(int itemId) async {
    final db = await instance.database;
    await db.update('order_items', {'is_printed': 1}, where: 'id = ?', whereArgs: [itemId]);
  }

  // --- Printers ---
  Future<List<Map<String, dynamic>>> getAllTokenPrinterAssignments() async {
    final db = await instance.database;
    return await db.query('token_printer_assignments');
  }

  Future<List<Map<String, dynamic>>> getAllCategoryPrinters() async {
    final db = await instance.database;
    return await db.query('category_printers');
  }

  Future<void> saveTokenPrinterAssignment(int tokenPrinterId, String address, String name, String type) async {
    final db = await instance.database;
    await db.insert('token_printer_assignments', {
      'token_printer_id': tokenPrinterId,
      'printer_address': address,
      'printer_name': name,
      'printer_type': type,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteTokenPrinterAssignment(int tokenPrinterId) async {
    final db = await instance.database;
    await db.delete('token_printer_assignments', where: 'token_printer_id = ?', whereArgs: [tokenPrinterId]);
  }

  // --- Master Data ---
  Future<void> insertCategories(List<Map<String, dynamic>> categories) async {
    final db = await instance.database;
    final batch = db.batch();
    for (var cat in categories) {
      batch.insert('categories', cat, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getCategories() async {
    final db = await instance.database;
    return await db.query('categories', orderBy: 'sort_order ASC');
  }

  Future<void> insertProducts(List<Map<String, dynamic>> products) async {
    final db = await instance.database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (var prod in products) {
        batch.insert('products', prod, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<Map<String, dynamic>>> getProducts({String? categoryId, int priceGroupId = 0}) async {
    final db = await instance.database;
    String query = '''
      SELECT p.*, c.token_printer_id as cat_token_printer
      FROM products p
      LEFT JOIN categories c ON p.category_id = c.id
      WHERE p.price_group_id = ?
    ''';
    List<dynamic> args = [priceGroupId];

    if (categoryId != null && categoryId.isNotEmpty) {
      query += " AND p.category_id = ?";
      args.add(categoryId.trim());
    }
    query += " ORDER BY p.sort_order ASC";

    return await db.rawQuery(query, args);
  }

  Future<List<Map<String, dynamic>>> searchProducts(String query, {int priceGroupId = 0}) async {
    final db = await instance.database;
    return await db.rawQuery('''
      SELECT p.*, c.token_printer_id as cat_token_printer
      FROM products p
      LEFT JOIN categories c ON p.category_id = c.id
      WHERE p.price_group_id = ? AND p.name LIKE ?
      ORDER BY p.sort_order ASC
    ''', [priceGroupId, '%$query%']);
  }

  Future<void> insertProductUnits(String prdId, int pgId, List<dynamic> units) async {
    final db = await instance.database;
    final batch = db.batch();
    for (var unit in units) {
      batch.insert('product_units', {
        'prd_id': prdId,
        'price_group_id': pgId,
        'unit_id': _toInt(unit['unit_id']),
        'unit_name': unit['prd_unit_name'],
        'unit_display': unit['unit_display'],
        'rate': _toDouble(unit['sale_rate']),
        'unit_base_qty': _toDouble(unit['unit_base_qty'], defaultValue: 1.0),
        'exist_addons': jsonEncode(unit['existAddOn'] ?? []),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getProductUnits(String prdId, int pgId) async {
    final db = await instance.database;
    return await db.rawQuery('''
      SELECT 
        p.id, p.prd_id, p.price_group_id, p.unit_id, p.rate, p.exist_addons,
        COALESCE(u.base_qty, p.unit_base_qty, 1.0) as unit_base_qty,
        CASE 
          WHEN p.unit_name IS NULL OR p.unit_name = '' OR p.unit_name = 'null' THEN u.name 
          ELSE p.unit_name 
        END as unit_name,
        CASE 
          WHEN p.unit_display IS NULL OR p.unit_display = '' OR p.unit_display = 'null' THEN u.display 
          ELSE p.unit_display 
        END as unit_display
      FROM product_units p
      LEFT JOIN units u ON p.unit_id = u.id
      WHERE p.prd_id = ? AND p.price_group_id = ?
    ''', [prdId, pgId]);
  }

  Future<void> insertCommonAddons(List<dynamic> addons) async {
    final db = await instance.database;
    final batch = db.batch();
    for (var addon in addons) {
      batch.insert('common_addons', {
        'prd_id': _toInt(addon['prd_id']),
        'name': addon['prd_name'],
        'price': _toDouble(addon['sale_rate']),
        'unit_id': _toInt(addon['unit_id']),
        'unit_display': addon['unit_display'],
        'tax_per': _toDouble(addon['tax_per']),
        'tax_cat_id': _toInt(addon['prd_tax_cat_id']),
        'unit_base_qty': _toDouble(addon['unit_base_qty'], defaultValue: 1.0),
        'prdaddon_flags': _toInt(addon['prdaddon_flags']),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getCommonAddons() async {
    final db = await instance.database;
    return await db.rawQuery('''
      SELECT 
        c.prd_id, c.name, c.price, c.unit_id, c.tax_per, c.tax_cat_id, c.prdaddon_flags,
        COALESCE(u.base_qty, c.unit_base_qty, 1.0) as unit_base_qty,
        CASE 
          WHEN c.unit_display IS NULL OR c.unit_display = '' OR c.unit_display = 'null' THEN u.display 
          ELSE c.unit_display 
        END as unit_display
      FROM common_addons c
      LEFT JOIN units u ON c.unit_id = u.id
    ''');
  }

  Future<void> insertAreas(List<Map<String, dynamic>> areas) async {
    final db = await instance.database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (int i = 0; i < areas.length; i++) {
        final area = areas[i];
        batch.insert('areas', {
          'id': _toInt(area['ra_id']),
          'name': area['ra_name'],
          'is_default': _toInt(area['ra_is_default']),
          'price_group_id': _toInt(area['ra_prcgrp_id']),
          'sort_order': i,
        }, conflictAlgorithm: ConflictAlgorithm.replace);

        if (area['pos_tables'] != null) {
          final List tables = area['pos_tables'];
          for (int j = 0; j < tables.length; j++) {
            final table = tables[j];
            batch.insert('pos_tables', {
              'id': _toInt(table['rt_id']),
              'area_id': _toInt(area['ra_id']),
              'name': table['rt_name'],
              'chair_count': _toInt(table['rt_seat_count']),
              'processing_table': jsonEncode(table['processing_table']),
              'sort_order': j,
            }, conflictAlgorithm: ConflictAlgorithm.replace);
          }
        }
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<Map<String, dynamic>>> getAreas() async {
    final db = await instance.database;
    return await db.query('areas', orderBy: 'sort_order ASC');
  }

  Future<List<Map<String, dynamic>>> getTablesForArea(int areaId) async {
    final db = await instance.database;
    return await db.query('pos_tables', where: 'area_id = ?', whereArgs: [areaId], orderBy: 'sort_order ASC');
  }

  Future<void> insertFavorites(List<Map<String, dynamic>> favorites) async {
    final db = await instance.database;
    final batch = db.batch();
    for (int i = 0; i < favorites.length; i++) {
      final fav = favorites[i];
      batch.insert('favorites', {
        'id': _toInt(fav['id']),
        'name': fav['name'],
        'image': fav['image'],
        'sort_order': i,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getFavorites() async {
    final db = await instance.database;
    return await db.query('favorites', orderBy: 'sort_order ASC');
  }

  // --- Units ---
  Future<void> insertUnits(List<dynamic> units) async {
    final db = await instance.database;
    final batch = db.batch();
    for (var unit in units) {
      batch.insert('units', {
        'id': _toInt(unit['unit_id']),
        'name': unit['unit_name']?.toString(),
        'code': unit['unit_code']?.toString(),
        'display': unit['unit_display']?.toString(),
        'base_qty': _toDouble(unit['unit_base_qty'], defaultValue: 1.0),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<Map<String, dynamic>?> getUnitById(int unitId) async {
    final db = await instance.database;
    final maps = await db.query('units', where: 'id = ?', whereArgs: [unitId]);
    if (maps.isNotEmpty) return maps.first;
    return null;
  }

  // --- Bulk Product Units ---
  Future<void> insertBulkProductUnits(List<dynamic> rawList) async {
    final db = await instance.database;
    const chunkSize = 200;
    for (int i = 0; i < rawList.length; i += chunkSize) {
      final end = (i + chunkSize < rawList.length) ? i + chunkSize : rawList.length;
      final chunk = rawList.sublist(i, end);
      await db.transaction((txn) async {
        final batch = txn.batch();
        for (final item in chunk) {
          String? unitName = item['unit_name']?.toString() ?? item['prd_unit_name']?.toString();
          String? unitDisplay = item['unit_display']?.toString() ?? item['unit_name']?.toString();
          batch.insert(
            'bulk_product_units',
            {
              'produnit_id': _toInt(item['produnit_id'] ?? item['id']),
              'produnit_prod_id': _toInt(item['produnit_prod_id'] ?? item['prd_id']),
              'produnit_unit_id': _toInt(item['produnit_unit_id'] ?? item['unit_id']),
              'unit_name': unitName,
              'unit_display': unitDisplay,
              'rate': _toDouble(item['sur_unit_rate'] ?? item['sale_rate'] ?? item['prd_unit_rate']),
              'unit_base_qty': _toDouble(item['unit_base_qty'], defaultValue: 1.0),
              'produnit_ean_barcode': item['produnit_ean_barcode']?.toString() ?? '',
              'produnit_flag': _toInt(item['produnit_flag'], defaultValue: 1),
              'exist_addons': jsonEncode(item['existAddOn'] ?? item['exist_addons'] ?? []),
              'common_addons': jsonEncode(item['cmmnAddon'] ?? item['common_addons'] ?? []),
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);
      });
    }
  }

  Future<List<Map<String, dynamic>>> getBulkProductUnits(int prodId) async {
    final db = await instance.database;
    return await db.rawQuery('''
      SELECT 
        b.produnit_id, b.produnit_prod_id, b.produnit_unit_id, b.produnit_ean_barcode,
        b.produnit_flag, b.exist_addons, b.common_addons, b.rate,
        COALESCE(u.base_qty, b.unit_base_qty, 1.0) as unit_base_qty,
        CASE 
          WHEN b.unit_name IS NULL OR b.unit_name = '' OR b.unit_name = 'null' THEN u.name 
          ELSE b.unit_name 
        END as unit_name,
        CASE 
          WHEN b.unit_display IS NULL OR b.unit_display = '' OR b.unit_display = 'null' THEN u.display 
          ELSE b.unit_display 
        END as unit_display
      FROM bulk_product_units b
      LEFT JOIN units u ON b.produnit_unit_id = u.id
      WHERE b.produnit_prod_id = ?
    ''', [prodId]);
  }

  Future<void> clearBulkProductUnits() async {
    final db = await instance.database;
    await db.delete('bulk_product_units');
  }

  // --- Stock Unit Rates ---
  Future<void> insertStockUnitRates(List<dynamic> rates) async {
    final db = await instance.database;
    const chunkSize = 200;
    for (int i = 0; i < rates.length; i += chunkSize) {
      final end = (i + chunkSize < rates.length) ? i + chunkSize : rates.length;
      final chunk = rates.sublist(i, end);
      await db.transaction((txn) async {
        final batch = txn.batch();
        for (final item in chunk) {
          batch.insert(
            'stock_unit_rates',
            {
              'sur_id':           _toInt(item['sur_id']),
              'branch_stock_id':  _toInt(item['branch_stock_id']),
              'sur_prd_id':       _toInt(item['sur_prd_id']),
              'sur_stock_id':     _toInt(item['sur_stock_id']),
              'sur_unit_id':      _toInt(item['sur_unit_id']),
              'sur_batch_id':     _toInt(item['sur_batch_id']),
              'sur_unit_rate':    _toDouble(item['sur_unit_rate']),
              'sur_unit_rate2':   _toDouble(item['sur_unit_rate2']),
              'sur_branch_id':    _toInt(item['sur_branch_id']),
              'sur_flag':         _toInt(item['sur_flag']),
              'price_group_id':   _toInt(item['price_group_id']),
              'server_sync_time': _toInt(item['server_sync_time']),
              'created_at':       item['created_at']?.toString(),
              'updated_at':       item['updated_at']?.toString(),
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);
      });
    }
  }

  Future<Map<String, double>?> getStockUnitRate(int prdId, int unitId, int priceGroupId) async {
    final db = await instance.database;

    // 1. Try with specific price group
    List<Map<String, dynamic>> maps = await db.query(
      'stock_unit_rates',
      columns: ['sur_unit_rate', 'sur_unit_rate2'],
      where: 'sur_prd_id = ? AND sur_unit_id = ? AND price_group_id = ?',
      whereArgs: [prdId, unitId, priceGroupId],
      limit: 1,
    );

    // 2. Fallback: Try without price group if not found (grab any available rate for this product and unit)
    if (maps.isEmpty) {
      maps = await db.query(
        'stock_unit_rates',
        columns: ['sur_unit_rate', 'sur_unit_rate2'],
        where: 'sur_prd_id = ? AND sur_unit_id = ?',
        whereArgs: [prdId, unitId],
        limit: 1,
      );
    }

    if (maps.isNotEmpty) {
      return {
        'sur_unit_rate': _toDouble(maps.first['sur_unit_rate']),
        'sur_unit_rate2': _toDouble(maps.first['sur_unit_rate2']),
      };
    }
    return null;
  }

  Future<void> clearStockUnitRates() async {
    final db = await instance.database;
    await db.delete('stock_unit_rates');
  }

  Future<void> clearAllCache() async {
    final db = await instance.database;
    await db.transaction((txn) async {
      await txn.delete('categories');
      await txn.delete('products');
      await txn.delete('product_units');
      await txn.delete('common_addons');
      await txn.delete('areas');
      await txn.delete('pos_tables');
      await txn.delete('favorites');
      await txn.delete('bulk_product_units');
      await txn.delete('units');
      await txn.delete('stock_unit_rates');
    });
  }
}
