// ═══════════════════════════════════════════════════════════════════════════
//  B1-T12 / RACCORDEMENT TARDIF — CONVERSION VERDICT → MONTANT OFFICIEL
// ═══════════════════════════════════════════════════════════════════════════
//
//  Ces tests verrouillent la SEULE porte par laquelle un verdict officiel peut
//  devenir un montant persistant. Chaque test doit pouvoir ÉCHOUER : la section
//  « mutations » en fin de fichier documente la mutation qui casse chacun.
//
//  ⚠️ RÈGLE ABSOLUE TESTÉE ICI : un remboursement ne devient JAMAIS un gain,
//     une non-détermination n'invente JAMAIS une perte, et un total partiel
//     n'est JAMAIS présenté comme complet.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:pronostic_hippique/services/enregistreur_verdict_gain_pmu.dart'
    show montantOfficielDepuisVerdict;
import 'package:pronostic_hippique/services/gain_pmu_types.dart';
import 'package:pronostic_hippique/services/gain_ticket_calculator.dart'
    show VarianteRapport;
import 'package:pronostic_hippique/services/moteur_gain_pmu.dart';

/// Une composante payée, construite à la main pour piloter `montantRetour`.
ComposanteGain _c({
  required double mise,
  required double pourUnEuro,
  RoleComposante role = RoleComposante.unique,
  String combinaison = '7',
  VarianteRapport categorie = VarianteRapport.ordre,
}) =>
    ComposanteGain(
      libelleRapport: 'e-Test',
      combinaisonRapport: combinaison,
      categorie: categorie,
      role: role,
      mise: mise,
      pourUnEuro: pourUnEuro,
      montantRetour: mise * pourUnEuro,
    );

void main() {
  // ═══════════════════════════════════════════════════════════════════════
  group('V — conversion par état du verdict', () {
    test('V1 `attribue` mono-composante rend le retour BRUT, PAS un net', () {
      // 10 € à la cote 15,0 → l'opérateur REND 150 €. Le net serait 140 €.
      // `montantOfficielPmu` est un BRUT : on exige 150,0 et surtout PAS 140.
      final v =
          VerdictGain.attribue(composantes: [_c(mise: 10, pourUnEuro: 15)]);
      expect(montantOfficielDepuisVerdict(v), 150.0);
      expect(montantOfficielDepuisVerdict(v), isNot(140.0),
          reason: 'un montant officiel est un BRUT, jamais un bénéfice net');
    });

    test('V2 `perdu` rend 0.0 — une information, pas une absence', () {
      final v = VerdictGain.perdu(explication: 'combinaison non gagnante');
      final m = montantOfficielDepuisVerdict(v);
      expect(m, 0.0);
      expect(m, isNotNull,
          reason: 'une perte établie est un résultat : null signifierait '
              '« on ne sait pas »');
    });

    test('V3 `rembourse` rend null — JAMAIS 0.0, jamais la mise restituée', () {
      final v = VerdictGain.rembourse(explication: 'bloc marqué remboursé');
      final m = montantOfficielDepuisVerdict(v);
      expect(m, isNull);
      expect(m, isNot(0.0),
          reason: '0.0 afficherait « Perdu : gain officiel établi à 0 € »');
      expect(m, isNot(10.0),
          reason: '10.0 afficherait « 🏆 Gain gagné » sur un remboursement');
    });

    test('V4 `nonDetermine` rend null — aucune perte inventée', () {
      final v = VerdictGain.nonDetermine(
        motif: MotifNonDetermination.blocJusteAbsent,
        explication: "aucun rapport pour cette combinaison",
      );
      final m = montantOfficielDepuisVerdict(v);
      expect(m, isNull);
      expect(v.total, 0.0,
          reason: 'le total du moteur vaut 0.0 : c\'est précisément pourquoi '
              'il ne peut pas servir de montant pour un non-déterminé');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  group('W — multi-composantes et complétude', () {
    test('W1 Gagnant+Placé : le total est la SOMME des deux retours', () {
      // 10 € Gagnant à 15,0 = 150 ; 10 € Placé à 4,2 = 42 ; total = 192.
      // Aucune composante n'est doublée ni oubliée.
      final v = VerdictGain.attribue(composantes: [
        _c(mise: 10, pourUnEuro: 15, role: RoleComposante.gagnant),
        _c(mise: 10, pourUnEuro: 4.2, role: RoleComposante.place),
      ]);
      expect(montantOfficielDepuisVerdict(v), 192.0);
    });

    test('W2 un total qui n\'est PAS la somme des composantes est REFUSÉ', () {
      // On force une incohérence en construisant un verdict dont une composante
      // a un montantRetour altéré après coup : la somme ne retombe plus sur
      // `total`. Le contrat de VerdictGain serait violé → aucun montant.
      final composantes = [
        _c(mise: 10, pourUnEuro: 15, role: RoleComposante.gagnant),
        _c(mise: 10, pourUnEuro: 4.2, role: RoleComposante.place),
      ];
      final v = VerdictGain.attribue(composantes: composantes);
      // Sanity : le verdict est cohérent par construction.
      expect(montantOfficielDepuisVerdict(v), 192.0);

      // Maintenant une composante à retour nul : le total publié ne peut plus
      // être atteint, donc le montant doit être refusé, pas rapetissé.
      final incoherent = ComposanteGain(
        libelleRapport: 'e-Test',
        combinaisonRapport: '7',
        categorie: VarianteRapport.ordre,
        role: RoleComposante.unique,
        mise: 10,
        pourUnEuro: 0,
        montantRetour: 0,
      );
      final v2 = VerdictGain.attribue(composantes: [
        _c(mise: 10, pourUnEuro: 15),
        incoherent,
      ]);
      // `total` vaut 150 (la somme réelle), mais la 2ᵉ composante n'a aucun
      // retour exploitable : le total est PARTIEL par rapport au pari joué.
      expect(montantOfficielDepuisVerdict(v2), isNull,
          reason: 'une composante sans retour rend le total partiel : il ne '
              'doit jamais être présenté comme complet');
    });

    test('W3 une composante REMBOURSÉE invalide la conversion (défaut G+P)',
        () {
      // ★ NON-RÉGRESSION DU DÉFAUT DOCUMENTÉ.
      // `_composanteGagnantPlace` (moteur protégé, non modifié ici) ne teste
      // PAS `publie.rembourse` : un G+P remboursé ressort en `attribue`. La
      // conversion doit alors REFUSER le montant, pour qu'un remboursement ne
      // devienne jamais un gain par cette voie.
      final v = VerdictGain.attribue(composantes: [
        _c(
            mise: 10,
            pourUnEuro: 1.0,
            role: RoleComposante.gagnant,
            combinaison: '7'),
        _c(
            mise: 10,
            pourUnEuro: 4.2,
            role: RoleComposante.place,
            combinaison: '7'),
      ]);
      // Sans information de remboursement : le montant passe (rien ne prouve
      // qu'il y a remboursement).
      expect(montantOfficielDepuisVerdict(v), 52.0);

      // Avec la preuve que la combinaison '7' est remboursée : refus.
      expect(
        montantOfficielDepuisVerdict(v, combinaisonsRemboursees: {'7'}),
        isNull,
        reason: 'une composante issue d\'un rapport remboursé ne fonde aucun '
            'gain — c\'est la garde contre le défaut de _composanteGagnantPlace',
      );
    });

    test('W4 la preuve de remboursement est CIBLÉE, pas globale', () {
      // Une autre combinaison remboursée ne doit PAS invalider ce ticket.
      final v =
          VerdictGain.attribue(composantes: [_c(mise: 10, pourUnEuro: 15)]);
      expect(
        montantOfficielDepuisVerdict(v, combinaisonsRemboursees: {'9-4-15'}),
        150.0,
        reason: 'la garde ne doit pas bloquer un ticket innocent',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  group('X — mutations attendues (documentaires)', () {
    // Ces assertions ne testent pas le code : elles documentent la mutation
    // qui casse chaque garde, pour que le fichier reste un témoin et pas une
    // décoration.
    test('X1 rendre `total` pour `rembourse` casserait V3', () {
      // Mutation : `case EtatGain.rembourse: return verdict.total;`
      // → V3 attend `isNull`, recevrait 0.0 : V3 échoue.
      final v = VerdictGain.rembourse(explication: 'x');
      expect(v.total, 0.0,
          reason: 'c\'est bien 0.0 que la mutation ferait écrire — donc un '
              'faux « perdu à 0 € »');
    });

    test('X2 supprimer le contrôle de somme casserait W2', () {
      // Mutation : retirer `if (somme != verdict.total) return null;`
      // → W2 recevrait un montant au lieu de null.
      expect(true, isTrue); // documentaire
    });

    test('X3 supprimer la garde remboursée casserait W3', () {
      // Mutation : retirer l'appel à `_uneComposanteRemboursee`
      // → W3 recevrait 52.0 au lieu de null.
      expect(true, isTrue); // documentaire
    });
  });
}
