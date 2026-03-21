import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../theme/app_colors.dart';
import '../../logic/messenger_provider.dart';

/// Bottom sheet for per-chat settings: rename + default self-destruct timer.
class ChatSettingsSheet extends StatefulWidget {
  final String chatId;

  const ChatSettingsSheet({super.key, required this.chatId});

  static void show(BuildContext context, String chatId) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
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

class _ChatSettingsSheetState extends State<ChatSettingsSheet> {
  static const _timerOptions = <Duration?>[
    null,
    Duration(seconds: 30),
    Duration(minutes: 5),
    Duration(hours: 1),
    Duration(days: 1),
    Duration(days: 7),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final messenger = context.watch<MessengerProvider>();
    final chat = messenger.chatById(widget.chatId);
    if (chat == null) return const SizedBox.shrink();

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
          // Handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          // Chat name header
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                child: Text(
                  chat.recipientName.isNotEmpty
                      ? chat.recipientName[0].toUpperCase()
                      : '?',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
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
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      chat.recipientId.length > 16
                          ? '${chat.recipientId.substring(0, 16)}...'
                          : chat.recipientId,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                            color: isDark
                                ? AppColors.textTertiaryDark
                                : AppColors.textTertiaryLight,
                          ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit_rounded, size: 20),
                color: AppColors.primary,
                onPressed: () => _showRenameDialog(context, chat.recipientName),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Self-destruct timer section
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'AUTO-DELETE TIMER',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: isDark
                        ? AppColors.textTertiaryDark
                        : AppColors.textTertiaryLight,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.0,
                  ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'New messages in this chat will automatically self-destruct after the selected time.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight,
                ),
          ),
          const SizedBox(height: 16),

          // Timer chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _timerOptions.map((duration) {
              final isSelected = chat.defaultSelfDestruct == duration;
              return ChoiceChip(
                label: Text(_durationLabel(duration)),
                selected: isSelected,
                onSelected: (_) => _onTimerChanged(duration),
                selectedColor: AppColors.primary,
                labelStyle: TextStyle(
                  color: isSelected ? Colors.white : null,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                side: isSelected
                    ? BorderSide.none
                    : BorderSide(
                        color: isDark
                            ? AppColors.dividerDark
                            : AppColors.dividerLight,
                      ),
              );
            }).toList(),
          ),

          // Current status indicator
          if (chat.defaultSelfDestruct != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.timer_outlined,
                      size: 18, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Messages auto-delete after ${_durationLabel(chat.defaultSelfDestruct)}',
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
          const SizedBox(height: 8),
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
    final controller = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Chat'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            hintText: 'Chat name',
            prefixIcon: Icon(Icons.person_outline, size: 20),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
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
            child: const Text('Save'),
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
