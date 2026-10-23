import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../controller/printer_controller.dart';

class PrintIssueBadge extends StatelessWidget {
  final String orderId;
  final bool compact;
  const PrintIssueBadge({super.key, required this.orderId, this.compact = false});

  Future<void> _retry(BuildContext ctx, PrinterController c) async {
    final failures = await c.retryPrintIssues(orderId);

    if (failures.isEmpty) {
      if (ctx.mounted) Navigator.pop(ctx);
      return;
    }
    if (!ctx.mounted) return;

    final tryAgain = await showDialog<bool>(
      context: ctx,
      builder: (d) => AlertDialog(
        icon: const Icon(Icons.print_disabled, color: Colors.red, size: 36),
        title: const Text('Printer not reachable'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final f in failures)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(f.target,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text(f.error),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            const Text(
              'Make sure the printer is switched on, in range, and not '
                  'connected to another device.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Try again'),
          ),
        ],
      ),
    );

    if (tryAgain == true && ctx.mounted) await _retry(ctx, c);
  }

  @override
  Widget build(BuildContext context) {
    final c = Get.find<PrinterController>();
    return Obx(() {
      if (!c.hasPrintIssue(orderId)) return const SizedBox.shrink();
      return InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showDetails(context, c),
        child: Container(
          padding: compact
              ? const EdgeInsets.all(3)
              : const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.red.withOpacity(0.12),
            border: Border.all(color: Colors.red),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.print_disabled, size: 14, color: Colors.red),
              if (!compact) ...const [
                SizedBox(width: 4),
                Text('Not printed',
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.red,
                        fontWeight: FontWeight.w600)),
              ],
            ],
          ),
        ),
      );
    });
  }

  void _showDetails(BuildContext context, PrinterController c) {
    showDialog(
      context: context,
      builder: (ctx) => Obx(() {
        final issues = c.printIssues[orderId] ?? const <PrintIssue>[];
        return AlertDialog(
          title: const Text('Print problems'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final i in issues)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('${i.kind}: ${i.message}'),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                c.clearPrintIssues(orderId);
                Navigator.pop(ctx);
              },
              child: const Text('Dismiss'),
            ),
            if (issues.any((i) => i.canRetry))
              TextButton(
                onPressed: c.isRetryingPrint.value ? null : () => _retry(ctx, c),
                child: c.isRetryingPrint.value
                    ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                    : const Text('Retry'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        );
      }),
    );
  }
}