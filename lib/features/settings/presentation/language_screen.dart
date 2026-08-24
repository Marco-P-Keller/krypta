import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/locale/locale_controller.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';

/// Die Sprachauswahl, einmal beim Einrichten und danach in den Einstellungen.
///
/// Die Sprachen stehen in ihrer eigenen Schreibweise da — wer die App auf
/// Spanisch stellen will, sucht „Español", nicht „Spanisch". Deshalb ist die
/// Liste auch dann bedienbar, wenn gerade eine Sprache eingestellt ist, die
/// man nicht liest.
class LanguageList extends StatelessWidget {
  const LanguageList({super.key, this.onSelected});

  /// Wird nach der Wahl aufgerufen — beim Einrichten für den nächsten
  /// Schritt, in den Einstellungen zum Schließen.
  final VoidCallback? onSelected;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LocaleController>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: LocaleController.supported.length,
      separatorBuilder: (_, _) => Divider(
        height: 1,
        color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
      ),
      itemBuilder: (context, index) {
        final locale = LocaleController.supported[index];
        final selected = controller.locale == locale;
        return ListTile(
          title: Text(
            LocaleController.labelFor(locale),
            style: TextStyle(
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected
                  ? AppColors.accent
                  : (isDark
                      ? AppColors.textPrimaryDark
                      : AppColors.textPrimaryLight),
            ),
          ),
          trailing: selected
              ? const Icon(Icons.check_rounded,
                  color: AppColors.accent, size: 20)
              : null,
          onTap: () async {
            await controller.select(locale);
            onSelected?.call();
          },
        );
      },
    );
  }
}

/// Ganzseitige Fassung für den Einrichtungs-Ablauf.
///
/// Steht bewusst vor dem Tutorial: alles danach ist Text, und der soll in der
/// Sprache erscheinen, die der Nutzer versteht.
class LanguageScreen extends StatelessWidget {
  const LanguageScreen({super.key, required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 48),
              const Icon(Icons.language_rounded,
                  size: 44, color: AppColors.accent),
              const SizedBox(height: 20),
              Text(
                l10n.chooseLanguage,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                    ),
              ),
              const SizedBox(height: 28),
              Expanded(
                child: SingleChildScrollView(
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.surfaceElevatedDark
                          : AppColors.surfaceElevatedLight,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const LanguageList(),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: onContinue,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: Text(
                  l10n.next,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

/// Die Auswahl als Blatt von unten — der Weg aus den Einstellungen.
Future<void> showLanguageSheet(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final l10n = AppLocalizations.of(context)!;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor:
        isDark ? AppColors.surfaceElevatedDark : AppColors.surfaceElevatedLight,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              l10n.language,
              style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          // Schließt nach der Wahl: der Wechsel ist sofort sichtbar, das Blatt
          // offen zu lassen wirkt, als sei nichts passiert.
          LanguageList(onSelected: () => Navigator.of(sheetContext).pop()),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
