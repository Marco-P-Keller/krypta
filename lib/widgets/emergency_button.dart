import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Emergency wipe button present throughout the app.
/// Single tap triggers immediate data destruction. No confirmation.
class EmergencyButton extends StatelessWidget {
  final VoidCallback onWipe;

  const EmergencyButton({super.key, required this.onWipe});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(
        Icons.warning_amber_rounded,
        color: AppColors.destructive,
      ),
      tooltip: 'Emergency Delete',
      onPressed: onWipe,
    );
  }
}
