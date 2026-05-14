// ═══════════════════════════════════════════════════════════════════════════
//  TYPE PARI BADGE — ★ v10.31
//  Widget global réutilisable. Badge cliquable → BottomSheet contextuel.
//  Taux de réussite lus DYNAMIQUEMENT depuis IaMemoryService.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../services/ia_memory_service.dart';

class TypePariBadge extends StatelessWidget {
  final String    type;
  final List<String> numeros;    // numéros IA sélectionnés (top N) — String car ZtPartant.numero est String
  final String?   nomFavori;  // nom du cheval favori

  const TypePariBadge({
    super.key,
    required this.type,
    this.numeros   = const <String>[],
    this.nomFavori,
  });

  static Color couleur(String type) {
    switch (type) {
      case 'Simple Gagnant':  return const Color(0xFFFFD700);
      case 'Simple Placé':    return const Color(0xFF4CAF7D);
      case 'Gagnant+Placé':   return const Color(0xFF4CAF7D);
      case 'Couplé Gagnant':  return const Color(0xFFFF7043);
      case 'Couplé Placé':    return const Color(0xFFFF8A65);
      case 'Tiercé':          return const Color(0xFFAB47BC);
      case 'Quarté+':         return const Color(0xFF26A69A);
      case 'Quinté+':         return const Color(0xFFFFD700);
      default:                return Colors.white38;
    }
  }

  static String emoji(String type) {
    switch (type) {
      case 'Simple Gagnant':  return '🏆';
      case 'Simple Placé':    return '🎯';
      case 'Gagnant+Placé':   return '🎯🏆';
      case 'Couplé Gagnant':  return '🔗';
      case 'Couplé Placé':    return '🔗🎯';
      case 'Tiercé':          return '3️⃣';
      case 'Quarté+':         return '4️⃣';
      case 'Quinté+':         return '5️⃣';
      case 'À surveiller':    return '👁️';
      default:                return '🎲';
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = couleur(type);
    return GestureDetector(
      onTap: () => showModalBottomSheet(
        context:            context,
        backgroundColor:    Colors.transparent,
        isScrollControlled: true,
        builder: (_) => TypePariDescriptifSheet(
          type: type, numeros: numeros, nomFavori: nomFavori),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color:  color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(emoji(type), style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 5),
          Text(type, style: TextStyle(
            color: color, fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(width: 4),
          Icon(Icons.help_outline_rounded,
              color: color.withValues(alpha: 0.6), size: 12),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  BottomSheet descriptif contextuel — source unique de vérité
// ══════════════════════════════════════════════════════════════════════════════
class TypePariDescriptifSheet extends StatelessWidget {
  final String       type;
  final List<String> numeros;
  final String?      nomFavori;

  const TypePariDescriptifSheet({
    super.key,
    required this.type,
    this.numeros   = const <String>[],
    this.nomFavori,
  });

  // ── Taux dynamique depuis IaMemoryService ────────────────────────────────
  String _tauxDynamique() {
    // ★ v10.36 : Lire precisionParType (pronostics IA résolus) et non
    // statsParType (paris utilisateur manuels) — source correcte pour
    // afficher la précision réelle de l'IA sur ce type de pari.
    try {
      final stats = IaMemoryService.instance.precisionParType;
      final st = stats.where((s) => s.typePari == type).toList();
      if (st.isEmpty) return '';
      final s    = st.first;
      final nb   = s.nbTotal;
      final bons = s.nbBons;
      if (nb < 5) return '';
      final pct = (bons / nb * 100).toStringAsFixed(0);
      return "Précision IA sur ce type : $bons/$nb = $pct%";
    } catch (_) { return ''; }
  }

  // ── Résumé contextuel personnalisé ──────────────────────────────────────
  String _titre() {
    // numeros est déjà List<String> (ex: ['3', '7']) — on préfixe N° pour l'affichage
    final nums = numeros.map((n) => 'N°$n').join(' · ');
    final fav  = nomFavori?.isNotEmpty == true
        ? nomFavori!
        : numeros.isNotEmpty ? 'N°${numeros.first}' : 'ton cheval';
    switch (type) {
      case 'Simple Gagnant':
        return '$fav doit finir 1ᵉʳ.';
      case 'Simple Placé':
        return '$fav doit finir dans les 3 premiers (2ᵉ ou 3ᵉ accepté).';
      case 'Gagnant+Placé':
        return '$fav doit gagner ou se placer dans le Top 3.';
      case 'Couplé Gagnant':
        return numeros.length >= 2
            ? "N°${numeros[0]} et N°${numeros[1]} doivent finir 1ᵉʳ et 2ᵉ, dans n'importe quel ordre."
            : "2 chevaux doivent finir 1ᵉʳ et 2ᵉ, dans n'importe quel ordre.";
      case 'Couplé Placé':
        return numeros.length >= 2
            ? 'N°${numeros[0]} et N°${numeros[1]} doivent tous deux finir dans les 3 premiers.'
            : '2 chevaux doivent finir dans les 3 premiers.';
      case 'Tiercé':
        return numeros.length >= 3
            ? "Tes 3 chevaux $nums doivent arriver dans les 3 premiers, dans n'importe quel ordre."
            : '3 chevaux doivent arriver dans les 3 premiers.';
      case 'Quarté+':
        return numeros.length >= 4
            ? "Tes 4 chevaux $nums doivent occuper les 4 premières places, dans n'importe quel ordre."
            : '4 chevaux doivent occuper les 4 premières places.';
      case 'Quinté+':
        return numeros.length >= 5
            ? "Tes 5 chevaux $nums doivent occuper les 5 premières places, dans n'importe quel ordre."
            : '5 chevaux doivent occuper les 5 premières places.';
      case 'À surveiller':
        return "L'IA surveille cette course sans conseil de pari ferme.";
      default:
        return 'Pari PMU — consulte les règles officielles.';
    }
  }

  String _explication() {
    switch (type) {
      case 'Simple Gagnant':
        return 'Tu mises sur UN seul cheval et il doit remporter la course. '
            'Plus la cote est élevée, plus le gain est grand, mais plus le risque est réel.';
      case 'Simple Placé':
        return 'Ton cheval doit terminer parmi les 3 premiers (2ᵉ ou 3ᵉ accepté). '
            "Gain plus faible qu'en Simple Gagnant, mais probabilité bien plus haute. "
            'Pour les courses de moins de 5 partants, seuls les 2 premiers comptent.';
      case 'Gagnant+Placé':
        return 'Tu joues les deux paris en même temps sur le même cheval. '
            "S'il gagne → Gagnant + Placé. S'il se place → uniquement le Placé. "
            'La mise est doublée mais tu as un filet de sécurité.';
      case 'Couplé Gagnant':
        return "Tes 2 chevaux doivent occuper les 2 premières places, peu importe l'ordre. "
            'Plus difficile que le Simple Gagnant mais cote combinée souvent intéressante.';
      case 'Couplé Placé':
        return 'Tes 2 chevaux doivent tous deux se classer dans les 3 premiers, '
            "dans n'importe quel ordre. Moins risqué que le Couplé Gagnant.";
      case 'Tiercé':
        return 'Tes 3 chevaux doivent occuper les 3 premières places. '
            "En Tiercé Désordre, l'ordre n'importe pas — c'est ce que l'IA conseille. "
            "En Tiercé Ordre, les gains sont multipliés mais c'est beaucoup plus difficile.";
      case 'Quarté+':
        return 'Disponible uniquement sur certaines courses PMU sélectionnées. '
            "Tes 4 chevaux doivent occuper les 4 premières places dans n'importe quel ordre. "
            'Un bonus "+" est accordé si tu trouves l\'ordre exact.';
      case 'Quinté+':
        return 'Le pari phare de PMU — disponible sur UNE course par jour. '
            "Tes 5 chevaux doivent occuper les 5 premières places dans n'importe quel ordre. "
            'Des bonus "4 sur 5" et "3 sur 5" existent si tu rates un cheval. '
            "Le jackpot peut atteindre plusieurs millions d'euros.";
      case 'À surveiller':
        return 'Les scores IA sont insuffisants pour recommander un pari avec confiance. '
            'La course est trop ouverte ou les données sont insuffisantes — ne pas parier.';
      default:
        return 'Consulte les règles officielles PMU pour ce type de pari.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final color  = TypePariBadge.couleur(type);
    final emo    = TypePariBadge.emoji(type);
    final titre  = _titre();
    final expli  = _explication();
    final taux   = _tauxDynamique();
    final nums   = numeros.map((n) => 'N°$n').toList(); // numeros = List<String>

    return Container(
      padding: EdgeInsets.fromLTRB(20, 20, 20,
          20 + MediaQuery.of(context).viewInsets.bottom),
      decoration: const BoxDecoration(
        color: Color(0xFF111F30),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(
            width: 40, height: 4, margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
                color: Colors.white24, borderRadius: BorderRadius.circular(2)),
          )),
          // ── En-tête ────────────────────────────────────────────────────
          Row(children: [
            Container(
              width: 50, height: 50,
              decoration: BoxDecoration(
                color:  color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: color.withValues(alpha: 0.4)),
              ),
              child: Center(child: Text(emo, style: const TextStyle(fontSize: 24))),
            ),
            const SizedBox(width: 14),
            Text(type, style: TextStyle(
              color: color, fontSize: 20, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 16),
          // ── Résumé contextuel ──────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color:  color.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.25)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('En résumé', style: TextStyle(
                  color: color, fontSize: 11,
                  fontWeight: FontWeight.w700, letterSpacing: 0.5)),
              const SizedBox(height: 6),
              Text(titre, style: const TextStyle(
                  color: Colors.white, fontSize: 15,
                  fontWeight: FontWeight.w600, height: 1.5)),
              if (nums.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (int i = 0; i < nums.length; i++)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color:  i == 0
                            ? color.withValues(alpha: 0.20)
                            : Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: i == 0
                              ? color.withValues(alpha: 0.5)
                              : Colors.white12),
                      ),
                      child: Text(nums[i], style: TextStyle(
                        color: i == 0 ? color : Colors.white60,
                        fontSize: 13, fontWeight: FontWeight.bold)),
                    ),
                ]),
              ],
            ]),
          ),
          const SizedBox(height: 14),
          const Divider(color: Colors.white12),
          const SizedBox(height: 10),
          // ── Explication ────────────────────────────────────────────────
          const Text('Comment ça marche ?', style: TextStyle(
              color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(expli, style: const TextStyle(
              color: Colors.white54, fontSize: 13, height: 1.6)),
          // ── Taux dynamique ──────────────────────────────────────────────
          if (taux.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color:  const Color(0xFF7C4DFF).withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: const Color(0xFF7C4DFF).withValues(alpha: 0.25)),
              ),
              child: Row(children: [
                const Icon(Icons.psychology_outlined,
                    color: Color(0xFF7C4DFF), size: 16),
                const SizedBox(width: 8),
                Expanded(child: Text(taux, style: const TextStyle(
                    color: Color(0xFFB39DDB), fontSize: 12, height: 1.5))),
              ]),
            ),
          ],
          const SizedBox(height: 24),
        ]),
      ),
    );
  }
}
