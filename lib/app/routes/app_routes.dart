part of 'app_pages.dart';


abstract class Routes {
  Routes._();
  static const HOME = _Paths.HOME;
  static const AUTH = _Paths.AUTH;
  static const CART = _Paths.CART;
  static const QrScann = _Paths.QrScann;
  static const SYNC = _Paths.SYNC;
  static const ORDER_TYPE = _Paths.ORDER_TYPE;
  static const CASHIER = _Paths.CASHIER;
  static const SETTINGS = _Paths.SETTINGS;
}

abstract class _Paths {
  _Paths._();
  static const HOME = '/home';
  static const AUTH = '/auth';
  static const CART = '/cart';
  static const QrScann = '/qr-scanner';
  static const SYNC = '/sync';
  static const ORDER_TYPE = '/order-type';
  static const CASHIER = '/cashier';
  static const SETTINGS = '/settings';
}
