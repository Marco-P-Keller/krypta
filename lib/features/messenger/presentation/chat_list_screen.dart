import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/platform/clipboard_helper.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../../widgets/emergency_button.dart';
import '../data/models/chat_model.dart';
import '../logic/frist_stufe.dart';
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: onBack,
        ),
        title: Text(
          l10n.chats,
          style: Theme.of(context).textTheme.headlineLarge,
          // Zwischen Zurueck-Pfeil und zwei Symbolen ist in dieser Schriftgroesse
          // kaum Platz. Deshalb heisst der Titel in allen Sprachen „Chats" —
          // und falls doch einmal etwas Laengeres hier landet, wird es
          // abgeschnitten statt ueber den Rand zu laufen.
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_rounded, size: 22),
            onPressed: () async {
              final messenger = context.read<MessengerProvider>();
              final uid = messenger.userId;
              if (uid != null) {
                final pubKey = await messenger.getIdentityPublicKey();
                if (pubKey != null && context.mounted) {
                  QrDisplaySheet.show(
                    context,
                    userId: uid,
                    publicKey: pubKey,
                  );
                }
              }
            },
          ),
          EmergencyButton(onWipe: onEmergencyWipe),
          IconButton(
            icon: const Icon(Icons.settings_outlined, size: 22),
            onPressed: onSettingsTap,
          ),
          IconButton(
            icon: const Icon(Icons.edit_rounded, size: 22),
            color: AppColors.accent,
            onPressed: onNewChat,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Consumer<MessengerProvider>(
        builder: (context, messenger, _) {
          if (messenger.chats.isEmpty) {
            return _buildEmptyState(context, l10n, isDark, messenger);
          }
          return _buildChatList(context, messenger, isDark);
        },
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, AppLocalizations l10n,
      bool isDark, MessengerProvider messenger) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.shield_rounded,
                  size: 36, color: AppColors.accent),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              l10n.noChats,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimaryLight,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              l10n.noChatsSubtitle,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight,
                    height: 1.6,
                  ),
              textAlign: TextAlign.center,
            ),
            if (messenger.userId != null) ...[
              const SizedBox(height: AppSpacing.xl),
              GestureDetector(
                onTap: () {
                  // M2-Client: ephemeral copy with auto-clear.
                  ClipboardHelper.copyEphemeral(messenger.userId!);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.userIdCopied)),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md, vertical: AppSpacing.sm + 4),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.surfaceElevatedDark
                        : AppColors.surfaceElevatedLight,
                    borderRadius:
                        BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.copy_rounded,
                          size: 14, color: AppColors.accent),
                      const SizedBox(width: 8),
                      Text(
                        '${l10n.userIdLabel}: ${messenger.userId!.substring(0, 12)}…',
                        style:
                            Theme.of(context).textTheme.bodySmall?.copyWith(
                                  fontFamily: 'monospace',
                                  letterSpacing: 0.5,
                                  color: isDark
                                      ? AppColors.textSecondaryDark
                                      : AppColors.textSecondaryLight,
                                ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildChatList(
      BuildContext context, MessengerProvider messenger, bool isDark) {
    return ListView.separated(
      padding: const EdgeInsets.only(top: 4, bottom: 120),
      itemCount: messenger.chats.length,
      separatorBuilder: (context, index) => Divider(
        height: 0.5,
        thickness: 0.33,
        indent: 88,
        endIndent: 0,
        color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
      ),
      itemBuilder: (context, index) {
        final chat = messenger.chats[index];
        return Dismissible(
          key: ValueKey(chat.id),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: AppSpacing.lg),
            color: AppColors.destructive,
            child: const Icon(Icons.delete_outline_rounded,
                color: Colors.white, size: 24),
          ),
          onDismissed: (_) => messenger.deleteChat(chat.id),
          child: ChatTile(
            chat: chat,
            onTap: () => onChatTap(chat),
            onLongPress: () =>
                _showChatContextMenu(context, chat, messenger),
            requestState:
                messenger.contactForId(chat.recipientId)?.requestState,
            requestLabel: AppLocalizations.of(context)!.requestBadge,
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
              leading: const Icon(Icons.edit_rounded),
              title: Text(l10n.renameChat),
              onTap: () {
                Navigator.of(ctx).pop();
                _showRenameDialog(context, chat, messenger);
              },
            ),
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: Text(l10n.selfDestructTimerLabel),
              subtitle: Text(_regelLabel(l10n,
                  frist: chat.defaultSelfDestruct,
                  nachLesen: chat.loeschtNachLesen)),
              onTap: () {
                Navigator.of(ctx).pop();
                _showTimerPicker(context, chat, messenger);
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded,
                  color: AppColors.destructive),
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
        // Sonst legt sich der Inhalt bei offener Tastatur und grosser
        // Systemschrift ueber die Knopfzeile, statt zu scrollen.
        scrollable: true,
        title: Text(l10n.renameChat),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(hintText: l10n.chatName),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) messenger.renameChat(chat.id, name);
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
    // Dieselben Zeiten wie im Chat-Einstellungsblatt. Bewusst gröber als die
    // Auswahl an einer einzelnen Nachricht: 30 Sekunden auf einen ganzen Chat
    // anzuwenden wäre kein Sicherheitsgewinn, sondern ein unbenutzbarer Chat.
    const options = <({Duration? frist, bool nachLesen})>[
      (frist: null, nachLesen: false),
      (frist: null, nachLesen: true),
      (frist: Duration(minutes: 5), nachLesen: false),
      (frist: Duration(minutes: 30), nachLesen: false),
      (frist: Duration(hours: 1), nachLesen: false),
      (frist: Duration(hours: 24), nachLesen: false),
      (frist: Duration(days: 7), nachLesen: false),
    ];
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(l10n.autoDeleteTimer),
        children: options.map((option) {
          final isSelected = option.nachLesen
              ? chat.loeschtNachLesen
              : (!chat.loeschtNachLesen &&
                  chat.defaultSelfDestruct == option.frist);
          return SimpleDialogOption(
            onPressed: () {
              messenger.setChatSelfDestruct(chat.id, option.frist,
                  nachLesen: option.nachLesen);
              Navigator.of(ctx).pop();
            },
            child: Row(
              children: [
                Icon(
                  isSelected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 20,
                  color: isSelected
                      ? AppColors.accent
                      : AppColors.textTertiaryDark,
                ),
                const SizedBox(width: 12),
                Text(
                  _regelLabel(AppLocalizations.of(context)!,
                      frist: option.frist, nachLesen: option.nachLesen),
                  style: TextStyle(
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected ? AppColors.accent : null,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  /// Beschriftung einer Selbstzerstörungs-Zeit, übersetzt.
  ///
  /// Stand hier zuvor in englischem Klartext — und kannte die neuen Zeiten
  /// nicht, die für den ganzen Chat wählbar sind.
  /// Die dritte Kopie dieser Zuordnung stand hier von Hand ausgeschrieben —
  /// und lief damit genau so auseinander, wie es der Kommentar oben
  /// befuerchtet. Jetzt entscheidet FristLabel, hier wird nur uebersetzt.
  String _regelLabel(AppLocalizations l10n,
          {Duration? frist, bool nachLesen = false}) =>
      switch (FristLabel.stufeFuerRegel(frist: frist, nachLesen: nachLesen)) {
        FristStufe.aus => l10n.off,
        FristStufe.sekunden30 => l10n.seconds30,
        FristStufe.minuten5 => l10n.minutes5,
        FristStufe.minuten30 => l10n.minutes30,
        FristStufe.stunde1 => l10n.hour1,
        FristStufe.tag1 => l10n.day1,
        FristStufe.woche1 => l10n.week1,
        FristStufe.nachLesen => l10n.autoDeleteAfterRead,
      };
}
