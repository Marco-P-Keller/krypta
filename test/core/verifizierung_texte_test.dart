import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/l10n/app_localizations.dart';

/// Die Texte rund um das Bestaetigen eines Kontakts, in allen sieben Sprachen.
///
/// Der Anlass: eine externe Durchsicht am 02.09.2026 bemaengelte, dass die
/// Oberflaeche „Bestaetigt" und „Sicher" nebeneinander zeigte, dass „Code
/// scannen" nicht sagt, WESSEN Code, und dass ein Nutzer „nicht bestaetigt"
/// fuer „unverschluesselt" halten koennte.
///
/// Der letzte Punkt ist der wichtigste und wird hier festgenagelt: der
/// Hinweis bei einem unbestaetigten Kontakt MUSS die Verschluesselung
/// erwaehnen. Sonst erschrickt jemand vor der falschen Sache.
void main() {
  const sprachen = ['de', 'en', 'es', 'fr', 'it', 'nl', 'pt'];

  Future<AppLocalizations> laden(String code) =>
      AppLocalizations.delegate.load(Locale(code));

  for (final code in sprachen) {
    group('Sprache $code', () {
      test('die vier Zustaende haben eigene, gefuellte Texte', () async {
        final l = await laden(code);
        final texte = <String, String>{
          'bestaetigt': l.identityKeyConfirmed,
          'nicht bestaetigt': l.identityNotConfirmed,
          'Schluessel geaendert': l.contactKeyChangedWarning,
          'blockiert': l.blockContact,
        };
        for (final e in texte.entries) {
          expect(e.value.trim(), isNotEmpty,
              reason: '${e.key} ist leer in $code');
        }
        expect(texte.values.toSet().length, texte.length,
            reason: 'zwei Zustaende teilen sich einen Text in $code: '
                '${texte.values.toList()}');
      });

      test('der Hinweis bei unbestaetigt nennt die Verschluesselung',
          () async {
        final l = await laden(code);
        final hinweis = l.identityNotConfirmedHint.toLowerCase();
        // In allen sieben Sprachen steckt der Wortstamm „crypt/chiffr/
        // versleutel/verschluessel" — geprueft wird der Stamm, nicht der
        // ganze Satz, damit eine Umformulierung den Test nicht bricht.
        const stamm = [
          'crypt',       // en: encrypted
          'crittograf',  // it: crittografati
          'chiffr',      // fr: chiffres
          'versleuteld', // nl: versleuteld
          'verschlüssel',// de: verschluesselt
          'cifrad',      // es/pt: cifrados / cifradas
        ];
        expect(stamm.any(hinweis.contains), isTrue,
            reason: 'in $code fehlt der Hinweis auf die Verschluesselung: '
                '$hinweis');
      });

      test('der Scan-Knopf nennt den Namen', () async {
        final l = await laden(code);
        expect(l.scanContactQr('Marco'), contains('Marco'),
            reason: 'ohne Namen bleibt offen, wessen Code gemeint ist');
      });

      test('die drei Entblock-Meldungen sind verschieden', () async {
        final l = await laden(code);
        final m = <String>[
          l.unblockedVerified('Marco'),
          l.unblockedUnverified('Marco'),
          l.unblockedKeyChanged('Marco'),
        ];
        for (final t in m) {
          expect(t, contains('Marco'));
        }
        expect(m.toSet().length, 3,
            reason: 'nach dem Entblocken muss ablesbar sein, was jetzt gilt');
      });

      test('bestaetigt und bereits-bestaetigt sind nicht derselbe Satz',
          () async {
        final l = await laden(code);
        expect(l.identityAlreadyConfirmed, isNot(equals(l.identityKeyConfirmed)),
            reason: 'der Dialog erklaert, WARUM keine Taste mehr da ist');
      });
    });
  }
}
