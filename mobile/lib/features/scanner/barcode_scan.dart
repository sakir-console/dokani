import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'scanner_screen.dart';

/// Opens the scanner and completes with the scanned (or typed) code,
/// or null if the user backed out.
typedef BarcodeScan = Future<String?> Function(BuildContext context);

/// Screens ask for a scan through this provider rather than opening the
/// camera themselves, so tests can supply a code without a camera.
final barcodeScanProvider = Provider<BarcodeScan>((ref) => (context) => context.push<String>('/scan'));

/// What to show after a code was handled in continuous mode.
class ScanFeedback {
  const ScanFeedback(this.message, {this.ok = true});

  final String message;
  final bool ok;
}

/// Keeps the scanner open and hands every scanned code to [onCode], one at a
/// time, until the user closes it. Used at the counter to scan a basket.
typedef ContinuousScan = Future<void> Function(
  BuildContext context,
  Future<ScanFeedback> Function(String code) onCode,
);

final continuousScanProvider = Provider<ContinuousScan>(
  (ref) => (context, onCode) => Navigator.of(context, rootNavigator: true).push<void>(
        MaterialPageRoute(builder: (_) => ScannerScreen(onCode: onCode)),
      ),
);
