import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/platform/platform_security_service.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/emergency_button.dart';
import '../data/models/chat_model.dart';
import '../data/models/message_model.dart';
import '../data/models/contact_model.dart';
import '../logic/messenger_provider.dart';
import 'widgets/chat_settings_sheet.dart';
import 'widgets/passwort_dialog.dart';
import 'widgets/message_bubble.dart';
import 'widgets/system_event_row.dart';

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

class _ChatScreenState extends State<ChatScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  /// Laesst die Eingabezeile kurz wackeln.
  ///
  /// Fuer den Fall, dass gar nicht gesendet werden kann. Vorher
  /// verschwand der Text wortlos aus dem Feld und nichts ging raus — das
  /// sah aus wie ein verschlucktes Senden.
  late final AnimationController _wackeln = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  );
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  Duration? _perMessageTimer;
  bool _hasPerMessageOverride = false;
  bool _burnAfterRead = false;
  String? _messagePassword;
  StreamSubscription<bool>? _screenshotSub;
  StreamSubscription<int>? _captureSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final messenger = context.read<MessengerProvider>();
    messenger.setActiveChat(widget.chat.id);
    _markVisibleMessagesAsRead(messenger);
    _listenForScreenshots();
  }

  @override
  void dispose() {
    _wackeln.dispose();
    _screenshotSub?.cancel();
    _captureSub?.cancel();
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

  /// Auf Screenshots und Bildschirmaufnahmen horchen.
  ///
  /// Beides laesst sich auf iOS nicht verhindern. Der fruehere Versuch, den
  /// Inhalt zu schwaerzen, beruhte auf undokumentiertem Verhalten und wirkte
  /// ab iOS 26 nicht mehr — die App behauptete einen Schutz, den sie nicht
  /// hatte. Jetzt erfahren stattdessen beide Seiten davon, als Eintrag im
  /// Verlauf.
  void _listenForScreenshots() {
    final platform = context.read<PlatformSecurityService>();
    final messenger = context.read<MessengerProvider>();

    _screenshotSub = platform.onScreenshotDetected.listen((_) {
      if (!mounted) return;
      messenger.reportSystemEvent(widget.chat.id, SystemEventKind.screenshot);
    });

    // Eine Aufnahme kann schon laufen, bevor dieser Chat geoeffnet wurde —
    // genau der heimliche Fall. Deshalb erst der aktuelle Zustand, dann jeder
    // spaetere Beginn. Das Ende ist nichts, was die Gegenseite erfahren muss.
    //
    // Die Nummer der Aufnahme haelt die Meldung im Zaum: dieser Bildschirm
    // wird beim Wechseln neu gebaut und liefe sonst fuer EINE Aufnahme
    // mehrfach los.
    //
    // Erst nach dem ersten Frame: der Hinweis landet als Eintrag im Verlauf,
    // und ein `notifyListeners` mitten im Aufbau des Baums ist ein Fehler.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      messenger.reportScreenRecording(widget.chat.id, platform.captureSession);
    });
    _captureSub = platform.onScreenRecordingStarted.listen((session) {
      if (!mounted) return;
      messenger.reportScreenRecording(widget.chat.id, session);
    });
  }

  Duration? get _effectiveTimer {
    if (_burnAfterRead) return null;
    if (_hasPerMessageOverride) return _perMessageTimer;
    final chat = context.read<MessengerProvider>().chatById(widget.chat.id);
    return chat?.defaultSelfDestruct;
  }

  /// Ob die Frist dieser Nachricht vom Chat-Timer stammt.
  ///
  /// Entscheidet, wann die Uhr startet: ein eigener Timer laeuft ab der
  /// Zustellung, der Chat-Timer ab dem Lesen. Siehe [SelfDestructPolicy].
  bool get _fristVomChat => !_burnAfterRead && !_hasPerMessageOverride;


  void _markVisibleMessagesAsRead(MessengerProvider messenger) {
    final messages = messenger.messagesForChat(widget.chat.id);
    for (final msg in messages) {
      if (msg.senderId != messenger.userId && msg.readAt == null) {
        messenger.markAsRead(widget.chat.id, msg.id);
      }
    }
  }

  /// Kurz wackeln und sagen, warum nichts rausging.
  void _abgelehnt(String hinweis) {
    HapticFeedback.heavyImpact();
    _wackeln.forward(from: 0);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(hinweis)));
  }

  void _sendMessage() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    // Blockiert: der Text bleibt stehen. Ihn zu leeren und nichts zu
    // senden ist das Schlechteste von beidem — es sieht aus, als waere die
    // Nachricht raus.
    final kontakt = context
        .read<MessengerProvider>()
        .contactForId(widget.chat.recipientId);
    if (kontakt != null && kontakt.isBlocked) {
      _abgelehnt(AppLocalizations.of(context)!.unblockToSend);
      return;
    }

    // Für das Passwort einer einzelnen Nachricht gelten bewusst keine Regeln
     // mehr. Es schützt eine Nachricht in einem ohnehin Ende-zu-Ende
     // verschlüsselten Chat vor jemandem, der einem über die Schulter schaut —
     // dafür reicht „baum". Erzwungene Sonderzeichen führen hier nur dazu,
     // dass niemand die Funktion benutzt. Für das Tresor-Passwort, das den
     // Zugang zur App schützt, gelten die Regeln weiterhin.

    final messenger = context.read<MessengerProvider>();
    messenger.sendMessage(
      chatId: widget.chat.id,
      text: text,
      selfDestruct: _effectiveTimer,
      selfDestructFromChat: _fristVomChat,
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
    // M1-Client follow-up (2026-05 Codex review): clear and dispose the
    // controller once the dialog is gone so the password text is not
    // held by a long-lived widget reference.
    showDialog(
      context: context,
      builder: (ctx) => PasswortDialog(
        symbol: Icons.lock_rounded,
        symbolFarbe: AppColors.warning,
        symbolGroesse: 22,
        titel: l10n.lockMessage,
        hinweis: l10n.lockMessageHint,
        feld: TextField(
          controller: pwController,
          autofocus: true,
          // M1-Client (audit 2026-05): obscure the message password as
          // the user types it. Without this, the password sits in
          // plaintext on the visible UI - defeating the point of
          // password-protecting a single message.
          obscureText: true,
          enableSuggestions: false,
          autocorrect: false,
          decoration: InputDecoration(
            hintText: l10n.enterPassword,
            prefixIcon: const Icon(Icons.key_rounded, size: 20),
          ),
        ),
        aktionen: [
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
    ).whenComplete(() {
      pwController.clear();
      pwController.dispose();
    });
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
          _buildVerificationStaleBanner(context, l10n),
          Expanded(child: _buildMessageList(context, l10n)),
          _buildStatusBars(context, l10n, isDark),
          // Solange die Kontaktanfrage nicht angenommen ist, steht hier die
          // Entscheidung statt des Schreibfelds — geschrieben wird erst
          // danach. Siehe docs/KONTAKTANFRAGEN.md.
          Consumer<MessengerProvider>(
            builder: (context, messenger, _) {
              final contact =
                  messenger.contactForId(widget.chat.recipientId);
              if (contact == null ||
                  contact.requestState == ContactRequestState.established) {
                return _buildMessageInput(context, l10n, isDark);
              }
              return _buildRequestBar(
                  context, l10n, isDark, messenger, contact);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildVerificationStaleBanner(
      BuildContext context, AppLocalizations l10n) {
    return Consumer<MessengerProvider>(
      builder: (context, messenger, _) {
        final contact = messenger.contactForId(widget.chat.recipientId);
        if (contact == null || !contact.isVerificationStale) {
          return const SizedBox.shrink();
        }
        const color = AppColors.warning;
        return InkWell(
          onTap: () => ChatSettingsSheet.show(context, widget.chat.id),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: color.withValues(alpha: 0.2),
                width: 0.5,
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.shield_outlined, size: 16, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.verificationStale,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w500,
                          fontSize: 12,
                        ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.verifyNow,
                  style: const TextStyle(
                    color: color,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded,
                    size: 16, color: color),
              ],
            ),
          ),
        );
      },
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
          final istBestaetigt =
              messenger.contactForId(widget.chat.recipientId)?.isVerified ??
                  false;
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
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      // „schreibt…" verdraengt den Hinweis, solange es
                      // laeuft — sonst springt die Zeile hin und her.
                      if (isTyping)
                        Text(
                          l10n.typing,
                          style: const TextStyle(
                            color: AppColors.accent,
                            fontSize: 12,
                          ),
                        )
                      else if (istBestaetigt)
                        // Klein und beilaeufig: es ist eine Feststellung,
                        // keine Werbung. Wer nicht bestaetigt hat, sieht
                        // hier nichts — eine Abwesenheit ist keine Warnung.
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.verified_rounded,
                                size: 11, color: AppColors.success),
                            const SizedBox(width: 3),
                            Text(
                              l10n.verifiedContact,
                              style: const TextStyle(
                                color: AppColors.success,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
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
            final isMine = msg.senderId == messenger.userId;
            // Hinweise gehoeren niemandem — sie stehen mittig zwischen den
            // Blasen, nicht auf einer Seite.
            if (msg.isSystemEvent) {
              return SystemEventRow(
                message: msg,
                isMine: isMine,
                peerName: widget.chat.recipientName,
              );
            }
            return MessageBubble(message: msg, isMine: isMine);
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
        label = l10n.chatDefaultWithTimer(_durationLabel(chatDefault, l10n));
      } else {
        label = _durationLabel(timerDuration, l10n);
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
          // Tap target widened from the visual icon's own ~18pt box toward the
          // 44pt HIG minimum (kept at 32pt, not the full 44pt: this badge sits
          // in a stack of info bars only 6pt apart, and a full-size invisible
          // tap area risks overlapping the next bar's own button — unverified
          // without a device, so a smaller, safe increase was chosen instead).
          GestureDetector(
            onTap: onClear,
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.all(9),
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

  /// Beschriftung einer Selbstzerstörungs-Zeit, übersetzt.
  ///
  /// Ersetzt zwei identische Kopien mit fest verdrahtetem Englisch. Die
  /// Reihenfolge der Vergleiche ist aufsteigend, damit ein Wert, der genau
  /// auf einer Grenze liegt, die kürzere Beschriftung bekommt.
  String _durationLabel(Duration? d, AppLocalizations l10n) {
    if (d == null) return l10n.off;
    if (d.inSeconds <= 30) return l10n.seconds30;
    if (d.inMinutes <= 1) return l10n.minute1;
    if (d.inMinutes <= 5) return l10n.minutes5;
    if (d.inMinutes <= 30) return l10n.minutes30;
    if (d.inHours <= 1) return l10n.hour1;
    if (d.inDays <= 1) return l10n.day1;
    return l10n.week1;
  }

  /// Die Leiste, die das Schreibfeld ersetzt, solange die Kontaktanfrage
  /// offen ist.
  Widget _buildRequestBar(
    BuildContext context,
    AppLocalizations l10n,
    bool isDark,
    MessengerProvider messenger,
    Contact contact,
  ) {
    final eingehend = contact.isIncomingRequest;
    final dimColor =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 14,
        bottom: MediaQuery.of(context).padding.bottom + 14,
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                eingehend
                    ? Icons.person_add_alt_1_rounded
                    : Icons.schedule_rounded,
                size: 18,
                color: AppColors.accent,
              ),
              const SizedBox(width: 8),
              Text(
                eingehend ? l10n.contactRequestTitle : l10n.contactRequestSent,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            eingehend
                ? l10n.contactRequestIncomingHint
                : l10n.contactRequestWaitingHint,
            style: TextStyle(fontSize: 13, color: dimColor),
          ),
          const SizedBox(height: 12),
          if (eingehend)
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: () =>
                        messenger.acceptContactRequest(contact.id),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                    ),
                    child: Text(l10n.acceptRequest),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () =>
                        messenger.declineContactRequest(contact.id),
                    child: Text(l10n.declineRequest),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: l10n.blockContact,
                  icon: const Icon(Icons.block_rounded,
                      color: AppColors.destructive),
                  onPressed: () => _confirmBlock(context, l10n, messenger,
                      contact.id),
                ),
              ],
            )
          else
            OutlinedButton.icon(
              onPressed: () => messenger.resendContactRequest(contact.id),
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: Text(l10n.resendRequest),
            ),
        ],
      ),
    );
  }

  /// Blockieren immer mit Rückfrage — es ist nicht offensichtlich, dass die
  /// Gegenseite davon nichts erfährt.
  Future<void> _confirmBlock(
    BuildContext context,
    AppLocalizations l10n,
    MessengerProvider messenger,
    String contactId,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.blockContact),
        content: Text(l10n.blockContactConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
                foregroundColor: AppColors.destructive),
            child: Text(l10n.blockContact),
          ),
        ],
      ),
    );
    if (ok == true) await messenger.blockContact(contactId);
  }

  Widget _buildMessageInput(BuildContext context, AppLocalizations l10n, bool isDark) {
    return AnimatedBuilder(
      animation: _wackeln,
      builder: (context, kind) {
        // Drei Ausschlaege, abklingend.
        final t = _wackeln.value;
        final weg = t == 0
            ? 0.0
            : 8 * (1 - t) * math.sin(t * math.pi * 6);
        return Transform.translate(offset: Offset(weg, 0), child: kind);
      },
      child: _buildMessageInputInner(context, l10n, isDark),
    );
  }

  Widget _buildMessageInputInner(
      BuildContext context, AppLocalizations l10n, bool isDark) {
    final dimColor = isDark
        ? AppColors.textTertiaryDark
        : AppColors.textTertiaryLight;

    // Gibt es das Konto nicht mehr, steht hier kein Eingabefeld. Eines
    // anzubieten, aus dem nichts herauskommt, waere eine Luege: Schluessel
    // und Konto sind auf dem Server geloescht, die Nachricht kaeme nie an.
    final istFort = context
            .watch<MessengerProvider>()
            .contactForId(widget.chat.recipientId)
            ?.isGone ??
        false;
    if (istFort) {
      return Container(
        width: double.infinity,
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 16,
          bottom: MediaQuery.of(context).padding.bottom + 16,
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
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_off_rounded, size: 16, color: dimColor),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                l10n.accountGoneCannotWrite,
                textAlign: TextAlign.center,
                style: TextStyle(color: dimColor, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

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
                            _durationLabel(chat!.defaultSelfDestruct, l10n))),
                      ),
                    PopupMenuItem(value: 'off', child: Text(l10n.off)),
                    PopupMenuItem(value: '30', child: Text(l10n.seconds30)),
                    PopupMenuItem(value: '60', child: Text(l10n.minute1)),
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
          // Send button — 36pt visible circle, 44pt tap target (HIG minimum;
          // this is the highest-frequency control in the whole screen).
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: GestureDetector(
              onTap: _sendMessage,
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                width: 44,
                height: 44,
                child: Center(
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
            ),
          ),
        ],
      ),
    );
  }
}
