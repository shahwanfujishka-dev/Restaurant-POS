import 'dart:developer';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:sqflite/sqflite.dart' as mobile_sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'app/data/services/api_endpoints.dart';
import 'app/data/services/api_services.dart';
import 'app/data/services/database_helper.dart';
import 'app/data/services/local_hub_server.dart';
import 'app/data/services/sync_service.dart';
import 'app/data/translations/app_translations.dart';
import 'app/data/utils/AppState.dart';
import 'app/routes/app_pages.dart';
import 'app/theme/app_theme.dart';
import 'app/theme/theme_controller.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase and disable Crashlytics collection in debug mode
  try {
    await Firebase.initializeApp();
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(!kDebugMode);

    if (!kDebugMode) {
      FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };
    }
  } catch (e) {
    debugPrint("Firebase/Crashlytics setup: $e");
  }

// GetStorage().erase();
  // Capture the existing native database directory on mobile before switching
  // the sqflite-compatible API to the SQLCipher-backed FFI implementation.
  final legacyMobileDatabasesPath =
      Platform.isAndroid || Platform.isIOS
          ? await mobile_sqflite.getDatabasesPath()
          : null;

  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  DatabaseHelper.configureDatabasesDirectory(
    legacyMobileDatabasesPath ?? await databaseFactoryFfi.getDatabasesPath(),
  );

  await GetStorage.init();
  final savedLang = GetStorage().read('app_language') ?? 'en';
  final initialLocale = savedLang == 'ar' ? const Locale('ar', 'AR') : const Locale('en', 'US');
  try {
    await LocalHubServer.instance.start();
  } catch (e) {
    debugPrint("Main: Failed to start LocalHubServer (port in use or network error): $e");
  }
  final apiService = Get.put(ApiService(), permanent: true);
  Get.put(SyncService(), permanent: true);
  debugPrint(
    'STORAGE: ${GetStorage().getKeys()} -> ${GetStorage().getValues()}',
  );
  final secureStorage = Platform.isMacOS
      ? const FlutterSecureStorage(
          mOptions: MacOsOptions(usesDataProtectionKeychain: false),
        )
      : const FlutterSecureStorage();
  final databaseKey = await secureStorage.read(
    key: 'pos_app_database_key_v1',
  );
  debugPrint('Database encryption key available: ${databaseKey != null}');
  final themeController = Get.put(ThemeController(), permanent: true);

  final storage = GetStorage();
  String initialRoute = AppPages.INITIAL;
  bool sessionExpired = false;
  if (AppState.isLoggedIn) {
    final requiresSync = await AppState.requiresMasterSync();
    initialRoute = requiresSync ? Routes.SYNC : Routes.HOME;

    try {
      final tempDio = Dio(
        BaseOptions(
          baseUrl: apiService.baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ),
      );
      final response = await tempDio.post(
        ApiEndpoints.checkActiveApp,
        options: Options(headers: {'mobileapptoken': AppState.token}),
      );
      final body = response.data;
      final status = body is Map ? body['status'] : null;
      sessionExpired = status != null && status.toString() != '200';
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      sessionExpired = status == 401 || status == 403;
      log("Main: Session check failed: ${e.type}");
    }

    if (sessionExpired) {
      await AppState.clearAllData();
      initialRoute = AppPages.INITIAL;
    }
  }

  if (AppState.upiId.isEmpty) {
    final dbUpi = await DatabaseHelper.instance.getSetting('as_upi_id');
    if (dbUpi != null && dbUpi.isNotEmpty) {
      storage.write('as_upi_id', dbUpi);
      log("Main: Restored UPI ID from Database: $dbUpi");
    }
    final dbUpiEnable = await DatabaseHelper.instance.getSetting(
      'as_upi_enable',
    );
    if (dbUpiEnable != null) {
      storage.write('as_upi_enable', int.tryParse(dbUpiEnable) ?? 0);
    }
  }
  if (sessionExpired) {
    storage.write('session_expired_flag', true);
  }
  // print("UPI: ${AppState.upiId}");
  runApp(MyApp(initialRoute: initialRoute, themeController: themeController, initialLocale: initialLocale));
}

class MyApp extends StatelessWidget {
  final String initialRoute;
  final ThemeController themeController;
  final Locale initialLocale;

  const MyApp({
    super.key,
    required this.initialRoute,
    required this.themeController,
    this.initialLocale = const Locale('en', 'US'),
  });

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(360, 812),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        return Obx(
          () => GetMaterialApp(
            title: 'Restaurant POS',
            debugShowCheckedModeBanner: false,
            initialRoute: initialRoute,
            getPages: AppPages.routes,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeController.isDark.value
                ? ThemeMode.dark
                : ThemeMode.light,
            translations: AppTranslations(),
            locale: initialLocale,
            fallbackLocale: const Locale('en', 'US'),
            defaultTransition: Transition.fade,
            transitionDuration: const Duration(milliseconds: 200),
          ),
        );
      },
    );
  }
}
