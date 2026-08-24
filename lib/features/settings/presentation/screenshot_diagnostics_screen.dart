import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../services/platform/platform_security_service.dart';

/// Geräte-Diagnose für die iOS-Maskierung von Screenshots und Aufnahmen.
///
/// Warum es diesen Bildschirm gibt: der Schutz hängt an einem
/// undokumentierten Verhalten von `isSecureTextEntry`. Die geschützte
/// Zeichenfläche wird nativ über einen festen Index in `sublayers` gesucht —
/// ab iOS 17 der erste, davor der letzte. Auf iOS 26.6 stimmt das nicht mehr,
/// die Verifikation fällt durch, und der Schutz schaltet sich (korrekt)
/// fail-closed ab. Nur schützt er dann nichts.
///
/// Welcher Index dort richtig wäre — oder ob Apple das Verhalten ganz
/// abgestellt hat — lässt sich am Schreibtisch nicht beantworten. Ohne diesen
/// Bildschirm bräuchte jeder Rateversuch einen eigenen TestFlight-Build von
/// rund 45 Minuten. Mit ihm reicht ein Build: jeden Kandidaten erzwingen, je
/// einen Screenshot machen, nachsehen welcher schwarz ist.
///
/// Der Bildschirm ist hinter `--dart-define=KRYPTA_DIAG=true` versteckt und
/// steckt in keinem normalen Build.
class ScreenshotDiagnosticsScreen extends StatefulWidget {
  const ScreenshotDiagnosticsScreen({super.key});

  /// Ob dieser Bildschirm in diesem Build überhaupt existiert.
  static const bool enabled = bool.fromEnvironment('KRYPTA_DIAG');

  @override
  State<ScreenshotDiagnosticsScreen> createState() =>
      _ScreenshotDiagnosticsScreenState();
}

class _ScreenshotDiagnosticsScreenState
    extends State<ScreenshotDiagnosticsScreen> {
  Map<String, dynamic>? _report;
  bool _loading = false;
  String? _lastAction;

  @override
  void initState() {
    super.initState();
    _runDiagnosis();
  }

  Future<void> _runDiagnosis() async {
    setState(() => _loading = true);
    final platform = context.read<PlatformSecurityService>();
    final report = await platform.diagnoseScreenshotMask();
    if (!mounted) return;
    setState(() {
      _report = report;
      _loading = false;
    });
  }

  Future<void> _force(int index) async {
    final platform = context.read<PlatformSecurityService>();
    final ok = await platform.forceSecureMaskCandidate(index);
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _lastAction = 'Kandidat $index wurde abgelehnt — die Prüfungen sind '
            'durchgefallen, die Maske ist wieder abgebaut.';
      });
      return;
    }
    setState(
        () => _lastAction = 'Kandidat $index eingebaut, prüfe ob er hält …');

    // Der native Watchdog prüft kurz nach dem Einbau noch einmal nach und
    // baut die Maske ab, wenn die Geometrie nicht stimmt — das passiert erst
    // nach rund 0,75 Sekunden. Stünde hier sofort „bestanden", ließe sich ein
    // Screenshot machen, während längst nichts mehr eingebaut ist, und der
    // Kandidat käme zu Unrecht als untauglich heraus.
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    final stillActive = await platform.refreshScreenshotProtectionState();
    if (!mounted) return;
    setState(() {
      _lastAction = stillActive
          ? 'Kandidat $index ist eingebaut und hält auch nach der '
              'Nachprüfung.\n\nJetzt einen Screenshot machen und in der '
              'Fotos-App nachsehen:\nschwarz = der Schutz greift, '
              'Inhalt sichtbar = er greift nicht.'
          : 'Kandidat $index hat den Einbau überstanden, wurde aber von der '
              'Nachprüfung wieder abgebaut. Ein Screenshot würde jetzt nichts '
              'aussagen.';
    });
  }

  /// Den Bericht als Text, zum Weiterreichen.
  String _reportAsText() {
    final r = _report;
    if (r == null) return '';
    final buffer = StringBuffer()
      ..writeln('Screenshot-Masken-Diagnose')
      ..writeln('iOS: ${r['iosVersion']}')
      ..writeln('Kill-Switch aktiv: ${r['killSwitch']}')
      ..writeln('Aufnahme läuft: ${r['isCaptured']}')
      ..writeln('Maske installiert: ${r['maskInstalled']}')
      ..writeln('Maske aktiv: ${r['maskActive']}')
      ..writeln('Standardwahl: Index ${r['defaultIndex']}, '
          'Ergebnis ${r['defaultReason']}')
      ..writeln('Sublayer gesamt: ${r['sublayerCount']}')
      ..writeln('Subviews: ${r['subviews']}')
      ..writeln('Nach der Diagnose wieder aktiv: ${r['restoredActive']}')
      ..writeln('');
    for (final c in (r['candidates'] as List? ?? const [])) {
      final m = c as Map;
      buffer.writeln('[${m['index']}] ${m['class']}');
      buffer.writeln('    Rahmen:    ${m['frame']}');
      buffer.writeln('    versteckt: ${m['hidden']}  '
          'Deckkraft: ${m['opacity']}  Sublayer: ${m['sublayers']}');
      buffer.writeln('    verifiziert: ${m['verifies']}  '
          '(${m['reason']})');
    }
    return buffer.toString();
  }

  Future<void> _copyReport() async {
    // Bewusst nicht ClipboardHelper.copyEphemeral: der Bericht enthält
    // Klassennamen und Rahmenmaße, nichts Vertrauliches — und er soll beim
    // Einfügen in eine Nachricht noch da sein, nicht nach 60 Sekunden
    // gelöscht.
    await Clipboard.setData(ClipboardData(text: _reportAsText()));
    if (!mounted) return;
    setState(() => _lastAction = 'Bericht in die Zwischenablage kopiert.');
  }

  @override
  Widget build(BuildContext context) {
    final r = _report;
    final candidates = (r?['candidates'] as List? ?? const []);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnose: Screenshot-Maske'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _runDiagnosis,
            tooltip: 'Neu messen',
          ),
          IconButton(
            icon: const Icon(Icons.copy),
            onPressed: r == null ? null : _copyReport,
            tooltip: 'Bericht kopieren',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (r == null || r.isEmpty)
                  const Text(
                    'Die Plattform liefert keinen Bericht. Auf Android und im '
                    'Simulator ist das erwartbar — die Maske gibt es nur auf '
                    'iOS-Geräten.',
                  )
                else ...[
                  _Section('Zustand', [
                    _Row('iOS', '${r['iosVersion']}'),
                    _Row('Kill-Switch', '${r['killSwitch']}'),
                    _Row('Aufnahme läuft', '${r['isCaptured']}'),
                    _Row('Maske installiert', '${r['maskInstalled']}'),
                    _Row('Maske aktiv', '${r['maskActive']}'),
                    _Row('Standardwahl',
                        'Index ${r['defaultIndex']} → ${r['defaultReason']}'),
                    _Row('Sublayer gesamt', '${r['sublayerCount']}'),
                    _Row('Subviews', '${r['subviews']}'),
                  ]),
                  const SizedBox(height: 8),
                  const Text(
                    'Kandidaten',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Jeder Sublayer wurde einmal wirklich eingebaut und durch '
                      'dieselben Prüfungen geschickt wie im Normalbetrieb. '
                      '„verifiziert" heißt nur: der Aufbau stimmt. Ob iOS den '
                      'Inhalt dann auch wirklich aus Aufnahmen ausschließt, '
                      'zeigt allein ein echter Screenshot.',
                    ),
                  ),
                  for (final c in candidates)
                    _CandidateCard(
                      data: c as Map,
                      onForce: () => _force(c['index'] as int),
                    ),
                ],
                if (_lastAction != null) ...[
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(_lastAction!),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Section(this.title, this.children);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  const _Row(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 150, child: Text(label)),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontFamily: 'monospace')),
          ),
        ],
      ),
    );
  }
}

class _CandidateCard extends StatelessWidget {
  final Map data;
  final VoidCallback onForce;
  const _CandidateCard({required this.data, required this.onForce});

  @override
  Widget build(BuildContext context) {
    final verifies = data['verifies'] == true;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  verifies ? Icons.check_circle : Icons.cancel,
                  color: verifies ? Colors.green : Colors.red,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '[${data['index']}] ${data['class']}',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Rahmen: ${data['frame']}\n'
              'versteckt: ${data['hidden']}   '
              'Deckkraft: ${data['opacity']}   '
              'Sublayer: ${data['sublayers']}\n'
              'Prüfung: ${data['reason']}',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton(
                onPressed: onForce,
                child: const Text('Diesen erzwingen'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
