import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:get/get_navigation/src/extension_navigation.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class QrScannerView extends StatefulWidget {
  const QrScannerView({super.key});

  @override
  State<QrScannerView> createState() => _QrScannerViewState();
}

class _QrScannerViewState extends State<QrScannerView>
    with SingleTickerProviderStateMixin {

  late AnimationController _controller;
  late Animation<double> _animation;
  bool isScanned = false;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0, end: 240).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleScan(String rawValue) {
    if (isScanned) return;

    try {
      String decodedString = rawValue;
      if (!rawValue.trim().startsWith('{')) {
        try {
          final decodedBytes = base64Decode(rawValue);
          decodedString = utf8.decode(decodedBytes);
        } catch (_) {}
      }

      final parsed = jsonDecode(decodedString);
      if (parsed['branch_id'] != null &&
          parsed['company_code'] != null &&
          parsed['servel_url'] != null) {
        isScanned = true;
        debugPrint("✅ Valid QR");
        debugPrint("✅ $parsed['branch_id']");
        debugPrint("✅ $rawValue");
        Get.back(result: parsed);
      }
    } catch (e) {
      debugPrint("❌ Scan error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Branch QR'),
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Get.back(),
        ),
      ),
      body: Stack(
        children: [
          MobileScanner(
            fit: BoxFit.cover,
            onDetect: (capture) {
              for (final barcode in capture.barcodes) {
                final rawValue = barcode.rawValue;
                if (rawValue != null) {
                  _handleScan(rawValue);
                }
              }
            },
          ),
          Positioned.fill(
            child: Builder(
              builder: (context) {
                final size = MediaQuery.of(context).size;
                const scanSize = 260.0;
                final topHeight = (size.height - scanSize) / 2.39;
                final sideWidth = (size.width - scanSize) / 2;
                return Stack(
                  children: [
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: topHeight,
                      child: Container(color: Colors.black.withOpacity(0.6)),
                    ),
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      height: topHeight,
                      child: Container(color: Colors.black.withOpacity(0.6)),
                    ),
                    Positioned(
                      top: topHeight,
                      left: 0,
                      width: sideWidth,
                      height: scanSize,
                      child: Container(color: Colors.black.withOpacity(0.6)),
                    ),
                    Positioned(
                      top: topHeight,
                      right: 0,
                      width: sideWidth,
                      height: scanSize,
                      child: Container(color: Colors.black.withOpacity(0.6)),
                    ),
                  ],
                );
              },
            ),
          ),
          Center(
            child: SizedBox(
              width: 260,
              height: 260,
              child: Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.green, width: 3),
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  AnimatedBuilder(
                    animation: _animation,
                    builder: (context, child) {
                      return Positioned(
                        top: _animation.value,
                        left: 0,
                        right: 0,
                        child: Container(
                          height: 2,
                          color: Colors.green,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 80,
            left: 0,
            right: 0,
            child: const Center(
              child: Text(
                "Align QR code inside the box",
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}