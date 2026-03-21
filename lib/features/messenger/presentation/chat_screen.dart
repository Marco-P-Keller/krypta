import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/emergency_button.dart';
import '../data/models/chat_model.dart';
import '../logic/messenger_provider.dart';
import 'widgets/chat_settings_sheet.dart';
import 'widgets/message_bubble.dart';

class ChatScreen extends StatefulWidget {
  final Chat chat;
  final VoidCallback onEmergencyWipe;
  final VoidCallback onBack;

  const ChatScreen({
    super.key,
    required this.chat,
    required this.onEmergencyWipe,
    required this.onBack,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  Duration? _perMessageTimer;
  bool _hasPerMessageOverride = false;
  bool _burnAfterRead = false;
  String? _messagePassword;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final messenger = context.read<MessengerProvider>();
    messenger.setActiveChat(widget.chat.id);
    _markVisibleMessagesAsRead(messenger);
  }

  @override
  void dispose() {
    final messenger = context.read<MessengerProvider>();
    messenger.setActiveChat(null);
    messenger.stopLocalTyping(widget.chat.recipientId);
    messenger.burnReadMessages(widget.chat.id);
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Duration? get _effectiveTimer {
    if (_burnAfterRead) return null;
    if (_hasPerMessageOverride) return _perMessageTimer;
    final chat = context.read<MessengerProvider>().chatById(widget.chat.id);
    return chat?.defaultSelfDestruct;
  }

  void _markVisibleMessagesAsRead(MessengerProvider messenger) {
    final messages = messenger.messagesForChat(widget.chat.id);
    for (final msg in messages) {
      if (msg.senderId != messenger.userId && msg.readAt == null) {
        messenger.markAsRead(widget.chat.id, msg.id);
      }
    }
  }

  void _sendMessage() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final messenger = context.read<MessengerProvider>();
    messenger.sendMessage(
      chatId: widget.chat.id,
      text: text,
      selfDestruct: _effectiveTimer,
      burnAfterRead: _burnAfterRead,
      password: _messagePassword,
    );
    messenger.stopLocalTyping(widget.chat.recipientId);
    _controller.clear();
    setState(() => _messagePassword = null);
    _scrollToBottom();
  }

  void _onTextChanged(String text) {
    if (text.isNotEmpty) {
      context.read<MessengerProvider>().onLocalTyping(widget.chat.recipientId);
    }
  }

  void _showPasswordSetDialog() {
    if (_messagePassword != null) {
      setState(() => _messagePassword = null);
      return;
    }

    final pwController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.lock_rounded, color: AppColors.warning, size: 22),
            SizedBox(width: 10),
            Text('Lock Message'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Set a password for the next message. '
              'The recipient must enter this password to read it.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: pwController,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Enter password',
                prefixIcon: Icon(Icons.key_rounded, size: 20),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final pw = pwController.text.trim();
              if (pw.isNotEmpty) {
                setState(() => _messagePassword = pw);
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('Set Password'),
          ),
        ],
      ),
    );
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
      appBar: _buildAppBar(context, l10n),
      body: Column(
        children: [
          Expanded(child: _buildMessageList(context, l10n)),
          _buildStatusBars(context, l10n, isDark),
          _buildMessageInput(context, l10n, isDark),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, AppLocalizations l10n) {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded),
        onPressed: widget.onBack,
      ),
      title: Consumer<MessengerProvider>(
        builder: (context, messenger, _) {
          final chat = messenger.chatById(widget.chat.id);
          final name = chat?.recipientName ?? widget.chat.recipientName;
          final isTyping = messenger.isTyping(widget.chat.recipientId);
          final hasTimer = chat?.defaultSelfDestruct != null;
          return GestureDetector(
            onTap: () => ChatSettingsSheet.show(context, widget.chat.id),
            child: Column(
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(child: Text(name, overflow: TextOverflow.ellipsis)),
                    if (hasTimer) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.timer_outlined,
                          size: 14, color: AppColors.primary),
                    ],
                  ],
                ),
                if (isTyping)
                  Text(
                    l10n.typing,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.primary,
                        ),
                  ),
              ],
            ),
          );
        },
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.settings_outlined, size: 22),
          onPressed: () => ChatSettingsSheet.show(context, widget.chat.id),
        ),
        EmergencyButton(onWipe: widget.onEmergencyWipe),
      ],
    );
  }

  Widget _buildMessageList(BuildContext context, AppLocalizations l10n) {
    return Consumer<MessengerProvider>(
      builder: (context, messenger, _) {
        final messages = messenger.messagesForChat(widget.chat.id);

        for (final msg in messages) {
          if (msg.senderId != messenger.userId && msg.readAt == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              messenger.markAsRead(widget.chat.id, msg.id);
            });
          }
        }

        if (messages.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline, size: 32, color: AppColors.primary),
                  const SizedBox(height: 12),
                  Text(
                    l10n.encryptionInfo,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.primary,
                        ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: messages.length,
          itemBuilder: (context, index) {
            final msg = messages[index];
            return MessageBubble(
              message: msg,
              isMine: msg.senderId == messenger.userId,
            );
          },
        );
      },
    );
  }

  Widget _buildStatusBars(BuildContext context, AppLocalizations l10n, bool isDark) {
    final bars = <Widget>[];
    final messenger = context.watch<MessengerProvider>();
    final chat = messenger.chatById(widget.chat.id);
    final chatDefault = chat?.defaultSelfDestruct;

    final showTimer = _hasPerMessageOverride
        ? _perMessageTimer != null
        : chatDefault != null;
    final timerDuration = _hasPerMessageOverride ? _perMessageTimer : chatDefault;

    if (showTimer || _burnAfterRead) {
      final String label;
      if (_burnAfterRead) {
        label = 'Burn after read';
      } else if (!_hasPerMessageOverride && chatDefault != null) {
        label = '${_durationLabel(chatDefault)} (chat default)';
      } else {
        label = _durationLabelFor(timerDuration);
      }

      bars.add(_buildInfoBar(
        context,
        icon: Icons.timer_outlined,
        text: label,
        onClear: () => setState(() {
          _perMessageTimer = null;
          _hasPerMessageOverride = false;
          _burnAfterRead = false;
        }),
        isDark: isDark,
      ));
    }

    if (_messagePassword != null) {
      bars.add(_buildInfoBar(
        context,
        icon: Icons.lock_rounded,
        text: 'Password protected',
        color: AppColors.warning,
        onClear: () => setState(() => _messagePassword = null),
        isDark: isDark,
      ));
    }

    if (bars.isEmpty) return const SizedBox.shrink();
    return Column(mainAxisSize: MainAxisSize.min, children: bars);
  }

  Widget _buildInfoBar(
    BuildContext context, {
    required IconData icon,
    required String text,
    Color color = AppColors.primary,
    required VoidCallback onClear,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: isDark ? AppColors.surfaceElevatedDark : AppColors.surfaceElevatedLight,
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
          GestureDetector(
            onTap: onClear,
            child: const Icon(Icons.close, size: 16, color: AppColors.textTertiaryDark),
          ),
        ],
      ),
    );
  }

  String _durationLabelFor(Duration? d) {
    if (d == null) return 'Off';
    if (d.inSeconds <= 30) return '30s';
    if (d.inMinutes <= 5) return '5 min';
    if (d.inHours <= 1) return '1h';
    if (d.inDays <= 1) return '1 day';
    return '1 week';
  }

  String _durationLabel(Duration? d) {
    if (d == null) return 'Off';
    if (d.inSeconds <= 30) return '30s';
    if (d.inMinutes <= 5) return '5 min';
    if (d.inHours <= 1) return '1h';
    if (d.inDays <= 1) return '1 day';
    return '1 week';
  }

  Widget _buildMessageInput(BuildContext context, AppLocalizations l10n, bool isDark) {
    return Container(
      padding: EdgeInsets.only(
        left: 8,
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
          IconButton(
            icon: Icon(
              _messagePassword != null
                  ? Icons.lock_rounded
                  : Icons.lock_open_rounded,
              color: _messagePassword != null ? AppColors.warning : null,
              size: 22,
            ),
            onPressed: _showPasswordSetDialog,
          ),
          PopupMenuButton<String>(
            icon: Icon(
              _perMessageTimer != null || _burnAfterRead
                  ? Icons.timer
                  : Icons.timer_outlined,
              color: _perMessageTimer != null || _burnAfterRead
                  ? AppColors.primary
                  : null,
              size: 22,
            ),
            onSelected: (value) {
              setState(() {
                _hasPerMessageOverride = true;
                if (value == 'burn') {
                  _burnAfterRead = true;
                  _perMessageTimer = null;
                } else if (value == 'off') {
                  _burnAfterRead = false;
                  _perMessageTimer = null;
                } else if (value == 'default') {
                  _hasPerMessageOverride = false;
                  _burnAfterRead = false;
                  _perMessageTimer = null;
                } else {
                  _burnAfterRead = false;
                  _perMessageTimer = Duration(seconds: int.parse(value));
                }
              });
            },
            itemBuilder: (context) {
              final chat = context
                  .read<MessengerProvider>()
                  .chatById(widget.chat.id);
              final hasDefault = chat?.defaultSelfDestruct != null;
              return [
                if (hasDefault)
                  PopupMenuItem(
                    value: 'default',
                    child: Text('Chat default (${_durationLabel(chat!.defaultSelfDestruct)})'),
                  ),
                PopupMenuItem(value: 'off', child: Text(l10n.off)),
                PopupMenuItem(value: '30', child: Text(l10n.seconds30)),
                PopupMenuItem(value: '300', child: Text(l10n.minutes5)),
                PopupMenuItem(value: '3600', child: Text(l10n.hour1)),
                PopupMenuItem(value: '86400', child: Text(l10n.day1)),
                PopupMenuItem(value: '604800', child: Text(l10n.week1)),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'burn',
                  child: Row(
                    children: [
                      Icon(Icons.local_fire_department,
                          color: AppColors.destructive, size: 18),
                      SizedBox(width: 8),
                      Text('Burn after read'),
                    ],
                  ),
                ),
              ];
            },
          ),
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
                focusNode: _focusNode,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 4,
                minLines: 1,
                onChanged: _onTextChanged,
                decoration: InputDecoration(
                  hintText: l10n.typeMessage,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
                onSubmitted: (_) => _sendMessage(),
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
              onPressed: _sendMessage,
              iconSize: 22,
            ),
          ),
        ],
      ),
    );
  }
}
