import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../theme/app_colors.dart';
import '../../../../theme/app_spacing.dart';
import '../../data/models/message_model.dart';
import '../../logic/messenger_provider.dart';
import '../../logic/einmalig_policy.dart';
import 'passwort_dialog.dart';

class MessageBubble extends StatelessWidget {
  final Message message;
  final bool isMine;
  final bool isLastInGroup;

  /// Die angemeldete Kennung.
  ///
  /// Nur fuer die einmalige Nachricht: sie entscheidet, ob es hier ein Tor
  /// gibt. [isMine] taugt dafuer nicht — das ist die Anzeige-Entscheidung des
  /// Aufrufers, und sie mit der Identitaetsfrage zu beantworten hiesse,
  /// denselben Schalter zweimal zu pruefen. Fehlt die Kennung, bleibt das Tor
  /// zu, siehe EinmaligPolicy.oeffenbar.
  final String? eigeneId;

  /// Wird gerufen, wenn der Empfaenger eine einmalige Nachricht oeffnen will.
  ///
  /// Die Rueckfrage und das Verbrauchen haengen beim Aufrufer, nicht an der
  /// Blase. Die Blase weiss nur, dass etwas verborgen ist.
  final VoidCallback? onOeffnen;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    this.eigeneId,
    this.isLastInGroup = true,
    this.onOeffnen,
  });

  void _showMessageMenu(BuildContext context, bool isDark) {
    HapticFeedback.mediumImpact();
    final messenger = context.read<MessengerProvider>();
    final l10n = AppLocalizations.of(context)!;

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
            // Kein Kopieren aus dem Chat. Die Zwischenablage ist systemweit
            // lesbar, und was dort landet, ist aus der App heraus nicht mehr
            // zu schützen — auch die 60-Sekunden-Löschung half nur gegen
            // Vergessen, nicht gegen einen Mitleser. Einfügen bleibt möglich:
            // ein anderswo kopierter Text lässt sich weiterhin senden.
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: Text(l10n.deleteForMe),
              onTap: () {
                Navigator.of(ctx).pop();
                messenger.deleteMessageForMe(message.chatId, message.id);
              },
            ),
            if (isMine)
              ListTile(
                leading: const Icon(Icons.delete_forever_rounded,
                    color: AppColors.destructive),
                title: Text(l10n.deleteForEveryone,
                    style: const TextStyle(color: AppColors.destructive)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _confirmDeleteForEveryone(context, messenger);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteForEveryone(BuildContext context, MessengerProvider messenger) {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deleteForEveryone),
        content: Text(l10n.deleteForEveryoneConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.destructive,
            ),
            onPressed: () {
              messenger.deleteMessageForEveryone(message.chatId, message.id);
              Navigator.of(ctx).pop();
            },
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
  }

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
        child: Column(
          crossAxisAlignment:
              isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
          onLongPress: () => _showMessageMenu(context, isDark),
          onDoubleTap: () => _showMessageMenu(context, isDark),
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
                  eigeneId: eigeneId,
                  isDark: isDark,
                  isLast: isLastInGroup,
                  onOeffnen: onOeffnen,
                ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Die Rundung einer Blase. Die letzte einer Gruppe bekommt unten an ihrer
/// Seite eine kleinere Ecke, damit sie wie ein Schwanz wirkt.
BorderRadius _bubbleRadius(bool isMine, bool isLast) {
  const r = Radius.circular(AppSpacing.radiusMd);
  const tail = Radius.circular(4);
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

  /// Die angemeldete Kennung, siehe MessageBubble.eigeneId.
  final String? eigeneId;
  final bool isDark;
  final bool isLast;

  /// Nur fuer eine einmalige Nachricht gesetzt. Die Blase zeigt dann statt
  /// des Textes eine Schaltflaeche, und das Oeffnen selbst haengt beim
  /// Aufrufer.
  final VoidCallback? onOeffnen;

  const _UnlockedBubble({
    required this.message,
    required this.isMine,
    required this.eigeneId,
    required this.isDark,
    required this.isLast,
    this.onOeffnen,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final bg = isMine
        ? AppColors.messageSent
        : (isDark ? AppColors.messageReceived : AppColors.messageReceivedLight);

    final meta = _Meta(message: message, isMine: isMine, isDark: isDark);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 7, 12, 7),
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
          // Die Uhrzeit gehoert ans Ende der letzten Textzeile, nicht in eine
          // eigene Zeile darunter. Vorher kostete ein blosses „ok" sechzig
          // Pixel Hoehe, obwohl eine Zeile Text zwanzig braucht.
          //
          // Der Platzhalter im Text haelt am Ende genau so viel Raum frei, wie
          // die Uhrzeit breit ist; darueber liegt sie dann unten rechts.
          // Passt sie auf der letzten Zeile nicht mehr hin, bricht der
          // Platzhalter um und nimmt sie mit auf die naechste — dasselbe
          // Verhalten wie bei WhatsApp.
          // Eine einmalige Nachricht zeigt auf **beiden** Seiten nichts vom
          // Inhalt. Der Empfaenger bekommt das Tor mit der Rueckfrage, der
          // Absender nur die Notiz, dass er sie geschickt hat. Siehe
          // EinmaligPolicy.
          if (EinmaligPolicy.verbergen(einmalig: message.einmalig))
            _EinmaligerInhalt(
              message: message,
              isMine: isMine,
              eigeneId: eigeneId,
              isDark: isDark,
              onOeffnen: onOeffnen,
            )
          else
          Stack(
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: message.decryptedContent ?? '••••••'),
                    WidgetSpan(
                      child: SizedBox(
                        width: _Meta.breite(context, message, isMine),
                        height: 1,
                      ),
                    ),
                  ],
                ),
                style: TextStyle(
                  color: isMine
                      ? Colors.white
                      : (isDark
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimaryLight),
                  fontSize: 16,
                  height: 1.25,
                  letterSpacing: -0.1,
                ),
              ),
              Positioned.fill(
                // bottomEnd, nicht bottomRight: der freigehaltene Platz haengt am
                // logischen Ende des Textes. Fest nach rechts gelegt laegen die
                // beiden bei einer Schrift von rechts nach links auf verschiedenen
                // Seiten, und die Uhrzeit schoebe sich ueber den Text.
                child: Align(
                  alignment: AlignmentDirectional.bottomEnd,
                  child: meta,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Was anstelle einer einmaligen Nachricht in der Blase steht.
///
/// Beim Empfaenger das Tor: der Hinweis und die Schaltflaeche, die die
/// Rueckfrage ausloest. Beim Absender nur die Notiz mit Uhrzeit und
/// Zustellstand — er soll sehen, **dass** er eine einmalige Nachricht
/// geschickt hat und wie weit sie gekommen ist, und sonst nichts.
///
/// Beim Absender ist das keine Kulisse vor einem noch vorhandenen Text: sein
/// Klartext wird beim Senden gar nicht erst behalten, siehe
/// EinmaligPolicy.klartextBeimAbsender.
class _EinmaligerInhalt extends StatelessWidget {
  final Message message;
  final bool isMine;
  final String? eigeneId;
  final bool isDark;
  final VoidCallback? onOeffnen;

  const _EinmaligerInhalt({
    required this.message,
    required this.isMine,
    required this.eigeneId,
    required this.isDark,
    this.onOeffnen,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final offen = EinmaligPolicy.oeffenbar(
      einmalig: message.einmalig,
      senderId: message.senderId,
      eigeneId: eigeneId,
    );

    // Auf der eigenen, eingefaerbten Blase traegt Grau nicht — dort gehoert
    // der Hinweis in dieselbe Familie wie die Uhrzeit daneben.
    final textFarbe = isMine
        ? Colors.white.withValues(alpha: 0.75)
        : (isDark
            ? AppColors.textSecondaryDark
            : AppColors.textSecondaryLight);
    final symbolFarbe =
        isMine ? Colors.white.withValues(alpha: 0.75) : AppColors.destructive;

    final zeile = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.visibility_off_rounded, size: 15, color: symbolFarbe),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            offen ? l10n.onceOnlyHiddenHint : l10n.onceOnlySentHint,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: textFarbe,
            ),
          ),
        ),
        // Die Uhrzeit haengt hier hinten an der Zeile, statt wie sonst ueber
        // dem Text zu schweben: es gibt keinen Text, ueber dem sie liegen
        // koennte. Nur beim Absender — der Empfaenger sieht bis zum Oeffnen
        // ohnehin nichts als das Tor.
        if (!offen) ...[
          const SizedBox(width: 8),
          _Meta(message: message, isMine: isMine, isDark: isDark),
        ],
      ],
    );

    if (!offen) return zeile;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        zeile,
        const SizedBox(height: 8),
        FilledButton(
          onPressed: onOeffnen,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.destructive,
            foregroundColor: Colors.white,
            minimumSize: const Size(0, 36),
            padding: const EdgeInsets.symmetric(horizontal: 16),
          ),
          child: Text(l10n.openOnceMessage),
        ),
      ],
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
        builder: (ctx, setDialogState) => PasswortDialog(
          symbol: Icons.lock_rounded,
          symbolFarbe: AppColors.accent,
          symbolGroesse: 20,
          titel: l10n.passwordRequired,
          hinweis: l10n.passwordRequiredHint,
          feld: TextField(
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
          aktionen: [
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
    ).then((_) => controller.dispose());
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

    // Kein Passwortdialog fuer die eigene Nachricht.
    //
    // Der Absender kann sie gar nicht aufschliessen: seine Fassung traegt
    // den Klartext, nicht den passwortverschluesselten Block, und sein
    // eigenes Passwort passt darauf nicht. Die Abfrage meldete deshalb
    // ausnahmslos „Falsches Passwort" — egal was man eintippte. Sie war
    // schlicht nie fuer ihn gedacht.
    return GestureDetector(
      onTap: isMine ? null : () => _showPasswordDialog(context),
      child: Container(
        // Mitgezogen mit der normalen Blase: stuende die geschuetzte weiter
        // in alter Groesse daneben, saehe sie wie ein Fehler aus.
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: _bubbleRadius(isMine, isLast),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: isMine
                    ? Colors.white.withValues(alpha: 0.15)
                    : AppColors.accent.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.lock_rounded,
                  color: isMine ? Colors.white : AppColors.accent, size: 16),
            ),
            const SizedBox(height: 6),
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
              // Der Absender wartet, der Empfaenger tippt.
              isMine ? l10n.awaitingUnlock : l10n.tapToUnlock,
              style: TextStyle(
                color: isMine
                    ? Colors.white.withValues(alpha: 0.55)
                    : AppColors.accent.withValues(alpha: 0.8),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 6),
            _Meta(message: message, isMine: isMine, isDark: isDark),
          ],
        ),
      ),
    );
  }
}

String _fmtZeit(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

class _Meta extends StatelessWidget {
  final Message message;
  final bool isMine;
  final bool isDark;

  const _Meta({
    required this.message,
    required this.isMine,
    required this.isDark,
  });

  static const double _schriftgroesse = 11;
  static const double _symbolgroesse = 13;

  /// Wie breit diese Zeile baut.
  ///
  /// Gebraucht, um im Nachrichtentext am Ende genau so viel Platz
  /// freizuhalten — die Uhrzeit liegt darueber, nicht darunter.
  ///
  /// **Muss mit [build] mitwandern.** Kommt dort ein Symbol dazu, gehoert es
  /// auch in diese Rechnung; sonst schiebt sich die Uhrzeit ueber den Text.
  ///
  /// Der Rueckgabewert ist **unskaliert**: den Platzhalter im Text rechnet
  /// Flutter selbst hoch.
  static double breite(BuildContext context, Message message, bool isMine) {
    final skalierer = MediaQuery.textScalerOf(context);

    final maler = TextPainter(
      text: TextSpan(
        text: _fmtZeit(message.timestamp),
        // Gemessen werden muss dieselbe Schrift, die spaeter gezeichnet wird:
        // die Uhrzeit erbt Schriftart, Schnitt und Laufweite vom Umfeld. Gegen
        // eine nackte Schrift gemessen faellt der Platz je nach Thema zu klein
        // aus, und die Uhrzeit legt sich ueber den Text.
        style: DefaultTextStyle.of(context)
            .style
            .merge(const TextStyle(fontSize: _schriftgroesse)),
      ),
      textDirection: Directionality.of(context),
      textScaler: skalierer,
    )..layout();

    var breite = maler.width;
    if (message.selfDestructDuration != null) breite += 11 + 3; // Sanduhr
    if (isMine) breite += 3 + _symbolgroesse; // Haken
    breite += 8; // Luft zwischen Text und Uhrzeit

    // Und wieder herunter: den Platzhalter im Text skaliert Flutter selbst mit
    // der Systemschrift. Ohne diese Gegenrechnung wuerde die Uhrzeit zweimal
    // hochgerechnet — bei doppelter Schrift hielt die Blase gut hundert Pixel
    // zu viel frei, und genau die Kompaktheit, um die es hier geht, waere bei
    // grosser Schrift wieder weg.
    final faktor = skalierer.scale(_schriftgroesse) / _schriftgroesse;
    return faktor > 0 ? breite / faktor : breite;
  }

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
          _fmtZeit(message.timestamp),
          style: TextStyle(fontSize: 11, color: color),
        ),
        if (isMine) ...[
          const SizedBox(width: 3),
          _StatusIcon(status: message.status),
        ],
      ],
    );
  }

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
