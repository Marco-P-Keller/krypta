import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_colors.dart';
import '../messenger/data/models/chat_model.dart';
import '../messenger/presentation/widgets/chat_tile.dart';
import '../messenger/presentation/widgets/message_bubble.dart';
import 'decoy_provider.dart';

/// Fake messenger shown when decoy code is entered.
/// Fully interactive: create chats, send messages, delete chats.
/// All data is local-only and stored separately from real chats.
class DecoyMessengerScreen extends StatefulWidget {
  final VoidCallback onBack;

  const DecoyMessengerScreen({super.key, required this.onBack});

  @override
  State<DecoyMessengerScreen> createState() => _DecoyMessengerScreenState();
}

class _DecoyMessengerScreenState extends State<DecoyMessengerScreen> {
  Chat? _selectedChat;

  @override
  void initState() {
    super.initState();
    context.read<DecoyProvider>().initialize();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (_selectedChat != null) {
      return _DecoyChatView(
        chatId: _selectedChat!.id,
        onBack: () => setState(() => _selectedChat = null),
      );
    }
    return _buildChatList(context, l10n);
  }

  Widget _buildChatList(BuildContext context, AppLocalizations l10n) {
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.decoyTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: widget.onBack,
        ),
      ),
      body: Consumer<DecoyProvider>(
        builder: (context, decoy, _) {
          if (decoy.chats.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.chat_bubble_outline_rounded,
                        size: 56,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? AppColors.textTertiaryDark
                            : AppColors.textTertiaryLight),
                    const SizedBox(height: 16),
                    Text(
                      l10n.noChats,
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.noChatsSubtitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).brightness == Brightness.dark
                                ? AppColors.textSecondaryDark
                                : AppColors.textSecondaryLight,
                          ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: decoy.chats.length,
            separatorBuilder: (context, index) =>
                const Divider(indent: 72, height: 1),
            itemBuilder: (context, index) {
              final chat = decoy.chats[index];
              return Dismissible(
                key: ValueKey(chat.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  color: AppColors.destructive,
                  child: const Icon(Icons.delete_outline, color: Colors.white),
                ),
                onDismissed: (_) => decoy.deleteChat(chat.id),
                child: ChatTile(
                  chat: chat,
                  onTap: () => setState(() => _selectedChat = chat),
                  onLongPress: () =>
                      _showChatOptions(context, chat, decoy),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showNewChatDialog(context),
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.edit_outlined, color: Colors.white),
      ),
    );
  }

  void _showNewChatDialog(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.newChat),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            hintText: l10n.chatName,
            prefixIcon: const Icon(Icons.person_outline, size: 20),
          ),
          onSubmitted: (val) {
            final name = val.trim();
            if (name.isNotEmpty) {
              final chat = context.read<DecoyProvider>().createChat(name);
              Navigator.of(ctx).pop();
              setState(() => _selectedChat = chat);
            }
          },
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
                final chat = context.read<DecoyProvider>().createChat(name);
                Navigator.of(ctx).pop();
                setState(() => _selectedChat = chat);
              }
            },
            child: Text(l10n.save),
          ),
        ],
      ),
    );
  }

  void _showChatOptions(
      BuildContext context, Chat chat, DecoyProvider decoy) {
    final l10n = AppLocalizations.of(context)!;
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
              title: Text(l10n.renameChat),
              onTap: () {
                Navigator.of(ctx).pop();
                _showRenameDialog(context, chat, decoy);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline,
                  color: AppColors.destructive),
              title: Text(l10n.deleteChat,
                  style: const TextStyle(color: AppColors.destructive)),
              onTap: () {
                Navigator.of(ctx).pop();
                decoy.deleteChat(chat.id);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showRenameDialog(
      BuildContext context, Chat chat, DecoyProvider decoy) {
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
            prefixIcon: const Icon(Icons.person_outline, size: 20),
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
                decoy.renameChat(chat.id, name);
              }
              Navigator.of(ctx).pop();
            },
            child: Text(l10n.save),
          ),
        ],
      ),
    );
  }
}

/// Individual chat view for the decoy messenger.
class _DecoyChatView extends StatefulWidget {
  final String chatId;
  final VoidCallback onBack;

  const _DecoyChatView({
    required this.chatId,
    required this.onBack,
  });

  @override
  State<_DecoyChatView> createState() => _DecoyChatViewState();
}

class _DecoyChatViewState extends State<_DecoyChatView> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    context.read<DecoyProvider>().sendMessage(
          chatId: widget.chatId,
          text: text,
        );
    _controller.clear();
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: widget.onBack,
        ),
        title: Consumer<DecoyProvider>(
          builder: (context, decoy, _) {
            final chat = decoy.chatById(widget.chatId);
            return Text(chat?.recipientName ?? '');
          },
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Consumer<DecoyProvider>(
              builder: (context, decoy, _) {
                final messages = decoy.messagesForChat(widget.chatId);

                if (messages.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        l10n.noChatsSubtitle,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: isDark
                                  ? AppColors.textTertiaryDark
                                  : AppColors.textTertiaryLight,
                            ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                WidgetsBinding.instance
                    .addPostFrameCallback((_) => _scrollToBottom());

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    return GestureDetector(
                      onLongPress: () => _confirmDeleteMessage(
                          context, msg.id, decoy),
                      child: MessageBubble(
                        message: msg,
                        isMine: decoy.isMine(msg),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          _buildInput(context, l10n, isDark),
        ],
      ),
    );
  }

  void _confirmDeleteMessage(
      BuildContext context, String messageId, DecoyProvider decoy) {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deleteChat),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.destructive),
            onPressed: () {
              decoy.deleteMessage(widget.chatId, messageId);
              Navigator.of(ctx).pop();
            },
            child: Text(l10n.deleteChat),
          ),
        ],
      ),
    );
  }

  Widget _buildInput(BuildContext context, AppLocalizations l10n, bool isDark) {
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 8,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        border: Border(
          top: BorderSide(
            color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.surfaceElevatedDark
                    : AppColors.surfaceElevatedLight,
                borderRadius: BorderRadius.circular(22),
              ),
              child: TextField(
                controller: _controller,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 4,
                minLines: 1,
                decoration: InputDecoration(
                  hintText: l10n.typeMessage,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: const Icon(Icons.arrow_upward_rounded, color: Colors.white),
              onPressed: _send,
              iconSize: 22,
            ),
          ),
        ],
      ),
    );
  }
}
