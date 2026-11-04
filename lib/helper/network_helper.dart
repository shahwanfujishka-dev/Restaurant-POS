import 'dart:io';
import '../app/data/utils/AppState.dart';

class NetworkHelper {
  /// Checks whether an active internet connection is available.
  /// Resolves the backend server host first, and falls back to 'google.com'.
  static Future<bool> hasInternetConnection() async {
    try {
      String host = 'google.com';
      final serverUrl = AppState.serverUrl;
      if (serverUrl.isNotEmpty && serverUrl.startsWith('http')) {
        final uri = Uri.tryParse(serverUrl);
        if (uri != null && uri.host.isNotEmpty) {
          host = uri.host;
        }
      }

      final result = await InternetAddress.lookup(host)
          .timeout(const Duration(seconds: 3));
      if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
        return true;
      }
    } catch (_) {}

    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 2));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}
