import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_colors.dart';

/// Emergency wipe button — semi-transparent, confirmation required.
/// Single tap opens a confirm dialog; wipe only fires after explicit confirm.
class EmergencyButton extends StatelessWidget {
  final VoidCallback onWipe;

  const EmergencyButton({super.key, required this.onWipe});

  void _confirm(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    HapticFeedback.heavyImpact();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.emergencyDelete),
        content: Text(l10n.emergencyDeleteDescription),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.destructive,
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              onWipe();
            },
            child: Text(l10n.emergencyDelete),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.5,
      child: IconButton(
        icon: const Icon(Icons.warning_amber_rounded, size: 20),
        color: AppColors.destructive,
        tooltip: 'Emergency wipe',
        onPressed: () => _confirm(context),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      ),
    );
  }
}
