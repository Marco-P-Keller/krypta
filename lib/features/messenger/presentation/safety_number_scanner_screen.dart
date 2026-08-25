import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_colors.dart';

/// Scannt den QR-Code einer Sicherheitsnummer und gibt ihn zurück.
///
/// Bewusst getrennt vom [QrScannerScreen]: der legt einen Kontakt an und
/// prüft ein JSON-Bündel aus Nutzerkennung, Schlüssel und Fingerabdruck.
/// Hier geht es nur darum, eine Zeichenkette einzulesen — verglichen und
/// bewertet wird sie von [checkScannedSafetyNumber], damit die Entscheidung
/// prüfbar bleibt und nicht in einem Kamera-Bildschirm steckt.
class SafetyNumberScannerScreen extends StatefulWidget {
  const SafetyNumberScannerScreen({super.key});

  @override
  State<SafetyNumberScannerScreen> createState() =>
      _SafetyNumberScannerScreenState();
}

class _SafetyNumberScannerScreenState extends State<SafetyNumberScannerScreen> {
  late final MobileScannerController _controller;

  /// Die Kamera liefert denselben Code mehrfach pro Sekunde. Ohne diese
  /// Sperre würde der Bildschirm mehrfach geschlossen.
  bool _fertig = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _gelesen(BarcodeCapture capture) {
    if (_fertig) return;
    final roh = capture.barcodes.firstOrNull?.rawValue;
    if (roh == null || roh.isEmpty) return;
    _fertig = true;
    Navigator.of(context).pop(roh);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (kIsWeb) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.scanQrCode)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(l10n.qrWebUnavailable, textAlign: TextAlign.center),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _gelesen),

          // Sucherrahmen
          Center(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.accent, width: 2),
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),

          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    Expanded(
                      child: Text(
                        l10n.safetyNumberTitle,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
            ),
          ),

          Positioned(
            left: 24,
            right: 24,
            bottom: 48,
            child: SafeArea(
              child: Text(
                l10n.safetyNumberScanHint,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
