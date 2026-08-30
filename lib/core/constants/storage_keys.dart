/// Secure storage key namespaces.
///
/// Logical separation — each namespace protects a different secret category.
/// Even if an attacker reads raw storage, hashed values (codes, vault pw)
/// cannot be reversed to reveal the originals.
///
/// Namespaces:
///   krypta_id_*    — Identity keys (managed by KeyManager, never read here)
///   krypta_code_*  — Access codes (Argon2id hashed — not recoverable)
///   krypta_vault_* — Vault password (Argon2id hashed — not recoverable)
///   krypta_db_*    — Local database key (random bytes, managed by EncryptedLocalStore)
///   krypta_cfg_*   — Configuration flags (non-secret preferences)
abstract final class StorageKeys {
  // ── Identity keys (KeyManager) ────────────────────────────────────────────
  static const String identityPrivateKey = 'krypta_id_priv';
  static const String identityPublicKey  = 'krypta_id_pub';
  static const String preKeyPrivate      = 'krypta_id_prekey_priv';
  static const String preKeyPublic       = 'krypta_id_prekey_pub';

  // ── Access codes (Argon2id hashed — CodeStorage) ─────────────────────────
  static const String secretCode = 'krypta_code_secret';
  static const String deleteCode = 'krypta_code_delete';

  /// Altlast: der Code des ausgebauten Tarn-Messengers.
  ///
  /// Es gibt keinen Weg mehr, ihn zu setzen oder zu pruefen. Der Name steht
  /// nur noch hier, weil man einen Schluessel benennen koennen muss, um ihn zu
  /// loeschen — [LegacyCleanup] raeumt ihn beim ersten Start weg. Er bleibt
  /// ausserdem in [all], damit eine Notfall-Loeschung ihn auf einem Geraet
  /// erwischt, das noch nicht aufgeraeumt hat.
  static const String legacyDecoyCode = 'krypta_code_decoy';

  // ── Vault password (Argon2id hashed — VaultStorage) ──────────────────────
  static const String vaultPassword        = 'krypta_vault_hash';
  static const String vaultPasswordEnabled = 'krypta_vault_enabled';

  // ── Local database key (EncryptedLocalStore) ──────────────────────────────
  static const String databaseKey = 'krypta_db_key';
  /// Hardware-wrapped version of the database key.
  /// Present only when hardware binding (StrongBox/Secure Enclave) is active.
  /// The wrapping key never leaves the secure hardware module.
  static const String databaseKeyWrapped = 'krypta_db_key_hw';

  // ── Configuration / non-secret flags (SettingsStorage) ───────────────────
  static const String setupComplete       = 'krypta_cfg_setup';
  static const String biometricEnabled    = 'krypta_cfg_biometric';
  static const String screenshotProtection = 'krypta_cfg_screenshot';
  static const String userId              = 'krypta_cfg_userid';

  // ── Privacy mode (push vs polling) ──────────────────────────────────────
  static const String pushPrivacyMode = 'krypta_cfg_push_privacy';

  /// Ob das einmalige Aufraeumen der Altlasten gelaufen ist.
  ///
  /// Bewusst neutral benannt: ein Schluessel namens `..._decoy_purged` wuerde
  /// jedem, der den Schluesselbund liest, erzaehlen, dass diese App einmal
  /// einen Tarnmodus hatte — genau der Hinweis, den das Aufraeumen beseitigt.
  static const String legacyCleanupDone = 'krypta_cfg_legacy_cleanup';

  /// Die gewaehlte Anzeigesprache als reiner Sprachcode ('en', 'de', ...).
  static const String languageCode = 'krypta_cfg_language';

  // ── Receipt privacy (metadata minimization) ────────────────────────────
  /// Whether delivery confirmations are sent. Default: false (disabled).
  static const String deliveryReceiptsEnabled = 'krypta_cfg_delivery_receipts';
  /// Whether read receipts are sent. Default: false (disabled).
  static const String readReceiptsEnabled = 'krypta_cfg_read_receipts';

  // ── Vault fail tracking (persistent brute-force protection) ─────────────
  static const String vaultFailCount      = 'krypta_vault_fails';
  static const String vaultLastFailTime   = 'krypta_vault_lastfail';

  // -- Gemeinsames Praefix -------------------------------------------------

  /// Alles, was Krypta im Schluesselbund ablegt, faengt damit an.
  /// [SecureStorageService.hasResidualData] erkennt daran Reste einer
  /// frueheren Installation.
  static const String prefix = 'krypta_';

  /// Jeder Schluessel einzeln - Rueckfallebene, wenn `readAll()` scheitert.
  /// Neue Schluessel gehoeren hier mit hinein, sonst uebersieht die
  /// Rueckfallebene sie.
  static const List<String> all = [
    identityPrivateKey,
    identityPublicKey,
    preKeyPrivate,
    preKeyPublic,
    secretCode,
    legacyDecoyCode,
    deleteCode,
    vaultPassword,
    vaultPasswordEnabled,
    databaseKey,
    databaseKeyWrapped,
    setupComplete,
    biometricEnabled,
    screenshotProtection,
    userId,
    pushPrivacyMode,
    languageCode,
    deliveryReceiptsEnabled,
    readReceiptsEnabled,
    vaultFailCount,
    vaultLastFailTime,
  ];
}
