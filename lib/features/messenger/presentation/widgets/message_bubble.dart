import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../theme/app_colors.dart';
import '../../../../theme/app_spacing.dart';
import '../../data/models/message_model.dart';
import '../../logic/messenger_provider.dart';

class MessageBubble extends StatelessWidget {
  final Message message;
  final bool isMine;
  final bool isLastInGroup;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    this.isLastInGroup = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: EdgeInsets.only(
        left: isMine ? 64 : AppSpacing.screenPadding,
        right: isMine ? AppSpacing.screenPadding : 64,
        top: 2,
        bottom: 2,
      ),
      child: Align(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: message.isLocked
            ? _LockedBubble(
                message: message,
                isMine: isMine,
                isDark: isDark,
                isLast: isLastInGroup,
              )
            : _UnlockedBubble(
                message: message,
                isMine: isMine,
                isDark: isDark,
                isLast: isLastInGroup,
              ),
      ),
    );
  }
}

BorderRadius _bubbleRadius(bool isMine, bool isLast) {
  const r = Radius.circular(20);
  const tail = Radius.circular(5);
  if (isMine) {
    return BorderRadius.only(
      topLeft: r,
      topRight: r,
      bottomLeft: r,
      bottomRight: isLast ? tail : r,
    );
  } else {
    return BorderRadius.only(
      topLeft: r,
      topRight: r,
      bottomLeft: isLast ? tail : r,
      bottomRight: r,
    );
  }
}

class _UnlockedBubble extends StatelessWidget {
  final Message message;
  final bool isMine;
  final bool isDark;
  final bool isLast;

  const _UnlockedBubble({
    required this.message,
    required this.isMine,
    required this.isDark,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final bg = isMine
        ? AppColors.messageSent
        : (isDark ? AppColors.messageReceived : AppColors.messageReceivedLight);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: _bubbleRadius(isMine, isLast),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (message.isPasswordProtected && message.passwordUnlocked)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_open_rounded,
                      size: 10,
                      color: isMine
                          ? Colors.white.withValues(alpha: 0.5)
                          : AppColors.accent.withValues(alpha: 0.6)),
                  const SizedBox(width: 3),
                  Text(
                    l10n.unlocked,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: isMine
                          ? Colors.white.withValues(alpha: 0.5)
                          : AppColors.accent.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
          Text(
            message.decryptedContent ?? '••••••',
            style: TextStyle(
              color: isMine
                  ? Colors.white
                  : (isDark
                      ? AppColors.textPrimaryDark
                      : AppColors.textPrimaryLight),
              fontSize: 16,
              height: 1.4,
              letterSpacing: -0.1,
            ),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.bottomRight,
            child: _Meta(message: message, isMine: isMine, isDark: isDark),
          ),
        ],
      ),
    );
  }
}

class _LockedBubble extends StatelessWidget {
  final Message message;
  final bool isMine;
  final bool isDark;
  final bool isLast;

  const _LockedBubble({
    required this.message,
    required this.isMine,
    required this.isDark,
    required this.isLast,
  });

  void _showPasswordDialog(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    bool isLoading = false;
    String? error;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.lock_rounded, color: AppColors.accent, size: 20),
              const SizedBox(width: 10),
              Text(l10n.passwordRequired),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.passwordRequiredHint),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                obscureText: true,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: l10n.password,
                  errorText: error,
                  prefixIcon: const Icon(Icons.key_rounded, size: 20),
                ),
                onSubmitted: (_) => _tryUnlock(
                  context, ctx, controller,
                  (l) => setDialogState(() => isLoading = l),
                  (e) => setDialogState(() => error = e),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: isLoading
                  ? null
                  : () => _tryUnlock(
                        context, ctx, controller,
                        (l) => setDialogState(() => isLoading = l),
                        (e) => setDialogState(() => error = e),
                      ),
              child: isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(l10n.unlock),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _tryUnlock(
    BuildContext parentCtx,
    BuildContext dialogCtx,
    TextEditingController controller,
    void Function(bool) setLoading,
    void Function(String?) setError,
  ) async {
    final password = controller.text;
    if (password.isEmpty) return;
    setLoading(true);
    setError(null);
    final messenger = parentCtx.read<MessengerProvider>();
    final success = await messenger.unlockMessage(
      chatId: message.chatId,
      messageId: message.id,
      password: password,
    );
    if (success) {
      if (dialogCtx.mounted) Navigator.of(dialogCtx).pop();
    } else {
      setLoading(false);
      final l10n = parentCtx.mounted ? AppLocalizations.of(parentCtx) : null;
      setError(l10n?.wrongPassword ?? 'Wrong password');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final bg = isMine
        ? AppColors.messageSent
        : (isDark ? AppColors.messageReceived : AppColors.messageReceivedLight);

    return GestureDetector(
      onTap: () => _showPasswordDialog(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: _bubbleRadius(isMine, isLast),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isMine
                    ? Colors.white.withValues(alpha: 0.15)
                    : AppColors.accent.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.lock_rounded,
                  color: isMine ? Colors.white : AppColors.accent, size: 20),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.passwordProtected,
              style: TextStyle(
                color: isMine
                    ? Colors.white
                    : (isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimaryLight),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              l10n.tapToUnlock,
              style: TextStyle(
                color: isMine
                    ? Colors.white.withValues(alpha: 0.55)
                    : AppColors.accent.withValues(alpha: 0.8),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            _Meta(message: message, isMine: isMine, isDark: isDark),
          ],
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  final Message message;
  final bool isMine;
  final bool isDark;

  const _Meta({
    required this.message,
    required this.isMine,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final color = isMine
        ? Colors.white.withValues(alpha: 0.55)
        : (isDark ? AppColors.textTertiaryDark : AppColors.textTertiaryLight);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (message.selfDestructDuration != null)
          Padding(
            padding: const EdgeInsets.only(right: 3),
            child: Icon(Icons.timer_outlined, size: 11, color: color),
          ),
        Text(
          _fmt(message.timestamp),
          style: TextStyle(fontSize: 11, color: color),
        ),
        if (isMine) ...[
          const SizedBox(width: 3),
          _StatusIcon(status: message.status),
        ],
      ],
    );
  }

  String _fmt(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

class _StatusIcon extends StatelessWidget {
  final MessageStatus status;
  const _StatusIcon({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = Colors.white.withValues(alpha: 0.55);
    switch (status) {
      case MessageStatus.sending:
        return Icon(Icons.schedule_rounded, size: 13, color: color);
      case MessageStatus.sent:
        return Icon(Icons.check_rounded, size: 13, color: color);
      case MessageStatus.delivered:
        return Icon(Icons.done_all_rounded, size: 13, color: color);
      case MessageStatus.read:
        return Icon(Icons.done_all_rounded,
            size: 13, color: Colors.white.withValues(alpha: 0.9));
      case MessageStatus.failed:
        return const Icon(Icons.error_outline_rounded,
            size: 13, color: AppColors.error);
    }
  }
}
