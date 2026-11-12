import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Opens the scanner and completes with the scanned (or typed) code,
/// or null if the user backed out.
typedef BarcodeScan = Future<String?> Function(BuildContext context);

/// Screens ask for a scan through this provider rather than opening the
/// camera themselves, so tests can supply a code without a camera.
final barcodeScanProvider = Provider<BarcodeScan>((ref) => (context) => context.push<String>('/scan'));
