import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:equatable/equatable.dart';
import '../../../../core/constants/app_constants.dart';

/// Trust state for a contact's identity key.
///
/// Security model:
/// - [unverified]: Key received from server, not yet independently verified.
///   Messages can be sent but user should be warned.
/// - [verified]: Key independently verified via QR code or safety number comparison.
/// - [keyChanged]: Key has changed since last verification — sending is BLOCKED
///   until user explicitly accepts or re-verifies.
/// - [blocked]: User explicitly blocked this contact — no messages sent/received.
enum TrustState {
  unverified,
  verified,
  keyChanged,
  blocked,
}

/// Ob der Kontakt zustande gekommen ist — getrennt von [TrustState].
///
/// [TrustState] beschreibt die *kryptografische* Vertrauenslage, dieser Typ
/// die Bekanntschaft. Das sind zwei Achsen: ein Fremder kann kryptografisch
/// einwandfrei sein. Beides in einen Typ zu legen würde die Logik um
/// `keyChanged` und `blocked` brechen, und genau die schützt vor MITM.
enum ContactRequestState {
  /// Angenommen — beide Seiten dürfen schreiben.
  established,

  /// Ich habe angefragt und warte. Ob die Gegenseite abgelehnt oder blockiert
  /// hat, erfahre ich nicht — beides sähe von hier aus gleich aus.
  outgoing,

  /// Jemand hat mich angefragt, ich entscheide.
  incoming,

  /// Ich habe abgelehnt. Die Gegenseite darf erneut anfragen, begrenzt durch
  /// [Contact.declineCount].
  declined,
}

/// Method used to verify a contact's identity.
enum VerificationMethod {
  qrCode,
  safetyNumber,
  manual,
}

class Contact extends Equatable {
  final String id;
  final String displayName;
  final Uint8List publicKey;
  final DateTime addedAt;

  /// Cryptographic trust state — determines if sending is allowed.
  final TrustState trustState;

  /// Ob der Kontakt zustande gekommen ist. Siehe [ContactRequestState].
  final ContactRequestState requestState;

  /// Wie oft ich Anfragen von diesem Absender abgelehnt habe.
  ///
  /// Bremst wiederholtes Anklopfen: ab [ContactRequestPolicy.maxDeclines]
  /// kommt von dieser ID nichts mehr durch. Wird zurückgesetzt, wenn ich die
  /// Person selbst hinzufüge — der Zähler bremst Fremde, nicht mich.
  final int declineCount;

  /// When the contact was last verified (null if never verified).
  final DateTime? verifiedAt;

  /// How the contact was verified.
  final VerificationMethod? verificationMethod;

  /// SHA-256 fingerprint of the current public key for display/comparison.
  final String keyFingerprint;

  /// Full SHA-256 hex fingerprint confirmed during QR verification.
  /// Null if never verified via QR. Used to detect post-verification key changes.
  final String? verifiedFingerprint;

  /// Previous public key — set when a key change is detected.
  /// Null if key has never changed.
  final Uint8List? previousPublicKey;

  /// The very first identity key observed for this contact (TOFU baseline).
  /// Set once on first contact add and never changed. Used to detect if the
  /// contact's identity has ever changed from the original trust anchor.
  final Uint8List? firstSeenIdentityKey;

  /// When the identity key last changed. Null if it has never changed.
  final DateTime? lastKeyChangeAt;

  /// Version of the safety number algorithm used for the last verification.
  /// Null if never verified. Used to prompt re-verification when the
  /// algorithm is upgraded.
  final int? safetyNumberVersion;

  /// Total number of key changes observed for this contact.
  /// Useful for risk assessment — frequent key changes may indicate compromise.
  final int keyChangeCount;

  /// Last epoch verified via Key Transparency log.
  /// Null if transparency has never been checked for this contact.
  final int? lastVerifiedEpoch;

  /// Whether the Key Transparency chain has been verified consistent.
  /// False if a split-view or chain break was detected.
  final bool transparencyVerified;

  Contact({
    required this.id,
    required this.displayName,
    required this.publicKey,
    required this.addedAt,
    this.trustState = TrustState.unverified,
    // Wer selbst hinzufügt, hat zugestimmt — der Standard ist deshalb
    // `established`, nicht „offene Anfrage".
    this.requestState = ContactRequestState.established,
    this.declineCount = 0,
    this.verifiedAt,
    this.verificationMethod,
    this.verifiedFingerprint,
    this.previousPublicKey,
    this.firstSeenIdentityKey,
    this.lastKeyChangeAt,
    this.safetyNumberVersion,
    this.keyChangeCount = 0,
    this.lastVerifiedEpoch,
    this.transparencyVerified = false,
  }) : keyFingerprint = _computeFingerprint(publicKey);

  /// For deserialization — fingerprint is provided, not computed.
  const Contact._internal({
    required this.id,
    required this.displayName,
    required this.publicKey,
    required this.addedAt,
    required this.trustState,
    required this.keyFingerprint,
    this.requestState = ContactRequestState.established,
    this.declineCount = 0,
    this.verifiedAt,
    this.verificationMethod,
    this.verifiedFingerprint,
    this.previousPublicKey,
    this.firstSeenIdentityKey,
    this.lastKeyChangeAt,
    this.safetyNumberVersion,
    this.keyChangeCount = 0,
    this.lastVerifiedEpoch,
    this.transparencyVerified = false,
  });

  static String _computeFingerprint(Uint8List key) {
    final hash = crypto.sha256.convert(key);
    return hash.bytes
        .take(8)
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(':');
  }

  /// Full SHA-256 hex fingerprint for QR verification payloads.
  static String computeFullFingerprint(Uint8List key) {
    final hash = crypto.sha256.convert(key);
    return hash.bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  String get publicKeyBase64 => base64Encode(publicKey);
  String get shortId => id.length > 8 ? '${id.substring(0, 8)}...' : id;
  bool get hasKeyChanged => trustState == TrustState.keyChanged;
  bool get isVerified => trustState == TrustState.verified;
  bool get isBlocked => trustState == TrustState.blocked;

  /// Whether sending messages to this contact is allowed.
  ///
  /// Gesperrt bei Schlüsselwechsel (MITM-Schutz), bei ausdrücklicher
  /// Blockierung — und solange die Kontaktanfrage nicht angenommen ist.
  /// Die Anfrage selbst läuft an dieser Sperre vorbei, über einen eigenen Weg.
  bool get canSendMessages =>
      trustState != TrustState.keyChanged &&
      trustState != TrustState.blocked &&
      requestState == ContactRequestState.established;

  /// Ob dieser Kontakt eine unbeantwortete Anfrage an mich ist.
  bool get isIncomingRequest =>
      requestState == ContactRequestState.incoming;

  /// Ob ich auf eine Antwort warte.
  bool get isOutgoingRequest =>
      requestState == ContactRequestState.outgoing;

  /// Whether this contact's verification is stale (>90 days old).
  /// Returns false if never verified — only applies to verified contacts.
  /// Used to prompt periodic re-verification for long-lived contacts.
  bool get isVerificationStale =>
      isVerified &&
      verifiedAt != null &&
      DateTime.now().difference(verifiedAt!) > AppConstants.verificationMaxAge;

  Contact copyWith({
    String? displayName,
    Uint8List? publicKey,
    TrustState? trustState,
    ContactRequestState? requestState,
    int? declineCount,
    Object? verifiedAt = _sentinel,
    Object? verificationMethod = _sentinel,
    Object? verifiedFingerprint = _sentinel,
    Object? previousPublicKey = _sentinel,
    Object? firstSeenIdentityKey = _sentinel,
    Object? lastKeyChangeAt = _sentinel,
    Object? safetyNumberVersion = _sentinel,
    int? keyChangeCount,
    Object? lastVerifiedEpoch = _sentinel,
    bool? transparencyVerified,
  }) {
    final newPublicKey = publicKey ?? this.publicKey;
    return Contact._internal(
      id: id,
      displayName: displayName ?? this.displayName,
      publicKey: newPublicKey,
      addedAt: addedAt,
      trustState: trustState ?? this.trustState,
      requestState: requestState ?? this.requestState,
      declineCount: declineCount ?? this.declineCount,
      keyFingerprint: publicKey != null
          ? _computeFingerprint(newPublicKey)
          : keyFingerprint,
      verifiedAt: verifiedAt == _sentinel
          ? this.verifiedAt
          : verifiedAt as DateTime?,
      verificationMethod: verificationMethod == _sentinel
          ? this.verificationMethod
          : verificationMethod as VerificationMethod?,
      verifiedFingerprint: verifiedFingerprint == _sentinel
          ? this.verifiedFingerprint
          : verifiedFingerprint as String?,
      previousPublicKey: previousPublicKey == _sentinel
          ? this.previousPublicKey
          : previousPublicKey as Uint8List?,
      firstSeenIdentityKey: firstSeenIdentityKey == _sentinel
          ? this.firstSeenIdentityKey
          : firstSeenIdentityKey as Uint8List?,
      lastKeyChangeAt: lastKeyChangeAt == _sentinel
          ? this.lastKeyChangeAt
          : lastKeyChangeAt as DateTime?,
      safetyNumberVersion: safetyNumberVersion == _sentinel
          ? this.safetyNumberVersion
          : safetyNumberVersion as int?,
      keyChangeCount: keyChangeCount ?? this.keyChangeCount,
      lastVerifiedEpoch: lastVerifiedEpoch == _sentinel
          ? this.lastVerifiedEpoch
          : lastVerifiedEpoch as int?,
      transparencyVerified:
          transparencyVerified ?? this.transparencyVerified,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'displayName': displayName,
        'publicKey': base64Encode(publicKey),
        'addedAt': addedAt.millisecondsSinceEpoch,
        'trustState': trustState.index,
        'requestState': requestState.index,
        'declineCount': declineCount,
        if (verifiedAt != null)
          'verifiedAt': verifiedAt!.millisecondsSinceEpoch,
        if (verificationMethod != null)
          'verificationMethod': verificationMethod!.index,
        if (verifiedFingerprint != null)
          'verifiedFingerprint': verifiedFingerprint,
        if (previousPublicKey != null)
          'prevPubKey': base64Encode(previousPublicKey!),
        if (firstSeenIdentityKey != null)
          'firstSeenKey': base64Encode(firstSeenIdentityKey!),
        if (lastKeyChangeAt != null)
          'lastKeyChangeAt': lastKeyChangeAt!.millisecondsSinceEpoch,
        if (safetyNumberVersion != null)
          'snVersion': safetyNumberVersion,
        'keyChangeCount': keyChangeCount,
        if (lastVerifiedEpoch != null)
          'ktEpoch': lastVerifiedEpoch,
        'ktVerified': transparencyVerified,
      };

  factory Contact.fromMap(Map<String, dynamic> map) {
    // Migration: old format used 'verified' int flag
    TrustState state;
    if (map.containsKey('trustState')) {
      state = TrustState.values[map['trustState'] as int];
    } else {
      state = (map['verified'] as int?) == 1
          ? TrustState.verified
          : TrustState.unverified;
    }

    // Migration: gespeicherte Kontakte aus der Zeit vor den Kontaktanfragen
    // tragen das Feld nicht. Sie gelten als angenommen — alles andere würde
    // laufende Chats nach dem Update in eine offene Anfrage verwandeln, und
    // niemand könnte mehr schreiben.
    final requestState = map.containsKey('requestState')
        ? ContactRequestState.values[map['requestState'] as int]
        : ContactRequestState.established;

    return Contact(
      id: map['id'] as String,
      displayName: map['displayName'] as String,
      publicKey: base64Decode(map['publicKey'] as String),
      addedAt: DateTime.fromMillisecondsSinceEpoch(map['addedAt'] as int),
      trustState: state,
      requestState: requestState,
      declineCount: (map['declineCount'] as int?) ?? 0,
      verifiedAt: map['verifiedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['verifiedAt'] as int)
          : null,
      verificationMethod: map['verificationMethod'] != null
          ? VerificationMethod.values[map['verificationMethod'] as int]
          : null,
      verifiedFingerprint: map['verifiedFingerprint'] as String?,
      previousPublicKey: map['prevPubKey'] != null
          ? base64Decode(map['prevPubKey'] as String)
          : null,
      firstSeenIdentityKey: map['firstSeenKey'] != null
          ? base64Decode(map['firstSeenKey'] as String)
          : null,
      lastKeyChangeAt: map['lastKeyChangeAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['lastKeyChangeAt'] as int)
          : null,
      safetyNumberVersion: map['snVersion'] as int?,
      keyChangeCount: (map['keyChangeCount'] as int?) ?? 0,
      lastVerifiedEpoch: map['ktEpoch'] as int?,
      transparencyVerified: (map['ktVerified'] as bool?) ?? false,
    );
  }

  @override
  List<Object?> get props => [id];
}

const _sentinel = Object();
