import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

import 'app/data/services/api_services.dart';
import 'app/data/services/sync_service.dart';
import 'app/data/translations/app_translations.dart';
import 'app/data/utils/AppState.dart';
import 'app/routes/app_pages.dart';
import 'app/theme/app_theme.dart';
import 'app/theme/theme_controller.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await GetStorage.init();

  final apiService = Get.put(ApiService(), permanent: true);
  Get.put(SyncService(), permanent: true);

  // Register before runApp so ThemeController.to is always available
  final themeController = Get.put(ThemeController(), permanent: true);

  final storage = GetStorage();
  String initialRoute = AppPages.INITIAL;
  bool sessionExpired = false;

  if (AppState.isLoggedIn) {
    try {
      final tempDio = Dio(BaseOptions(
        baseUrl: apiService.baseUrl,
        connectTimeout: const Duration(seconds: 10),
      ));

      final response = await tempDio.post(
        "mobileapp/user/check_active_app",
        options: Options(headers: {'mobileapptoken': AppState.token}),
      );

      if (response.statusCode == 200 && response.data['status'] == 200) {
        // ✅ Show Order Type selection instead of Home on entry
        initialRoute = Routes.ORDER_TYPE;
      } else {
        await AppState.clearAllData();
        sessionExpired = true;
      }
    } catch (e) {
      if (e is DioException &&
          (e.response?.statusCode == 403 ||
              e.type == DioExceptionType.badResponse)) {
        await AppState.clearAllData();
        sessionExpired = true;
      } else {
        // Offline / timeout — allow in with cached data
        // ✅ Show Order Type selection instead of Home on entry
        initialRoute = Routes.ORDER_TYPE;
      }
    }
  }

  if (sessionExpired) {
    storage.write('session_expired_flag', true);
  }

  runApp(MyApp(
    initialRoute: initialRoute,
    themeController: themeController,
  ));
}

class MyApp extends StatelessWidget {
  final String initialRoute;
  final ThemeController themeController;

  const MyApp({
    super.key,
    required this.initialRoute,
    required this.themeController,
  });

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(360, 812),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        // Obx rebuilds GetMaterialApp when isDark changes
        return Obx(() => GetMaterialApp(
          title: 'Fujishka TablePro',
          debugShowCheckedModeBanner: false,
          initialRoute: initialRoute,
          getPages: AppPages.routes,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeController.isDark.value
              ? ThemeMode.dark
              : ThemeMode.light,
          translations: AppTranslations(),
          locale: const Locale('en', 'US'),
          fallbackLocale: const Locale('en', 'US'),
          defaultTransition: Transition.fade,
          transitionDuration: const Duration(milliseconds: 200),
        ));
      },
    );
  }
}
