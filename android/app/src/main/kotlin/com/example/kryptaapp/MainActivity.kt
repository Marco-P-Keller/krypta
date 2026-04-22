package com.example.kryptaapp

import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.security.keystore.StrongBoxUnavailableException
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class MainActivity : FlutterActivity() {
    private val CHANNEL = "krypta/security"
    private val HARDWARE_KEY_ALIAS = "krypta_hw_wrapping_key"
    private val GCM_TAG_LENGTH = 128

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Enable FLAG_SECURE by default — prevents screenshots, screen recording,
        // and task switcher preview. Can be toggled via MethodChannel if needed.
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE
        )

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "enableSecureFlag" -> {
                    window.setFlags(
                        WindowManager.LayoutParams.FLAG_SECURE,
                        WindowManager.LayoutParams.FLAG_SECURE
                    )
                    result.success(true)
                }
                "disableSecureFlag" -> {
                    window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    result.success(true)
                }
                "isStrongBoxAvailable" -> {
                    result.success(isStrongBoxAvailable())
                }
                "isHardwareKeyReady" -> {
                    result.success(isHardwareKeyReady())
                }
                "createHardwareBoundKey" -> {
                    try {
                        val created = createHardwareBoundKey()
                        result.success(created)
                    } catch (e: Exception) {
                        result.error("HW_KEY_CREATE_FAILED", e.message, null)
                    }
                }
                "wrapKey" -> {
                    val keyBytes = call.argument<ByteArray>("key")
                    if (keyBytes == null) {
                        result.error("INVALID_ARGS", "Missing 'key' argument", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val wrapped = wrapKey(keyBytes)
                        result.success(wrapped)
                    } catch (e: Exception) {
                        result.error("WRAP_FAILED", e.message, null)
                    }
                }
                "unwrapKey" -> {
                    val wrappedBytes = call.argument<ByteArray>("wrapped")
                    if (wrappedBytes == null) {
                        result.error("INVALID_ARGS", "Missing 'wrapped' argument", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val unwrapped = unwrapKey(wrappedBytes)
                        result.success(unwrapped)
                    } catch (e: Exception) {
                        result.error("UNWRAP_FAILED", e.message, null)
                    }
                }
                "deleteHardwareBoundKey" -> {
                    try {
                        deleteHardwareBoundKey()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("HW_KEY_DELETE_FAILED", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    // --- StrongBox Hardware Key Operations ---

    /// Check if the device supports StrongBox Keymaster (dedicated HSM).
    /// Requires API 28+ (Android 9). The actual availability depends on
    /// hardware — not all API 28+ devices have StrongBox.
    private fun isStrongBoxAvailable(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return false
        return try {
            // Attempt to create a test key with StrongBox — the only reliable
            // way to detect StrongBox, since there's no direct query API.
            val keyGen = KeyGenerator.getInstance(
                KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore"
            )
            keyGen.init(
                KeyGenParameterSpec.Builder(
                    "krypta_strongbox_probe",
                    KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
                )
                    .setKeySize(256)
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setIsStrongBoxBacked(true)
                    .build()
            )
            keyGen.generateKey()
            // Clean up probe key
            val ks = KeyStore.getInstance("AndroidKeyStore")
            ks.load(null)
            ks.deleteEntry("krypta_strongbox_probe")
            true
        } catch (e: StrongBoxUnavailableException) {
            false
        } catch (e: Exception) {
            false
        }
    }

    /// Check if a hardware-bound wrapping key already exists.
    private fun isHardwareKeyReady(): Boolean {
        return try {
            val ks = KeyStore.getInstance("AndroidKeyStore")
            ks.load(null)
            ks.containsAlias(HARDWARE_KEY_ALIAS)
        } catch (e: Exception) {
            false
        }
    }

    /// Create a non-extractable AES-256-GCM key in StrongBox.
    ///
    /// This key never leaves the hardware security module. It's used to
    /// wrap (encrypt) the database encryption key, binding it to this
    /// specific device's secure hardware.
    ///
    /// Returns true if created successfully.
    private fun createHardwareBoundKey(): Boolean {
        // Don't recreate if already exists
        if (isHardwareKeyReady()) return true

        val keyGen = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore"
        )
        val builder = KeyGenParameterSpec.Builder(
            HARDWARE_KEY_ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
        )
            .setKeySize(256)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)

        // Use StrongBox if available (API 28+)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            try {
                builder.setIsStrongBoxBacked(true)
            } catch (e: Exception) {
                // Fall back to TEE-backed key (still hardware, not StrongBox)
            }
        }

        keyGen.init(builder.build())
        keyGen.generateKey()
        return true
    }

    /// Wrap (encrypt) a key using the hardware-bound AES-GCM key.
    ///
    /// Returns [12-byte IV || ciphertext+tag] — the IV is needed for
    /// unwrapping and is prepended to the output.
    private fun wrapKey(plainKey: ByteArray): ByteArray {
        val ks = KeyStore.getInstance("AndroidKeyStore")
        ks.load(null)
        val secretKey = ks.getKey(HARDWARE_KEY_ALIAS, null) as SecretKey

        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, secretKey)

        val iv = cipher.iv // 12 bytes for GCM
        val encrypted = cipher.doFinal(plainKey)

        // Prepend IV so the caller doesn't need to store it separately
        return iv + encrypted
    }

    /// Unwrap (decrypt) a key using the hardware-bound AES-GCM key.
    ///
    /// Input format: [12-byte IV || ciphertext+tag]
    private fun unwrapKey(wrapped: ByteArray): ByteArray {
        if (wrapped.size < 13) {
            throw IllegalArgumentException("Wrapped key too short")
        }

        val iv = wrapped.copyOfRange(0, 12)
        val encrypted = wrapped.copyOfRange(12, wrapped.size)

        val ks = KeyStore.getInstance("AndroidKeyStore")
        ks.load(null)
        val secretKey = ks.getKey(HARDWARE_KEY_ALIAS, null) as SecretKey

        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, secretKey, GCMParameterSpec(GCM_TAG_LENGTH, iv))
        return cipher.doFinal(encrypted)
    }

    /// Delete the hardware-bound key (on emergency wipe).
    private fun deleteHardwareBoundKey() {
        val ks = KeyStore.getInstance("AndroidKeyStore")
        ks.load(null)
        if (ks.containsAlias(HARDWARE_KEY_ALIAS)) {
            ks.deleteEntry(HARDWARE_KEY_ALIAS)
        }
        // Also clean up any leftover probe key
        if (ks.containsAlias("krypta_strongbox_probe")) {
            ks.deleteEntry("krypta_strongbox_probe")
        }
    }
}
