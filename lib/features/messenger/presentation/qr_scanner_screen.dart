import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import '../../../theme/app_colors.dart';
import '../data/models/chat_model.dart';
import '../logic/messenger_provider.dart';

/// Full-screen QR scanner that reads another user's ID and opens a chat.
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

  Future<void> _handleBarcode(BarcodeCapture capture) async {
    if (_isProcessing) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;

    final scannedId = barcode.rawValue!.trim();
    if (scannedId.isEmpty) return;

    setState(() {
      _isProcessing = true;
      _error = null;
    });

    await _controller.stop();

    if (!mounted) return;
    final messenger = context.read<MessengerProvider>();

    if (scannedId == messenger.userId) {
      setState(() {
        _isProcessing = false;
        _error = 'That\'s your own ID';
      });
      await _controller.start();
      return;
    }

    final contact = await messenger.addContact(scannedId);
    if (contact == null) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _error = 'User not found';
        });
        await _controller.start();
      }
      return;
    }

    final chat = messenger.getOrCreateChat(contact);
    if (mounted) {
      widget.onChatCreated(chat);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Scan QR Code'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            onPressed: widget.onBack,
          ),
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              'QR scanning is not available on web.\nUse a mobile device to scan QR codes.',
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
          _ScannerOverlay(error: _error),

          // Top bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded,
                          color: Colors.white),
                      onPressed: widget.onBack,
                    ),
                    const Expanded(
                      child: Text(
                        'Scan QR Code',
                        textAlign: TextAlign.center,
                        style: TextStyle(
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

class _ScannerOverlay extends StatelessWidget {
  final String? error;

  const _ScannerOverlay({this.error});

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
                      horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.destructive.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    error!,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                ),
              if (error == null)
                const Text(
                  'Point your camera at a Krypta QR code',
                  style: TextStyle(
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
    canvas.drawLine(Offset(r, size.height),
        Offset(cornerLen, size.height), paint);

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
