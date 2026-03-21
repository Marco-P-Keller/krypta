import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/emergency_button.dart';
import '../data/models/chat_model.dart';
import '../logic/messenger_provider.dart';
import 'widgets/chat_tile.dart';
import 'widgets/qr_display_sheet.dart';

class ChatListScreen extends StatelessWidget {
  final VoidCallback onSettingsTap;
  final void Function(Chat chat) onChatTap;
  final VoidCallback onNewChat;
  final VoidCallback onEmergencyWipe;
  final VoidCallback onBack;

  const ChatListScreen({
    super.key,
    required this.onSettingsTap,
    required this.onChatTap,
    required this.onNewChat,
    required this.onEmergencyWipe,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.chats),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: onBack,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_rounded),
            tooltip: 'QR Code',
            onPressed: () {
              final uid = context.read<MessengerProvider>().userId;
              if (uid != null) QrDisplaySheet.show(context, uid);
            },
          ),
          EmergencyButton(onWipe: onEmergencyWipe),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: onSettingsTap,
          ),
        ],
      ),
      body: Consumer<MessengerProvider>(
        builder: (context, messenger, _) {
          if (messenger.chats.isEmpty) {
            return _buildEmptyState(context, l10n, isDark);
          }
          return _buildChatList(context, messenger);
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: onNewChat,
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.edit_outlined, color: Colors.white),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, AppLocalizations l10n, bool isDark) {
    final messenger = context.read<MessengerProvider>();

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.lock_outline_rounded,
              size: 64,
              color: isDark ? AppColors.textTertiaryDark : AppColors.textTertiaryLight,
            ),
            const SizedBox(height: 20),
            Text(
              l10n.noChats,
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.noChatsSubtitle,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Text(
              l10n.encryptionInfo,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.primary,
                  ),
            ),
            const SizedBox(height: 32),
            // Show user ID for sharing
            if (messenger.userId != null)
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: messenger.userId!));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.userIdCopied)),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.surfaceElevatedDark : AppColors.surfaceElevatedLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.copy, size: 16, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Text(
                        '${l10n.userIdLabel}: ${messenger.userId!.substring(0, 12)}...',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                            ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatList(BuildContext context, MessengerProvider messenger) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: messenger.chats.length,
      separatorBuilder: (context, index) => const Divider(indent: 72, height: 1),
      itemBuilder: (context, index) {
        final chat = messenger.chats[index];
        return Dismissible(
          key: ValueKey(chat.id),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            color: AppColors.destructive,
            child: const Icon(Icons.delete_outline, color: Colors.white),
          ),
          onDismissed: (_) => messenger.deleteChat(chat.id),
          child: ChatTile(
            chat: chat,
            onTap: () => onChatTap(chat),
            onLongPress: () => _showChatContextMenu(context, chat, messenger),
          ),
        );
      },
    );
  }

  void _showChatContextMenu(
      BuildContext context, Chat chat, MessengerProvider messenger) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.only(
          top: 12,
          bottom: MediaQuery.of(ctx).padding.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.edit_rounded),
              title: const Text('Rename Chat'),
              onTap: () {
                Navigator.of(ctx).pop();
                _showRenameDialog(context, chat, messenger);
              },
            ),
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: const Text('Self-Destruct Timer'),
              subtitle: chat.defaultSelfDestruct != null
                  ? Text(_durationLabel(chat.defaultSelfDestruct))
                  : const Text('Off'),
              onTap: () {
                Navigator.of(ctx).pop();
                _showTimerPicker(context, chat, messenger);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.destructive),
              title: const Text('Delete Chat',
                  style: TextStyle(color: AppColors.destructive)),
              onTap: () {
                Navigator.of(ctx).pop();
                messenger.deleteChat(chat.id);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showRenameDialog(
      BuildContext context, Chat chat, MessengerProvider messenger) {
    final controller = TextEditingController(text: chat.recipientName);
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
                messenger.renameChat(chat.id, name);
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showTimerPicker(
      BuildContext context, Chat chat, MessengerProvider messenger) {
    final options = <Duration?>[
      null,
      const Duration(seconds: 30),
      const Duration(minutes: 5),
      const Duration(hours: 1),
      const Duration(days: 1),
      const Duration(days: 7),
    ];

    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Auto-Delete Timer'),
        children: options.map((d) {
          final isSelected = chat.defaultSelfDestruct == d;
          return SimpleDialogOption(
            onPressed: () {
              messenger.setChatSelfDestruct(chat.id, d);
              Navigator.of(ctx).pop();
            },
            child: Row(
              children: [
                if (isSelected)
                  const Icon(Icons.check_circle, color: AppColors.primary, size: 20)
                else
                  const Icon(Icons.radio_button_unchecked, size: 20),
                const SizedBox(width: 12),
                Text(
                  _durationLabel(d),
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected ? AppColors.primary : null,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  String _durationLabel(Duration? d) {
    if (d == null) return 'Off';
    if (d.inSeconds <= 30) return '30 seconds';
    if (d.inMinutes <= 5) return '5 minutes';
    if (d.inHours <= 1) return '1 hour';
    if (d.inDays <= 1) return '1 day';
    return '1 week';
  }
}
