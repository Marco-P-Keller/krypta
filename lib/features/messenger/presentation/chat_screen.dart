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
    // Clear sensitive state from memory immediately on screen exit.
    _messagePassword = null;
    _controller.clear();
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
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.lock_rounded, color: AppColors.warning, size: 22),
            const SizedBox(width: 10),
            Text(l10n.lockMessage),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.lockMessageHint),
            const SizedBox(height: 16),
            TextField(
              controller: pwController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: l10n.enterPassword,
                prefixIcon: const Icon(Icons.key_rounded, size: 20),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () {
              final pw = pwController.text.trim();
              if (pw.isNotEmpty) {
                setState(() => _messagePassword = pw);
              }
              Navigator.of(ctx).pop();
            },
            child: Text(l10n.setPassword),
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
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
        onPressed: widget.onBack,
      ),
      titleSpacing: 0,
      title: Consumer<MessengerProvider>(
        builder: (context, messenger, _) {
          final chat = messenger.chatById(widget.chat.id);
          final name = chat?.recipientName ?? widget.chat.recipientName;
          final isTyping = messenger.isTyping(widget.chat.recipientId);
          final colors = _avatarGradient(name);

          return GestureDetector(
            onTap: () => ChatSettingsSheet.show(context, widget.chat.id),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: colors,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      if (isTyping)
                        Text(
                          l10n.typing,
                          style: const TextStyle(
                            color: AppColors.accent,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.tune_rounded, size: 20),
          onPressed: () => ChatSettingsSheet.show(context, widget.chat.id),
        ),
        EmergencyButton(onWipe: widget.onEmergencyWipe),
      ],
    );
  }

  static const _chatAvatarGradients = [
    [Color(0xFF5B7FFF), Color(0xFF7C5CFC)],
    [Color(0xFF00C9A7), Color(0xFF00B4D8)],
    [Color(0xFFFF6B6B), Color(0xFFFF8E72)],
    [Color(0xFFFFC75F), Color(0xFFFF9671)],
    [Color(0xFFE04DE8), Color(0xFF7C5CFC)],
    [Color(0xFF43E97B), Color(0xFF38F9D7)],
  ];

  List<Color> _avatarGradient(String name) {
    final idx = name.isEmpty ? 0 : name.codeUnitAt(0) % _chatAvatarGradients.length;
    return _chatAvatarGradients[idx];
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
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.primary.withValues(alpha: 0.08),
                          AppColors.accent.withValues(alpha: 0.08),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(Icons.shield_rounded,
                        size: 32, color: AppColors.primary),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.encryptionInfo,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: isDark
                              ? AppColors.textSecondaryDark
                              : AppColors.textSecondaryLight,
                          height: 1.5,
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
        label = l10n.burnAfterRead;
      } else if (!_hasPerMessageOverride && chatDefault != null) {
        label = l10n.chatDefaultWithTimer(_durationLabel(chatDefault));
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
        text: l10n.passwordProtected,
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
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withValues(alpha: 0.15),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                  ),
            ),
          ),
          GestureDetector(
            onTap: onClear,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.close_rounded, size: 14, color: color),
            ),
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
    final dimColor = isDark
        ? AppColors.textTertiaryDark
        : AppColors.textTertiaryLight;

    return Container(
      padding: EdgeInsets.only(
        left: 8,
        right: 8,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
        border: Border(
          top: BorderSide(
            color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
            width: 0.33,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Lock icon
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: SizedBox(
              width: 36,
              height: 36,
              child: IconButton(
                icon: Icon(
                  _messagePassword != null
                      ? Icons.lock_rounded
                      : Icons.lock_outline_rounded,
                  color: _messagePassword != null ? AppColors.warning : dimColor,
                  size: 22,
                ),
                onPressed: _showPasswordSetDialog,
                padding: EdgeInsets.zero,
              ),
            ),
          ),
          // Timer icon
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: SizedBox(
              width: 36,
              height: 36,
              child: PopupMenuButton<String>(
                icon: Icon(
                  _perMessageTimer != null || _burnAfterRead
                      ? Icons.timer_rounded
                      : Icons.timer_outlined,
                  color: _perMessageTimer != null || _burnAfterRead
                      ? AppColors.accent
                      : dimColor,
                  size: 22,
                ),
                padding: EdgeInsets.zero,
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
                        child: Text(l10n.chatDefaultWithTimer(
                            _durationLabel(chat!.defaultSelfDestruct))),
                      ),
                    PopupMenuItem(value: 'off', child: Text(l10n.off)),
                    PopupMenuItem(value: '30', child: Text(l10n.seconds30)),
                    PopupMenuItem(value: '300', child: Text(l10n.minutes5)),
                    PopupMenuItem(value: '3600', child: Text(l10n.hour1)),
                    PopupMenuItem(value: '86400', child: Text(l10n.day1)),
                    PopupMenuItem(value: '604800', child: Text(l10n.week1)),
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'burn',
                      child: Row(
                        children: [
                          const Icon(Icons.local_fire_department_rounded,
                              color: AppColors.destructive, size: 18),
                          const SizedBox(width: 8),
                          Text(l10n.burnAfterRead),
                        ],
                      ),
                    ),
                  ];
                },
              ),
            ),
          ),
          const SizedBox(width: 4),
          // Text field
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 120),
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
                maxLines: 5,
                minLines: 1,
                onChanged: _onTextChanged,
                style: TextStyle(
                  fontSize: 17,
                  color: isDark
                      ? AppColors.textPrimaryDark
                      : AppColors.textPrimaryLight,
                  height: 1.35,
                ),
                decoration: InputDecoration(
                  hintText: l10n.typeMessage,
                  hintStyle: TextStyle(
                    color: isDark
                        ? AppColors.textTertiaryDark
                        : AppColors.textTertiaryLight,
                    fontSize: 17,
                  ),
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
          // Send button — circular, no shadow
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: GestureDetector(
              onTap: _sendMessage,
              child: Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  color: AppColors.accent,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.arrow_upward_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
