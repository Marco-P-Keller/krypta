import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../theme/app_colors.dart';
import '../../../../theme/app_spacing.dart';
import '../../data/models/chat_model.dart';
import '../../data/models/contact_model.dart';
import '../../data/models/message_model.dart';
import '../../logic/chatliste_policy.dart';

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

  /// Was unter dem Namen steht, siehe [VorschauPolicy].
  ///
  /// Kommt vom Aufrufer, weil sie aus dem Verlauf im Provider abgeleitet wird
  /// und nicht am Chat haengt — der Klartext soll weiterhin nur an einer
  /// Stelle auf der Platte liegen.
  final Vorschau vorschau;

  /// Der Zustellstand der letzten Nachricht, wenn sie von mir ist.
  ///
  /// Nur dann: was die Gegenseite mir geschickt hat, braucht kein Haekchen.
  final MessageStatus? eigenerStand;

  /// Wann die Kachel gebaut wird. Nur fuer den Test — er darf sich nicht
  /// darauf verlassen muessen, welcher Tag heute ist.
  final DateTime? jetzt;

  const ChatTile({
    super.key,
    required this.chat,
    required this.onTap,
    this.onLongPress,
    this.requestState,
    this.requestLabel,
    this.vorschau = (
      art: VorschauArt.keine,
      text: null,
      vonMir: false,
      ereignis: null
    ),
    this.eigenerStand,
    this.jetzt,
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
    final offeneAnfrage =
        requestState != null && requestState != ContactRequestState.established;

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
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
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
                          zeitText(context, chat.displayTime!,
                              jetzt: jetzt ?? DateTime.now()),
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

                  // Vorschau + Ballon
                  Row(
                    children: [
                      if (offeneAnfrage)
                        Expanded(
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color:
                                      AppColors.accent.withValues(alpha: 0.15),
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
                        // Die Tipp-Anzeige geht vor: was gerade geschrieben
                        // wird, ist neuer als alles, was dasteht.
                        Expanded(
                          child: chat.isTyping
                              ? _TypingIndicator(isDark: isDark)
                              : _Vorschauzeile(
                                  vorschau: vorschau,
                                  eigenerStand: eigenerStand,
                                  hasUnread: hasUnread,
                                  isDark: isDark,
                                ),
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

  /// Die Uhrzeit rechts in der Kachel, in der Sprache des Nutzers.
  ///
  /// Hier stand einmal eine eigene Rechnung mit `Yesterday` und einer festen
  /// Liste `['Mon', 'Tue', …]` — englisch, in einer App mit sieben Sprachen,
  /// und die Grenze lief ueber `difference(...).inDays`. Um zehn nach
  /// Mitternacht stand deshalb fuer eine Nachricht von gestern 23:50 immer
  /// noch `23:50` da. Welche Form gilt, entscheidet jetzt [ChatlistZeit] nach
  /// Kalendertagen; die Woerter kommen aus der Uebersetzung und aus `intl`.
  static String zeitText(BuildContext context, DateTime zeit,
      {required DateTime jetzt}) {
    final sprache = Localizations.localeOf(context).toString();
    switch (ChatlistZeit.form(zeit, jetzt)) {
      case ZeitForm.uhrzeit:
        // Ueber MaterialLocalizations, nicht selbst formatiert: nur so
        // richtet sich die Anzeige nach der 24-Stunden-Einstellung des
        // Geraets.
        return MaterialLocalizations.of(context).formatTimeOfDay(
          TimeOfDay.fromDateTime(zeit),
          alwaysUse24HourFormat: MediaQuery.of(context).alwaysUse24HourFormat,
        );
      case ZeitForm.gestern:
        // Erst hier nachgeschlagen: die drei anderen Formen kommen ohne
        // Uebersetzung aus, und eine Kachel soll nicht daran scheitern, dass
        // ein Aufrufer die Delegates vergessen hat.
        return AppLocalizations.of(context)?.yesterday ?? 'Yesterday';
      case ZeitForm.wochentag:
        return DateFormat.E(sprache).format(zeit);
      case ZeitForm.datum:
        return DateFormat.yMd(sprache).format(zeit);
    }
  }
}

/// Die Zeile unter dem Namen: Haekchen, Symbol, Text.
///
/// Der Text kommt aus dem Verlauf im Speicher und steht nur hier — er wird
/// nicht am Chat gespeichert, siehe VorschauPolicy. Eine einmalige und eine
/// passwortgeschuetzte Nachricht zeigen nie ihren Inhalt, sondern sagen nur,
/// dass sie da sind: den Inhalt gibt es genau einmal, und zwar im Chat.
class _Vorschauzeile extends StatelessWidget {
  const _Vorschauzeile({
    required this.vorschau,
    required this.eigenerStand,
    required this.hasUnread,
    required this.isDark,
  });

  final Vorschau vorschau;
  final MessageStatus? eigenerStand;
  final bool hasUnread;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    if (vorschau.art == VorschauArt.keine) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    final farbe = hasUnread
        ? (isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight)
        : (isDark ? AppColors.textTertiaryDark : AppColors.textTertiaryLight);

    final symbol = switch (vorschau.art) {
      VorschauArt.einmalig => Icons.visibility_off_rounded,
      VorschauArt.passwort => Icons.lock_rounded,
      VorschauArt.hinweis => _hinweisSymbol(vorschau.ereignis),
      _ => null,
    };

    final text = switch (vorschau.art) {
      VorschauArt.text => vorschau.text ?? '',
      VorschauArt.einmalig => l10n.onceOnlyMessage,
      VorschauArt.passwort => l10n.previewLocked,
      VorschauArt.hinweis => _hinweisText(l10n, vorschau.ereignis),
      VorschauArt.keine => '',
    };

    return Row(
      children: [
        // Das Haekchen gehoert nur an eine eigene Nachricht, und nur an eine
        // gewoehnliche: bei einem Hinweis gibt es nichts zuzustellen.
        if (eigenerStand != null && vorschau.art != VorschauArt.hinweis) ...[
          _Haekchen(status: eigenerStand!, farbe: farbe),
          const SizedBox(width: 3),
        ],
        if (vorschau.vonMir && vorschau.art != VorschauArt.hinweis)
          Text(
            '${l10n.previewYou}: ',
            style: TextStyle(fontSize: 13, color: farbe),
          ),
        if (symbol != null) ...[
          Icon(symbol, size: 14, color: farbe),
          const SizedBox(width: 4),
        ],
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              color: farbe,
              fontStyle: vorschau.art == VorschauArt.text
                  ? FontStyle.normal
                  : FontStyle.italic,
            ),
          ),
        ),
      ],
    );
  }

  static IconData _hinweisSymbol(SystemEventKind? art) => switch (art) {
        SystemEventKind.screenshot => Icons.screenshot_rounded,
        SystemEventKind.screenRecording => Icons.videocam_rounded,
        SystemEventKind.accountDeleted => Icons.person_off_rounded,
        SystemEventKind.selfDestructChanged => Icons.timer_outlined,
        SystemEventKind.selfDestructAfterRead => Icons.drafts_outlined,
        null => Icons.info_outline_rounded,
      };

  /// Knapp, nicht der ganze Satz aus dem Verlauf.
  ///
  /// „Marco hat einen Screenshot vom Chat gemacht" passt in die Blase im
  /// Chat, aber nicht in eine Zeile neben einem Ballon — dort bliebe von
  /// jedem Hinweis dasselbe abgeschnittene „Marco hat einen Screensh…".
  static String _hinweisText(AppLocalizations l10n, SystemEventKind? art) =>
      switch (art) {
        SystemEventKind.screenshot => l10n.previewScreenshot,
        SystemEventKind.screenRecording => l10n.previewRecording,
        SystemEventKind.accountDeleted => l10n.previewAccountGone,
        SystemEventKind.selfDestructChanged ||
        SystemEventKind.selfDestructAfterRead =>
          l10n.previewRuleChanged,
        null => '',
      };
}

/// Ein Haken, zwei Haken, zwei blaue Haken — wie man es kennt.
class _Haekchen extends StatelessWidget {
  const _Haekchen({required this.status, required this.farbe});

  final MessageStatus status;
  final Color farbe;

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      MessageStatus.sending =>
        Icon(Icons.schedule_rounded, size: 13, color: farbe),
      MessageStatus.failed => const Icon(Icons.error_outline_rounded,
          size: 13, color: AppColors.destructive),
      MessageStatus.sent => Icon(Icons.check_rounded, size: 13, color: farbe),
      MessageStatus.delivered =>
        Icon(Icons.done_all_rounded, size: 13, color: farbe),
      MessageStatus.read => const Icon(Icons.done_all_rounded,
          size: 13, color: AppColors.accent),
    };
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
