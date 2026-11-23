import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../utils/format_euros.dart';

// ══════════════════════════════════════════════════════════════════════════════
//  MiseManuelleDialog — B1-T12 / LOT 2-B
//
//  Remplace le `Slider` de `bet_bottom_sheet` par une SAISIE NUMÉRIQUE.
//
//  MESURES QUI ONT GUIDÉ CETTE FENÊTRE :
//    • Le `Slider` imposait `min: 2, max: 200` — une commodité d'interface,
//      PAS une règle métier. Vérifié : aucune borne équivalente dans le
//      modèle `UserPrediction`/`TrackedCourse` ni dans `PmuProvider`. Le seul
//      seuil réel du projet est « mise strictement positive » (`> 0`). Les
//      anciennes bornes ne sont donc PAS reportées : une mise de 1 € ou de
//      500 € est acceptée.
//    • La virgule décimale n'était gérée par AUCUN parcours de mise du
//      projet (seules des cotes PMU la normalisaient). Elle l'est ici, comme
//      au lot 2-A pour le gain manuel.
//
//  CE QUE CETTE FENÊTRE NE FAIT PAS :
//    • elle n'écrit rien : elle rend un `double?` à l'appelant ;
//    • elle ne touche ni aux combinaisons, ni aux règles Gagnant/Placé, ni aux
//      gains PMU. La mise rendue est ensuite utilisée EXACTEMENT comme avant.
//
//  ANNULATION : `Navigator.pop(context, null)` — l'appelant n'écrit rien,
//  donc la mise précédente est intacte.
// ══════════════════════════════════════════════════════════════════════════════

class MiseManuelleDialog extends StatefulWidget {
  /// Mise actuelle, affichée en valeur initiale (éditable).
  final double montantActuel;

  const MiseManuelleDialog({super.key, required this.montantActuel});

  /// ★ LOT 2-B — RÈGLE DE LECTURE, **PUBLIQUE ET SANS ÉTAT**.
  ///
  /// Elle est volontairement hors de l'`State` : un test peut l'appeler
  /// directement, il n'a donc AUCUN besoin de la réécrire. (Le lot 2-A avait
  /// laissé sa règle privée ; son test la dupliquait dans un helper, ce qui
  /// prouve la copie et non le code. Ce lot-ci ne refait pas cette erreur.)
  ///
  /// Virgule ET point acceptés (`10`, `10,50`, `10.50`). Aucun nettoyage
  /// deviné : on refuse plutôt que d'interpréter au hasard.
  static double? lireMontant(String saisie) {
    final brut = saisie.trim();
    if (brut.isEmpty) return null;
    final v = double.tryParse(brut.replaceAll(',', '.'));
    if (v == null) return null;
    // Contrainte MÉTIER réelle, la seule mesurée dans le projet : une mise
    // doit être strictement positive. Zéro et négatif sont donc refusés.
    // (Aucune borne haute : le Slider en imposait une, ce n'était pas métier.)
    if (v <= 0) return null;
    // Arrondi au centime : une mise ne se saisit pas au dix-millième.
    final centimes = (v * 100).round();
    return centimes / 100;
  }

  /// Texte de pré-remplissage : « 10 » si entier, « 10.50 » sinon.
  /// Jamais de « 10.0 » parasite, jamais d'arrondi de la valeur affichée.
  static String texteInitial(double montant) =>
      montant == montant.truncateToDouble()
          ? montant.toStringAsFixed(0)
          : montant.toStringAsFixed(2);

  @override
  State<MiseManuelleDialog> createState() => _MiseManuelleDialogState();
}

class _MiseManuelleDialogState extends State<MiseManuelleDialog> {
  late final TextEditingController _ctrl;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
      text: MiseManuelleDialog.texteInitial(widget.montantActuel),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _valider() {
    final v = MiseManuelleDialog.lireMontant(_ctrl.text);
    if (v == null) {
      setState(() => _erreur =
          'Montant invalide : saisissez une valeur strictement positive (10, 10,50 ou 10.50)');
      return;
    }
    Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF0A1628),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text(
        'Montant de la mise',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _ctrl,
            autofocus: true,
            // C'est ce réglage qui fait apparaître la VIRGULE sur les claviers
            // qui la proposent (le Slider n'avait aucun clavier).
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              // Chiffres + virgule + point. Volontairement permissif sur le
              // séparateur : la validation métier se fait dans `lireMontant`,
              // pas dans le formateur — un formateur trop strict empêcherait
              // de TAPER la virgule avant de pouvoir la valider.
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            style: const TextStyle(color: Colors.white, fontSize: 22),
            decoration: InputDecoration(
              labelText: 'Mise (€)',
              labelStyle: const TextStyle(color: Colors.white38),
              prefixText: '€ ',
              prefixStyle: const TextStyle(color: Color(0xFFFFD700)),
              helperText: 'Virgule ou point acceptés',
              helperStyle: const TextStyle(color: Colors.white30, fontSize: 11),
              errorText: _erreur,
              errorMaxLines: 2,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF2E7D52)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFFFD700)),
              ),
            ),
            onSubmitted: (_) => _valider(),
          ),
          const SizedBox(height: 10),
          // Rappel de la mise actuelle : l'annulation doit être un choix
          // conscient, pas une perte silencieuse.
          Text(
            'Mise actuelle : ${fmtEuros(widget.montantActuel)} €',
            style: const TextStyle(color: Colors.white30, fontSize: 11),
          ),
        ],
      ),
      actions: [
        // ── Annuler : rend `null`, donc AUCUNE écriture côté appelant.
        TextButton(
          onPressed: () => Navigator.pop(context),
          child:
              const Text('Annuler', style: TextStyle(color: Colors.white38)),
        ),
        // ── OK : valide et rend le montant.
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2E7D52),
            foregroundColor: Colors.white,
          ),
          onPressed: _valider,
          child: const Text('OK'),
        ),
      ],
    );
  }
}
