import 'package:flutter/material.dart';
import '../../../../services/platform/clipboard_helper.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../security/verification/safety_number.dart';
import '../../../../theme/app_colors.dart';
import '../../../../theme/app_spacing.dart';
import '../../data/models/contact_model.dart';
import '../../logic/messenger_provider.dart';

class ChatSettingsSheet extends StatefulWidget {
  final String chatId;

  const ChatSettingsSheet({super.key, required this.chatId});

  static void show(BuildContext context, String chatId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<MessengerProvider>(),
        child: ChatSettingsSheet(chatId: chatId),
      ),
    );
  }

  @override
  State<ChatSettingsSheet> createState() => _ChatSettingsSheetState();
}

const _avatarGradients = [
  [Color(0xFF5B7FFF), Color(0xFF7C5CFC)],
  [Color(0xFF00C9A7), Color(0xFF00B4D8)],
  [Color(0xFFFF6B6B), Color(0xFFFF8E72)],
  [Color(0xFFFFC75F), Color(0xFFFF9671)],
  [Color(0xFFE04DE8), Color(0xFF7C5CFC)],
  [Color(0xFF43E97B), Color(0xFF38F9D7)],
];

class _ChatSettingsSheetState extends State<ChatSettingsSheet> {
  static const _timerOptions = <Duration?>[
    null,
    Duration(seconds: 30),
    Duration(minutes: 5),
    Duration(hours: 1),
    Duration(days: 1),
    Duration(days: 7),
  ];

  List<Color> _gradientForName(String name) {
    final idx = name.isEmpty ? 0 : name.codeUnitAt(0) % _avatarGradients.length;
    return _avatarGradients[idx];
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final messenger = context.watch<MessengerProvider>();
    final chat = messenger.chatById(widget.chatId);
    if (chat == null) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context)!;
    final colors = _gradientForName(chat.recipientName);

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),

          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: colors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(17),
                  boxShadow: [
                    BoxShadow(
                      color: colors[0].withValues(alpha: 0.25),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    chat.recipientName.isNotEmpty
                        ? chat.recipientName[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      chat.recipientName,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      chat.recipientId.length > 16
                          ? '${chat.recipientId.substring(0, 16)}...'
                          : chat.recipientId,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            letterSpacing: 0.3,
                            color: isDark
                                ? AppColors.textTertiaryDark
                                : AppColors.textTertiaryLight,
                          ),
                    ),
                  ],
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: IconButton(
                  icon: const Icon(Icons.edit_rounded, size: 18),
                  color: AppColors.primary,
                  // No VisualDensity.compact: it shrinks IconButton's default
                  // 48x48pt minimum tap target to 40x40pt, under the 44x44pt
                  // HIG floor, for the sake of a slightly tighter row — not
                  // worth it for a rename control.
                  onPressed: () => _showRenameDialog(context, chat.recipientName),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 66),
              child: Row(
                children: [
                  Icon(Icons.visibility_off_outlined,
                      size: 11,
                      color: isDark
                          ? AppColors.textTertiaryDark
                          : AppColors.textTertiaryLight),
                  const SizedBox(width: 4),
                  Text(
                    l10n.onlyVisibleToYou,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: 10.5,
                          color: isDark
                              ? AppColors.textTertiaryDark
                              : AppColors.textTertiaryLight,
                        ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.surfaceElevatedDark
                  : AppColors.surfaceElevatedLight,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isDark
                    ? AppColors.dividerDark.withValues(alpha: 0.3)
                    : AppColors.dividerLight.withValues(alpha: 0.5),
                width: 0.5,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.timer_outlined, size: 16, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Text(
                      l10n.autoDeleteTimer,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.1,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.autoDeleteHint,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondaryLight,
                        height: 1.4,
                      ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _timerOptions.map((duration) {
                    final isSelected = chat.defaultSelfDestruct == duration;
                    return GestureDetector(
                      onTap: () => _onTimerChanged(duration),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          gradient: isSelected
                              ? const LinearGradient(
                                  colors: [
                                    AppColors.messageSentStart,
                                    AppColors.messageSentEnd,
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                )
                              : null,
                          color: isSelected
                              ? null
                              : (isDark
                                  ? AppColors.surfaceDark
                                  : AppColors.surfaceLight),
                          borderRadius: BorderRadius.circular(12),
                          border: isSelected
                              ? null
                              : Border.all(
                                  color: isDark
                                      ? AppColors.dividerDark
                                      : AppColors.dividerLight,
                                  width: 0.5,
                                ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: AppColors.primary.withValues(alpha: 0.2),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                              : null,
                        ),
                        child: Text(
                          _durationLabel(duration),
                          style: TextStyle(
                            color: isSelected
                                ? Colors.white
                                : (isDark
                                    ? AppColors.textSecondaryDark
                                    : AppColors.textSecondaryLight),
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),

          // ── Key Change Warning ──
          Builder(builder: (_) {
            final contact = messenger.contactForId(chat.recipientId);
            if (contact == null || !contact.hasKeyChanged) {
              return const SizedBox.shrink();
            }
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  border: Border.all(
                    color: AppColors.warning.withValues(alpha: 0.4),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded,
                            size: 18, color: AppColors.warning),
                        const SizedBox(width: 8),
                        Text(
                          l10n.securitySettings,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: AppColors.warning,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'The security key for this contact has changed. '
                      'Messages are blocked until you verify their identity. '
                      'Scan their QR code or compare safety numbers to resume messaging.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: isDark
                                ? AppColors.textSecondaryDark
                                : AppColors.textSecondaryLight,
                          ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _showSafetyNumber(
                                context, messenger, chat.recipientId),
                            icon: const Icon(Icons.qr_code_2_rounded, size: 16),
                            label: const Text('Verify Identity'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.accent,
                              side: const BorderSide(color: AppColors.accent),
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () {
                            messenger.blockContact(chat.recipientId);
                            setState(() {});
                          },
                          icon: const Icon(Icons.block_rounded, size: 16),
                          label: const Text('Block'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.destructive,
                            side: const BorderSide(color: AppColors.destructive),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),

          // ── Safety Number / Verification ──
          Builder(builder: (_) {
            final contact = messenger.contactForId(chat.recipientId);
            if (contact == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.surfaceElevatedDark
                      : AppColors.surfaceElevatedLight,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: isDark
                        ? AppColors.dividerDark.withValues(alpha: 0.3)
                        : AppColors.dividerLight.withValues(alpha: 0.5),
                    width: 0.5,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          contact.isVerified
                              ? Icons.verified_rounded
                              : Icons.shield_outlined,
                          size: 16,
                          color: contact.isVerified
                              ? AppColors.success
                              : AppColors.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          contact.isVerified ? 'Verified' : 'Identity',
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: -0.1,
                                  ),
                        ),
                        const Spacer(),
                        if (contact.isVerified)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.success.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'Secure',
                              style: TextStyle(
                                  color: AppColors.success,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Compare safety numbers or scan QR codes to verify end-to-end encryption.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: isDark
                                ? AppColors.textSecondaryDark
                                : AppColors.textSecondaryLight,
                            height: 1.4,
                          ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _showSafetyNumber(
                            context, messenger, chat.recipientId),
                        icon: const Icon(Icons.qr_code_2_rounded, size: 18),
                        label: const Text('View Safety Number'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: const BorderSide(color: AppColors.accent),
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppSpacing.radiusMd),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),

          if (chat.defaultSelfDestruct != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  width: 0.5,
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded,
                      size: 16, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.messagesAutoDelete(
                          _durationLabel(chat.defaultSelfDestruct)),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),

          // ── Clear Chat ──
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _confirmClearChat(context, messenger),
              icon: const Icon(Icons.delete_sweep_rounded, size: 18),
              label: Text(l10n.clearChat),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.destructive,
                side: const BorderSide(color: AppColors.destructive),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  void _confirmClearChat(BuildContext context, MessengerProvider messenger) {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.clearChat),
        content: Text(l10n.clearChatConfirm),
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
              messenger.clearChat(widget.chatId);
              Navigator.of(ctx).pop();
              Navigator.of(context).pop();
            },
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
  }

  void _onTimerChanged(Duration? duration) {
    context.read<MessengerProvider>().setChatSelfDestruct(
          widget.chatId,
          duration,
        );
  }

  void _showRenameDialog(BuildContext context, String currentName) {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.renameChat),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            hintText: l10n.chatName,
            prefixIcon: const Icon(Icons.person_outline_rounded, size: 20),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                context
                    .read<MessengerProvider>()
                    .renameChat(widget.chatId, name);
              }
              Navigator.of(ctx).pop();
            },
            child: Text(l10n.save),
          ),
        ],
      ),
    ).then((_) => controller.dispose());
  }

  Future<void> _showSafetyNumber(
      BuildContext context, MessengerProvider messenger, String contactId) async {
    final contact = messenger.contactForId(contactId);
    if (contact == null || messenger.userId == null) return;

    final keyPair = await messenger.getIdentityPublicKey();
    if (keyPair == null) return;

    final safetyNumber = await SafetyNumber.generate(
      localUserId: messenger.userId!,
      localIdentityPublic: keyPair,
      remoteUserId: contact.id,
      remoteIdentityPublic: contact.publicKey,
    );

    final formatted = SafetyNumber.formatForDisplay(safetyNumber);

    if (!context.mounted) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.shield_rounded, size: 20),
            const SizedBox(width: 8),
            Text('Safety Number',
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    )),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: QrImageView(
                data: safetyNumber,
                size: 180,
              ),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () {
                // M2-Client: ephemeral copy with auto-clear (60s).
                ClipboardHelper.copyEphemeral(safetyNumber);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Safety number copied')),
                );
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.surfaceElevatedDark
                      : AppColors.backgroundLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  formatted,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.5,
                    height: 1.6,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Compare this number with your contact. If they match, your conversation is secure.',
              textAlign: TextAlign.center,
              style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight,
                  ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
          if (!contact.isVerified)
            ElevatedButton.icon(
              onPressed: () async {
                final ok = await messenger.markContactVerified(
                  contactId,
                  method: VerificationMethod.safetyNumber,
                  verifiedPublicKey: contact.publicKey,
                );
                if (ctx.mounted) {
                  if (ok) {
                    Navigator.of(ctx).pop();
                  } else {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(
                        content: Text('Verifikation fehlgeschlagen — Schlüssel stimmen nicht überein'),
                        backgroundColor: AppColors.destructive,
                      ),
                    );
                  }
                }
              },
              icon: const Icon(Icons.verified_rounded, size: 16),
              label: const Text('Mark Verified'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
              ),
            ),
        ],
      ),
    );
  }

  String _durationLabel(Duration? d) {
    if (d == null) return 'Off';
    if (d.inSeconds <= 30) return '30s';
    if (d.inMinutes <= 5) return '5 min';
    if (d.inHours <= 1) return '1 hour';
    if (d.inDays <= 1) return '1 day';
    return '1 week';
  }
}
