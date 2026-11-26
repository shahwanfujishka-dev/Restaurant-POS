import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:restaurant_pos/app/data/services/api_services.dart';
import 'package:restaurant_pos/app/data/services/sync_service.dart';
import 'package:restaurant_pos/app/modules/auth/controllers/sync_controller.dart';
import 'package:restaurant_pos/app/modules/cart/controller/cart_controller.dart';

class _StallingApiService extends ApiService {
  final attempts = <CancelToken>[];
  static const stalledPath = 'mobileapp/category/download';
  final otherPaths = <String>[];

  @override
  Future<Response> postForMasterSync(
    String path, {
    required Map<String, dynamic> data,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    final request = RequestOptions(path: path);
    if (path != stalledPath) {
      otherPaths.add(path);
      return Response(requestOptions: request, data: {'data': []});
    }

    attempts.add(cancelToken!);
    if (attempts.length == 2) {
      throw DioException(
        requestOptions: request,
        error: const HttpException("Can't assign requested address"),
      );
    }
    throw await cancelToken.whenCancel;
  }
}

class _SyncServiceWithoutStorage extends SyncService {
  @override
  Future<void> runMasterSync(Future<void> Function() download) => download();
}

class _TrackingCartController extends CartController {
  int resetCount = 0;

  @override
  Future<void> loadCaptains() async {}

  @override
  void stopEditing() {
    super.stopEditing();
    resetCount++;
  }
}

void main() {
  testWidgets('sync retries only the stalled request and handles macOS errors',
      (tester) async {
    final api = _StallingApiService();
    Get.put<ApiService>(api);
    Get.put<SyncService>(_SyncServiceWithoutStorage());
    final cart = Get.put<CartController>(_TrackingCartController())
        as _TrackingCartController;
    cart.editingOrderId.value = 'order-being-edited';
    late SyncController controller;

    await tester.pumpWidget(
      Builder(builder: (_) {
        controller = Get.put(SyncController());
        expect(cart.editingOrderId.value, 'order-being-edited');
        expect(cart.resetCount, 0);
        expect(api.attempts, isEmpty);
        return const SizedBox.shrink();
      }),
    );
    await tester.pump();
    expect(cart.editingOrderId.value, isEmpty);
    expect(cart.resetCount, 1);
    expect(api.attempts, hasLength(1));
    expect(controller.slowRequests.value, 0);
    final completedPaths = List.of(api.otherPaths);
    expect(completedPaths, isNotEmpty);

    await tester.pump(const Duration(seconds: 5));
    expect(controller.slowRequests.value, 1);
    expect(controller.hasError.value, isFalse);

    await tester.pump(const Duration(seconds: 40));
    expect(api.attempts.single.isCancelled, isTrue);
    expect(controller.slowRequests.value, 0);
    expect(controller.reconnectingRequests.value, 1);
    expect(controller.retrySeconds.value, 2);

    await tester.pump(const Duration(seconds: 1));
    expect(controller.retrySeconds.value, 1);
    await tester.pump(const Duration(seconds: 1));
    expect(api.attempts, hasLength(2));
    expect(controller.hasError.value, isFalse);
    expect(controller.retrySeconds.value, 4);

    controller.retryNow();
    await tester.pump();
    expect(api.attempts, hasLength(3));
    expect(api.otherPaths, completedPaths);
    expect(controller.retrySeconds.value, 0);

    Get.delete<SyncController>();
    await tester.pump();
    expect(api.attempts.last.isCancelled, isTrue);
    Get.delete<CartController>();
    Get.delete<SyncService>(force: true);
    Get.reset();
  });
}
