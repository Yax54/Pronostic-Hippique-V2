// ═══════════════════════════════════════════════════════════════════════════
//  ARRIVÉE OFFICIELLE — AFFICHAGE DES GROUPES D'EX ÆQUO
//
//  ★ A6 — Rendu PARTAGÉ, unique source de vérité visuelle pour TOUTES les
//  bulles contenant un pronostic (widget d'arrivée réelle, calendrier IA,
//  carte mémoire IA, détail journée, Mes Paris).
//
//  PÉRIMÈTRE STRICT : AFFICHAGE. Ce fichier ne lit aucun service, n'écrit
//  rien, ne déclenche aucun réseau et n'est importé par AUCUN service.
//  Il ne reçoit que des groupes déjà lus ailleurs — jamais une liste plate.
//
//  ── Pourquoi un rendu dédié ──────────────────────────────────────────────
//  `[[7,12],[8],[6]]` n'est pas `[7,12,8,6]`. Le PMU publie un groupe de
//  chevaux arrivés SIMULTANÉMENT ; aplatir ou masquer la simultanéité fait
//  lire à l'utilisateur un classement qui n'existe pas.
//
//  ── Règle d'affichage retenue (spécification validée) ────────────────────
//  • Les numéros gardent leur présentation habituelle.
//  • SEULS les chevaux ex æquo sont mis en évidence : fond jaune doré et
//    bordure assortie.
//  • Sous chacun de ces numéros figure son RANG OFFICIEL (« 2e », « 3e »…).
//  • Un petit encadré gris « Ex æquo » est placé à droite du titre.
//  • Les positions SAUTÉES sont respectées : un groupe de 2 chevaux occupe
//    UN rang et consomme 2 places, le groupe suivant démarre donc au rang 3.
//  • Aucune phrase explicative longue.
//
//  ⚠️ Ce widget n'est INSTANCIÉ que lorsqu'un ex æquo existe réellement.
//  Une arrivée sans ex æquo continue d'emprunter le rendu historique de son
//  écran, strictement inchangé (aucun rang, aucun encadré, aucune retouche).
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

/// Jaune doré réservé à la mise en évidence des chevaux ex æquo.
const Color kCouleurExAequo = Color(0xFFFFD700);

/// Gris de l'encadré « Ex æquo ».
const Color kCouleurBadgeExAequo = Color(0xFF9E9E9E);

/// `true` si au moins un groupe contient plusieurs numéros.
///
/// PURE. C'est le seul test qui décide si une bulle doit passer au rendu
/// ex æquo ou conserver son rendu historique.
bool arriveeAvecExAequo(List<List<int>>? groupes) {
  if (groupes == null || groupes.isEmpty) return false;
  for (final g in groupes) {
    if (g.length > 1) return true;
  }
  return false;
}

/// Rang officiel (base 1) de la PREMIÈRE place de chaque groupe.
///
/// PURE. Un groupe de `k` chevaux occupe un seul rang et consomme `k`
/// places, d'où les positions sautées :
///   `[[7,12],[8],[6]]` → `[1, 3, 4]`
///   `[[7],[4],[11,9],[6]]` → `[1, 2, 3, 5]`
///
/// Un groupe vide consomme 0 place et ne décale donc pas les suivants.
List<int> rangsOfficiels(List<List<int>> groupes) {
  final rangs = <int>[];
  var rang = 1;
  for (final g in groupes) {
    rangs.add(rang);
    rang += g.length;
  }
  return rangs;
}

/// Libellé français abrégé d'un rang : « 1er », « 2e », « 3e »…
///
/// PURE. Une seule forme abrégée, conformément à la spécification (aucune
/// phrase explicative).
String libelleRang(int rang) => rang == 1 ? '1er' : '${rang}e';

/// Petit encadré gris « Ex æquo », destiné à être placé à droite du titre.
class BadgeExAequo extends StatelessWidget {
  const BadgeExAequo({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: kCouleurBadgeExAequo.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: kCouleurBadgeExAequo.withValues(alpha: 0.55),
        ),
      ),
      child: const Text(
        'Ex æquo',
        style: TextStyle(
          color: kCouleurBadgeExAequo,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// Ligne de numéros d'une arrivée officielle comportant au moins un ex æquo.
///
/// [groupes] est rendu TEL QUEL : ni aplatissement, ni déduplication, ni
/// recalcul d'ordre. [numerosIa] permet à chaque écran de conserver son
/// surlignage habituel des chevaux retenus par l'IA, sans changer la règle
/// de mise en évidence des ex æquo.
class LigneArriveeExAequo extends StatelessWidget {
  final List<List<int>> groupes;
  final double fontSize;

  /// Numéros (sous forme texte) à conserver en vert — sélection IA de
  /// l'écran appelant. Vide par défaut : aucun surlignage IA.
  final Set<String> numerosIa;

  const LigneArriveeExAequo({
    super.key,
    required this.groupes,
    this.fontSize = 14,
    this.numerosIa = const <String>{},
  });

  @override
  Widget build(BuildContext context) {
    final rangs = rangsOfficiels(groupes);
    final children = <Widget>[];

    for (var gi = 0; gi < groupes.length; gi++) {
      final groupe = groupes[gi];
      if (groupe.isEmpty) continue;

      // Séparateur entre groupes de rangs différents (convention existante).
      if (gi > 0) {
        children.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Text(
            '·',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.35),
              fontSize: fontSize,
            ),
          ),
        ));
      }

      final estExAequo = groupe.length > 1;

      for (var ni = 0; ni < groupe.length; ni++) {
        final num = groupe[ni];

        // « = » entre deux numéros du MÊME rang (convention existante).
        if (ni > 0) {
          children.add(Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              '=',
              style: TextStyle(
                color: kCouleurExAequo,
                fontSize: fontSize,
                fontWeight: FontWeight.bold,
              ),
            ),
          ));
        }

        children.add(_buildNumero(
          numero: num,
          exAequo: estExAequo,
          rang: rangs[gi],
        ));
      }
    }

    return Wrap(spacing: 4, runSpacing: 4, children: children);
  }

  Widget _buildNumero({
    required int numero,
    required bool exAequo,
    required int rang,
  }) {
    final estIa = numerosIa.contains(numero.toString());

    // Mise en évidence RÉSERVÉE aux ex æquo : fond doré + bordure dorée.
    // Les autres numéros gardent leur présentation habituelle (vert si dans
    // la sélection IA, neutre sinon).
    final Color fond;
    final Color bordure;
    final Color texte;
    if (exAequo) {
      fond = kCouleurExAequo.withValues(alpha: 0.20);
      bordure = kCouleurExAequo;
      texte = kCouleurExAequo;
    } else if (estIa) {
      fond = const Color(0xFF4CAF7D).withValues(alpha: 0.12);
      bordure = const Color(0xFF4CAF7D).withValues(alpha: 0.6);
      texte = const Color(0xFF4CAF7D);
    } else {
      fond = Colors.white.withValues(alpha: 0.04);
      bordure = Colors.white.withValues(alpha: 0.2);
      texte = Colors.white54;
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: fontSize > 12 ? 7 : 5,
        vertical: fontSize > 12 ? 4 : 2,
      ),
      decoration: BoxDecoration(
        color: fond,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: bordure),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'N°$numero',
            style: TextStyle(
              color: texte,
              fontSize: fontSize,
              fontWeight:
                  exAequo || estIa ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          // Le rang n'est affiché QUE sous les chevaux ex æquo.
          if (exAequo)
            Text(
              libelleRang(rang),
              style: TextStyle(
                color: kCouleurExAequo.withValues(alpha: 0.85),
                fontSize: fontSize - 3,
                fontWeight: FontWeight.bold,
                height: 1.0,
              ),
            ),
        ],
      ),
    );
  }
}
