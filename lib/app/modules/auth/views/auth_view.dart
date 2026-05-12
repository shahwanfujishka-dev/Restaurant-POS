
import 'package:flutter/cupertino.dart';
import 'package:get/get_state_manager/src/simple/get_view.dart';
import 'package:restaurant_pos/app/modules/auth/views/widgets/login_mobile_view.dart';
import 'package:restaurant_pos/app/modules/auth/views/widgets/login_tablet_view.dart';
import '../../../../helper/screen_type.dart';
import '../controllers/auth_controller.dart';

class AuthView extends GetView<AuthController> {
  const AuthView({super.key});
  @override
  Widget build(BuildContext context) {
    return ScreenType.isMobile()
        ? const LoginMobileView()
        : const LoginTabletView();
  }
}
