// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Italian (`it`).
class AppLocalizationsIt extends AppLocalizations {
  AppLocalizationsIt([String locale = 'it']) : super(locale);

  @override
  String get appName => 'Krypta ECC';

  @override
  String get calculator => 'Calcolatrice';

  @override
  String get messenger => 'Messaggi';

  @override
  String get settings => 'Impostazioni';

  @override
  String get chats => 'Chats';

  @override
  String get contacts => 'Contatti';

  @override
  String get setupTitle => 'Benvenuto in Krypta ECC';

  @override
  String get setupSubtitle => 'Imposta i tuoi codici segreti per iniziare';

  @override
  String get secretCodeLabel => 'Codice segreto';

  @override
  String get secretCodeHint =>
      'Inserisci il codice che sblocca la messaggistica';

  @override
  String get deleteCodeLabel => 'Codice di cancellazione';

  @override
  String get deleteCodeHint =>
      'Inserisci un codice che cancella subito tutti i dati';

  @override
  String get setupComplete => 'Configurazione completata';

  @override
  String get setupContinue => 'Continua';

  @override
  String get setupCodesInfo =>
      'Tutti i codici devono essere diversi e di almeno 4 cifre';

  @override
  String get back => 'Indietro';

  @override
  String get next => 'Avanti';

  @override
  String get newChat => 'Nuova chat';

  @override
  String get typeMessage => 'Scrivi un messaggio...';

  @override
  String get send => 'Invia';

  @override
  String get delivered => 'Consegnato';

  @override
  String get sent => 'Inviato';

  @override
  String get read => 'Letto';

  @override
  String get typing => 'sta scrivendo...';

  @override
  String get selfDestructTimer => 'Timer di autodistruzione';

  @override
  String get seconds30 => '30 secondi';

  @override
  String get minutes5 => '5 minuti';

  @override
  String get hour1 => '1 ora';

  @override
  String get day1 => '1 giorno';

  @override
  String get week1 => '1 settimana';

  @override
  String get off => 'Disattivato';

  @override
  String get emergencyDelete => 'Cancellazione d’emergenza';

  @override
  String get emergencyDeleteDescription =>
      'Cancella subito tutti i dati e le chiavi ed esce dall’account';

  @override
  String get allDataDeleted => 'Tutti i dati sono stati cancellati';

  @override
  String get settingsTitle => 'Impostazioni';

  @override
  String get securitySettings => 'Sicurezza';

  @override
  String get changeSecretCode => 'Cambia il codice segreto';

  @override
  String get changeDeleteCode => 'Cambia il codice di cancellazione';

  @override
  String get biometricUnlock => 'Sblocco biometrico';

  @override
  String get biometricDescription =>
      'Richiedi Face ID o impronta dopo l’inserimento del codice';

  @override
  String get autoDeleteMessages => 'Cancellazione automatica dei messaggi';

  @override
  String get accountSection => 'Account';

  @override
  String get privacySection => 'Privacy';

  @override
  String get dangerZone => 'Zona a rischio';

  @override
  String get deleteAccount => 'Elimina account e dati';

  @override
  String get about => 'Informazioni su Krypta ECC';

  @override
  String version(String version) {
    return 'Versione $version';
  }

  @override
  String get noChats => 'Ancora nessuna conversazione';

  @override
  String get noChatsSubtitle =>
      'Avvia una nuova chat per scrivere in sicurezza';

  @override
  String get encryptionInfo => 'I messaggi sono cifrati end-to-end';

  @override
  String get anonymousUser => 'Utente anonimo';

  @override
  String get userIdLabel => 'Il tuo ID';

  @override
  String get userIdCopied => 'ID utente copiato negli appunti';

  @override
  String get addContactById => 'Aggiungi contatto tramite ID';

  @override
  String get contactIdHint => 'Inserisci l’ID del contatto';

  @override
  String get addContact => 'Aggiungi contatto';

  @override
  String get cannotAddYourself => 'Non puoi aggiungere te stesso';

  @override
  String get userNotFound => 'Utente non trovato';

  @override
  String get myQrCode => 'Il mio codice QR';

  @override
  String get scanQrCode => 'Scansiona codice QR';

  @override
  String get scanQr => 'Scansiona QR';

  @override
  String get qrScanHint => 'Punta la fotocamera verso un codice QR di Krypta';

  @override
  String get qrShareHint => 'Fallo scansionare agli altri per connettervi';

  @override
  String get yourQrCode => 'Il tuo codice QR';

  @override
  String get idCopied => 'ID copiato';

  @override
  String get qrWebUnavailable =>
      'La scansione dei codici QR non è disponibile sul web.\nUsa un dispositivo mobile per scansionare i codici QR.';

  @override
  String get thatsYourOwnId => 'Questo è il tuo ID';

  @override
  String get renameChat => 'Rinomina chat';

  @override
  String get chatName => 'Nome della chat';

  @override
  String get save => 'Salva';

  @override
  String get cancel => 'Annulla';

  @override
  String get skip => 'Salta';

  @override
  String get deleteChat => 'Elimina chat';

  @override
  String get clearChat => 'Svuota chat';

  @override
  String clearChatConfirm(String name) {
    return 'Eliminare tutti i messaggi di questa chat? Sul dispositivo di $name spariranno anche i messaggi che hai inviato; i suoi restano. L\'operazione non può essere annullata.';
  }

  @override
  String get autoDeleteTimer => 'Timer di cancellazione automatica';

  @override
  String get autoDeleteHint =>
      'I nuovi messaggi di questa chat si autodistruggeranno dopo il tempo scelto.';

  @override
  String get chatDefault => 'Impostazione predefinita della chat';

  @override
  String chatDefaultWithTimer(String timer) {
    return 'Impostazione predefinita della chat ($timer)';
  }

  @override
  String messagesAutoDelete(String timer) {
    return 'I messaggi si cancellano automaticamente dopo $timer';
  }

  @override
  String get onlyVisibleToYou => 'Visibile solo a te';

  @override
  String get burnAfterRead => 'Distruggi dopo la lettura';

  @override
  String get passwordProtected => 'Protetto da password';

  @override
  String get lockMessage => 'Blocca messaggio';

  @override
  String get lockMessageHint =>
      'Imposta una password per il prossimo messaggio. Il destinatario dovrà inserirla per leggerlo.';

  @override
  String get enterPassword => 'Inserisci la password';

  @override
  String get setPassword => 'Imposta password';

  @override
  String get passwordRequired => 'Password richiesta';

  @override
  String get passwordRequiredHint =>
      'Inserisci la password per decifrare questo messaggio.';

  @override
  String get password => 'Password';

  @override
  String get unlock => 'Sblocca';

  @override
  String get unlocked => 'Sbloccato';

  @override
  String get wrongPassword => 'Password errata';

  @override
  String get tapToUnlock => 'Tocca per sbloccare';

  @override
  String get nameThisContact => 'Dai un nome a questo contatto';

  @override
  String get nameContactHint =>
      'Assegna un nome a questo contatto per sapere di chi si tratta. Questa etichetta la vedi solo tu.';

  @override
  String get nameContactPlaceholder => 'es. Alex, mamma, lavoro...';

  @override
  String get selfDestructTimerLabel => 'Timer di autodistruzione';

  @override
  String get vaultPassword => 'Password della cassaforte';

  @override
  String get vaultPasswordDescription =>
      'Richiedi una password robusta dopo il codice, prima di accedere alla messaggistica';

  @override
  String get vaultPasswordTitle => 'Cassaforte bloccata';

  @override
  String get vaultPasswordHint =>
      'Inserisci la password della cassaforte per accedere alla messaggistica.';

  @override
  String get setVaultPassword => 'Imposta la password della cassaforte';

  @override
  String get changeVaultPassword => 'Cambia la password della cassaforte';

  @override
  String get removeVaultPassword => 'Rimuovi la password della cassaforte';

  @override
  String get vaultPasswordSet => 'Password della cassaforte impostata';

  @override
  String get vaultPasswordRemoved => 'Password della cassaforte rimossa';

  @override
  String get vaultPasswordRules =>
      'Almeno 10 caratteri, con maiuscola, minuscola, numero e carattere speciale.';

  @override
  String get newPassword => 'Nuova password';

  @override
  String get confirmPassword => 'Conferma password';

  @override
  String get passwordsDoNotMatch => 'Le password non coincidono';

  @override
  String get passwordTooWeak => 'La password non soddisfa i requisiti';

  @override
  String get copy => 'Copia';

  @override
  String get copied => 'Copiato';

  @override
  String get delete => 'Elimina';

  @override
  String get deleteMessage => 'Elimina messaggio';

  @override
  String get deleteMessageConfirm =>
      'Questo messaggio sarà eliminato definitivamente da questo dispositivo.';

  @override
  String get deleteForMe => 'Elimina per me';

  @override
  String get deleteForEveryone => 'Elimina per tutti';

  @override
  String get deleteForEveryoneConfirm =>
      'Questo messaggio sarà eliminato sia per te sia per il destinatario.';

  @override
  String get qrInvalidFormat =>
      'Formato del codice QR non valido. Sono accettati solo i codici QR di Krypta.';

  @override
  String get qrUnsupportedVersion =>
      'Versione del codice QR non supportata. Aggiorna l’app.';

  @override
  String get qrFingerprintMismatch =>
      'Avviso di sicurezza: l’impronta del codice QR è stata manomessa. Operazione annullata.';

  @override
  String get qrKeyMismatch =>
      'AVVISO DI SICUREZZA: la chiave del server NON corrisponde a quella del codice QR. Possibile attacco rilevato. Il contatto è stato bloccato.';

  @override
  String get qrVerified => 'Chiave verificata';

  @override
  String get verificationStale => 'La verifica risale a più di 90 giorni fa';

  @override
  String get verifyNow => 'Verifica di nuovo';

  @override
  String get showTutorial => 'Rivedi il tutorial';

  @override
  String get showTutorialSubtitle => 'Riproduci di nuovo l’introduzione';

  @override
  String get openSourceLicenses => 'Licenze open source';

  @override
  String get openSourceLicensesSubtitle => 'Librerie di terze parti e avvisi';

  @override
  String get aboutClose => 'Chiudi';

  @override
  String get confirm => 'Conferma';

  @override
  String lockedForSeconds(int seconds) {
    return 'Bloccato per $seconds secondi.';
  }

  @override
  String wrongPasswordWarning(int remaining) {
    String _temp0 = intl.Intl.pluralLogic(
      remaining,
      locale: localeName,
      other: 'Restano $remaining tentativi',
      one: 'Resta 1 tentativo',
    );
    return 'Password errata. $_temp0 prima che tutti i dati vengano cancellati.';
  }

  @override
  String get keysNotPublishedDenied =>
      'Il server ha rifiutato le tue chiavi: nessuno può scriverti.';

  @override
  String get keysNotPublishedFailed =>
      'Non è stato possibile pubblicare le tue chiavi: nessuno può scriverti.';

  @override
  String get biometricUnlockReason => 'Sblocca Krypta Messenger';

  @override
  String get deviceCompromised => 'Il dispositivo potrebbe essere compromesso.';

  @override
  String get deviceCompromisedDegraded =>
      'Il dispositivo potrebbe essere compromesso. Sicurezza hardware disattivata.';

  @override
  String get fieldRequired => 'Obbligatorio';

  @override
  String codeMinDigits(int count) {
    return 'Almeno $count cifre';
  }

  @override
  String get codeDigitsOnly => 'Solo cifre';

  @override
  String get deleteCodeMustDiffer =>
      'Il codice di cancellazione deve essere diverso dal codice segreto.';

  @override
  String get setupFailed => 'Configurazione non riuscita. Riprova.';

  @override
  String get setupSecretCodeSubtitle =>
      'Inseriscilo nella calcolatrice per aprire la cassaforte.';

  @override
  String get setupDeleteCodeSubtitle =>
      'Cancella tutto all’istante. Usalo solo in caso di emergenza.';

  @override
  String get contactKeyChangedWarning =>
      'La chiave di sicurezza di questo contatto è cambiata. I messaggi restano bloccati finché non ne verifichi l’identità. Scansiona il suo codice QR o confrontate i numeri di sicurezza per riprendere a scrivervi.';

  @override
  String get verifyIdentity => 'Verifica identità';

  @override
  String get safetyNumberCompareHint =>
      'Confrontate i numeri di sicurezza o scansionate i codici QR per verificare la cifratura end-to-end.';

  @override
  String get viewSafetyNumber => 'Mostra il numero di sicurezza';

  @override
  String get safetyNumberTitle => 'Numero di sicurezza';

  @override
  String get safetyNumberCopied => 'Numero di sicurezza copiato';

  @override
  String get safetyNumberMatchHint =>
      'Confronta questo numero con il tuo contatto. Se coincidono, la vostra conversazione è sicura.';

  @override
  String get verificationFailedKeyMismatch =>
      'Verifica non riuscita: le chiavi non coincidono';

  @override
  String get markVerified => 'Segna come verificato';

  @override
  String get securitySettingsReason =>
      'Modificare le impostazioni di sicurezza';

  @override
  String get vaultPasswordReAuthHint =>
      'Inserisci la password della cassaforte per modificare le impostazioni di sicurezza.';

  @override
  String get codeAlreadyInUse =>
      'Questo codice è già usato per un’altra azione.';

  @override
  String get deviceSecure => 'Dispositivo sicuro';

  @override
  String get deviceCompromisedDetected => 'Compromissione rilevata';

  @override
  String get deviceStatusUnknown => 'Stato sconosciuto';

  @override
  String get deviceSecureSubtitle =>
      'Nessun indizio di root, jailbreak o Frida';

  @override
  String get deviceCompromisedSubtitle =>
      'Rilevati root, jailbreak o strumentazione. Sicurezza hardware disattivata.';

  @override
  String get deviceStatusUnknownSubtitle =>
      'Controllo di integrità non riuscito: modalità limitata attiva.';

  @override
  String get hardwareEnclave => 'Enclave hardware';

  @override
  String get hardwareTee => 'Archivio chiavi TEE';

  @override
  String get hardwareSoftware => 'Archivio chiavi software';

  @override
  String get hardwareBoundSubtitle => 'Chiave del database legata all’hardware';

  @override
  String get hardwareEnclaveSubtitle => 'StrongBox/Secure Enclave disponibile';

  @override
  String get hardwareTeeSubtitle =>
      'Chiave conservata nel Trusted Execution Environment';

  @override
  String get hardwareSoftwareSubtitle =>
      'Nessuna sicurezza hardware disponibile';

  @override
  String get pushPrivacy => 'Privacy delle notifiche';

  @override
  String get pushPrivacyOn =>
      'Attiva: i messaggi vengono recuperati tramite polling';

  @override
  String get pushPrivacyOff => 'Disattivata: notifiche push attive';

  @override
  String get readReceipts => 'Conferme di lettura';

  @override
  String get readReceiptsOn => 'Attive: il mittente vede quando leggi';

  @override
  String get readReceiptsOff => 'Disattivate: massima privacy';

  @override
  String get deliveryReceipts => 'Conferme di consegna';

  @override
  String get deliveryReceiptsOn =>
      'Attive: il mittente vede quando il messaggio è consegnato';

  @override
  String get deliveryReceiptsOff => 'Disattivate: massima privacy';

  @override
  String get privacyPolicyBody =>
      'Krypta ECC — Informativa sulla privacy\n\nUltimo aggiornamento: aprile 2026\n\n1. Titolare del trattamento\nConnexa GmbH\nContatto: https://connexa-gmbh.ch\n\n2. Quali dati vengono raccolti?\nKrypta raccoglie il minor numero di dati tecnicamente possibile:\n• ID Firebase anonimo (nessuna e-mail, nessun nome, nessun numero di telefono)\n• Chiave pubblica di cifratura (X25519)\n• Token push FCM (per le notifiche)\n\n3. Cifratura\nTutti i messaggi sono cifrati end-to-end (protocollo Signal: X3DH + Double Ratchet). In nessun momento il server ha accesso al testo in chiaro dei tuoi messaggi. Cifratura: XChaCha20-Poly1305. Hashing delle password: Argon2id.\n\n4. Conservazione dei dati\n• I messaggi sono conservati solo sul tuo dispositivo (cifrati)\n• Il server funge solo da relè temporaneo: i messaggi vengono eliminati dopo la consegna\n• Le chiavi sono conservate nel Portachiavi iOS / Android Keystore\n\n5. Nessun tracciatore\nKrypta non contiene strumenti di analisi, pubblicità o tracciatori (0 su 432 tracciatori noti).\n\n6. Comunicazione dei dati\nNessun dato personale viene comunicato a terzi. Google Firebase è utilizzato come fornitore di infrastruttura (autenticazione anonima e notifiche push).\n\n7. Cancellazione dei dati\nPuoi cancellare in modo irreversibile tutti i tuoi dati in qualsiasi momento:\n• Nelle impostazioni, tramite «Cancella tutto»\n• Inserendo il codice di cancellazione nella calcolatrice\nQuesto distrugge tutti i dati locali, le chiavi e i dati sul server.\n\n8. I tuoi diritti (GDPR)\nHai diritto di accesso, rettifica, cancellazione e portabilità dei dati. Contattaci all’indirizzo: https://connexa-gmbh.ch\n\n9. Modifiche\nLa presente informativa può essere aggiornata. La versione in vigore è sempre consultabile nell’app.';

  @override
  String get tutStartSetup => 'Avvia la configurazione';

  @override
  String get tutWelcomeTitle => 'Benvenuto in Krypta';

  @override
  String get tutWelcomeBody =>
      'Krypta è una messaggistica segreta.\n\nPer tutti gli altri l’app sembra una comune calcolatrice: nessuno sospetterà che dietro si nasconda una chat cifrata.\n\nTi consigliamo di leggere con attenzione questo tutorial.';

  @override
  String get tutSecretCodeTitle => 'Il tuo codice segreto';

  @override
  String get tutSecretCodeBody =>
      'Durante la configurazione scegli un codice numerico.\n\nQuesto codice è la tua chiave: è l’unico modo per aprire la messaggistica nascosta.';

  @override
  String get tutDeleteCodeBody =>
      'Il secondo codice serve per le emergenze.\n\nInserendolo viene cancellato subito tutto: messaggi, chiavi, account. In modo irreversibile.\n\nScegli un codice che non digiterai per sbaglio.';

  @override
  String get tutDeleteCodeWarning =>
      'Tutto viene cancellato subito.\nNon è possibile alcun recupero.';

  @override
  String get tutOpenMessengerTitle => 'Aprire la messaggistica';

  @override
  String get tutOpenMessengerBody =>
      'Per aprire la tua messaggistica:\n\n1. Inserisci il codice segreto nella calcolatrice\n2. Premi il tasto =\n\nLa messaggistica si apre subito.';

  @override
  String get tutPressEquals => 'Premi =';

  @override
  String get tutMessengerUnlocked => 'Messaggistica sbloccata';

  @override
  String get tutVaultBody =>
      'Nelle impostazioni puoi attivare una password aggiuntiva.\n\nDopo il codice segreto viene richiesta anche la password della cassaforte: doppia sicurezza per i tuoi messaggi.';

  @override
  String get tutAddContactsTitle => 'Aggiungere contatti';

  @override
  String get tutAddContactsBody =>
      'Ci sono due modi per aggiungere contatti:\n\n• Scansionare un codice QR: rapido e semplice\n• Inserire un ID utente: quando non siete nello stesso posto\n\nDopodiché potete scrivervi.';

  @override
  String get tutQrFast => 'Rapido e semplice';

  @override
  String get tutEnterUserId => 'Inserire l’ID utente';

  @override
  String get tutForRemoteContacts => 'Per contatti a distanza';

  @override
  String get tutEmergencyBody =>
      'Nell’app trovi pulsanti rossi d’emergenza.\n\nCancellano tutto all’istante, proprio come il codice di cancellazione. Usali solo quando serve davvero.';

  @override
  String get tutInSettings => 'Nelle impostazioni';

  @override
  String get tutChatFeaturesIntro =>
      'In una chat hai tre funzioni particolari:';

  @override
  String get tutLockMessageDesc =>
      'Proteggere singoli messaggi con una password';

  @override
  String get tutAutoDeleteDesc =>
      'I messaggi si cancellano da soli dopo un tempo stabilito';

  @override
  String get tutBurnAfterReadDesc =>
      'Il messaggio viene eliminato subito dopo la lettura';

  @override
  String get tutReadyTitle => 'Tutto pronto!';

  @override
  String get tutReadyBody =>
      'Ora sai tutto quello che ti serve.\n\nNel passo successivo imposti i tuoi codici; dopodiché la messaggistica è pronta all’uso.';

  @override
  String get language => 'Lingua';

  @override
  String get chooseLanguage => 'Scegli la tua lingua';

  @override
  String get deviceSecuritySection => 'Sicurezza del dispositivo';

  @override
  String get tutDeleteCodeTitle => 'Codice d’emergenza';

  @override
  String get tutEmergencyTitle => 'Pulsanti d’emergenza';

  @override
  String get tutChatFeaturesTitle => 'Funzioni della chat';

  @override
  String get blockContact => 'Blocca';

  @override
  String get authentication => 'Autenticazione';

  @override
  String get contactRequestTitle => 'Richiesta di contatto';

  @override
  String get contactRequestIncomingHint =>
      'Questa persona vuole scriverti. Potrete scrivervi solo dopo che l’avrai accettata.';

  @override
  String get acceptRequest => 'Accetta';

  @override
  String get declineRequest => 'Rifiuta';

  @override
  String get contactRequestSent => 'Richiesta inviata';

  @override
  String get contactRequestWaitingHint =>
      'Potrai scrivere non appena l’altra persona accetta.';

  @override
  String get resendRequest => 'Richiedi di nuovo';

  @override
  String get acceptToReply => 'Accetta la richiesta per rispondere';

  @override
  String get requestBadge => 'Richiesta';

  @override
  String get blockContactConfirm =>
      'Bloccare questa persona? Non potrà più scriverti e non ne verrà informata.';

  @override
  String get unblockContact => 'Sblocca';

  @override
  String get contactBlocked => 'Bloccato';

  @override
  String get minute1 => '1 minuto';

  @override
  String get welcomeBack => 'Bentornato';

  @override
  String get minutes30 => '30 minuti';

  @override
  String get screenshotByYou => 'Hai fatto uno screenshot della chat';

  @override
  String screenshotByPeer(String name) {
    return '$name ha fatto uno screenshot della chat';
  }

  @override
  String get recordingByYou => 'Stai registrando lo schermo';

  @override
  String recordingByPeer(String name) {
    return '$name sta registrando lo schermo';
  }

  @override
  String get screenshotNotice => 'Avviso screenshot';

  @override
  String get screenshotNoticeDescription =>
      'Entrambe le parti vengono informate di screenshot e registrazioni';

  @override
  String get privacyPolicy => 'Informativa sulla privacy';

  @override
  String get legalSection => 'Note legali';

  @override
  String get identityTitle => 'Identità';

  @override
  String get identityVerified => 'Verificato';

  @override
  String get identityBadge => 'Sicuro';

  @override
  String get scanSafetyNumber => 'Scansiona il codice';

  @override
  String get safetyNumberScanHint =>
      'Punta la fotocamera sul numero di sicurezza del tuo contatto';

  @override
  String safetyNumberMatches(String name) {
    return 'I numeri coincidono — $name è verificato.';
  }

  @override
  String get safetyNumberDiffers => 'I numeri non coincidono.';

  @override
  String get safetyNumberDiffersHint =>
      'Qualcuno potrebbe intercettare questa conversazione. Non inviare nulla di riservato finché non lo verificate di persona.';

  @override
  String get safetyNumberNotRecognised =>
      'Questo non è un numero di sicurezza. Scansiona il codice che il tuo contatto mostra sotto il numero di sicurezza.';

  @override
  String get verifiedContact => 'verificato';

  @override
  String accountGone(String name) {
    return '$name non esiste più';
  }

  @override
  String get accountGoneCannotWrite =>
      'Questo account non esiste più: qui non si può più scrivere.';
}
