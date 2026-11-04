import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:restaurant_pos/app/data/services/api_services.dart';
import 'package:restaurant_pos/app/routes/app_pages.dart';
import 'package:restaurant_pos/app/theme/theme_controller.dart';
import 'package:restaurant_pos/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    Get.testMode = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        return '.';
      },
    );
    await GetStorage.init();
  });

  tearDown(() {
    Get.reset();
  });

  testWidgets('MyApp builds successfully', (WidgetTester tester) async {
    Get.put(ApiService());
    final themeController = Get.put(ThemeController());

    await tester.pumpWidget(
      MyApp(
        initialRoute: AppPages.INITIAL,
        themeController: themeController,
      ),
    );

    await tester.pump();

    expect(find.byType(MyApp), findsOneWidget);
  });
}
