import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ══════════════════════════════════════════════════════════════════════════════
//  GainManuelDialog — B1-T12 / étape 2 (lot 2-A)
//
//  Saisie NUMÉRIQUE du gain réellement reçu sur un ticket.
//
//  POURQUOI CETTE FENÊTRE EXISTE, MESURÉ : `resultat_dialog` appelait
//  `signalerResultat(gainEstime:)`, qui ne fait que CRÉER UNE ALERTE
//  (`alert_service.dart`). Le montant n'était écrit NULLE PART. Il n'existait
//  donc aucun moyen de déclarer un gain manuel, et le gain affiché restait
//  celui du calcul PMU — ou indéterminé.
//
//  CE QUE CETTE FENÊTRE NE FAIT PAS :
//    • elle n'écrit RIEN elle-même : elle rend un montant (`double?`) à
//      l'appelant, qui décide. Une fenêtre qui écrit serait intestable ;
//    • elle ne lit ni ne modifie aucun rapport PMU, aucun verdict ;
//    • elle ne déduit aucun ticket : elle reçoit déjà le montant courant.
//
//  VIRGULE : les claviers numériques de certains appareils/paramètres
//  régionaux ne proposent que la virgule. Le formateur accepte donc virgule ET
//  point, et le parsing normalise la virgule en point avant `double.tryParse`
//  (mesuré : aucun autre parcours de mise du projet ne le faisait pour une
//  saisie utilisateur).
//
//  `0` EST UN MONTANT VALIDE : il signifie « j'ai déclaré 0 € », ce qui n'est
//  pas la même chose que « je n'ai rien déclaré ». La fenêtre distingue donc
//  trois sorties : ANNULER (ne rien changer), « aucun gain » (null explicite),
//  et une valeur (0 comprise).
// ══════════════════════════════════════════════════════════════════════════════

/// Résultat d'une fenêtre de saisie de gain.
///
/// Trois états DISTINCTS, et c'est tout l'intérêt : sans cette distinction,
/// « annuler » et « effacer la déclaration » deviendraient indiscernables.
class ResultatSaisieGain {
  /// `true` quand l'utilisateur a validé (par OK ou par « aucun gain »).
  /// `false` quand il a annulé : l'appelant ne doit RIEN écrire.
  final bool valide;

  /// Montant validé. `null` = déclaration explicitement effacée.
  /// Ignoré quand [valide] est `false`.
  final double? montant;

  const ResultatSaisieGain._(this.valide, this.montant);

  /// Annulation : aucune écriture.
  static const ResultatSaisieGain annule = ResultatSaisieGain._(false, null);

  /// Validation d'un montant (0 € compris).
  /// Initialisation formelle (`this.montant`) : l'analyseur la préfère à
  /// l'affectation manuelle, et le comportement est identique.
  const ResultatSaisieGain.valideAvec(this.montant) : valide = true;

  /// Validation de l'EFFACEMENT de la déclaration (retour au PMU).
  static const ResultatSaisieGain efface = ResultatSaisieGain._(true, null);
}

class GainManuelDialog extends StatefulWidget {
  /// Montant actuellement déclaré, s'il y en a un. Sert de valeur initiale.
  final double? montantActuel;

  /// Contexte affiché : course et cheval, en LECTURE SEULE.
  final String? nomCourse;
  final String? nomCheval;

  const GainManuelDialog({
    super.key,
    this.montantActuel,
    this.nomCourse,
    this.nomCheval,
  });

  @override
  State<GainManuelDialog> createState() => _GainManuelDialogState();
}

class _GainManuelDialogState extends State<GainManuelDialog> {
  late final TextEditingController _ctrl;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    // Pré-remplissage : un montant entier s'affiche sans « .0 » parasite.
    final m = widget.montantActuel;
    _ctrl = TextEditingController(
      text: m == null
          ? ''
          : (m == m.truncateToDouble()
              ? m.toStringAsFixed(0)
              : m.toStringAsFixed(2)),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// Normalise puis convertit la saisie.
  ///
  /// `null` = champ vide (saisie effacée). `'!'` ne sert jamais : en cas
  /// d'entrée illisible on lève une erreur d'affichage et on ne valide pas.
  double? _lireMontant() {
    final brut = _ctrl.text.trim();
    if (brut.isEmpty) return null;
    // Virgule décimale → point. Aucun autre nettoyage : on refuse plutôt que
    // de deviner (pas de suppression d'espaces ou de symboles au hasard).
    final normalise = brut.replaceAll(',', '.');
    final v = double.tryParse(normalise);
    if (v == null) return null;
    if (v < 0) return null;
    return v;
  }

  void _valider() {
    final brut = _ctrl.text.trim();
    if (brut.isEmpty) {
      // Champ vide = effacement explicite, PAS une annulation.
      Navigator.pop(context, ResultatSaisieGain.efface);
      return;
    }
    final v = _lireMontant();
    if (v == null) {
      setState(() => _erreur = 'Montant illisible : utilisez 12,50 ou 12.50');
      return;
    }
    // Arrondi au centime : un gain ne se saisit pas au dix-millième.
    final centimes = (v * 100).round();
    Navigator.pop(context, ResultatSaisieGain.valideAvec(centimes / 100));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF0A1628),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text(
        'Gain réellement reçu',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Contexte, en LECTURE SEULE : on rappelle de quel ticket parle.
          if (widget.nomCourse != null && widget.nomCourse!.isNotEmpty)
            Text(widget.nomCourse!,
                style: const TextStyle(color: Colors.white60, fontSize: 14)),
          if (widget.nomCheval != null && widget.nomCheval!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('Cheval : ${widget.nomCheval}',
                  style:
                      const TextStyle(color: Color(0xFF4CAF7D), fontSize: 14)),
            ),
          const SizedBox(height: 14),
          TextField(
            controller: _ctrl,
            autofocus: true,
            // `numberWithOptions(decimal: true)` : c'est ce qui fait apparaître
            // la virgule sur les claviers qui la proposent. Mesuré : les trois
            // autres parcours de mise utilisent `TextInputType.number` nu, qui
            // ne la propose pas.
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              // Virgule ET point, chiffres uniquement, UN séparateur au plus.
              // On n'utilise PAS le formateur `^\d+\.?\d{0,2}` de l'ex-widget
              // `mise_gain_widget` (supprimé en BL1-A18) : il refusait la
              // virgule et forçait l'utilisateur à saisir un point.
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            style: const TextStyle(color: Colors.white, fontSize: 18),
            decoration: InputDecoration(
              labelText: 'Montant brut (€)',
              labelStyle: const TextStyle(color: Colors.white38),
              prefixText: '€ ',
              prefixStyle: const TextStyle(color: Color(0xFFFFD700)),
              helperText: 'Virgule ou point acceptés',
              helperStyle: const TextStyle(color: Colors.white30, fontSize: 11),
              errorText: _erreur,
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
          // 0 € est un montant : le rappeler évite de le confondre avec « rien ».
          const Text(
            '0 € est un montant valide et sera conservé comme tel.',
            style: TextStyle(color: Colors.white30, fontSize: 11),
          ),
        ],
      ),
      actions: [
        // ── Effacer : présent uniquement si une déclaration existe déjà.
        if (widget.montantActuel != null)
          TextButton(
            onPressed: () =>
                Navigator.pop(context, ResultatSaisieGain.efface),
            child: const Text('Retirer le gain',
                style: TextStyle(color: Color(0xFFFFB300))),
          ),
        // ── Annuler : NE RIEN ÉCRIRE.
        TextButton(
          onPressed: () => Navigator.pop(context, ResultatSaisieGain.annule),
          child:
              const Text('Annuler', style: TextStyle(color: Colors.white38)),
        ),
        // ── OK : valide la saisie.
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
