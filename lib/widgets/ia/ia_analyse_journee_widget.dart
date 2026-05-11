// ignore_for_file: unused_element
import 'package:flutter/material.dart';
import '../../services/ia_memory_service.dart';

// ─── Couleurs partagées (palette IaPerformanceScreen) ─────────────────────────
const Color _kDark   = Color(0xFF0D1B2A);
const Color _kCard   = Color(0xFF111F30);
const Color _kGreen  = Color(0xFF4CAF7D);
const Color _kDGreen = Color(0xFF2E7D52);
const Color _kGold   = Color(0xFFFFD700);
const Color _kPurple = Color(0xFF7C4DFF);

// ══════════════════════════════════════════════════════════════════════════════
//  Widgets d'affichage du résultat d'analyse journée — fonctions pures
//  Extrait de IaPerformanceScreen.
//  Usage : buildResumeAnalyse(r)
// ══════════════════════════════════════════════════════════════════════════════

  // ── Widget : Résumé du résultat de l'analyse ──────────────────────────────

Widget buildResumeAnalyse(AnalyseJourneeResultat r) {
    if (!r.succes) {
      // ★ Cas "vide/info" (première utilisation ou installation le soir) :
      // → bandeau orange informatif, PAS rouge erreur
      final isVide = r.isVide;
      final bgColor    = isVide ? const Color(0xFFFF9800) : Colors.red;
      final iconWidget = isVide
          ? const Icon(Icons.info_outline, color: Color(0xFFFF9800), size: 18)
          : const Icon(Icons.error_outline, color: Colors.red, size: 18);
      final textColor  = isVide ? const Color(0xFFFFCC80) : Colors.redAccent;

      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bgColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: bgColor.withValues(alpha: 0.30)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          iconWidget,
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              r.messageErreur ?? 'Erreur inconnue',
              style: TextStyle(color: textColor, fontSize: 14, height: 1.45),
            ),
          ),
        ]),
      );
    }

    final bool avecResultats = r.nbNouveauxResultats > 0;
    final bool toutEnAttente = r.nbNouveauxResultats == 0 && r.nbSansResultat > 0;
    final bool toutFutur = r.nbCoursesAnalysees == 0 && r.nbCoursesFutures > 0 && r.nbSansResultat == 0;

    Color bannerColor;
    IconData bannerIcon;
    String bannerText;
    if (avecResultats) {
      bannerColor = _kGreen;
      bannerIcon = Icons.check_circle_outline;
      bannerText = '${r.nbNouveauxResultats} résultat(s) comparé(s) — IA mise à jour n°${r.nbMisesAJour}';
    } else if (toutEnAttente) {
      bannerColor = Colors.orange;
      bannerIcon = Icons.schedule_rounded;
      bannerText = 'Courses passées mais résultats PMU pas encore publiés';
    } else if (toutFutur) {
      bannerColor = Colors.blue;
      bannerIcon = Icons.upcoming_rounded;
      bannerText = 'Toutes les courses sont encore à venir aujourd\'hui';
    } else {
      bannerColor = _kGreen;
      bannerIcon = Icons.check_circle_outline;
      bannerText = 'Analyse terminée — mise à jour n°${r.nbMisesAJour}';
    }

    return Column(children: [
      // Bannière de statut
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bannerColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: bannerColor.withValues(alpha: 0.3)),
        ),
        child: Row(children: [
          Icon(bannerIcon, color: bannerColor, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              bannerText,
              style: TextStyle(color: bannerColor, fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 10),

      // Grille de stats : 4 tuiles principales
      // Si nbNouveauxResultats==0 mais courses déjà traitées → afficher nbCoursesAnalysees en teal
      // pour éviter l'affichage trompeur "0 résultats comparés" quand tout est déjà à jour
      Builder(builder: (context) {
        final bool dejaAJour = r.nbNouveauxResultats == 0 && r.nbCoursesAnalysees > 0;
        final String valResultats = dejaAJour ? '${r.nbCoursesAnalysees}' : '${r.nbNouveauxResultats}';
        final String labelResultats = dejaAJour ? 'résultats\ndéjà à jour' : 'résultats\ncomparés';
        final Color couleurResultats = dejaAJour ? const Color(0xFF26A69A) : _kGold;
        return Row(children: [
          _buildMiniStat(valResultats, labelResultats, couleurResultats),
          const SizedBox(width: 6),
          _buildMiniStat('${r.nbCoursesAnalysees}', 'courses\ntraitées', const Color(0xFF42A5F5)),
          const SizedBox(width: 6),
          _buildMiniStat('${r.nbPronosticsAjoutes}', 'pronostics\ncréés', _kPurple),
          const SizedBox(width: 6),
          _buildMiniStat('${r.nbCoursesFutures}', 'futures\nignorées', Colors.white38),
        ]);
      }),

      // Ligne secondaire : sans résultat + erreurs
      if (r.nbSansResultat > 0 || r.nbCoursesEchouees > 0) ...[
        const SizedBox(height: 6),
        Row(children: [
          if (r.nbSansResultat > 0) ...[
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 8),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
                ),
                child: Row(children: [
                  const Icon(Icons.schedule, color: Colors.orange, size: 13),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      '${r.nbSansResultat} en attente PMU',
                      style: const TextStyle(color: Colors.orange, fontSize: 13),
                    ),
                  ),
                ]),
              ),
            ),
          ],
          if (r.nbSansResultat > 0 && r.nbCoursesEchouees > 0)
            const SizedBox(width: 6),
          if (r.nbCoursesEchouees > 0) ...[
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 8),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
                ),
                child: Row(children: [
                  const Icon(Icons.error_outline, color: Colors.redAccent, size: 13),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      '${r.nbCoursesEchouees} erreur(s) réseau',
                      style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                    ),
                  ),
                ]),
              ),
            ),
          ],
        ]),
      ],

      // Message explicatif si tout en attente
      if (toutEnAttente) ...[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
          ),
          child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('💡', style: TextStyle(fontSize: 15)),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'L\'IA a récupéré les partants et calculé ses pronostics pour toutes les courses passées. '
                'Les résultats officiels PMU ne sont pas encore publiés. '
                'Relancez l\'analyse après 20h00 pour comparer et déclencher l\'apprentissage.',
                style: TextStyle(color: Colors.white60, fontSize: 14),
              ),
            ),
          ]),
        ),
      ],

      // ── Détail par course (liste scrollable) ─────────────────────────────
      if (r.coursesAnalysees.isNotEmpty) ...[
        const SizedBox(height: 10),
        _buildDetailCourses(r.coursesAnalysees),
      ],

      // Poids dominants si apprentissage effectif
      if (r.poidsApres.isNotEmpty && avecResultats) ...[
        const SizedBox(height: 8),
        _buildResumePoidsApres(r.poidsApres),
      ],
    ]);
  }

  /// Liste détaillée des courses avec icône colorée selon statut
Widget _buildDetailCourses(List<String> lignes) {
    // Trier : ✓ d'abord, puis ⏳, puis 🔄, puis 🕐/🔁
    int _priorite(String l) {
      if (l.contains('✓'))  return 0;
      if (l.contains('⏳')) return 1;
      if (l.contains('🔄')) return 2;
      if (l.contains('🕐')) return 3;
      return 4;
    }
    final sorted = [...lignes]..sort((a, b) => _priorite(a).compareTo(_priorite(b)));

    Color _couleur(String l) {
      if (l.contains('✓'))  return const Color(0xFF4CAF7D);   // vert  → analysé
      if (l.contains('⏳')) return Colors.orange;              // orange → en attente PMU
      if (l.contains('🔄')) return Colors.blueAccent;         // bleu  → en cours
      if (l.contains('🕐')) return Colors.white38;            // gris  → à venir
      return Colors.white38;
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // En-tête
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Row(children: [
              const Icon(Icons.list_alt_rounded, color: Colors.white38, size: 14),
              const SizedBox(width: 6),
              Text(
                'Détail des ${sorted.length} course(s)',
                style: const TextStyle(color: Colors.white54, fontSize: 12,
                    fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              // Légende compacte
              _legendePuce(const Color(0xFF4CAF7D), 'Analysé'),
              const SizedBox(width: 8),
              _legendePuce(Colors.orange, 'En attente'),
              const SizedBox(width: 8),
              _legendePuce(Colors.white38, 'À venir'),
            ]),
          ),
          const Divider(height: 1, color: Colors.white10),
          // Lignes
          ...sorted.asMap().entries.map((entry) {
            final i    = entry.key;
            final line = entry.value;
            final col  = _couleur(line);
            // Séparer nom de course et statut entre crochets
            final bracketIdx = line.indexOf('[');
            final nom    = bracketIdx > 0 ? line.substring(0, bracketIdx).trim() : line;
            final statut = bracketIdx > 0
                ? line.substring(bracketIdx).replaceAll(RegExp(r'[\[\]]'), '').trim()
                : '';
            return Container(
              decoration: BoxDecoration(
                color: i.isEven
                    ? Colors.transparent
                    : Colors.white.withValues(alpha: 0.015),
                border: Border(
                  bottom: i < sorted.length - 1
                      ? BorderSide(color: Colors.white.withValues(alpha: 0.04))
                      : BorderSide.none,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              child: Row(children: [
                // Pastille couleur statut
                Container(
                  width: 7, height: 7,
                  decoration: BoxDecoration(
                    color: col,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                // Nom de la course
                Expanded(
                  child: Text(
                    nom,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                // Statut coloré
                if (statut.isNotEmpty)
                  Text(
                    statut,
                    style: TextStyle(
                      color: col,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ]),
            );
          }),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

Widget _legendePuce(Color color, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 7, height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 3),
      Text(label, style: TextStyle(color: color, fontSize: 10)),
    ],
  );

Widget _buildMiniStat(String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(children: [
          Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 15), textAlign: TextAlign.center),
        ]),
      ),
    );
  }

Widget _buildResumePoidsApres(Map<String, double> poids) {
    // ★ v5.0 : labels pour les 10 critères
    const labels = {
      'forme': 'Forme', 'gains': 'Gains', 'record': 'Record',
      'cote': 'Cote', 'constance': 'Régul.', 'victoires': 'Victoires',
      'discipline': 'Disc.', 'distSpec': 'DistSpec', 'jockey': 'Jockey', 'repos': 'Repos',
    };
    final sorted = poids.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final top3 = sorted.take(3).toList();

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(mainAxisSize: MainAxisSize.min, children: const [
          Icon(Icons.trending_up, color: Colors.white24, size: 13),
          SizedBox(width: 6),
          Text('Poids dominants :', style: TextStyle(color: Colors.white38, fontSize: 13)),
        ]),
        ...top3.map((e) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: _kGold.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: _kGold.withValues(alpha: 0.25)),
          ),
          child: Text(
            '${labels[e.key] ?? e.key} ${(e.value * 100).toStringAsFixed(0)}%',
            style: const TextStyle(color: _kGold, fontSize: 12, fontWeight: FontWeight.bold),
          ),
        )),
      ],
    );
  }

  // ── Widget : Stats par type de pari ──────────────────────────────────────


