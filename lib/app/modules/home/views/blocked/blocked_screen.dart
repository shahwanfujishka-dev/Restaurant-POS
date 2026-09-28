import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get_storage/get_storage.dart';

class BlockedView extends StatelessWidget {
  const BlockedView({super.key});
  @override
  Widget build(BuildContext context) {
    final storage = GetStorage();
    final reason = storage.read('blockedReason') ?? 'violation of terms';

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.block, size: 80.sp, color: Colors.red),
            SizedBox(height: 20.h),
            Text(
              'Account Suspended',
              style: TextStyle(fontSize: 22.sp, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 10.h),
            Text(
              'Your account has been suspended\ndue to: $reason',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14.sp, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}