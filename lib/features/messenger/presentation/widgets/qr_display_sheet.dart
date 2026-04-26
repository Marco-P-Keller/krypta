import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../theme/app_colors.dart';
import '../../data/models/contact_model.dart';

/// Bottom sheet that shows the user's identity QR code for contact verification.
///
/// The QR code contains a structured JSON payload with:
/// - v: protocol version
/// - uid: user ID
/// - ik: identity public key (Base64)
/// - fp: SHA-256 fingerprint of the public key (hex)
///
/// This eliminates first-key-trust: the scanner can verify the key
/// independently from the server.
class QrDisplaySheet extends StatelessWidget {
  final String userId;
  final Uint8List identityPublicKey;

  const QrDisplaySheet({
    super.key,
    required this.userId,
    required this.identityPublicKey,
  });

  static void show(
    BuildContext context, {
    required String userId,
    required Uint8List publicKey,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => QrDisplaySheet(
        userId: userId,
        identityPublicKey: publicKey,
      ),
    );
  }

  /// Build the cryptographic QR payload as JSON.
  String _buildQrPayload() {
    final ikBase64 = base64Encode(identityPublicKey);
    final fp = Contact.computeFullFingerprint(identityPublicKey);
    return jsonEncode({
      'v': 1,
      'uid': userId,
      'ik': ikBase64,
      'fp': fp,
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;
    final qrData = _buildQrPayload();
    final fingerprint = Contact.computeFullFingerprint(identityPublicKey);
    // Format fingerprint for display: groups of 8 with spaces
    final fpDisplay = fingerprint
        .toUpperCase()
        .replaceAllMapped(RegExp('.{8}'), (m) => '${m.group(0)} ')
        .trim();

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 16,
        bottom: MediaQuery.of(context).padding.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.yourQrCode,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            l10n.qrShareHint,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight,
                ),
          ),
          const SizedBox(height: 24),

          // QR code in a white card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: QrImageView(
              data: qrData,
              version: QrVersions.auto,
              size: 220,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: Color(0xFF1A1A1E),
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.circle,
                color: Color(0xFF1A1A1E),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Key fingerprint display
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.surfaceElevatedDark
                  : AppColors.surfaceElevatedLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.success.withValues(alpha: 0.3),
                width: 0.5,
              ),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.fingerprint_rounded,
                        size: 14,
                        color: isDark
                            ? AppColors.textTertiaryDark
                            : AppColors.textTertiaryLight),
                    const SizedBox(width: 6),
                    Text(
                      'Key Fingerprint',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: isDark
                                ? AppColors.textTertiaryDark
                                : AppColors.textTertiaryLight,
                            fontSize: 10,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  fpDisplay,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        fontSize: 10,
                        letterSpacing: 0.5,
                        height: 1.5,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Copyable user ID
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: userId));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l10n.idCopied)),
              );
            },
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.surfaceElevatedDark
                    : AppColors.surfaceElevatedLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      userId,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                            letterSpacing: 0.5,
                          ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.copy, size: 16, color: AppColors.primary),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
