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
        title: Text(
          l10n.chats,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
        ),
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: onBack,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_rounded, size: 22),
            tooltip: 'QR Code',
            onPressed: () {
              final uid = context.read<MessengerProvider>().userId;
              if (uid != null) QrDisplaySheet.show(context, uid);
            },
          ),
          EmergencyButton(onWipe: onEmergencyWipe),
          IconButton(
            icon: const Icon(Icons.settings_outlined, size: 22),
            onPressed: onSettingsTap,
          ),
        ],
      ),
      body: Consumer<MessengerProvider>(
        builder: (context, messenger, _) {
          if (messenger.chats.isEmpty) {
            return _buildEmptyState(context, l10n, isDark);
          }
          return _buildChatList(context, messenger, isDark);
        },
      ),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.messageSentStart, AppColors.messageSentEnd],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.35),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: FloatingActionButton(
          onPressed: onNewChat,
          backgroundColor: Colors.transparent,
          elevation: 0,
          hoverElevation: 0,
          focusElevation: 0,
          highlightElevation: 0,
          child: const Icon(Icons.edit_rounded, color: Colors.white, size: 22),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, AppLocalizations l10n, bool isDark) {
    final messenger = context.read<MessengerProvider>();

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primary.withValues(alpha: 0.08),
                    AppColors.accent.withValues(alpha: 0.08),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(28),
              ),
              child: const Icon(
                Icons.shield_rounded,
                size: 52,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 28),
            Text(
              l10n.noChats,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              l10n.noChatsSubtitle,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                    height: 1.5,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_rounded, size: 14, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Text(
                    l10n.encryptionInfo,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            if (messenger.userId != null)
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: messenger.userId!));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(l10n.userIdCopied),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.surfaceElevatedDark : AppColors.surfaceElevatedLight,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isDark
                          ? AppColors.dividerDark.withValues(alpha: 0.5)
                          : AppColors.dividerLight.withValues(alpha: 0.5),
                      width: 0.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.copy_rounded, size: 15, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Text(
                        '${l10n.userIdLabel}: ${messenger.userId!.substring(0, 12)}...',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                              letterSpacing: 0.5,
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

  Widget _buildChatList(BuildContext context, MessengerProvider messenger, bool isDark) {
    return ListView.separated(
      padding: const EdgeInsets.only(top: 4, bottom: 100),
      itemCount: messenger.chats.length,
      separatorBuilder: (context, index) => Padding(
        padding: const EdgeInsets.only(left: 84),
        child: Divider(
          height: 0.5,
          thickness: 0.5,
          color: isDark
              ? AppColors.dividerDark.withValues(alpha: 0.4)
              : AppColors.dividerLight.withValues(alpha: 0.6),
        ),
      ),
      itemBuilder: (context, index) {
        final chat = messenger.chats[index];
        return Dismissible(
          key: ValueKey(chat.id),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFF6B6B), Color(0xFFFF4757)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.delete_outline_rounded, color: Colors.white, size: 24),
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
    final l10n = AppLocalizations.of(context)!;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).padding.bottom + 8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.edit_rounded, color: AppColors.primary, size: 20),
              ),
              title: Text(l10n.renameChat),
              onTap: () {
                Navigator.of(ctx).pop();
                _showRenameDialog(context, chat, messenger);
              },
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.timer_outlined, color: AppColors.primary, size: 20),
              ),
              title: Text(l10n.selfDestructTimerLabel),
              subtitle: chat.defaultSelfDestruct != null
                  ? Text(_durationLabel(chat.defaultSelfDestruct))
                  : Text(l10n.off),
              onTap: () {
                Navigator.of(ctx).pop();
                _showTimerPicker(context, chat, messenger);
              },
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Divider(height: 1),
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.destructive.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.delete_outline_rounded, color: AppColors.destructive, size: 20),
              ),
              title: Text(l10n.deleteChat,
                  style: const TextStyle(color: AppColors.destructive)),
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
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: chat.recipientName);
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
                messenger.renameChat(chat.id, name);
              }
              Navigator.of(ctx).pop();
            },
            child: Text(l10n.save),
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

    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(l10n.autoDeleteTimer),
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
                  const Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 20)
                else
                  Icon(Icons.radio_button_unchecked_rounded, size: 20,
                      color: AppColors.textTertiaryDark.withValues(alpha: 0.5)),
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
