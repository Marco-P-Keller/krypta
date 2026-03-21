import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../theme/app_colors.dart';
import '../../data/models/message_model.dart';
import '../../logic/messenger_provider.dart';

class MessageBubble extends StatelessWidget {
  final Message message;
  final bool isMine;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        margin: EdgeInsets.only(
          left: isMine ? 64 : 16,
          right: isMine ? 16 : 64,
          top: 2,
          bottom: 2,
        ),
        child: message.isLocked
            ? _LockedBubble(message: message, isMine: isMine, isDark: isDark)
            : _UnlockedBubble(message: message, isMine: isMine, isDark: isDark),
      ),
    );
  }
}

/// Shown when the message is password-protected and not yet unlocked.
class _LockedBubble extends StatelessWidget {
  final Message message;
  final bool isMine;
  final bool isDark;

  const _LockedBubble({
    required this.message,
    required this.isMine,
    required this.isDark,
  });

  void _showPasswordDialog(BuildContext context) {
    final controller = TextEditingController();
    bool isLoading = false;
    String? error;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.lock_rounded, color: AppColors.primary, size: 22),
              SizedBox(width: 10),
              Text('Password Required'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Enter the password to decrypt this message.'),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                obscureText: true,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Password',
                  errorText: error,
                  prefixIcon: const Icon(Icons.key_rounded, size: 20),
                ),
                onSubmitted: (_) => _tryUnlock(
                  context, ctx, controller, isLoading,
                  (l) => setDialogState(() => isLoading = l),
                  (e) => setDialogState(() => error = e),
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
              onPressed: isLoading
                  ? null
                  : () => _tryUnlock(
                        context, ctx, controller, isLoading,
                        (l) => setDialogState(() => isLoading = l),
                        (e) => setDialogState(() => error = e),
                      ),
              child: isLoading
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Unlock'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _tryUnlock(
    BuildContext parentContext,
    BuildContext dialogContext,
    TextEditingController controller,
    bool isLoading,
    void Function(bool) setLoading,
    void Function(String?) setError,
  ) async {
    final password = controller.text;
    if (password.isEmpty) return;

    setLoading(true);
    setError(null);

    final messenger = parentContext.read<MessengerProvider>();
    final success = await messenger.unlockMessage(
      chatId: message.chatId,
      messageId: message.id,
      password: password,
    );

    if (success) {
      if (dialogContext.mounted) Navigator.of(dialogContext).pop();
    } else {
      setLoading(false);
      setError('Wrong password');
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showPasswordDialog(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isMine
              ? AppColors.messageSent.withValues(alpha: 0.7)
              : (isDark
                  ? AppColors.messageReceived.withValues(alpha: 0.7)
                  : AppColors.messageReceivedLight.withValues(alpha: 0.7)),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isMine ? 18 : 4),
            bottomRight: Radius.circular(isMine ? 4 : 18),
          ),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              Icons.lock_rounded,
              color: isMine
                  ? Colors.white.withValues(alpha: 0.9)
                  : AppColors.primary,
              size: 24,
            ),
            const SizedBox(height: 6),
            Text(
              'Password Protected',
              style: TextStyle(
                color: isMine
                    ? Colors.white.withValues(alpha: 0.9)
                    : (isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Tap to unlock',
              style: TextStyle(
                color: isMine
                    ? Colors.white.withValues(alpha: 0.6)
                    : AppColors.primary,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatTime(message.timestamp),
                  style: TextStyle(
                    fontSize: 11,
                    color: isMine
                        ? Colors.white.withValues(alpha: 0.7)
                        : (isDark
                            ? AppColors.textTertiaryDark
                            : AppColors.textTertiaryLight),
                  ),
                ),
                if (isMine) ...[
                  const SizedBox(width: 4),
                  _StatusIcon(status: message.status, isMine: isMine),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

/// Normal message bubble (also used for unlocked password messages).
class _UnlockedBubble extends StatelessWidget {
  final Message message;
  final bool isMine;
  final bool isDark;

  const _UnlockedBubble({
    required this.message,
    required this.isMine,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isMine
            ? AppColors.messageSent
            : (isDark ? AppColors.messageReceived : AppColors.messageReceivedLight),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(isMine ? 18 : 4),
          bottomRight: Radius.circular(isMine ? 4 : 18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Show a small unlock badge for password-protected messages
          if (message.isPasswordProtected && message.passwordUnlocked)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.lock_open_rounded,
                    size: 11,
                    color: isMine
                        ? Colors.white.withValues(alpha: 0.6)
                        : AppColors.primary.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 3),
                  Text(
                    'Unlocked',
                    style: TextStyle(
                      fontSize: 10,
                      color: isMine
                          ? Colors.white.withValues(alpha: 0.6)
                          : AppColors.primary.withValues(alpha: 0.7),
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
                  : (isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight),
              fontSize: 15,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (message.selfDestructDuration != null)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(
                    Icons.timer_outlined,
                    size: 12,
                    color: isMine
                        ? Colors.white.withValues(alpha: 0.7)
                        : (isDark
                            ? AppColors.textTertiaryDark
                            : AppColors.textTertiaryLight),
                  ),
                ),
              Text(
                _formatTime(message.timestamp),
                style: TextStyle(
                  fontSize: 11,
                  color: isMine
                      ? Colors.white.withValues(alpha: 0.7)
                      : (isDark
                          ? AppColors.textTertiaryDark
                          : AppColors.textTertiaryLight),
                ),
              ),
              if (isMine) ...[
                const SizedBox(width: 4),
                _StatusIcon(status: message.status, isMine: isMine),
              ],
            ],
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

class _StatusIcon extends StatelessWidget {
  final MessageStatus status;
  final bool isMine;

  const _StatusIcon({required this.status, required this.isMine});

  @override
  Widget build(BuildContext context) {
    final color = isMine ? Colors.white.withValues(alpha: 0.7) : AppColors.textTertiaryDark;

    switch (status) {
      case MessageStatus.sending:
        return Icon(Icons.access_time, size: 14, color: color);
      case MessageStatus.sent:
        return Icon(Icons.check, size: 14, color: color);
      case MessageStatus.delivered:
        return Icon(Icons.done_all, size: 14, color: color);
      case MessageStatus.read:
        return Icon(Icons.done_all, size: 14, color: AppColors.primary);
      case MessageStatus.failed:
        return const Icon(Icons.error_outline, size: 14, color: AppColors.error);
    }
  }
}
