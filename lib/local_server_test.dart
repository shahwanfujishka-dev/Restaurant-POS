// import 'dart:io';
// import 'package:shelf/shelf.dart';
// import 'package:shelf/shelf_io.dart' as shelf_io;
// import 'package:shelf_router/shelf_router.dart';
//
// class TestLocalServer {
//   HttpServer? _server;
//
//   Future<void> start() async {
//     final router = Router();
//
//     router.get('/ping', (Request req) {
//       return Response.ok('pong from counter device');
//     });
//
//     _server = await shelf_io.serve(
//       router.call,
//       InternetAddress.anyIPv4, // listens on the device's WiFi IP
//       4040,
//     );
//
//     print('✅ Local server running at http://${_server!.address.host}:${_server!.port}');
//   }
//
//   Future<void> stop() async {
//     await _server?.close(force: true);
//     _server = null;
//   }
// }