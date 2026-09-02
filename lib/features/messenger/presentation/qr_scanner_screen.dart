import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_colors.dart';
import '../data/models/chat_model.dart';
import '../data/models/contact_model.dart';
import '../logic/messenger_provider.dart';

/// Full-screen QR scanner that reads a contact's cryptographic identity payload.
///
/// The QR payload must be a JSON object with:
/// - v: version (must be 1)
/// - uid: user ID
/// - ik: identity public key (Base64)
/// - fp: SHA-256 fingerprint of the public key (hex)
///
/// Fail-closed: invalid format, missing fields, fingerprint mismatch,
/// or key mismatch with the server all abort the operation.
class QrScannerScreen extends StatefulWidget {
  final void Function(Chat chat) onChatCreated;
  final VoidCallback onBack;

  const QrScannerScreen({
    super.key,
    required this.onChatCreated,
    required this.onBack,
  });

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  late final MobileScannerController _controller;
  bool _isProcessing = false;
  String? _error;
  bool _isCriticalError = false;

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

  /// Parse and validate the QR payload. Returns null on failure (sets _error).
  _QrPayload? _parseQrPayload(String raw) {
    // Strict JSON parse — fail-closed on any non-JSON content
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      _error = AppLocalizations.of(context)!.qrInvalidFormat;
      return null;
    }

    // Version check
    // v1 bleibt lesbar: ein Gerät mit älterem Stand zeigt weiterhin solche
    // Codes, und dann läuft es eben über die gewöhnliche Rückfrage.
    final version = json['v'];
    if (version is! int || (version != 1 && version != 2)) {
      _error = AppLocalizations.of(context)!.qrUnsupportedVersion;
      return null;
    }

    // Required field validation
    final uid = json['uid'];
    final ik = json['ik'];
    final fp = json['fp'];

    if (uid is! String || uid.isEmpty ||
        ik is! String || ik.isEmpty ||
        fp is! String || fp.isEmpty) {
      _error = AppLocalizations.of(context)!.qrInvalidFormat;
      return null;
    }

    // Decode and validate the public key
    final Uint8List publicKey;
    try {
      publicKey = base64Decode(ik);
      if (publicKey.isEmpty) {
        _error = AppLocalizations.of(context)!.qrInvalidFormat;
        return null;
      }
    } catch (_) {
      _error = AppLocalizations.of(context)!.qrInvalidFormat;
      return null;
    }

    // Recompute fingerprint and verify against the QR's fp field
    final recomputedFp = Contact.computeFullFingerprint(publicKey);
    if (recomputedFp != fp) {
      _error = AppLocalizations.of(context)!.qrFingerprintMismatch;
      _isCriticalError = true;
      return null;
    }

    // Ab v2 liegt ein Einmal-Token bei. Fehlt es, ist das kein Fehler —
    // dann gilt der gewöhnliche Weg mit Rückfrage.
    final rt = json['rt'];
    return _QrPayload(
      uid: uid,
      publicKey: publicKey,
      fingerprint: fp,
      requestToken: rt is String && rt.isNotEmpty ? rt : null,
    );
  }

  Future<void> _handleBarcode(BarcodeCapture capture) async {
    if (_isProcessing) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;

    final raw = barcode.rawValue!.trim();
    if (raw.isEmpty) return;

    setState(() {
      _isProcessing = true;
      _error = null;
      _isCriticalError = false;
    });

    await _controller.stop();

    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    final messenger = context.read<MessengerProvider>();

    // Parse and validate QR payload
    final payload = _parseQrPayload(raw);
    if (payload == null) {
      if (mounted) {
        setState(() => _isProcessing = false);
        if (!_isCriticalError) await _controller.start();
      }
      return;
    }

    // Self-scan prevention
    if (payload.uid == messenger.userId) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _error = l10n.thatsYourOwnId;
        });
        await _controller.start();
      }
      return;
    }

    // Add contact with cryptographic verification
    final (contact, result) = await messenger.addContactFromQr(
      contactId: payload.uid,
      qrPublicKey: payload.publicKey,
      qrFingerprint: payload.fingerprint,
      qrToken: payload.requestToken,
    );

    if (!mounted) return;

    switch (result) {
      case QrContactResult.verified:
        // Key match — contact is now verified. Show name dialog.
        final name = await _showNameDialog(context, contact!.shortId);
        if (!mounted) return;

        if (name != null && name.isNotEmpty) {
          await messenger.renameContact(contact.id, name);
        }

        final chat = messenger.getOrCreateChat(
          messenger.contactForId(contact.id) ?? contact,
        );
        if (mounted) {
          widget.onChatCreated(chat);
        }

      case QrContactResult.keyMismatch:
        // CRITICAL: Server key differs from QR key — possible MITM.
        // Fail-closed: no chat created, no communication allowed.
        setState(() {
          _isProcessing = false;
          _error = l10n.qrKeyMismatch;
          _isCriticalError = true;
        });
        // Do NOT resume scanning — this is a security incident.

      case QrContactResult.userNotFound:
        setState(() {
          _isProcessing = false;
          _error = l10n.userNotFound;
        });
        await _controller.start();
    }
  }

  Future<String?> _showNameDialog(BuildContext context, String shortId) {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        // Sonst legt sich der Inhalt bei offener Tastatur und grosser
        // Systemschrift ueber die Knopfzeile, statt zu scrollen.
        scrollable: true,
        title: Text(l10n.nameThisContact),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.nameContactHint,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondaryDark,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'ID: $shortId',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    color: AppColors.textTertiaryDark,
                  ),
            ),
            const SizedBox(height: 12),
            // Verification badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.success.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.verified_rounded,
                      size: 14, color: AppColors.success),
                  const SizedBox(width: 6),
                  Text(
                    l10n.qrVerified,
                    style: const TextStyle(
                      color: AppColors.success,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                hintText: l10n.nameContactPlaceholder,
                prefixIcon: const Icon(Icons.person_outline, size: 20),
              ),
              onSubmitted: (val) => Navigator.of(ctx).pop(val.trim()),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: Text(l10n.skip),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: Text(l10n.save),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (kIsWeb) {
      return Scaffold(
        appBar: AppBar(
          title: Text(l10n.scanQrCode),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            onPressed: widget.onBack,
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              l10n.qrWebUnavailable,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera preview
          MobileScanner(
            controller: _controller,
            onDetect: _handleBarcode,
          ),

          // Overlay with viewfinder cutout
          _ScannerOverlay(
            error: _error,
            isCritical: _isCriticalError,
          ),

          // Top bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded,
                          color: Colors.white),
                      onPressed: widget.onBack,
                    ),
                    Expanded(
                      child: Text(
                        l10n.scanQrCode,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    ValueListenableBuilder(
                      valueListenable: _controller,
                      builder: (_, state, child) {
                        return IconButton(
                          icon: Icon(
                            state.torchState == TorchState.on
                                ? Icons.flash_on
                                : Icons.flash_off,
                            color: Colors.white,
                          ),
                          onPressed: () => _controller.toggleTorch(),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Loading indicator
          if (_isProcessing)
            const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
        ],
      ),
    );
  }
}

/// Parsed and validated QR payload.
class _QrPayload {
  final String uid;
  final Uint8List publicKey;
  final String fingerprint;

  /// Nachweis, dass der Code wirklich vorlag. Null bei v1.
  final String? requestToken;

  const _QrPayload({
    required this.uid,
    required this.publicKey,
    required this.fingerprint,
    this.requestToken,
  });
}

class _ScannerOverlay extends StatelessWidget {
  final String? error;
  final bool isCritical;

  const _ScannerOverlay({this.error, this.isCritical = false});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final scanArea = size.width * 0.7;

    return Stack(
      children: [
        // Dark overlay with transparent center
        ColorFiltered(
          colorFilter: const ColorFilter.mode(
            Colors.black54,
            BlendMode.srcOut,
          ),
          child: Stack(
            children: [
              Container(
                decoration: const BoxDecoration(
                  color: Colors.black,
                  backgroundBlendMode: BlendMode.dstOut,
                ),
              ),
              Center(
                child: Container(
                  width: scanArea,
                  height: scanArea,
                  decoration: BoxDecoration(
                    color: Colors.red, // any opaque color
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Corner decoration
        Center(
          child: SizedBox(
            width: scanArea,
            height: scanArea,
            child: CustomPaint(
              painter: _CornerPainter(),
            ),
          ),
        ),

        // Instructions + error
        Positioned(
          bottom: 120,
          left: 32,
          right: 32,
          child: Column(
            children: [
              if (error != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isCritical
                        ? AppColors.destructive.withValues(alpha: 0.95)
                        : AppColors.destructive.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(12),
                    border: isCritical
                        ? Border.all(color: Colors.white24, width: 1)
                        : null,
                  ),
                  child: Column(
                    children: [
                      if (isCritical)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 6),
                          child: Icon(Icons.shield_rounded,
                              color: Colors.white, size: 20),
                        ),
                      Text(
                        error!,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 14),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              if (error == null)
                Text(
                  AppLocalizations.of(context)!.qrScanHint,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CornerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.primary
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const cornerLen = 30.0;
    const r = 20.0;

    // Top-left
    canvas.drawArc(
      const Rect.fromLTWH(0, 0, r * 2, r * 2),
      3.14,
      1.57,
      false,
      paint,
    );
    canvas.drawLine(const Offset(0, r), Offset(0, cornerLen), paint);
    canvas.drawLine(const Offset(r, 0), Offset(cornerLen, 0), paint);

    // Top-right
    canvas.drawArc(
      Rect.fromLTWH(size.width - r * 2, 0, r * 2, r * 2),
      -1.57,
      1.57,
      false,
      paint,
    );
    canvas.drawLine(
        Offset(size.width, r), Offset(size.width, cornerLen), paint);
    canvas.drawLine(
        Offset(size.width - r, 0), Offset(size.width - cornerLen, 0), paint);

    // Bottom-left
    canvas.drawArc(
      Rect.fromLTWH(0, size.height - r * 2, r * 2, r * 2),
      1.57,
      1.57,
      false,
      paint,
    );
    canvas.drawLine(
        Offset(0, size.height - r), Offset(0, size.height - cornerLen), paint);
    canvas.drawLine(
        Offset(r, size.height), Offset(cornerLen, size.height), paint);

    // Bottom-right
    canvas.drawArc(
      Rect.fromLTWH(
          size.width - r * 2, size.height - r * 2, r * 2, r * 2),
      0,
      1.57,
      false,
      paint,
    );
    canvas.drawLine(Offset(size.width, size.height - r),
        Offset(size.width, size.height - cornerLen), paint);
    canvas.drawLine(Offset(size.width - r, size.height),
        Offset(size.width - cornerLen, size.height), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
