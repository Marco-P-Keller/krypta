import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../l10n/app_localizations.dart';
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

    return Padding(
      padding: EdgeInsets.only(
        left: isMine ? 60 : 14,
        right: isMine ? 14 : 60,
        top: 3,
        bottom: 3,
      ),
      child: Align(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: message.isLocked
            ? _LockedBubble(message: message, isMine: isMine, isDark: isDark)
            : _UnlockedBubble(message: message, isMine: isMine, isDark: isDark),
      ),
    );
  }
}

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
              const Icon(Icons.lock_rounded, color: AppColors.primary, size: 22),
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
              child: Text(l10n.cancel),
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
                  : Text(l10n.unlock),
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
      final l10n = parentContext.mounted
          ? AppLocalizations.of(parentContext)
          : null;
      setError(l10n?.wrongPassword ?? 'Wrong password');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return GestureDetector(
      onTap: () => _showPasswordDialog(context),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: isMine
              ? const LinearGradient(
                  colors: [
                    Color(0xFF4A6AE5),
                    Color(0xFF6A4FD4),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: isMine
              ? null
              : (isDark
                  ? AppColors.messageReceived.withValues(alpha: 0.8)
                  : AppColors.messageReceivedLight.withValues(alpha: 0.9)),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(isMine ? 20 : 6),
            bottomRight: Radius.circular(isMine ? 6 : 20),
          ),
          border: Border.all(
            color: isMine
                ? Colors.white.withValues(alpha: 0.1)
                : AppColors.primary.withValues(alpha: 0.15),
            width: 0.5,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isMine
                      ? Colors.white.withValues(alpha: 0.15)
                      : AppColors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.lock_rounded,
                  color: isMine ? Colors.white : AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.passwordProtected,
                style: TextStyle(
                  color: isMine
                      ? Colors.white.withValues(alpha: 0.95)
                      : (isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.1,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                l10n.tapToUnlock,
                style: TextStyle(
                  color: isMine
                      ? Colors.white.withValues(alpha: 0.55)
                      : AppColors.primary.withValues(alpha: 0.8),
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 8),
              _MetaRow(message: message, isMine: isMine, isDark: isDark),
            ],
          ),
        ),
      ),
    );
  }
}

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
    final l10n = AppLocalizations.of(context)!;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: isMine
            ? const LinearGradient(
                colors: [
                  AppColors.messageSentStart,
                  AppColors.messageSentEnd,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: isMine
            ? null
            : (isDark ? AppColors.messageReceived : AppColors.messageReceivedLight),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(20),
          topRight: const Radius.circular(20),
          bottomLeft: Radius.circular(isMine ? 20 : 6),
          bottomRight: Radius.circular(isMine ? 6 : 20),
        ),
        boxShadow: [
          BoxShadow(
            color: isMine
                ? AppColors.primary.withValues(alpha: 0.15)
                : Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message.isPasswordProtected && message.passwordUnlocked)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.lock_open_rounded,
                      size: 10,
                      color: isMine
                          ? Colors.white.withValues(alpha: 0.5)
                          : AppColors.primary.withValues(alpha: 0.6),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      l10n.unlocked,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.3,
                        color: isMine
                            ? Colors.white.withValues(alpha: 0.5)
                            : AppColors.primary.withValues(alpha: 0.6),
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
                fontSize: 15.5,
                height: 1.4,
                letterSpacing: -0.1,
              ),
            ),
            const SizedBox(height: 5),
            Align(
              alignment: Alignment.bottomRight,
              child: _MetaRow(message: message, isMine: isMine, isDark: isDark),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  final Message message;
  final bool isMine;
  final bool isDark;

  const _MetaRow({
    required this.message,
    required this.isMine,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final timeColor = isMine
        ? Colors.white.withValues(alpha: 0.55)
        : (isDark ? AppColors.textTertiaryDark : AppColors.textTertiaryLight);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (message.selfDestructDuration != null)
          Padding(
            padding: const EdgeInsets.only(right: 3),
            child: Icon(Icons.timer_outlined, size: 11, color: timeColor),
          ),
        Text(
          _formatTime(message.timestamp),
          style: TextStyle(fontSize: 10.5, color: timeColor),
        ),
        if (isMine) ...[
          const SizedBox(width: 4),
          _StatusIcon(status: message.status, isMine: isMine),
        ],
      ],
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
    final baseColor = isMine
        ? Colors.white.withValues(alpha: 0.6)
        : AppColors.textTertiaryDark;

    switch (status) {
      case MessageStatus.sending:
        return Icon(Icons.schedule_rounded, size: 13, color: baseColor);
      case MessageStatus.sent:
        return Icon(Icons.check_rounded, size: 13, color: baseColor);
      case MessageStatus.delivered:
        return Icon(Icons.done_all_rounded, size: 13, color: baseColor);
      case MessageStatus.read:
        return const Icon(Icons.done_all_rounded, size: 13,
            color: Color(0xFF82FFBA));
      case MessageStatus.failed:
        return const Icon(Icons.error_outline_rounded, size: 13,
            color: AppColors.error);
    }
  }
}
