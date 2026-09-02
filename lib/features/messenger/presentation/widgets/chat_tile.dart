import 'package:flutter/material.dart';
import '../../../../theme/app_colors.dart';
import '../../../../theme/app_spacing.dart';
import '../../data/models/chat_model.dart';
import '../../data/models/contact_model.dart';

const _avatarGradients = [
  [Color(0xFF0A84FF), Color(0xFF5856D6)],
  [Color(0xFF30D158), Color(0xFF34C759)],
  [Color(0xFFFF453A), Color(0xFFFF6B6B)],
  [Color(0xFFFFD60A), Color(0xFFFF9F0A)],
  [Color(0xFFBF5AF2), Color(0xFF5856D6)],
  [Color(0xFF32ADE6), Color(0xFF007AFF)],
];

class ChatTile extends StatelessWidget {
  final Chat chat;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// Anfragezustand des Kontakts. Ist er nicht `established`, steht statt der
  /// Vorschau eine Markierung — eine offene Anfrage traegt ohnehin keinen
  /// Inhalt, den man zeigen koennte.
  final ContactRequestState? requestState;

  /// Beschriftung der Markierung, lokalisiert vom Aufrufer gereicht.
  final String? requestLabel;

  const ChatTile({
    super.key,
    required this.chat,
    required this.onTap,
    this.onLongPress,
    this.requestState,
    this.requestLabel,
  });

  List<Color> _gradientFor(String name) {
    final idx = name.isEmpty ? 0 : name.codeUnitAt(0) % _avatarGradients.length;
    return _avatarGradients[idx];
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Fett, farbige Uhrzeit und Hervorhebung gelten fuer alles Ungesehene —
    // auch fuer einen blossen Screenshot-Hinweis ohne Nachricht.
    final hasUnread = chat.hatNeues;
    final hatHinweis = chat.hinweisCount > 0;
    final colors = _gradientFor(chat.recipientName);

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenPadding, vertical: 10),
        child: Row(
          children: [
            // Circular avatar
            Container(
              width: 56,
              height: 56,
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
                  chat.recipientName.isNotEmpty
                      ? chat.recipientName[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),

            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name + time row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          chat.recipientName,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                                fontWeight: hasUnread
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (chat.displayTime != null)
                        Text(
                          _formatTimestamp(chat.displayTime!),
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: hasUnread
                                        ? AppColors.accent
                                        : (isDark
                                            ? AppColors.textTertiaryDark
                                            : AppColors.textTertiaryLight),
                                    fontWeight: hasUnread
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                    fontSize: 12,
                                  ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),

                  // Preview + unread badge
                  Row(
                    children: [
                      if (requestState != null &&
                          requestState != ContactRequestState.established)
                        Expanded(
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.accent.withValues(
                                      alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  requestLabel ?? '',
                                  style: const TextStyle(
                                    color: AppColors.accent,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                      // Hier stand einmal der Klartext der letzten Nachricht.
                      // Die Chatliste ist die eine Ansicht, die jemand sieht,
                      // ohne einen Chat zu oeffnen — ueber die Schulter, oder
                      // weil das entsperrte Telefon kurz aus der Hand gegeben
                      // wurde. Was noetig ist, sagt der Ballon rechts: dass
                      // etwas da ist, und wie viel. Nicht, was drinsteht.
                      //
                      // Die Zeile bleibt, weil die Anfrage-Markierung und die
                      // Tipp-Anzeige darin sitzen.
                      Expanded(
                        child: chat.isTyping
                            ? _TypingIndicator(isDark: isDark)
                            : const SizedBox.shrink(),
                      ),
                      // Der Punkt sagt: hier ist etwas passiert. Die Zahl
                      // daneben sagt, wie viele echte Nachrichten liegen.
                      // Bewusst zwei verschiedene Zeichen — ein Screenshot ist
                      // keine Nachricht, und „1 neu" darf nicht beides heissen
                      // koennen. Eine Menge wird beim Punkt nicht genannt: sie
                      // sagt nichts, was jemanden weiterbraechte.
                      if (hatHinweis) ...[
                        const SizedBox(width: 8),
                        Container(
                          // Der Avatar ist ebenfalls ein Kreis; ohne den
                          // Schluessel liesse sich der Punkt nicht sicher
                          // von ihm unterscheiden.
                          key: const Key('hinweis-punkt'),
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppColors.accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                      if (chat.unreadCount > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.accent,
                            borderRadius:
                                BorderRadius.circular(AppSpacing.radiusFull),
                          ),
                          child: Text(
                            chat.unreadCount > 99
                                ? '99+'
                                : chat.unreadCount.toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inDays == 0) {
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[time.weekday - 1];
    } else {
      return '${time.day}.${time.month}';
    }
  }
}

class _TypingIndicator extends StatefulWidget {
  final bool isDark;
  const _TypingIndicator({required this.isDark});

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with TickerProviderStateMixin {
  final _controllers = <AnimationController>[];

  @override
  void initState() {
    super.initState();
    for (int i = 0; i < 3; i++) {
      final ctrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 600),
      )..repeat(
          reverse: true,
          period: Duration(milliseconds: 600 + i * 150),
        );
      _controllers.add(ctrl);
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < 3; i++)
          AnimatedBuilder(
            animation: _controllers[i],
            builder: (context, child) => Container(
              width: 5,
              height: 5,
              margin: const EdgeInsets.only(right: 3),
              decoration: BoxDecoration(
                color: AppColors.accent
                    .withValues(alpha: 0.4 + _controllers[i].value * 0.6),
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    );
  }
}
