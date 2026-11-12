import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../app/theme/app_theme.dart';
import '../../core/widgets/dialogs.dart';
import '../../l10n/app_localizations.dart';
import 'barcode_scan.dart';

/// Full-screen barcode / QR scanner.
///
/// Without [onCode] it pops with the first code scanned. With [onCode] it
/// stays open: every code is passed on, the result is shown at the top, and
/// scanning continues — the same code scanned again counts again.
///
/// Tuned for low-end phones:
///  - the camera starts on its own and scanning needs no button
///  - analysis runs at the plugin's default 640x480, which ML Kit reads fine
///    and cheap chipsets can keep up with
///  - only retail formats and QR are searched for
///  - the frame guide is static; nothing is animated over the preview
class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key, this.onCode});

  final Future<ScanFeedback> Function(String code)? onCode;

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      BarcodeFormat.itf14,
      BarcodeFormat.qrCode,
    ],
  );

  bool _done = false;

  // Continuous mode.
  bool _handling = false;
  String? _lastCode;
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);
  ScanFeedback? _feedback;

  bool get _continuous => widget.onCode != null;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _finish(String code) {
    if (_continuous) {
      _handle(code);
      return;
    }
    if (_done || !mounted) return;
    _done = true;
    HapticFeedback.mediumImpact();
    SystemSound.play(SystemSoundType.click);
    Navigator.of(context).pop(code);
  }

  Future<void> _handle(String code) async {
    final now = DateTime.now();
    // The camera sees the same barcode many times a second. Holding it steady
    // counts once; showing it again after a short pause counts again.
    if (_handling || (code == _lastCode && now.difference(_lastAt) < const Duration(milliseconds: 1500))) return;

    _handling = true;
    _lastCode = code;
    _lastAt = now;

    final feedback = await widget.onCode!(code);
    if (!mounted) return;

    // A light buzz and click for "added"; a heavier one for "not found" or "out of stock".
    unawaited(feedback.ok ? HapticFeedback.mediumImpact() : HapticFeedback.heavyImpact());
    unawaited(SystemSound.play(feedback.ok ? SystemSoundType.click : SystemSoundType.alert));
    setState(() => _feedback = feedback);
    _lastAt = DateTime.now();
    _handling = false;
  }

  void _onDetect(BarcodeCapture capture) {
    for (final barcode in capture.barcodes) {
      final code = barcode.rawValue?.trim();
      if (code != null && code.isNotEmpty) {
        _finish(code);
        return;
      }
    }
  }

  Future<void> _typeCode() async {
    final l10n = AppLocalizations.of(context);
    final code = await showTextInputDialog(
      context,
      title: l10n.enterBarcodeManually,
      label: l10n.barcode,
      confirmLabel: l10n.continueLabel,
      maxLength: 64,
      keyboardType: TextInputType.visiblePassword, // letters and digits, no autocorrect
    );
    if (code != null && code.isNotEmpty) _finish(code);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(l10n.scanBarcode, style: const TextStyle(color: Colors.white)),
        actions: [
          ValueListenableBuilder(
            valueListenable: _controller,
            builder: (context, state, _) {
              if (state.torchState == TorchState.unavailable) return const SizedBox.shrink();
              final on = state.torchState == TorchState.on;
              return IconButton(
                tooltip: l10n.torch,
                isSelected: on,
                icon: Icon(on ? Icons.flashlight_on : Icons.flashlight_off_outlined),
                onPressed: _controller.toggleTorch,
              );
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            tapToFocus: true,
            errorBuilder: (context, error) => _CameraProblem(
              permissionDenied: error.errorCode == MobileScannerErrorCode.permissionDenied,
              onTypeCode: _typeCode,
            ),
            overlayBuilder: (context, constraints) => const _FrameGuide(),
          ),
          if (_feedback != null)
            Align(
              alignment: Alignment.topCenter,
              child: Semantics(
                liveRegion: true,
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: _feedback!.ok ? AppColors.brandDark : AppColors.danger,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _feedback!.message,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _continuous ? l10n.scanContinuousHint : l10n.scanHint,
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    ),
                    const SizedBox(height: 12),
                    if (_continuous) ...[
                      FilledButton(
                        style: FilledButton.styleFrom(minimumSize: const Size(200, 52)),
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(l10n.done),
                      ),
                      const SizedBox(height: 8),
                    ],
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white54),
                        minimumSize: const Size(0, 48),
                      ),
                      onPressed: _typeCode,
                      icon: const Icon(Icons.keyboard_outlined),
                      label: Text(l10n.enterBarcodeManually),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A static rounded rectangle showing where to hold the barcode.
class _FrameGuide extends StatelessWidget {
  const _FrameGuide();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: FractionallySizedBox(
          widthFactor: 0.78,
          child: AspectRatio(
            aspectRatio: 1.6,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 3),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CameraProblem extends StatelessWidget {
  const _CameraProblem({required this.permissionDenied, required this.onTypeCode});

  final bool permissionDenied;
  final VoidCallback onTypeCode;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography_outlined, color: Colors.white70, size: 56),
              const SizedBox(height: 16),
              Text(
                permissionDenied ? l10n.cameraPermissionTitle : l10n.cameraErrorTitle,
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                permissionDenied ? l10n.cameraPermissionBody : l10n.cameraErrorBody,
                style: const TextStyle(color: Colors.white70, fontSize: 15),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
