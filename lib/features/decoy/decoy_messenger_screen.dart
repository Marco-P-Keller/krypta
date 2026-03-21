import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_colors.dart';
import '../messenger/data/models/chat_model.dart';
import '../messenger/presentation/widgets/chat_tile.dart';
import '../messenger/presentation/widgets/message_bubble.dart';
import 'decoy_data.dart';

/// Fake messenger shown when decoy code is entered.
/// Displays harmless dummy conversations. Read-only.
class DecoyMessengerScreen extends StatefulWidget {
  final VoidCallback onBack;

  const DecoyMessengerScreen({super.key, required this.onBack});

  @override
  State<DecoyMessengerScreen> createState() => _DecoyMessengerScreenState();
}

class _DecoyMessengerScreenState extends State<DecoyMessengerScreen> {
  Chat? _selectedChat;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (_selectedChat != null) {
      return _buildDecoyChat(context, l10n);
    }
    return _buildDecoyList(context, l10n);
  }

  Widget _buildDecoyList(BuildContext context, AppLocalizations l10n) {
    final chats = DecoyData.chats;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.decoyTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: widget.onBack,
        ),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: chats.length,
        separatorBuilder: (context, index) => const Divider(indent: 72, height: 1),
        itemBuilder: (context, index) {
          return ChatTile(
            chat: chats[index],
            onTap: () => setState(() => _selectedChat = chats[index]),
          );
        },
      ),
    );
  }

  Widget _buildDecoyChat(BuildContext context, AppLocalizations l10n) {
    final messages = DecoyData.messagesForChat(_selectedChat!.id);

    return Scaffold(
      appBar: AppBar(
        title: Text(_selectedChat!.recipientName),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => setState(() => _selectedChat = null),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final msg = messages[index];
                return MessageBubble(
                  message: msg,
                  isMine: msg.senderId == 'self',
                );
              },
            ),
          ),
          Container(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 12,
              bottom: MediaQuery.of(context).padding.bottom + 12,
            ),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? AppColors.surfaceDark
                  : AppColors.surfaceLight,
              border: Border(
                top: BorderSide(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? AppColors.dividerDark
                      : AppColors.dividerLight,
                  width: 0.5,
                ),
              ),
            ),
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? AppColors.surfaceElevatedDark
                    : AppColors.surfaceElevatedLight,
                borderRadius: BorderRadius.circular(22),
              ),
              child: TextField(
                readOnly: true,
                decoration: InputDecoration(
                  hintText: l10n.typeMessage,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
