import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';

/// Die ausfuehrliche Sicherheitsansicht, erreichbar aus „Ueber Krypta ECC".
///
/// Angelegt am 02.09.2026 auf Daniels Wunsch. Die Ueber-Ansicht selbst bleibt
/// knapp; wer es genauer wissen will, tippt hier hinein.
///
/// **Jede Angabe ist am Quelltext geprueft.** Was sich nicht eindeutig belegen
/// liess, steht nicht drin. Zwei Beispiele, die es beinahe hineingeschafft
/// haetten und dann doch nicht stimmten: die HMAC-Bindung des Delivery-Tokens
/// ist im Code entfernt, und Certificate Pinning gibt es nur nativ, nicht
/// zusaetzlich auf Dart-Ebene.
///
/// **Was bewusst fehlt:** Betriebsgroessen wie Fehlversuchsgrenzen,
/// Token-Laufzeiten oder wie viele uebersprungene Nachrichten der Ratchet
/// duldet. Die helfen niemandem ausser jemandem, der etwas kaputtmachen will.
/// Die Verfahren und ihre Parameter dagegen stehen vollstaendig da: sie geheim
/// zu halten waere Sicherheit durch Verschleierung, und die traegt nicht.
class SicherheitsdetailsScreen extends StatelessWidget {
  const SicherheitsdetailsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Die technischen Zeilen bleiben unuebersetzt. Ein Algorithmus heisst in
    // jeder Sprache gleich, und wer sie liest, sucht genau diese Namen.
    final abschnitte = <(String, String, String)>[
      (
        l10n.secMessagesTitle,
        l10n.secMessagesBody,
        'XChaCha20-Poly1305 · AEAD mit AAD · 256-Bit-Schlüssel',
      ),
      (
        l10n.secExchangeTitle,
        l10n.secExchangeBody,
        'X3DH · X25519 · 3 × Diffie-Hellman → HKDF-SHA256',
      ),
      (
        l10n.secForwardTitle,
        l10n.secForwardBody,
        'Double Ratchet · HKDF-SHA256 · Schlüssel je Nachricht',
      ),
      (
        l10n.secIdentityTitle,
        l10n.secIdentityBody,
        'Ed25519-Signaturen · Sicherheitsnummer: SHA-512, 5200 Runden',
      ),
      (
        l10n.secPasswordTitle,
        l10n.secPasswordBody,
        'Argon2id · 19 MiB · 2 Durchgänge · p=1 · 32 Byte',
      ),
      (
        l10n.secLocalTitle,
        l10n.secLocalBody,
        'XChaCha20-Poly1305 · Keychain / Keystore · Secure Enclave, StrongBox',
      ),
      (
        l10n.secServerTitle,
        l10n.secServerBody,
        'Sealed Sender · kurzlebige Zustellkennung',
      ),
      (
        l10n.secTransportTitle,
        l10n.secTransportBody,
        'TLS · Certificate Pinning (Android, iOS)',
      ),
    ];

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      appBar: AppBar(
        title: Text(
          l10n.securityDetails,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenPadding, 8, AppSpacing.screenPadding, 40),
        children: [
          Text(
            l10n.secIntro,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight,
                  height: 1.5,
                ),
          ),
          const SizedBox(height: 24),
          for (final (titel, text, technik) in abschnitte) ...[
            _Abschnitt(
                isDark: isDark, titel: titel, text: text, technik: technik),
            const SizedBox(height: 18),
          ],
          const SizedBox(height: 6),
          Text(
            l10n.secFooter,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: isDark
                      ? AppColors.textTertiaryDark
                      : AppColors.textTertiaryLight,
                  height: 1.4,
                ),
          ),
        ],
      ),
    );
  }
}

/// Ein Abschnitt: Ueberschrift, ein Absatz Klartext, darunter die Verfahren.
class _Abschnitt extends StatelessWidget {
  final bool isDark;
  final String titel;
  final String text;
  final String technik;

  const _Abschnitt({
    required this.isDark,
    required this.titel,
    required this.text,
    required this.technik,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titel,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight,
                  height: 1.5,
                ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              technik,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11.5,
                height: 1.4,
                color: AppColors.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
