import 'dart:io';
import 'package:flutter/foundation.dart';

class LocalHubNetwork {
  static Future<String?> getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );

      debugPrint('======================================');
      debugPrint('NETWORK INTERFACES');
      debugPrint('======================================');

      for (final interface in interfaces) {
        debugPrint('Interface: ${interface.name}');

        for (final address in interface.addresses) {
          debugPrint(
            '  Address: ${address.address}',
          );
        }
      }

      debugPrint('======================================');

      // Prefer Wi-Fi / hotspot interfaces.
      for (final interface in interfaces) {
        final name = interface.name.toLowerCase();

        if (name.contains('wlan') ||
            name.contains('wifi') ||
            name.contains('ap') ||
            name.contains('softap')) {
          for (final address in interface.addresses) {
            if (_isPrivateIPv4(address.address)) {
              return address.address;
            }
          }
        }
      }

      // Fallback:
      // return any private IPv4 address.
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (_isPrivateIPv4(address.address)) {
            return address.address;
          }
        }
      }

      return null;
    } catch (e) {
      debugPrint(
        'LOCAL HUB NETWORK ERROR: $e',
      );

      return null;
    }
  }

  static bool _isPrivateIPv4(String ip) {
    final parts = ip.split('.');

    if (parts.length != 4) {
      return false;
    }

    final numbers = parts
        .map(int.tryParse)
        .toList();

    if (numbers.any((e) => e == null)) {
      return false;
    }

    final a = numbers[0]!;
    final b = numbers[1]!;

    // 10.0.0.0/8
    if (a == 10) {
      return true;
    }

    // 172.16.0.0/12
    if (a == 172 && b >= 16 && b <= 31) {
      return true;
    }

    // 192.168.0.0/16
    if (a == 192 && b == 168) {
      return true;
    }

    return false;
  }
}