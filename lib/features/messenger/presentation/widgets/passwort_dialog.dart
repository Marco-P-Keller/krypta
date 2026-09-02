import 'package:flutter/material.dart';

/// Das Geruest der beiden Passwortdialoge — „Nachricht sperren" beim Absender
/// und „Passwort erforderlich" beim Empfaenger.
///
/// Der Anlass: Daniel meldet aus Build 98, dass der Abbrechen-Knopf im
/// Sperren-Dialog auf dem Telefon seines Kollegen ueber dem Passwortfeld
/// liegt, waehrend auf seinem eigenen alles sitzt. Die Ursache liegt nicht am
/// Dialoginhalt, sondern in AlertDialog selbst. Dessen eigene Doku sagt es:
/// „If the content is too large to fit on the screen vertically, the dialog
/// will display the title and actions, and let the content overflow."
/// Der Inhalt wird also nicht gekuerzt, sondern **ueber die Knopfzeile
/// gemalt** — genau das gemeldete Bild.
///
/// Eng wird es aus drei Gruenden, die sich addieren und von Geraet zu Geraet
/// verschieden ausfallen: ein niedrigerer Bildschirm, die Tastatur (beide
/// Felder haben `autofocus`, sie ist also sofort da) und eine groessere
/// Systemschrift. Auf einem hohen Geraet mit Standardschrift bleibt genug
/// Luft, deshalb sieht Daniel nichts.
///
/// Zwei Stellen sind es, die nicht mitgehen:
///   1. **Senkrecht** — `scrollable: true` legt Titel und Inhalt in einen
///      Scrollbereich. Die Knopfzeile bleibt fest darunter stehen und kann
///      nicht mehr ueberdeckt werden.
///   2. **Waagerecht** — der Titeltext lag frei in einer `Row` neben dem
///      Symbol. Ein `Text` schrumpft dort nicht, also lief er bei langer
///      Uebersetzung oder grosser Schrift nach rechts heraus. `Expanded`
///      laesst ihn stattdessen umbrechen.
class PasswortDialog extends StatelessWidget {
  const PasswortDialog({
    super.key,
    required this.symbol,
    required this.symbolFarbe,
    required this.symbolGroesse,
    required this.titel,
    required this.hinweis,
    required this.feld,
    required this.aktionen,
  });

  final IconData symbol;
  final Color symbolFarbe;
  final double symbolGroesse;
  final String titel;
  final String hinweis;

  /// Das Passwortfeld. Bleibt beim Aufrufer, weil Beschriftung, Fehlertext
  /// und das Verhalten bei Enter sich zwischen den beiden Dialogen
  /// unterscheiden.
  final Widget feld;

  final List<Widget> aktionen;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      // Ohne das laeuft der Inhalt bei wenig Hoehe ueber die Knoepfe.
      scrollable: true,
      title: Row(
        children: [
          Icon(symbol, color: symbolFarbe, size: symbolGroesse),
          const SizedBox(width: 10),
          // Umbrechen statt herauslaufen.
          Expanded(child: Text(titel)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(hinweis),
          const SizedBox(height: 16),
          feld,
        ],
      ),
      actions: aktionen,
    );
  }
}
