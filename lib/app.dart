import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'l10n/app_localizations.dart';
import 'core/locale/locale_controller.dart';
import 'features/auth/presentation/welcome_back_screen.dart';
import 'features/settings/presentation/language_screen.dart';
import 'features/messenger/logic/key_publish_status.dart';
import 'features/auth/logic/zugang_policy.dart';
import 'features/auth/presentation/lock_screen.dart';
import 'features/auth/presentation/setup_screen.dart';
import 'features/auth/presentation/tutorial_screen.dart';
import 'features/auth/presentation/vault_password_screen.dart';
import 'features/calculator/presentation/calculator_screen.dart';
import 'features/messenger/data/models/chat_model.dart';
import 'features/messenger/logic/messenger_provider.dart';
import 'features/messenger/logic/screen_lock_policy.dart';
import 'features/messenger/logic/sync_lifecycle_policy.dart';
import 'features/messenger/presentation/chat_list_screen.dart';
import 'features/messenger/presentation/chat_screen.dart';
import 'features/messenger/presentation/new_chat_screen.dart';
import 'features/messenger/presentation/qr_scanner_screen.dart';
import 'features/settings/presentation/settings_screen.dart';
import 'security/device/device_integrity_policy.dart';
import 'services/emergency/emergency_wipe_service.dart';
import 'services/platform/clipboard_helper.dart';
import 'services/platform/biometric_outcome.dart';
import 'services/platform/platform_security_service.dart';
import 'services/platform/privacy_cover.dart';
import 'services/storage/encrypted_local_store.dart';
import 'services/storage/secure_storage_service.dart';
import 'services/storage/legacy_cleanup.dart';
import 'theme/app_theme.dart';

class KryptaApp extends StatelessWidget {
  const KryptaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Calculator',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // Die Liste kommt aus dem Controller, damit sie nicht an zwei Stellen
      // gepflegt werden muss und nicht auseinanderlaufen kann.
      supportedLocales: LocaleController.supported,
      // Die bewusste Wahl des Nutzers schlaegt die Geraetesprache. Ohne das
      // hier richtete sich die App nach dem Telefon — und weil ein guter Teil
      // der Oberflaeche fest verdrahtete Texte trug, ergab das einen
      // Mischmasch aus Deutsch und Englisch.
      locale: context.watch<LocaleController>().locale,
      home: const KryptaShell(),
    );
  }
}

/// Root navigation shell.
///
/// Navigation is state-based (no named routes / deep links).
/// This prevents app structure from leaking into system logs.
class KryptaShell extends StatefulWidget {
  const KryptaShell({super.key});

  @override
  State<KryptaShell> createState() => _KryptaShellState();
}

enum _AppScreen {
  calculator,

  /// Die Sperre ohne Rechner.
  ///
  /// Der Taschenrechner ist seit dem 22.09.2026 freiwillig. Wer ihn
  /// abschaltet, aber ein Tresor-Passwort oder Face ID benutzt, bekommt
  /// diesen Bildschirm; wer gar nichts davon hat, landet direkt im
  /// Messenger. Siehe [_KryptaShellState._sperrziel].
  lock,
  // Steht vor dem Tutorial: alles danach ist Text, und der soll in der
  // Sprache erscheinen, die der Nutzer versteht.
  language,
  setup,
  tutorial,
  /// Übergang zwischen Taschenrechner und Messenger — begrüßt und lädt.
  welcomeBack,
  vaultPassword,
  messenger,
  chat,
  newChat,
  qrScanner,
  settings,
}

class _KryptaShellState extends State<KryptaShell> with WidgetsBindingObserver {
  _AppScreen _currentScreen = _AppScreen.calculator;
  bool _isInitialized = false;

  /// Nimmt die Abdeckung des App-Umschalters erst ab, wenn ein Bild steht.
  late final PrivacyCover _privacyCover =
      PrivacyCover(context.read<PlatformSecurityService>());

  DeviceIntegrityAction _deviceAction = DeviceIntegrityAction.allow;
  Chat? _selectedChat;

  /// Ob der Taschenrechner vor dem Messenger steht.
  ///
  /// Vorgabe `true`, und das ist wichtig: jedes Geraet, das schon laeuft, hat
  /// einen Geheimcode vergeben und erwartet den Rechner. Erst die Antwort aus
  /// dem Schluesselbund kann das aendern, siehe
  /// SecureStorageService.isCalculatorLockEnabled.
  bool _rechnerSperre = true;

  /// Ob ein Tresor-Passwort gesetzt ist.
  bool _tresor = false;

  /// Ob Face ID eingeschaltet ist.
  ///
  /// Zusammen mit [_tresor] der Unterschied zwischen einem Sperrbildschirm
  /// und gar keinem: eine Sperre, die jeder Fingertipp oeffnet, ist keine.
  bool _biometrie = false;

  /// Ob gerade geprueft wird. Face ID braucht ein paar Sekunden, und der
  /// Sperrbildschirm soll in der Zeit nicht aussehen, als haette der Knopf
  /// nichts getan.
  bool _pruefungLaeuft = false;


  /// Zaehlt jedes Sperren mit.
  ///
  /// Das Entsperren laeuft ueber mehrere `await` — Aufnahmeschutz,
  /// `initialize()`, die Mindestdauer des Willkommens-Uebergangs. Wer die
  /// App in dieser Zeit weglegt, wird gesperrt; der fertige Vorgang schaltete
  /// danach trotzdem auf den Messenger und hebelte die Sperre aus, ohne dass
  /// je wieder ein Code eingegeben wurde. Am Ende wird deshalb geprueft, ob
  /// zwischendurch gesperrt wurde.
  int _sperrZaehler = 0;

  /// Der Stand des Sperrzaehlers, als die laufende Anmeldung begann.
  int _anmeldungBegonnenBei = 0;

  /// Ob seit dem Beginn der Anmeldung nicht gesperrt wurde.
  bool get _anmeldungGiltNoch => _sperrZaehler == _anmeldungBegonnenBei;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  @override
  void dispose() {
    // C6: ensure periodic integrity polling doesn't outlive the shell.
    try {
      context.read<DeviceIntegrityPolicyService>().stopPeriodicChecks();
    } catch (_) {}
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// When app goes to background, always lock back to calculator.
  /// This ensures the messenger is never visible when returning to the app.
  ///
  /// Gesperrt wird nur bei einem **echten** Hintergrundwechsel. Ein blosses
  /// `inactive` zaehlt nicht — es feuert beim Screenshot, beim
  /// Kontrollzentrum, bei einem Anruf-Banner und beim Face-ID-Dialog. Warum
  /// das so bleiben muss, steht in [ScreenLockPolicy]; kurz: der Versuch,
  /// dort mitzusperren, liess den Taschenrechner bei jedem Screenshot
  /// aufblitzen und hat Face ID vollstaendig blockiert.
  /// Die Vorschau im App-Umschalter deckt ein eigener Mechanismus ab, der
  /// unabhaengig vom Screenshot-Hinweis laeuft.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Der Empfang zuerst, vor allem anderen. Er hing bisher an gar nichts:
    // im Hintergrund lief der Listener gegen eine gekappte Verbindung
    // weiter, und beim Aufwachen holte ihn niemand zurueck — eine
    // Kontaktanfrage vom Vormittag lag deshalb nach dem Oeffnen noch eine
    // Minute herum, obwohl die Chatliste laengst stand.
    final messenger = context.read<MessengerProvider>();
    if (SyncLifecyclePolicy.shouldPause(state)) {
      messenger.pauseSync();
    } else if (SyncLifecyclePolicy.shouldResume(state)) {
      messenger.resumeSync();
    }

    if (ScreenLockPolicy.shouldLock(state)) _sperren();

    final isBackgrounded = state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden;
    if (isBackgrounded) {
      // Wer die App wegwischt, hat den Chat verlassen — in einem Chat mit
      // „Direkt nach dem Lesen" geht das Gelesene damit auch dann, wenn die
      // Chat-Ansicht selbst stehen bleibt.
      unawaited(messenger.burnReadInActiveChat());
      // Evict stale ratchet state entries (containing private keys) from memory.
      // This reduces the window where sensitive cryptographic material is in RAM.
      context.read<EncryptedLocalStore>().evictStaleCacheEntries();
      // C6: stop periodic integrity polling while backgrounded — the resume
      // path re-runs a one-shot check and _unlockMessenger re-starts it.
      context.read<DeviceIntegrityPolicyService>().stopPeriodicChecks();
      // M2-Client (audit 2026-05 follow-up): the 60s clipboard auto-clear
      // timer dies if the OS kills the backgrounded app, so wipe now while
      // we still hold the process. No-op if the user has since copied
      // something else themselves.
      unawaited(ClipboardHelper.clearEphemeralNow());

    }

    // On resume, re-validate device integrity and evict stale cache entries.
    if (state == AppLifecycleState.resumed) {
      final integrity = context.read<DeviceIntegrityPolicyService>();
      final store = context.read<EncryptedLocalStore>();

      // Die Abdeckung faellt erst, wenn ein Bild steht — und die Pruefungen
      // laufen erst danach. Beide gehoeren zusammen: `recheck` tastet das
      // Dateisystem synchron ab (vierzehn Pfade und ein Schreibversuch, den
      // die Sandbox ablehnt) und blockiert dabei genau den Faden, der das
      // Bild bauen soll. Frueher stand das vor dem ersten Bild und die
      // Abdeckung fiel nach Zeit — wer beides verlor, sah den Messenger
      // aufblitzen.
      _privacyCover.dismissWhenPainted(afterwards: () {
        if (!mounted) return;
        integrity.recheck().then((_) {
          if (!mounted) return;
          final action = integrity.enforce();
          if (action != _deviceAction) {
            setState(() => _deviceAction = action);
          }
        });
        store.evictStaleCacheEntries();
      });
    }
  }

  Future<void> _initialize() async {
    // Capture context references before async gaps.
    final integrity = context.read<DeviceIntegrityPolicyService>();
    final storage = context.read<SecureStorageService>();
    final store = context.read<EncryptedLocalStore>();

    // Device integrity check — enforce configured policy.
    await integrity.checkIntegrity();
    final action = integrity.enforce();
    if (!mounted) return;

    if (action == DeviceIntegrityAction.block) {
      setState(() {
        _deviceAction = action;
        _isInitialized = true;
      });
      return;
    }

    // Store the action for UI (warning banners etc.)
    _deviceAction = action;

    final isSetup = await storage.isSetupComplete();

    if (!isSetup) {
      if (!mounted) return;
      setState(() {
        // Beim allerersten Start zuerst die Sprache. Wurde sie schon einmal
        // gewaehlt (etwa nach einem abgebrochenen Einrichten), direkt weiter
        // ins Tutorial.
        _currentScreen = context.read<LocaleController>().hasChosen
            ? _AppScreen.tutorial
            : _AppScreen.language;
        _isInitialized = true;
      });
      return;
    }

    // Einmalig die Reste des ausgebauten Tarn-Messengers wegraeumen. Nur
    // eingerichtete Installationen koennen welche haben — ein frisches Geraet
    // hat den Modus nie gesehen. Scheitert der Lauf, bleibt der Merker aus
    // und der naechste Start holt es nach.
    await LegacyCleanup(
      markerSet: storage.isLegacyCleanupDone,
      setMarker: storage.markLegacyCleanupDone,
      purgeFiles: store.purgeLegacyDecoyFiles,
      deleteLegacyKeys: storage.deleteLegacyKeys,
    ).run();

    await _ladeZugang();

    if (!mounted) return;
    // Ohne jede Sperre gibt es nichts zu entsperren. Dann steht hier der
    // Uebergang, und der Messenger laedt dahinter — wie nach einem Code.
    final ziel = _sperrziel();
    setState(() {
      _currentScreen = ziel ?? _AppScreen.welcomeBack;
      _isInitialized = true;
    });
    if (ziel == null) unawaited(_unlockMessenger());
  }

  /// Nachlesen, was den Zugang gerade schuetzt.
  ///
  /// Drei Schalter, die sich in den Einstellungen aendern lassen, und alle
  /// drei entscheiden, wohin die App beim Sperren faellt. Gelesen wird
  /// deshalb nicht nur beim Start, sondern auch nach jedem Besuch der
  /// Einstellungen und nach der Einrichtung.
  Future<void> _ladeZugang() async {
    final storage = context.read<SecureStorageService>();
    final rechner = await storage.isCalculatorLockEnabled();
    final tresor = await storage.isVaultPasswordEnabled();
    final biometrie = await storage.isBiometricEnabled();
    if (!mounted) return;
    _rechnerSperre = rechner;
    _tresor = tresor;
    _biometrie = biometrie;
  }

  /// Wohin die App faellt, wenn sie sperrt — oder `null`, wenn es nichts zu
  /// sperren gibt.
  ///
  /// Der Rechner geht vor: wer ihn anhat, soll ihn sehen, auch wenn er
  /// zusaetzlich ein Tresor-Passwort benutzt. Ohne ihn uebernimmt der
  /// Sperrbildschirm, sofern ueberhaupt etwas zu pruefen ist.
  _AppScreen? _sperrziel() => switch (ZugangsPolicy.ziel(
        rechner: _rechnerSperre,
        tresor: _tresor,
        biometrie: _biometrie,
      )) {
        Sperrziel.rechner => _AppScreen.calculator,
        Sperrziel.sperrbildschirm => _AppScreen.lock,
        Sperrziel.offen => null,
      };

  /// Ob die App ueberhaupt sperren kann.
  bool get _kannSperren => _sperrziel() != null;

  /// Den Zugang pruefen und, wenn er haelt, den Messenger oeffnen.
  ///
  /// Zwei Wege fuehren hierher: der richtige Code im Rechner, und der Knopf
  /// auf dem Sperrbildschirm, wenn der Rechner abgeschaltet ist. Was danach
  /// kommt, ist in beiden Faellen dasselbe — Face ID, dann gegebenenfalls das
  /// Tresor-Passwort.
  Future<void> _zugangPruefen() async {
    // Defense-in-depth: block messenger access on compromised devices.
    if (_deviceAction == DeviceIntegrityAction.block) return;
    // Ein zweiter Tipp waehrend der Pruefung startet keinen zweiten
    // Durchlauf. Der Riegel steht **vor** dem ersten await: zwischen dem
    // Nachschlagen des Fehlzaehlers und dem Face-ID-Dialog liegen mehrere,
    // und zwei Dialoge uebereinander sind genau das, was an der einmaligen
    // Nachricht am 07.09.2026 schon einmal schiefging.
    if (_pruefungLaeuft) return;
    if (mounted) setState(() => _pruefungLaeuft = true);
    try {
      await _zugangPruefenIntern();
    } finally {
      if (mounted) setState(() => _pruefungLaeuft = false);
    }
  }

  Future<void> _zugangPruefenIntern() async {

    // Der Stand VOR dem ersten await. Face ID, das Nachschlagen der
    // Tresor-Einstellung und die Passwortpruefung dauern; wer die App in
    // dieser Zeit weglegt, wird gesperrt. Ohne diesen Stand liefe die
    // Anmeldung danach einfach weiter und haette die Sperre umgangen.
    _anmeldungBegonnenBei = _sperrZaehler;

    final storage = context.read<SecureStorageService>();
    final platform = context.read<PlatformSecurityService>();
    // Vor dem ersten await gelesen: danach ist der context nicht mehr
    // unstrittig gueltig, und der Text wird erst nach mehreren awaits
    // gebraucht.
    final l10n = AppLocalizations.of(context)!;

    // H4: if the unified fail counter is already at wipe threshold, act now.
    // This catches the case where an earlier biometric-only session
    // accumulated enough fails to wipe.
    if (await storage.getVaultFailCount() >=
        SecureStorageService.maxVaultAttempts) {
      await _handleEmergencyWipe();
      return;
    }

    final biometricEnabled = await storage.isBiometricEnabled();

    if (biometricEnabled) {
      final outcome = await platform.authenticateDetailed(
        reason: l10n.biometricUnlockReason,
      );
      if (!mounted) return;
      if (outcome != BiometricOutcome.success) {
        // H4: unify biometric fails into the vault counter so an attacker
        // cannot burn through biometric attempts and then get a fresh
        // 5-attempt vault budget.
        //
        // Aber nur eine echte Ablehnung zaehlt. Ein Abbruch oder ein Geraet,
        // das gerade nicht pruefen kann, ist kein Angriffsversuch — und
        // fuenf davon wuerden alles loeschen. Zugang gibt es trotzdem
        // keinen: ohne Erfolg geht es hier nicht weiter.
        if (outcome.countsAsFailedAttempt) {
          await storage.incrementVaultFailCount();
          final fails = await storage.getVaultFailCount();
          if (fails >= SecureStorageService.maxVaultAttempts) {
            await _handleEmergencyWipe();
          }
        }
        return;
      }
      // Biometric success — reset counter so one bad taps don't linger.
      await storage.resetVaultFailCount();
      if (!_anmeldungGiltNoch) return;
    }

    final vaultEnabled = await storage.isVaultPasswordEnabled();
    if (!mounted || !_anmeldungGiltNoch) return;
    if (vaultEnabled) {
      setState(() => _currentScreen = _AppScreen.vaultPassword);
      return;
    }

    await _unlockMessenger();
  }

  /// Wie lange der Willkommensbildschirm mindestens steht.
  ///
  /// Ohne Untergrenze blitzt er auf einem schnellen Gerät nur auf, was
  /// unruhiger wirkt als gar kein Übergang. Dauert das Laden länger, bleibt
  /// er entsprechend länger stehen — er ist auch der Ladebildschirm.
  static const _welcomeBackMinimum = Duration(milliseconds: 900);

  /// Auf die Sperre zurueckfallen: Rechner oder Sperrbildschirm.
  ///
  /// Die Einrichtung ist ausgenommen: wer beim ersten Start kurz die App
  /// verlaesst, soll nicht auf dem Rechner landen, ohne je einen Code
  /// vergeben zu haben. Der Willkommens-Uebergang ist NICHT ausgenommen —
  /// dahinter liegt bereits der entsperrte Messenger.
  ///
  /// Schuetzt weder Rechner noch Tresor noch Face ID, wird nicht gesperrt.
  /// Ein Bildschirm, den ein einziger Tipp oeffnet, waere keine Sperre,
  /// sondern nur eine Huerde fuer den Besitzer — und er wuerde eine
  /// Sicherheit behaupten, die es nicht gibt.
  void _sperren() {
    if (!mounted) return;
    final ziel = _sperrziel();
    // Ohne Ziel gibt es nichts zu sperren — und dann darf auch kein
    // laufendes Entsperren verfallen. Wuerde hier trotzdem gezaehlt, bliebe
    // eine App ganz ohne Sperre nach einem Wegwischen waehrend des Starts
    // auf dem Willkommensbildschirm stehen: `_unlockMessenger` prueft am
    // Ende, ob zwischendurch gesperrt wurde, und faende einen erhoehten
    // Zaehler ohne jede Sperre dahinter.
    if (ziel == null) return;
    // Ab hier zaehlt jedes Sperren mit, auch wenn unten frueh ausgestiegen
    // wird: ein laufendes Entsperren muss auch dann abbrechen, wenn schon
    // der Rechner steht.
    _sperrZaehler++;
    if (_currentScreen == ziel ||
        _currentScreen == _AppScreen.calculator ||
        _currentScreen == _AppScreen.lock ||
        _currentScreen == _AppScreen.setup ||
        _currentScreen == _AppScreen.language ||
        _currentScreen == _AppScreen.tutorial) {
      return;
    }

    // Offene Sheets und Dialoge liegen als eigene Route UEBER allem. Nur
    // `_currentScreen` umzuschalten laesst sie stehen — samt ihrer
    // Abdunklung, die dann als milchiger Schleier ueber dem Taschenrechner
    // liegt, mit dem Messenger noch sichtbar darunter. Ohne Neustart war das
    // nicht mehr wegzubekommen.
    Navigator.of(context).popUntil((route) => route.isFirst);


    // Do NOT disable screenshot protection here — keep it active until the
    // calculator screen is fully visible.
    setState(() {
      _currentScreen = ziel;
      _selectedChat = null;
    });
    // Disable screenshot protection AFTER state change, so the calculator is
    // rendered before the secure flag is removed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Nicht abschalten, wenn inzwischen wieder entsperrt wurde.
      if (_currentScreen != ziel) return;
      context.read<PlatformSecurityService>().disableScreenshotProtection();
    });
  }

  Future<void> _unlockMessenger() async {
    final platform = context.read<PlatformSecurityService>();
    final messenger = context.read<MessengerProvider>();
    final integrity = context.read<DeviceIntegrityPolicyService>();

    // Erst der Übergang, dann die Arbeit: Schlüssel laden und den
    // Aufnahmeschutz einrichten dauert, und solange soll nicht der Rechner
    // stehenbleiben, als wäre der Code nicht angekommen.
    if (mounted) setState(() => _currentScreen = _AppScreen.welcomeBack);
    final gezeigtSeit = DateTime.now();


    // Enable screenshot/recording protection BEFORE rendering the messenger.
    // Awaited so the native content mask is installed first. If the OS mask
    // is unavailable (returns false), we continue in a degraded mode rather
    // than blocking the messenger — E2E encryption is the core guarantee and
    // the post-capture warning stays honest about the unprotected state.
    await platform.enableScreenshotProtection();
    await messenger.initialize();

    // C6: start periodic integrity monitoring while the messenger is unlocked
    // — catches Frida / debugger attachment that happens after the initial
    // start-time check. Stopped on background/logout/emergency wipe.
    integrity.startPeriodicChecks(
      onAction: (action) {
        if (!mounted) return;
        if (action != _deviceAction) {
          setState(() => _deviceAction = action);
        }
      },
    );

    // Den Rest der Mindestdauer abwarten, falls das Laden schneller war.
    final verstrichen = DateTime.now().difference(gezeigtSeit);
    if (verstrichen < _welcomeBackMinimum) {
      await Future<void>.delayed(_welcomeBackMinimum - verstrichen);
    }

    // Wurde zwischendurch gesperrt, ist diese Anmeldung verfallen. Sonst
    // schaltete ein spaet fertig gewordenes Entsperren an der Sperre vorbei.
    // Wurde zwischendurch gesperrt, ist diese Anmeldung verfallen.
    if (!mounted || !_anmeldungGiltNoch) return;
    setState(() => _currentScreen = _AppScreen.messenger);
  }

  Future<void> _handleEmergencyWipe() async {
    final wipeService = context.read<EmergencyWipeService>();
    final messenger = context.read<MessengerProvider>();
    final platform = context.read<PlatformSecurityService>();
    final integrity = context.read<DeviceIntegrityPolicyService>();

    integrity.stopPeriodicChecks();
    await messenger.wipeAll();
    await wipeService.wipeEverything();
    await platform.disableScreenshotProtection();

    if (mounted) {
      setState(() {
        // Wie ein frisches Geraet: die Einrichtung entscheidet neu, ob ein
        // Rechner davorsteht.
        _rechnerSperre = true;
        _tresor = false;
        _biometrie = false;
        _currentScreen = _AppScreen.setup;
        _selectedChat = null;
      });
    }
  }

  /// Von Hand sperren: der Pfeil links oben in der Chatliste.
  ///
  /// Gibt es nichts zu sperren, gibt es den Pfeil auch nicht — siehe
  /// [_kannSperren]. Eine Schaltflaeche, die auf einen Bildschirm fuehrt, den
  /// jeder Tipp wieder oeffnet, waere eine Behauptung.
  void _zurueckZurSperre() {
    final ziel = _sperrziel();
    if (ziel == null) return;
    // C6: stop periodic integrity checks — messenger is no longer active.
    context.read<DeviceIntegrityPolicyService>().stopPeriodicChecks();
    setState(() => _currentScreen = ziel);
    // Disable screenshot protection AFTER the lock screen is rendered
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final platform = context.read<PlatformSecurityService>();
        platform.disableScreenshotProtection();
      }
    });
  }

  /// Nach der Einrichtung: dorthin, wo der frisch gewaehlte Zugang hinfuehrt.
  ///
  /// Wer den Rechner uebersprungen hat, soll nicht auf einem Rechner landen,
  /// fuer den er nie einen Code vergeben hat — das waere eine Tuer ohne
  /// Schluessel. Siehe SetupScreen.
  Future<void> _nachDerEinrichtung() async {
    await _ladeZugang();
    if (!mounted) return;
    final ziel = _sperrziel();
    if (ziel != null) {
      setState(() => _currentScreen = ziel);
      return;
    }
    await _unlockMessenger();
  }

  /// Zwischen den Bildschirmen wechseln.
  ///
  /// **Vom Taschenrechner fuehrt hier kein Weg weg.** Nach dem Sperren
  /// treffen noch Rueckrufe ein, die vorher losgeschickt wurden: ein
  /// Benenn-Dialog etwa, den `popUntil` beim Sperren weggeraeumt hat, laeuft
  /// danach weiter und wuerde den frisch angelegten Chat oeffnen. Damit
  /// stuende der Messenger wieder da, ohne dass je ein Code eingegeben
  /// wurde.
  ///
  /// Der einzige Weg heraus ist [_unlockMessenger], und der setzt den
  /// Bildschirm selbst.
  void _navigateTo(_AppScreen screen) {
    final gesperrt = _currentScreen == _AppScreen.calculator ||
        _currentScreen == _AppScreen.lock;
    if (gesperrt && screen != _currentScreen) return;
    setState(() => _currentScreen = screen);
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Hard block on compromised devices — shows blank calculator-like screen.
    // Only triggered when policy is [DeviceIntegrityPolicy.block].
    if (_deviceAction == DeviceIntegrityAction.block) {
      return const Scaffold(
        body: Center(
          child: Text(
            'Calculator',
            style: TextStyle(fontSize: 20, color: Colors.grey),
          ),
        ),
      );
    }

    final screen = _buildCurrentScreen();

    // Wrap messenger screens with integrity warning if device is compromised.
    final showWarning = _deviceAction == DeviceIntegrityAction.warnAndDegrade ||
        _deviceAction == DeviceIntegrityAction.warnOnly;
    final isMessengerScreen = _currentScreen == _AppScreen.messenger ||
        _currentScreen == _AppScreen.chat ||
        _currentScreen == _AppScreen.newChat ||
        _currentScreen == _AppScreen.qrScanner ||
        _currentScreen == _AppScreen.settings;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: isMessengerScreen
          ? _wrapWithBanners(screen, integrity: showWarning)
          : screen,
    );
  }

  /// Legt die Warnbanner über einen Messenger-Bildschirm.
  ///
  /// Der Schlüssel-Zustand wird per [Selector] gelesen statt per `watch`:
  /// sonst würde die ganze Hülle bei jeder Änderung im MessengerProvider neu
  /// bauen — also bei jeder eingehenden Nachricht.
  Widget _wrapWithBanners(Widget screen, {required bool integrity}) {
    return Column(
      key: ValueKey('shell_${screen.key}'),
      children: [
        if (integrity) _buildIntegrityBanner(context),
        Selector<MessengerProvider, KeyPublishState>(
          selector: (_, messenger) => messenger.keyPublishState,
          builder: (context, state, _) => state == KeyPublishState.ok
              ? const SizedBox.shrink()
              : _buildKeyPublishBanner(context, state),
        ),
        Expanded(child: screen),
      ],
    );
  }

  /// Persistent device integrity warning banner.
  Widget _buildIntegrityBanner(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final degraded = _deviceAction == DeviceIntegrityAction.warnAndDegrade;
    return MaterialBanner(
      backgroundColor: Colors.orange.shade900,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      content: Text(
        degraded ? l10n.deviceCompromisedDegraded : l10n.deviceCompromised,
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
      leading: const Icon(Icons.warning_amber_rounded,
          color: Colors.orange, size: 20),
      actions: const [SizedBox.shrink()],
    );
  }

  /// Warnt, wenn die eigenen Schlüssel nicht auf dem Server liegen.
  ///
  /// Ohne sie kann niemand eine Session aufbauen und es kommt keine Nachricht
  /// an. Vorher verschwand dieser Fehlschlag in einem `catch`, das nur in
  /// Debug-Builds etwas ausgab — im TestFlight-Build war er unsichtbar, und
  /// die App wirkte, als sei alles in Ordnung.
  Widget _buildKeyPublishBanner(BuildContext context, KeyPublishState state) {
    final l10n = AppLocalizations.of(context)!;
    final denied = state == KeyPublishState.denied;
    return MaterialBanner(
      backgroundColor: denied ? Colors.red.shade900 : Colors.orange.shade900,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      content: Text(
        denied ? l10n.keysNotPublishedDenied : l10n.keysNotPublishedFailed,
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
      leading: Icon(
        denied ? Icons.gpp_bad_rounded : Icons.cloud_off_rounded,
        color: Colors.white,
        size: 20,
      ),
      actions: const [SizedBox.shrink()],
    );
  }

  Widget _buildCurrentScreen() {
    switch (_currentScreen) {
      case _AppScreen.setup:
        return SetupScreen(
          key: const ValueKey('setup'),
          onSetupComplete: () => unawaited(_nachDerEinrichtung()),
        );

      case _AppScreen.language:
        return LanguageScreen(
          key: const ValueKey('language'),
          onContinue: () => _navigateTo(_AppScreen.tutorial),
        );

      case _AppScreen.welcomeBack:
        return const WelcomeBackScreen(key: ValueKey('welcome_back'));

      case _AppScreen.tutorial:
        return TutorialScreen(
          key: const ValueKey('tutorial'),
          onComplete: () => _navigateTo(_AppScreen.setup),
        );

      case _AppScreen.vaultPassword:
        return VaultPasswordScreen(
          key: const ValueKey('vault_password'),
          onVerify: (password) async {
            // Jede Pruefung ist ein eigener Anlauf: wer waehrend der
            // Pruefung die App weglegt, kommt danach nicht durch.
            _anmeldungBegonnenBei = _sperrZaehler;
            final storage = context.read<SecureStorageService>();
            final ok = await storage.verifyVaultPassword(password);
            if (ok && _anmeldungGiltNoch) await _unlockMessenger();
            return ok;
          },
          onCancel: () =>
              _navigateTo(_sperrziel() ?? _AppScreen.vaultPassword),
          onEmergencyWipe: _handleEmergencyWipe,
        );

      case _AppScreen.calculator:
        return CalculatorScreen(
          key: const ValueKey('calculator'),
          onSecretCode: _zugangPruefen,
          onDeleteCode: () => _handleEmergencyWipe(),
        );

      case _AppScreen.lock:
        return LockScreen(
          key: const ValueKey('lock'),
          onUnlock: _zugangPruefen,
          laeuft: _pruefungLaeuft,
        );

      case _AppScreen.messenger:
        return ChatListScreen(
          key: const ValueKey('messenger'),
          onSettingsTap: () => _navigateTo(_AppScreen.settings),
          onChatTap: (chat) {
            _selectedChat = chat;
            _navigateTo(_AppScreen.chat);
          },
          onNewChat: () => _navigateTo(_AppScreen.newChat),
          onEmergencyWipe: _handleEmergencyWipe,
          // Ohne Sperre kein Pfeil: es gaebe nichts, wohin er fuehrt.
          onBack: _kannSperren ? _zurueckZurSperre : null,
        );

      case _AppScreen.chat:
        if (_selectedChat == null) {
          _navigateTo(_AppScreen.messenger);
          return const SizedBox.shrink();
        }
        return ChatScreen(
          key: ValueKey('chat_${_selectedChat?.id}'),
          chat: _selectedChat!,
          onEmergencyWipe: _handleEmergencyWipe,
          onBack: () => _navigateTo(_AppScreen.messenger),
        );

      case _AppScreen.newChat:
        return NewChatScreen(
          key: const ValueKey('new_chat'),
          onChatCreated: (chat) {
            _selectedChat = chat;
            _navigateTo(_AppScreen.chat);
          },
          onBack: () => _navigateTo(_AppScreen.messenger),
          onScanQr: () => _navigateTo(_AppScreen.qrScanner),
        );

      case _AppScreen.qrScanner:
        return QrScannerScreen(
          key: const ValueKey('qr_scanner'),
          onChatCreated: (chat) {
            _selectedChat = chat;
            _navigateTo(_AppScreen.chat);
          },
          onBack: () => _navigateTo(_AppScreen.newChat),
        );

      case _AppScreen.settings:
        return SettingsScreen(
          key: const ValueKey('settings'),
          onEmergencyWipe: _handleEmergencyWipe,
          // Der Zugang wird beim Verlassen neu gelesen: in den Einstellungen
          // laesst sich der Rechner abschalten, ein Tresor-Passwort setzen
          // oder Face ID umlegen. Ohne diesen Schritt fiele die App danach
          // auf die Sperre von vorhin.
          onBack: () async {
            await _ladeZugang();
            if (mounted) _navigateTo(_AppScreen.messenger);
          },
          userId: context.read<MessengerProvider>().userId,
        );
    }
  }
}
