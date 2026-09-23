import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_constants.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/firebase/auth_service.dart';
import '../../../services/storage/secure_storage_service.dart';
import '../../../security/key_management/key_manager.dart';
import '../../../services/firebase/firestore_service.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';

class SetupScreen extends StatefulWidget {
  final VoidCallback onSetupComplete;
  const SetupScreen({super.key, required this.onSetupComplete});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen>
    with SingleTickerProviderStateMixin {
  final _controllers = [
    TextEditingController(),
    TextEditingController(),
  ];
  late final AnimationController _progressCtrl;
  bool _isLoading = false;
  int _step = 0;

  @override
  void initState() {
    super.initState();
    _progressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
      value: 1 / 2,
    );
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    _progressCtrl.dispose();
    super.dispose();
  }

  String? _validateCode(String? v) {
    final l10n = AppLocalizations.of(context)!;
    if (v == null || v.isEmpty) return l10n.fieldRequired;
    if (v.length < AppConstants.minCodeLength) {
      return l10n.codeMinDigits(AppConstants.minCodeLength);
    }
    if (!RegExp(r'^\d+$').hasMatch(v)) return l10n.codeDigitsOnly;
    return null;
  }

  void _next() {
    if (_validateCode(_controllers[_step].text) != null) return;

    // Prevent identical secret and delete codes — CodeDetector checks delete
    // first, so a collision would make the secret code permanently unreachable.
    if (_step == 1 && _controllers[1].text == _controllers[0].text) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.deleteCodeMustDiffer),
        ),
      );
      return;
    }

    if (_step < 1) {
      setState(() => _step++);
      _progressCtrl.animateTo((_step + 1) / 2);
    } else {
      _completeSetup();
    }
  }

  void _back() {
    if (_step > 0) {
      setState(() => _step--);
      _progressCtrl.animateTo((_step + 1) / 2);
    }
  }

  /// Den Taschenrechner ueberspringen.
  ///
  /// Daniels Liste vom 22.09.2026: „Die Einrichtung muss übersprungen werden
  /// können. TR kann später jederzeit über die Einstellungen eingerichtet
  /// bzw. aktiviert werden." Es entstehen dabei **keine** Codes — weder ein
  /// Geheimcode noch ein Loeschcode. Ein Code ohne Rechner waere ein
  /// Schluessel ohne Tuer, und beim spaeteren Einschalten wird er ohnehin neu
  /// vergeben.
  ///
  /// Das Konto entsteht trotzdem: Anmeldung, Schluesselpaar und
  /// Veroeffentlichung sind der Teil, ohne den niemand schreiben kann.
  void _ueberspringen() => _completeSetup(mitRechner: false);

  Future<void> _completeSetup({bool mitRechner = true}) async {
    setState(() => _isLoading = true);
    try {
      final storage = context.read<SecureStorageService>();
      final auth = context.read<AuthService>();
      final keyManager = context.read<KeyManager>();
      final firestore = context.read<FirestoreService>();

      final user = await auth.signInAnonymously();
      if (user == null) throw Exception('Auth failed');

      final keyPair = await keyManager.getOrCreateIdentityKeyPair();
      await firestore.registerPublicKey(
        userId: user.uid,
        publicKeyBase64: keyPair.publicKeyBase64,
      );

      await Future.wait([
        if (mitRechner) storage.saveSecretCode(_controllers[0].text),
        if (mitRechner) storage.saveDeleteCode(_controllers[1].text),
        // Die Wahl wird immer geschrieben, auch das Ja. Der Schluessel gilt
        // sonst als „nie gefragt" und faellt auf die Vorgabe zurueck, die
        // ihrerseits Ja heisst — richtig, aber aus dem falschen Grund.
        storage.setCalculatorLockEnabled(mitRechner),
        storage.saveUserId(user.uid),
        storage.markSetupComplete(),
      ]);

      if (mounted) widget.onSetupComplete();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.setupFailed)),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Aus `static const` zu einer Methode geworden: Titel und Untertitel
  /// kommen jetzt aus der Übersetzung und brauchen deshalb den context.
  /// Symbol und Farbe bleiben fest.
  static List<({IconData icon, Color color, String title, String subtitle})>
      _stepData(AppLocalizations l10n) => [
            (
              icon: Icons.lock_outline_rounded,
              color: AppColors.accent,
              title: l10n.secretCodeLabel,
              subtitle: l10n.setupSecretCodeSubtitle,
            ),
            (
              icon: Icons.delete_forever_outlined,
              color: AppColors.destructive,
              title: l10n.deleteCodeLabel,
              subtitle: l10n.setupDeleteCodeSubtitle,
            ),
          ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final step = _stepData(AppLocalizations.of(context)!)[_step];

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      body: SafeArea(
        child: Column(
          children: [
            // Progress bar
            AnimatedBuilder(
              animation: _progressCtrl,
              builder: (context, child) => LinearProgressIndicator(
                value: _progressCtrl.value,
                backgroundColor:
                    isDark ? AppColors.surfaceElevatedDark : AppColors.surfaceElevatedLight,
                color: step.color,
                minHeight: 2,
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.screenPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: AppSpacing.xxl),

                    // Icon
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Container(
                        key: ValueKey(_step),
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: step.color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                        ),
                        child: Icon(step.icon, color: step.color, size: 32),
                      ),
                    ),

                    const SizedBox(height: AppSpacing.lg),

                    // Title
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: Text(
                        key: ValueKey('title$_step'),
                        step.title,
                        style:
                            Theme.of(context).textTheme.headlineLarge?.copyWith(
                                  color: isDark
                                      ? AppColors.textPrimaryDark
                                      : AppColors.textPrimaryLight,
                                ),
                      ),
                    ),

                    const SizedBox(height: AppSpacing.sm),

                    // Subtitle
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: Text(
                        key: ValueKey('sub$_step'),
                        step.subtitle,
                        style:
                            Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  color: isDark
                                      ? AppColors.textSecondaryDark
                                      : AppColors.textSecondaryLight,
                                  height: 1.5,
                                ),
                      ),
                    ),

                    // Freiwillig, und das gehoert hierher und nicht nur ins
                    // Tutorial: wer das Tutorial weggewischt hat, steht sonst
                    // vor einer Maske, die aussieht, als gaebe es keinen Weg
                    // daran vorbei.
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      AppLocalizations.of(context)!.setupOptionalHint,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: isDark
                                ? AppColors.textTertiaryDark
                                : AppColors.textTertiaryLight,
                            height: 1.4,
                          ),
                    ),

                    const SizedBox(height: AppSpacing.xl),

                    // PIN input
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: TextFormField(
                        key: ValueKey('input$_step'),
                        controller: _controllers[_step],
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(
                              AppConstants.maxCodeLength),
                        ],
                        obscureText: true,
                        autofocus: true,
                        textAlign: TextAlign.center,
                        onFieldSubmitted: (_) => _next(),
                        style: Theme.of(context)
                            .textTheme
                            .displayMedium
                            ?.copyWith(
                              letterSpacing: 16,
                              color: isDark
                                  ? AppColors.textPrimaryDark
                                  : AppColors.textPrimaryLight,
                            ),
                        decoration: InputDecoration(
                          counterText: '',
                          hintText: '• • • • •',
                          hintStyle: TextStyle(
                            color: isDark
                                ? AppColors.textTertiaryDark
                                : AppColors.textTertiaryLight,
                            fontSize: 28,
                            letterSpacing: 12,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Navigation
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenPadding,
                  AppSpacing.md,
                  AppSpacing.screenPadding,
                  AppSpacing.lg),
              child: Row(
                children: [
                  if (_step > 0)
                    TextButton(
                      onPressed: _isLoading ? null : _back,
                      child: Text(AppLocalizations.of(context)!.back),
                    )
                  else
                    TextButton(
                      onPressed: _isLoading ? null : _ueberspringen,
                      child: Text(AppLocalizations.of(context)!.skipSetup),
                    ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _isLoading ? null : _next,
                    style: FilledButton.styleFrom(
                      backgroundColor: step.color,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(120, 52),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppSpacing.radiusMd),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        // Stand hier einmal fest verdrahtet auf Englisch,
                        // mitten in einer App mit sieben Sprachen.
                        : Text(_step < 1
                            ? AppLocalizations.of(context)!.setupContinue
                            : AppLocalizations.of(context)!.setupComplete),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
