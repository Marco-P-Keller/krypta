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
  static const String decoyCode  = 'krypta_code_decoy';
  static const String deleteCode = 'krypta_code_delete';

  // ── Vault password (Argon2id hashed — VaultStorage) ──────────────────────
  static const String vaultPassword        = 'krypta_vault_hash';
  static const String vaultPasswordEnabled = 'krypta_vault_enabled';

  // ── Local database key (EncryptedLocalStore) ──────────────────────────────
  static const String databaseKey = 'krypta_db_key';

  // ── Configuration / non-secret flags (SettingsStorage) ───────────────────
  static const String setupComplete       = 'krypta_cfg_setup';
  static const String biometricEnabled    = 'krypta_cfg_biometric';
  static const String screenshotProtection = 'krypta_cfg_screenshot';
  static const String userId              = 'krypta_cfg_userid';
}
