// ═══════════════════════════════════════════════════════════════════════════
//  BetBottomSheet — Fiche de pari universelle Pronostic Hippique v3.0
//
//  Nouvelles fonctionnalités :
//   • Liens directs vers PMU, Betclic, Winamax, Unibet, ZEbet, ParionsSport
//   • Calculateur de gains multi-type (Simple, Placé, Couplé, Tiercé, Quinté+)
//   • Comparateur de cotes entre bookmakers
//   • Mise conseillée par l'IA selon le niveau de confiance
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/zt_models.dart';
import '../models/pmu_models.dart';
import '../providers/pmu_provider.dart';
import '../services/alert_service.dart';
import '../services/bookmaker_service.dart';
import '../services/gain_calculator.dart';
import '../services/data_refresh_service.dart'; // ★ Lot 4 : fix écran gris
import '../services/ia_memory_service.dart';
import '../services/ia_pronostic_engine.dart';
import '../utils/format_euros.dart';

// ── Point d'entrée public ────────────────────────────────────────────────────

void showBetSheet(
  BuildContext context, {
  required ZtReunion reunion,
  required ZtCourse course,
  required AlertService alertService,
  required VoidCallback onBetPlaced,
  ZtPartant? chevalSuggere,
  String? overrideKey,
}) {
  // ★ FIX BUG ÉCRAN GRIS (Lot 4) :
  // showModalBottomSheet crée une nouvelle route isolée → les Providers
  // du contexte parent (PmuProvider, DataRefreshService) sont perdus.
  // Solution : capturer les providers AVANT d'ouvrir le sheet, puis les
  // réinjecter via MultiProvider.value dans le builder.
  // useSafeArea: true → Flutter gère le padding système Android/iOS
  // → évite l'écran gris sur certains appareils.
  final pmuProvider        = context.read<PmuProvider>();
  final dataRefreshService = context.read<DataRefreshService>();

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: false,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      try {
        return MultiProvider(
          providers: [
            ChangeNotifierProvider<PmuProvider>.value(value: pmuProvider),
            ChangeNotifierProvider<DataRefreshService>.value(value: dataRefreshService),
          ],
          child: _BetSheet(
            reunion: reunion,
            course: course,
            alertService: alertService,
            onBetPlaced: onBetPlaced,
            chevalSuggere: chevalSuggere,
            overrideKey: overrideKey,
          ),
        );
      } catch (e, stack) {
        // Filet de sécurité permanent : si le sheet plante un jour,
        // affiche l'erreur exacte au lieu d'un écran gris muet.
        return Container(
          height: 300,
          decoration: const BoxDecoration(
            color: Color(0xFF1A0000),
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('🔴 ERREUR — merci de copier ce message',
                    style: TextStyle(color: Colors.red, fontSize: 14, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Text('$e', style: const TextStyle(color: Colors.orange, fontSize: 12)),
                const SizedBox(height: 8),
                Text('${stack.toString().split('\n').take(6).join('\n')}',
                    style: const TextStyle(color: Colors.white38, fontSize: 11)),
              ],
            ),
          ),
        );
      }
    },
  );
}

// ── Widget principal ──────────────────────────────────────────────────────────

class _BetSheet extends StatefulWidget {
  final ZtReunion reunion;
  final ZtCourse course;
  final AlertService alertService;
  final VoidCallback onBetPlaced;
  final ZtPartant? chevalSuggere;
  final String? overrideKey;

  const _BetSheet({
    required this.reunion,
    required this.course,
    required this.alertService,
    required this.onBetPlaced,
    this.chevalSuggere,
    this.overrideKey,
  });

  @override
  State<_BetSheet> createState() => _BetSheetState();
}

class _BetSheetState extends State<_BetSheet> with SingleTickerProviderStateMixin {
  double _mise = 10.0;
  ZtPartant? _chevalSelectionne;
  TabController? _tabController;

  // Types de pari disponibles
  static const _typesPari = ['Simple Gagnant', 'Simple Placé', 'Gagnant+Placé', 'Couplé Gagnant', 'Couplé Placé', 'Tiercé', 'Quarté+', 'Quinté+'];
  int _typePariIndex = 0;

  // ── Sélection manuelle pour paris combinés ───────────────────────────────
  // Numéros sélectionnés manuellement par l'utilisateur (pour Tiercé/Quarté+/Quinté+)
  final Set<int> _numerosManuelsSel = {};
  bool _modeManuel = false; // false = auto IA, true = sélection manuelle

  // Couleurs
  static const _gold   = Color(0xFFFFD700);
  static const _green  = Color(0xFF4CAF7D);
  static const _dark   = Color(0xFF0A1628);
  static const _card   = Color(0xFF111F30);
  static const _dgreen = Color(0xFF2E7D52);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    try {
      final partants = widget.course.partantsParRangIA;
      if (widget.chevalSuggere != null) {
        _chevalSelectionne = widget.chevalSuggere;
      } else if (partants.isNotEmpty) {
        _chevalSelectionne = partants.first;
      }
      // Adapter le type de pari selon la course
      if (widget.course.isQuinte && _typesPari.length > 7) {
        _typePariIndex = 7; // Quinté+
      }
      // Mise conseillée selon le score IA du favori
      if (_chevalSelectionne != null) {
        final score = _chevalSelectionne!.scoreIA;
        if (score >= 80) _mise = 20.0;
        else if (score >= 65) _mise = 10.0;
        else if (score >= 50) _mise = 5.0;
        else _mise = 2.0;
      }
    } catch (e) {
      debugPrint('[BetSheet] initState erreur : $e');
      _mise = 5.0;
      _typePariIndex = 0;
    }
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  bool get _sansPartants => widget.course.partants.isEmpty;

  /// Vrai si aucun partant n'a de cote PMU disponible
  bool get _sansCote {
    if (widget.course.partants.isEmpty) return false;
    return widget.course.partants.every((p) => p.coteDecimale >= 99);
  }

  int get _nbPartants => widget.course.partants.length.clamp(5, 30);

  /// Vrai si le type de pari actuel est un combiné multi-chevaux
  bool get _estPariCombi {
    final t = _typesPari[_typePariIndex];
    return t == 'Couplé Gagnant' || t == 'Couplé Placé' ||
           t == 'Tiercé' || t == 'Quarté+' || t == 'Quinté+';
  }

  /// Vrai si c'est un Couplé (Gagnant ou Placé)
  bool get _estCouple {
    final t = _typesPari[_typePariIndex];
    return t == 'Couplé Gagnant' || t == 'Couplé Placé';
  }

  /// Nombre de chevaux requis selon le type de pari
  int get _nbChevauxRequis {
    switch (_typesPari[_typePariIndex]) {
      case 'Couplé Gagnant': return 2;
      case 'Couplé Placé':   return 2;
      case 'Tiercé':         return 3;
      case 'Quarté+':        return 4;
      case 'Quinté+':        return 5;
      default:               return 1;
    }
  }

  /// Liste des numéros finaux à jouer (manuel ou auto-IA)
  List<int> get _numerosFinaux {
    if (_modeManuel && _numerosManuelsSel.isNotEmpty) {
      final list = _numerosManuelsSel.toList()..sort();
      return list.take(_nbChevauxRequis).toList();
    }
    // Mode auto : cheval principal + meilleurs IA
    final partantsIA = widget.course.partantsParRangIA;
    final numerosAuto = <int>[];
    final numPrincipal = int.tryParse(_chevalSelectionne?.numero ?? '');
    if (numPrincipal != null) numerosAuto.add(numPrincipal);
    for (final p in partantsIA) {
      if (numerosAuto.length >= _nbChevauxRequis) break;
      final n = int.tryParse(p.numero);
      if (n != null && !numerosAuto.contains(n)) numerosAuto.add(n);
    }
    return numerosAuto;
  }

  /// Cote Gagnant brute du cheval sélectionné
  double get _coteGagnant {
    if (_chevalSelectionne == null) return 2.5;
    final c = _chevalSelectionne!.coteDecimale;
    return (c > 1 && c < 99) ? c : 2.5;
  }

  /// Cote Placé réelle PMU = (coteGagnant - 1) / diviseur + 1
  double get _cotePlacee =>
      GainCalculator.cotePlaceDepuisGagnant(_coteGagnant, _nbPartants);

  /// Cote affichée selon le TYPE de pari sélectionné
  double get _coteAffichee {
    final type = _typesPari[_typePariIndex];
    switch (type) {
      case 'Simple Placé':  return _cotePlacee;
      case 'Gagnant+Placé':  return _coteGagnant; // mise ×2, on affiche Gagnant
      case 'Couplé Placé':   return _cotePlacee;
      default:               return _coteGagnant;
    }
  }

  /// Gain estimé net selon le type de pari sélectionné
  double get _gainEstime {
    try {
    final type = _typesPari[_typePariIndex];
    switch (type) {
      case 'Simple Gagnant':
        return _mise * _coteGagnant - _mise;
      case 'Simple Placé':
        return _mise * _cotePlacee - _mise;
      case 'Gagnant+Placé':
        return _mise * _coteGagnant + _mise * _cotePlacee - _mise * 2;
      case 'Couplé Gagnant':
        // Estimation : cote1 × cote2 / facteur PMU ≈ 0.7
        return _mise * _getCoupleGagnantEstime() - _mise;
      case 'Couplé Placé':
        // Estimation : cotes placées réduites
        return _mise * _getCouplePlaceEstime() - _mise;
      case 'Tiercé':
        final cotes = _getCotes3();
        return GainCalculator.tierce(_mise, cotes, _nbPartants).gainNet;
      case 'Quarté+':
        final cotes = _getCotes4();
        return GainCalculator.quarte(_mise, cotes, _nbPartants).gainNet;
      case 'Quinté+':
        final cotes = _getCotes5();
        return GainCalculator.quinte(_mise, cotes, _nbPartants).gainNet;
      default:
        return _mise * _coteGagnant - _mise;
    }
    } catch (e) {
      debugPrint('[BetSheet] _gainEstime erreur : \$e');
      return 0.0;
    }
  }

  /// Retour total du billet si gagnant (ce que le billet rapporte, mise incluse)
  /// À utiliser pour l'AFFICHAGE sur le billet — différent de _gainEstime (gain net)
  double get _retourTotal => _gainEstime + _mise;

  /// Estimation cote Couplé Gagnant (2 chevaux dans le top 2, ordre indéfini)
  double _getCoupleGagnantEstime() {
    final cotes = _getCotes2();
    if (cotes.length < 2) return _coteGagnant * 1.5;
    // Formule approximative PMU : (c1 * c2) * 0.65 (marge PMU ~35%)
    return (cotes[0] * cotes[1] * 0.65).clamp(1.5, 999.0);
  }

  /// Estimation cote Couplé Placé (2 chevaux dans le top 3)
  double _getCouplePlaceEstime() {
    final cotes = _getCotes2();
    if (cotes.length < 2) return _cotePlacee * 1.3;
    final cp1 = GainCalculator.cotePlaceDepuisGagnant(cotes[0], _nbPartants);
    final cp2 = GainCalculator.cotePlaceDepuisGagnant(cotes[1], _nbPartants);
    return (cp1 * cp2 * 0.7).clamp(1.2, 99.0);
  }

  /// 2 cotes des chevaux sélectionnés (ou top-2 IA)
  List<double> _getCotes2() {
    final nums = _numerosFinaux.take(2).toList();
    final partants = widget.course.partants;
    final result = <double>[];
    for (final num in nums) {
      final p = partants.where((x) => int.tryParse(x.numero) == num).firstOrNull;
      if (p != null) {
        final c = p.coteDecimale;
        result.add((c > 1 && c < 90) ? c : 5.0);
      } else {
        result.add(5.0);
      }
    }
    while (result.length < 2) result.add(5.0);
    return result;
  }

  /// Mise réellement engagée (×2 pour Gagnant+Placé)
  double get _miseReelle {
    if (_typesPari[_typePariIndex] == 'Gagnant+Placé') return _mise * 2;
    return _mise;
  }

  List<double> _getCotes3() {
    final p = widget.course.partantsParRangIA;
    return p.take(3).map((x) {
      final c = x.coteDecimale; return (c > 1 && c < 90) ? c : 5.0;
    }).toList()..addAll(List.filled((3 - p.length).clamp(0, 3), 6.0));
  }

  List<double> _getCotes4() {
    final p = widget.course.partantsParRangIA;
    return p.take(4).map((x) {
      final c = x.coteDecimale; return (c > 1 && c < 90) ? c : 6.0;
    }).toList()..addAll(List.filled((4 - p.length).clamp(0, 4), 7.0));
  }

  List<double> _getCotes5() {
    final p = widget.course.partantsParRangIA;
    return p.take(5).map((x) {
      final c = x.coteDecimale; return (c > 1 && c < 90) ? c : 7.0;
    }).toList()..addAll(List.filled((5 - p.length).clamp(0, 5), 8.0));
  }

  bool get _peutValider {
    if (_sansPartants) return true;
    // Pour un Couplé : il faut exactement 2 numéros sélectionnés
    if (_estCouple) {
      return _numerosFinaux.length >= 2;
    }
    // Pour Tiercé/Quarté/Quinté en mode manuel : vérifier nb requis
    if (_estPariCombi && _modeManuel) {
      return _numerosManuelsSel.length >= _nbChevauxRequis;
    }
    return _chevalSelectionne != null;
  }

  // ── Recommandation IA du type de pari ───────────────────────────────────────
  // Retourne : {index, label, emoji, raison, couleur, risque}
  Map<String, dynamic> get _conseilIA {
    try {
    final score  = _chevalSelectionne?.scoreIA ?? 0.0;
    final coteG  = _coteGagnant;
    final nb     = _nbPartants;
    final isQ    = widget.course.isQuinte;
    // ★ v9.93 : Grande course classique → pas de Quarté/Quinté
    final isClassique = widget.course.isClassiqueSansMultiple;

    // ── Indice de compétitivité : écart entre les 2 premiers chevaux IA ────
    final top2 = widget.course.partantsParRangIA.take(2).toList();
    final score2 = top2.length >= 2 ? top2[1].scoreIA : 0.0;
    final ecartTop2 = (score - score2).abs();
    // Si les 2 premiers sont très proches (≤15 pts) et scores ≥60 → Couplé
    final estCourseEquilibree = !isQ && !isClassique && ecartTop2 <= 15 && score >= 60 && score2 >= 50;

    // ── ★ v9.93 : Grande course classique — Quarté/Quinté impossibles ──────
    if (isClassique) {
      final top3 = widget.course.partantsParRangIA.take(3).toList();
      final s3 = top3.length >= 3 ? top3[2].scoreIA : 0.0;
      if (score >= 75 && score2 >= 55 && s3 >= 45) {
        return {
          'index': 5, 'emoji': '📋', 'label': 'Tiercé',
          'risque': 'Risque modéré',
          'risqueColor': const Color(0xFFAB47BC),
          'raison': 'Grande course classique (Groupe 1/2) — seuls Simple, Couplé et Tiercé sont disponibles sur PMU. '
              'L\'IA conseille le Tiercé avec N°${top3.isNotEmpty ? top3[0].numero : "?"}, '
              '${top3.length > 1 ? "N°${top3[1].numero}" : ""}, '
              '${top3.length > 2 ? "N°${top3[2].numero}" : ""}.',
          'probabilite': GainCalculator.tierce(_mise, _getCotes3(), nb).probabiliteEstimee,
          'gainEstime': GainCalculator.tierce(_mise, _getCotes3(), nb).gainNet,
        };
      }
      if (score >= 80 && coteG <= 8.0) {
        return {
          'index': 0, 'emoji': '🏆', 'label': 'Simple Gagnant',
          'risque': 'Risque modéré',
          'risqueColor': const Color(0xFF4CAF7D),
          'raison': 'Grande course classique — favori IA dominant (${score.round()}/100). '
              'Simple Gagnant recommandé (Quarté/Quinté non disponibles sur cette course).',
          'probabilite': _coteToProbaPct(coteG),
          'gainEstime': _mise * coteG - _mise,
        };
      }
      return {
        'index': 1, 'emoji': '🎯', 'label': 'Simple Placé',
        'risque': 'Risque faible',
        'risqueColor': const Color(0xFF4CAF7D),
        'raison': 'Grande course classique — Paris Classiques uniquement (pas de Quarté/Quinté). '
            'Simple Placé pour limiter le risque sur cette course de prestige.',
        'probabilite': (_coteToProbaPct(coteG) * 2.5).clamp(5, 85),
        'gainEstime': _mise * _cotePlacee - _mise,
      };
    }

    // ── Règles de décision ──────────────────────────────────────────────────

    // Cas Couplé : 2 chevaux IA très proches en score → Couplé Gagnant
    if (estCourseEquilibree && score >= 75) {
      // index 3 = 'Couplé Gagnant' dans la nouvelle liste
      return {
        'index': 3, // Couplé Gagnant
        'emoji': '💑',
        'label': 'Couplé Gagnant',
        'risque': 'Risque modéré',
        'risqueColor': const Color(0xFF4CAF7D),
        'raison':
            'Les 2 favoris IA sont très proches (${score.round()} vs ${score2.round()}/100). '
            'Le Couplé Gagnant couvre les 2 issues : '
            '${top2.isNotEmpty ? "N°${top2[0].numero} ${top2[0].nom}" : "favori 1"} '
            'et ${top2.length > 1 ? "N°${top2[1].numero} ${top2[1].nom}" : "favori 2"} '
            'dans le top 2 (ordre indifférent).',
        'probabilite': (_coteToProbaPct(coteG) * 1.8).clamp(5.0, 80.0),
        'gainEstime': _mise * _getCoupleGagnantEstime() - _mise,
      };
    }

    // Couplé Placé : scores bons mais moins dominants
    if (estCourseEquilibree && score >= 60 && score < 75) {
      return {
        'index': 4, // Couplé Placé
        'emoji': '💑🎯',
        'label': 'Couplé Placé',
        'risque': 'Risque faible',
        'risqueColor': const Color(0xFF4CAF7D),
        'raison':
            'Deux chevaux à niveau similaire (${score.round()} vs ${score2.round()}/100). '
            'Le Couplé Placé est l\'option la plus sécurisée : '
            '${top2.isNotEmpty ? "N°${top2[0].numero}" : "N°1"} et '
            '${top2.length > 1 ? "N°${top2[1].numero}" : "N°2"} '
            'doivent tous les deux finir dans le top 3.',
        'probabilite': (_coteToProbaPct(coteG) * 2.2).clamp(5.0, 85.0),
        'gainEstime': _mise * _getCouplePlaceEstime() - _mise,
      };
    }

    // Score très élevé (≥80) + cote raisonnable (≤8) → Simple Gagnant
    if (!isQ && score >= 80 && coteG <= 8.0) {
      return {
        'index': 0, // Simple Gagnant
        'emoji': '🏆',
        'label': 'Simple Gagnant',
        'risque': 'Risque modéré',
        'risqueColor': const Color(0xFF4CAF7D),
        'raison':
            'Score IA très élevé (${score.round()}/100) — forte confiance '
            'sur ce cheval. La cote ×${coteG.toStringAsFixed(1)} offre un '
            'bon rapport gain/risque. Mise recommandée : ${_mise.toStringAsFixed(0)} €.',
        'probabilite': _coteToProbaPct(coteG),
        'gainEstime': _mise * coteG - _mise,
      };
    }

    // Score élevé (≥80) + cote élevée (>8) → Gagnant+Placé pour sécuriser
    if (!isQ && score >= 80 && coteG > 8.0) {
      return {
        'index': 2, // Gagnant+Placé
        'emoji': '🎯🏆',
        'label': 'Gagnant + Placé',
        'risque': 'Risque couvert',
        'risqueColor': const Color(0xFF4CAF7D),
        'raison':
            'Score IA élevé (${score.round()}/100) mais cote longue '
            '×${coteG.toStringAsFixed(1)}. Le Gagnant+Placé vous garantit '
            'un retour si votre cheval finit dans le top 3 (mise ×2 = '
            '${(_mise * 2).toStringAsFixed(0)} €).',
        'probabilite': (_coteToProbaPct(coteG) * 2.8).clamp(5, 85),
        'gainEstime': _mise * _cotePlacee - _mise * 2,
      };
    }

    // Score bon (65-79) → Placé pour limiter le risque
    if (!isQ && score >= 65 && score < 80) {
      return {
        'index': 1, // Simple Placé
        'emoji': '🎯',
        'label': 'Simple Placé',
        'risque': 'Risque faible',
        'risqueColor': const Color(0xFF4CAF7D),
        'raison':
            'Score IA correct (${score.round()}/100) — confiance suffisante '
            'pour un top 3. Le Placé (cote ×${_cotePlacee.toStringAsFixed(2)}) '
            'réduit le risque tout en offrant un gain intéressant. '
            'Idéal si le cheval a tendance à finir 2e ou 3e.',
        'probabilite': (_coteToProbaPct(coteG) * 2.5).clamp(5, 85),
        'gainEstime': _mise * _cotePlacee - _mise,
      };
    }

    // Score moyen (50-64) → Gagnant+Placé pour couvrir les 2 cas
    if (!isQ && score >= 50 && score < 65) {
      return {
        'index': 2, // Gagnant+Placé
        'emoji': '🎯🏆',
        'label': 'Gagnant + Placé',
        'risque': 'Risque modéré',
        'risqueColor': const Color(0xFFFFB74D),
        'raison':
            'Score IA moyen (${score.round()}/100) — résultat incertain. '
            'Le Gagnant+Placé vous couvre : si 1er vous touchez le max, '
            'si 2e/3e vous récupérez une partie. Mise ×2 = '
            '${(_mise * 2).toStringAsFixed(0)} €.',
        'probabilite': (_coteToProbaPct(coteG) * 2.0).clamp(5, 70),
        'gainEstime': _mise * _cotePlacee - _mise * 2,
      };
    }

    // Score faible (<50) + course Quinté → Quinté+
    if (isQ || (score < 50 && nb >= 10)) {
      return {
        'index': 7, // Quinté+
        'emoji': '🌟',
        'label': 'Quinté+',
        'risque': 'Risque élevé / Gros gains',
        'risqueColor': const Color(0xFFEF5350),
        'raison':
            isQ
            ? 'Course Quinté+ officielle — c\'est le pari phare de la journée. '
              'L\'IA a sélectionné les 5 meilleurs chevaux pour maximiser vos '
              'chances. Dividende fixé par PMU après la course.'
            : 'Score IA faible (${score.round()}/100) — cheval incertain en '
              'Simple. Le Quinté+ avec la sélection IA complète (5 chevaux) '
              'offre des gains bien supérieurs pour une mise identique.',
        'probabilite': (GainCalculator.quinte(_mise, _getCotes5(), nb).probabiliteEstimee),
        'gainEstime': GainCalculator.quinte(_mise, _getCotes5(), nb).gainNet,
      };
    }

    // Score très faible (<35) → Tiercé comme compromis
    return {
      'index': 5, // Tiercé
      'emoji': '📋',
      'label': 'Tiercé',
      'risque': 'Risque élevé',
      'risqueColor': const Color(0xFFEF5350),
      'raison':
          'Score IA faible (${score.round()}/100). En Simple, le risque '
          'est trop élevé. Le Tiercé avec la sélection IA des 3 meilleurs '
          'chevaux offre un meilleur rapport gain/probabilité.',
      'probabilite': GainCalculator.tierce(_mise, _getCotes3(), nb).probabiliteEstimee,
      'gainEstime': GainCalculator.tierce(_mise, _getCotes3(), nb).gainNet,
    };
    } catch (e) {
      debugPrint('[BetSheet] _conseilIA erreur : \$e');
      return {'index':0,'emoji':'📊','label':'Simple Gagnant','risque':'Modéré','risqueColor':const Color(0xFF78909C),'raison':'Données insuffisantes.','probabilite':20.0,'gainEstime':_mise*2.5-_mise};
    }
  }

  double _coteToProbaPct(double cote) {
    if (cote <= 1) return 0;
    return (1 / cote * 100).clamp(1.0, 95.0);
  }

  int get _numReunion {
    final m = RegExp(r'R(\d+)').firstMatch(widget.reunion.code);
    return int.tryParse(m?.group(1) ?? '1') ?? 1;
  }

  String get _courseKey {
    if (widget.overrideKey != null) return widget.overrideKey!;
    // ★ Fix écran gris : inclure la date pour éviter les collisions entre journées
    // Format identique à buildCourseKey() : R3C5_23042026 (ddmmyyyy)
    final d = widget.course.heureDateTime;
    final dateStr = '${d.day.toString().padLeft(2,'0')}${d.month.toString().padLeft(2,'0')}${d.year}';
    return 'R${_numReunion}C${widget.course.numCourse}_$dateStr';
  }

  Color _scoreColor(double score) {
    if (score >= 80) return _gold;
    if (score >= 65) return const Color(0xFF00C853);
    if (score >= 50) return _green;
    if (score >= 35) return const Color(0xFF9C27B0);
    return const Color(0xFFEF5350);
  }

  @override
  Widget build(BuildContext context) {
    // ★ Fix doublon : utiliser estDejaEnSuivi (cherche par préfixe baseKey)
    // isSuivi(key) cherche la clé exacte mais les storageKeys ont un timestamp
    final dejasuivi = widget.alertService.estDejaEnSuivi(_courseKey);

    return DraggableScrollableSheet(
      initialChildSize: 0.96,
      minChildSize: 0.5,
      maxChildSize: 1.0,
      expand: false,
      builder: (ctx, sheetScrollCtrl) {
        try {
          // Padding bas = nav bar Android (système)
          final bottomPad = MediaQuery.of(ctx).padding.bottom;
          return Container(
            decoration: const BoxDecoration(
              color: _dark,
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
            ),
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 6),
                  width: 44, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                _buildHeader(),
                if (dejasuivi) _buildDejasuiviBanner(ctx),
                _buildTabBar(),
                Expanded(
                  child: TabBarView(
                    controller: _tabController!,
                    children: [
                      _buildTabPari(sheetScrollCtrl, bottomPad),
                      _buildTabBookmakers(sheetScrollCtrl, bottomPad),
                      _buildTabCalculateur(sheetScrollCtrl, bottomPad),
                    ],
                  ),
                ),
              ],
            ),
          );
        } catch (e, stack) {
          // ★ Fix écran gris silencieux : si le build crash en release,
          // affiche un message d'erreur visible au lieu d'un fond transparent.
          debugPrint('[BetSheet] build crash: $e\n$stack');
          return Container(
            decoration: const BoxDecoration(
              color: Color(0xFF1A0A00),
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
            ),
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 8, bottom: 16),
                    width: 44, height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const Text('🔴 Erreur d\'affichage',
                      style: TextStyle(color: Colors.red, fontSize: 16,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(
                    'Course : ${widget.course.nom} (R${_numReunion}C${widget.course.numCourse})',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  Text(e.toString(),
                      style: const TextStyle(color: Colors.orange, fontSize: 12)),
                  const SizedBox(height: 8),
                  Text(
                    stack.toString().split('\n').take(6).join('\n'),
                    style: const TextStyle(color: Colors.white30, fontSize: 10),
                  ),
                ],
              ),
            ),
          );
        }
      },
    );
  }

  // ── TabBar ──────────────────────────────────────────────────────────────────

  Widget _buildTabBar() {
    return Container(
      color: _card,
      child: TabBar(
        controller: _tabController!,
        indicatorColor: _green,
        indicatorWeight: 2.5,
        labelColor: _green,
        unselectedLabelColor: Colors.white38,
        labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        tabs: const [
          Tab(text: '💰 Parier', icon: null),
          Tab(text: '🏦 Sites', icon: null),
          Tab(text: '📊 Calculateur', icon: null),
        ],
      ),
    );
  }

  // ── Onglet 1 : Pari ─────────────────────────────────────────────────────────

  Widget _buildTabPari(ScrollController sheetCtrl, double bottomPad) {
    final extraBottom = 40.0 + bottomPad;

    // Aucune cote PMU disponible — course étrangère ou cotes pas encore publiées
    if (_sansCote && !_sansPartants) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('⚠️', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 16),
              const Text(
                'Cotes PMU non disponibles',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              // Toutes les courses affichées sont françaises (filtre zone_turf_service).
              // Si les cotes manquent, c'est uniquement parce qu'elles ne sont pas
              // encore publiées par PMU (généralement 1h avant le départ).
              Column(children: [
                Text(
                  'Les cotes ne sont pas encore publiées par PMU pour cette course.\nRevenez environ 1h avant le départ.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 14, height: 1.5),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFB74D).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFFB74D).withValues(alpha: 0.4)),
                  ),
                  child: const Text(
                    '💡 Les cotes PMU sont généralement disponibles 1h avant le départ de la course.',
                    style: TextStyle(color: Color(0xFFFFB74D), fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ),
              ]),
            ],
          ),
        ),
      );
    }

    return ListView(
      controller: sheetCtrl,
      padding: EdgeInsets.fromLTRB(18, 14, 18, extraBottom),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        _buildChevalSelector(),
        const SizedBox(height: 14),
        _buildMiseSelector(),
        const SizedBox(height: 14),
        // ── Tableau comparatif TOUS les types de paris ──
        _buildTableauComparatifParis(),
        const SizedBox(height: 14),
        _buildConseilIA(),
        const SizedBox(height: 14),
        _buildTypePariSelector(),
        const SizedBox(height: 14),
        // Sélection manuelle uniquement pour paris combinés
        if (_estPariCombi) ...[
          _buildSelectionManuelleHeader(),
          const SizedBox(height: 10),
          if (_modeManuel) _buildGrilleNumeros(),
          const SizedBox(height: 14),
        ],
        _buildGainPreview(),
        const SizedBox(height: 20),
        _buildValiderBtn(context),
        const SizedBox(height: 14),
        _buildAccesRapideBookmakers(),
        const SizedBox(height: 20),
      ],
    );
  }

  // ── Tableau comparatif de tous les types de paris ────────────────────────────
  Widget _buildTableauComparatifParis() {
    final coteG  = _coteGagnant;
    final coteP  = _cotePlacee;
    final nb     = _nbPartants;
    final cotes3 = _getCotes3();
    final cotes4 = _getCotes4();
    final cotes5 = _getCotes5();
    final m      = _mise;

    // Construction des lignes : [emoji, nom, mise réelle, scénarios]
    // Chaque entrée : {emoji, nom, miseR, scenarios: [{label, gain, color}]}
    final rows = <Map<String, dynamic>>[
      {
        'emoji': '🏆', 'nom': 'Simple Gagnant', 'miseR': m,
        'coteLabel': '×${coteG.toStringAsFixed(2)}',
        'scenarios': [
          {'label': '1er ✅', 'gain': m * coteG - m, 'color': const Color(0xFF4CAF7D)},
          {'label': '2e+ ❌', 'gain': -m, 'color': const Color(0xFFEF5350)},
        ],
      },
      {
        'emoji': '🎯', 'nom': 'Simple Placé', 'miseR': m,
        'coteLabel': '×${coteP.toStringAsFixed(2)}',
        'scenarios': [
          {'label': 'Top3 ✅', 'gain': m * coteP - m, 'color': const Color(0xFF4CAF7D)},
          {'label': '4e+ ❌', 'gain': -m, 'color': const Color(0xFFEF5350)},
        ],
      },
      {
        'emoji': '🎯🏆', 'nom': 'Gagnant+Placé', 'miseR': m * 2,
        'coteLabel': '×2 mise',
        'scenarios': [
          {'label': '1er ✅✅', 'gain': m * coteG + m * coteP - m * 2, 'color': const Color(0xFF4CAF7D)},
          {'label': '2e/3e 🥈', 'gain': m * coteP - m * 2, 'color': const Color(0xFFFFB74D)},
          {'label': '4e+ ❌', 'gain': -m * 2, 'color': const Color(0xFFEF5350)},
        ],
      },
      {
        'emoji': '🔗', 'nom': 'Couplé Gagnant', 'miseR': m,
        'coteLabel': '≈×${(() { final cg = GainCalculator.couple(m, cotes3.isNotEmpty ? cotes3[0] : coteG, cotes3.length >= 2 ? cotes3[1] : coteG * 0.6); return ((cg.gainNet + m) / m).toStringAsFixed(1); })()}',
        'scenarios': () {
          final r = GainCalculator.couple(m, cotes3.isNotEmpty ? cotes3[0] : coteG, cotes3.length >= 2 ? cotes3[1] : coteG * 0.6);
          return [
            {'label': 'Top2 ✅', 'gain': r.gainNet, 'color': const Color(0xFF4CAF7D)},
            {'label': 'Raté ❌', 'gain': -m, 'color': const Color(0xFFEF5350)},
          ];
        }(),
      },
      {
        'emoji': '🔗🎯', 'nom': 'Couplé Placé', 'miseR': m,
        'coteLabel': '2 ds top3',
        'scenarios': [
          {'label': 'Top3 ✅', 'gain': m * _getCouplePlaceEstime() - m, 'color': const Color(0xFF4CAF7D)},
          {'label': 'Raté ❌', 'gain': -m, 'color': const Color(0xFFEF5350)},
        ],
      },
      {
        'emoji': '📋', 'nom': 'Tiercé', 'miseR': m,
        'coteLabel': '3 dans top3',
        'scenarios': () {
          final r = GainCalculator.tierce(m, cotes3, nb);
          return [
            {'label': 'En ordre ✅', 'gain': r.gainNet, 'color': const Color(0xFF4CAF7D)},
            {'label': 'Désordre 🥈', 'gain': r.gainSiDesordre ?? 0, 'color': const Color(0xFFFFB74D)},
            {'label': 'Raté ❌', 'gain': -m, 'color': const Color(0xFFEF5350)},
          ];
        }(),
      },
      {
        'emoji': '🎰', 'nom': 'Quarté+', 'miseR': m,
        'coteLabel': '4 dans top4',
        'scenarios': () {
          final r = GainCalculator.quarte(m, cotes4, nb);
          return [
            {'label': 'En ordre ✅', 'gain': r.gainNet, 'color': const Color(0xFF4CAF7D)},
            {'label': 'Désordre 🥈', 'gain': r.gainSiDesordre ?? 0, 'color': const Color(0xFFFFB74D)},
            {'label': 'Raté ❌', 'gain': -m, 'color': const Color(0xFFEF5350)},
          ];
        }(),
      },
      {
        'emoji': '🌟', 'nom': 'Quinté+', 'miseR': m,
        'coteLabel': '5 dans top5',
        'scenarios': () {
          final r = GainCalculator.quinte(m, cotes5, nb);
          return [
            {'label': 'En ordre ✅', 'gain': r.gainNet, 'color': const Color(0xFF4CAF7D)},
            {'label': 'Désordre 🥈', 'gain': r.gainSiDesordre ?? 0, 'color': const Color(0xFFFFB74D)},
            {'label': 'Bonus 4/5 ⭐', 'gain': r.gainBonus4sur5 ?? 0, 'color': const Color(0xFF64B5F6)},
            {'label': 'Raté ❌', 'gain': -m, 'color': const Color(0xFFEF5350)},
          ];
        }(),
      },
    ];

    // Conseil IA actuel — pour mettre en avant le type recommandé
    final conseilLabel = (_conseilIA['label'] as String? ?? '').toLowerCase();
    String _typeRecommande() {
      if (conseilLabel.contains('quinté')) return 'Quinté+';
      if (conseilLabel.contains('quarté')) return 'Quarté+';
      if (conseilLabel.contains('tiercé')) return 'Tiercé';
      if (conseilLabel.contains('couplé gagnant')) return 'Couplé Gagnant';
      if (conseilLabel.contains('couplé placé')) return 'Couplé Placé';
      if (conseilLabel.contains('placé')) return 'Simple Placé';
      if (conseilLabel.contains('gagnant+placé') || conseilLabel.contains('gagnant + placé')) return 'Gagnant+Placé';
      return 'Simple Gagnant';
    }
    final typeRecom = _typeRecommande();

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D1520),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // En-tête
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF1A2F3D),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(children: [
              const Text('📊', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              const Text('Tous les types de paris',
                  style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD700).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('Mise : ${m.toStringAsFixed(0)}€',
                    style: const TextStyle(color: Color(0xFFFFD700), fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ]),
          ),
          const Divider(height: 1, color: Color(0xFF1E3A4A)),
          // Lignes du tableau
          ...rows.asMap().entries.map((entry) {
            final i = entry.key;
            final row = entry.value;
            final nom = row['nom'] as String;
            final isRecom = nom == typeRecom;
            final scenarios = row['scenarios'] as List<Map<String, dynamic>>;
            final isLast = i == rows.length - 1;

            return Container(
              decoration: BoxDecoration(
                color: isRecom
                    ? const Color(0xFF4CAF7D).withValues(alpha: 0.06)
                    : Colors.transparent,
                borderRadius: isLast
                    ? const BorderRadius.vertical(bottom: Radius.circular(14))
                    : BorderRadius.zero,
                border: isRecom
                    ? Border(left: BorderSide(color: const Color(0xFF4CAF7D), width: 3))
                    : null,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Ligne titre
                  Row(children: [
                    Text(row['emoji'] as String, style: const TextStyle(fontSize: 16)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Row(children: [
                        Text(nom,
                            style: TextStyle(
                              color: isRecom ? const Color(0xFF4CAF7D) : Colors.white,
                              fontSize: 14,
                              fontWeight: isRecom ? FontWeight.bold : FontWeight.w500,
                            )),
                        if (isRecom) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: const Color(0xFF4CAF7D).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('✨ IA', style: TextStyle(color: Color(0xFF4CAF7D), fontSize: 10, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ]),
                    ),
                    Text(row['coteLabel'] as String,
                        style: TextStyle(
                          color: isRecom ? const Color(0xFFFFD700) : Colors.white38,
                          fontSize: 12, fontWeight: FontWeight.w600,
                        )),
                  ]),
                  const SizedBox(height: 6),
                  // Scénarios gains/pertes
                  Wrap(
                    spacing: 6, runSpacing: 4,
                    children: scenarios.map((s) {
                      final gain = (s['gain'] as num).toDouble();
                      final col = s['color'] as Color;
                      final gainStr = gain >= 0
                          ? '+${fmtEuros(gain)}€'
                          : '${fmtEuros(gain)}€';
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: col.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: col.withValues(alpha: 0.30)),
                        ),
                        child: RichText(
                          text: TextSpan(children: [
                            TextSpan(text: '${s['label']}  ',
                                style: const TextStyle(color: Colors.white54, fontSize: 12)),
                            TextSpan(text: gainStr,
                                style: TextStyle(color: col, fontSize: 13, fontWeight: FontWeight.bold)),
                          ]),
                        ),
                      );
                    }).toList(),
                  ),
                  if (i < rows.length - 1)
                    const Divider(height: 14, color: Color(0xFF1E3A4A)),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  // ── Widget Conseil IA ────────────────────────────────────────────────────────

  Widget _buildConseilIA() {
    final conseil = _conseilIA;
    final emoji        = conseil['emoji']        as String;
    final label        = conseil['label']        as String;
    final raison       = conseil['raison']       as String;
    final risque       = conseil['risque']       as String;
    final risqueColor  = conseil['risqueColor']  as Color;
    final probabilite  = (conseil['probabilite']  as num).toDouble();
    final gainEstime   = (conseil['gainEstime']   as num).toDouble();
    final indexConseil = conseil['index']        as int;

    final isDejaApplique = _typePariIndex == indexConseil;

    // Couleur de probabilité
    final probaColor = probabilite >= 40
        ? const Color(0xFF4CAF7D)
        : probabilite >= 20
            ? const Color(0xFFFFB74D)
            : const Color(0xFFEF5350);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1A2E1A).withValues(alpha: 0.9),
            const Color(0xFF0D1B0D).withValues(alpha: 0.9),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDejaApplique
              ? _gold.withValues(alpha: 0.6)
              : _green.withValues(alpha: 0.4),
          width: isDejaApplique ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── En-tête : "Conseil IA"
          Row(children: [
            Icon(Icons.psychology, color: _gold, size: 18),
            const SizedBox(width: 6),
            Expanded(child: Text(
              'Conseil IA — Type de pari recommandé',
              style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            )),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: risqueColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: risqueColor.withValues(alpha: 0.4)),
              ),
              child: Text(risque,
                  style: TextStyle(color: risqueColor, fontSize: 10, fontWeight: FontWeight.bold)),
            ),
          ]),
          const SizedBox(height: 10),

          // ── Type recommandé + probabilité
          Row(children: [
            Container(
              width: 44, height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _gold.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _gold.withValues(alpha: 0.3)),
              ),
              child: Text(emoji, style: const TextStyle(fontSize: 20)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 4),
                  Row(children: [
                    // Badge probabilité
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: probaColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '~${probabilite.toStringAsFixed(0)}% de réussite',
                        style: TextStyle(color: probaColor, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Gain estimé
                    Text(
                      gainEstime > 0
                          ? '+${fmtEuros(gainEstime)} € estimé'
                          : '${fmtEuros(gainEstime)} € estimé',
                      style: TextStyle(
                        color: gainEstime > 0 ? _gold : const Color(0xFFEF5350),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 10),

          // ── Explication de l'IA
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              raison,
              style: const TextStyle(color: Colors.white60, fontSize: 12, height: 1.4),
            ),
          ),
          const SizedBox(height: 10),

          // ── Bouton "Appliquer ce conseil"
          SizedBox(
            width: double.infinity,
            child: isDejaApplique
                ? Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _gold.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _gold.withValues(alpha: 0.4)),
                    ),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.check_circle, color: _gold, size: 16),
                      const SizedBox(width: 6),
                      Text('Type "$label" déjà sélectionné',
                          style: TextStyle(color: _gold, fontSize: 13, fontWeight: FontWeight.bold)),
                    ]),
                  )
                : ElevatedButton.icon(
                    icon: const Icon(Icons.auto_fix_high, size: 16),
                    label: Text('Appliquer : $label',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _dgreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => setState(() => _typePariIndex = indexConseil),
                  ),
          ),
        ],
      ),
    );
  }

  // ── Onglet 2 : Sites de paris ────────────────────────────────────────────────

  Widget _buildTabBookmakers(ScrollController sheetCtrl, double bottomPad) {
    final cote = _coteAffichee;
    final cotes = BookmakerService.getCotesTriees(cote);
    final extraBottom = 80.0 + bottomPad;

    return ListView(
      controller: sheetCtrl,
      padding: EdgeInsets.fromLTRB(18, 14, 18, extraBottom),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [const Color(0xFF1A3A5C), const Color(0xFF0D1B2A)],
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '🏦 Où parier en ligne ?',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                _chevalSelectionne != null
                    ? 'Meilleure cote pour ${_chevalSelectionne!.nom} (N°${_chevalSelectionne!.numero})'
                    : 'Choisissez votre site de paris préféré',
                style: const TextStyle(color: Colors.white54, fontSize: 14),
              ),
              if (cote > 1) ...[
                const SizedBox(height: 8),
                Row(children: [
                  const Icon(Icons.info_outline, color: Colors.white38, size: 13),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Cotes estimées basées sur la cote PMU ×${cote.toStringAsFixed(1)}. Les cotes réelles peuvent varier.',
                      style: const TextStyle(color: Colors.white38, fontSize: 14),
                    ),
                  ),
                ]),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Carte PMU — toujours en premier
        _buildBookmakerCard(
          BookmakerCote(
            bookmaker: const BookmakerInfo(
              nom: 'PMU',
              emoji: '🇫🇷',
              couleur: 0xFF1B5E20,
              facteurMarge: 1.00,
              urlBase: 'https://www.pmu.fr',
              urlApp: 'https://www.pmu.fr/turf/offre/courses',
              description: 'Opérateur officiel français',
              bonus: '',
            ),
            cote: cote,
            isMeilleure: false,
          ),
          horseName: _chevalSelectionne?.nom,
          isPmu: true,
        ),
        const SizedBox(height: 8),

        // Comparateur cotes (si cote disponible)
        if (cote > 1 && cotes.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _gold.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _gold.withValues(alpha: 0.3)),
            ),
            child: Row(children: [
              const Text('⚡', style: TextStyle(fontSize: 14)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Meilleure cote : ${cotes.first.cote.toStringAsFixed(2)} chez ${cotes.first.bookmaker.nom} — soit +${BookmakerService.bonusCoteVsPmu(cote, cotes.first.cote).toStringAsFixed(0)}% vs PMU',
                  style: const TextStyle(color: _gold, fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 10),
        ],

        // Autres bookmakers
        ...cotes.map((bc) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _buildBookmakerCard(bc, horseName: _chevalSelectionne?.nom),
        )),

        const SizedBox(height: 10),
        const Divider(color: Colors.white12),
        const SizedBox(height: 8),
        const Text(
          '⚠️ Pariez de manière responsable. Les paris comportent des risques de perte.',
          style: TextStyle(color: Colors.white24, fontSize: 13),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildBookmakerCard(BookmakerCote bc, {String? horseName, bool isPmu = false}) {
    final bm = bc.bookmaker;
    final bmColor = Color(bm.couleur);
    final gain = (bc.cote * _mise) - _mise;

    return GestureDetector(
      onTap: () => _ouvrirBookmaker(bm, horseName),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: bc.isMeilleure
              ? bmColor.withValues(alpha: 0.18)
              : _card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: bc.isMeilleure
                ? bmColor.withValues(alpha: 0.6)
                : isPmu
                    ? Colors.white.withValues(alpha: 0.15)
                    : Colors.white.withValues(alpha: 0.08),
            width: bc.isMeilleure ? 1.5 : 1.0,
          ),
        ),
        child: Row(children: [
          // Emoji + couleur
          Container(
            width: 42, height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: bmColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: bmColor.withValues(alpha: 0.4)),
            ),
            child: Text(bm.emoji, style: const TextStyle(fontSize: 20)),
          ),
          const SizedBox(width: 12),
          // Nom + description
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(
                    bm.nom,
                    style: TextStyle(
                      color: bc.isMeilleure ? bmColor : Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  if (bc.isMeilleure) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _gold.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: _gold.withValues(alpha: 0.5)),
                      ),
                      child: const Text('MEILLEURE COTE', style: TextStyle(color: _gold, fontSize: 14, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ]),
                Text(bm.description, style: const TextStyle(color: Colors.white38, fontSize: 14)),
                if (bm.bonus.isNotEmpty)
                  Text('🎁 ${bm.bonus}', style: TextStyle(color: bmColor, fontSize: 14, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          // Cote + gain estimé
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (bc.cote > 1)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: bmColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: bmColor.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    'c.${bc.cote.toStringAsFixed(2)}',
                    style: TextStyle(
                      color: bmColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
              const SizedBox(height: 4),
              if (bc.cote > 1 && _mise > 0)
                Text(
                  '+${fmtEuros(gain)}€',
                  style: const TextStyle(color: Colors.white38, fontSize: 14),
                ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: bmColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: bmColor.withValues(alpha: 0.4)),
                ),
                child: Row(children: [
                  const Text('Parier', style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 4),
                  Icon(Icons.open_in_new, color: bmColor, size: 13),
                ]),
              ),
            ],
          ),
        ]),
      ),
    );
  }

  // ── Onglet 3 : Calculateur de gains ─────────────────────────────────────────

  Widget _buildTabCalculateur(ScrollController sheetCtrl, double bottomPad) {
    final coteG = _coteGagnant;
    final nb    = _nbPartants;
    final cotes3 = _getCotes3();
    final cotes4 = _getCotes4();
    final cotes5 = _getCotes5();

    final results = [
      GainCalculator.simpleGagnant(_mise, coteG),
      GainCalculator.place(_mise, coteG, nb),
      GainCalculator.gagnantEtPlace(_mise, coteG, nb),
      GainCalculator.tierce(_mise, cotes3, nb),
      GainCalculator.quarte(_mise, cotes4, nb),
      GainCalculator.quinte(_mise, cotes5, nb),
    ];

    final extraBottomCalc = 80.0 + bottomPad;
    return ListView(
      controller: sheetCtrl,
      padding: EdgeInsets.fromLTRB(18, 14, 18, extraBottomCalc),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        // Header calculateur
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [const Color(0xFF1A2F5A), const Color(0xFF0D1B2A)],
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('📊 Calculateur de gains PMU', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(
                'Mise actuelle : ${_mise.toStringAsFixed(0)} € — Cote Gagnant : ×${_coteGagnant.toStringAsFixed(2)} — Cote Placé : ×${_cotePlacee.toStringAsFixed(2)}',
                style: const TextStyle(color: Colors.white60, fontSize: 14),
              ),
              const SizedBox(height: 4),
              const Text(
                'Gains estimatifs basés sur les cotes IA. Les gains réels dépendent du dividende PMU final.',
                style: TextStyle(color: Colors.white38, fontSize: 14),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Mise rapide
        const Text('Modifier la mise :', style: TextStyle(color: Colors.white60, fontSize: 13)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8, runSpacing: 8,
          children: [2.0, 5.0, 10.0, 20.0, 50.0, 100.0].map((v) {
            final sel = (_mise - v).abs() < 0.5;
            return GestureDetector(
              onTap: () => setState(() => _mise = v),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: sel ? _gold.withValues(alpha: 0.2) : _card,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: sel ? _gold : Colors.white.withValues(alpha: 0.15), width: sel ? 1.5 : 1.0),
                ),
                child: Text(
                  '${v.toInt()} €',
                  style: TextStyle(color: sel ? _gold : Colors.white60, fontWeight: sel ? FontWeight.bold : FontWeight.normal, fontSize: 13),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),

        // Résultats par type de pari
        ...results.map((r) => _buildGainResultCard(r)),

        const SizedBox(height: 12),
        const Divider(color: Colors.white12),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF1A2F1A).withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF2E7D52).withValues(alpha: 0.4)),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('ℹ️ ', style: TextStyle(fontSize: 14)),
            const Expanded(child: Text(
              'Simple Gagnant/Placé : cotes RÉELLES PMU actualisées en direct.\n'
              'Tiercé/Quarté/Quinté : fourchettes basées sur les statistiques PMU réelles. Le dividende exact est fixé par PMU après la course et récupéré automatiquement.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            )),
          ]),
        ),
      ],
    );
  }

  Widget _buildGainResultCard(GainResult r) {
    final isPositif = r.gainNet > 0;
    final probColor = r.probabiliteEstimee >= 30
        ? _green
        : r.probabiliteEstimee >= 10
            ? const Color(0xFFFFB74D)
            : const Color(0xFFEF5350);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isPositif
              ? _green.withValues(alpha: 0.3)
              : Colors.white.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            // Emoji + label type
            Container(
              width: 40, height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isPositif
                    ? _dgreen.withValues(alpha: 0.2)
                    : Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(r.typeEmoji, style: const TextStyle(fontSize: 20)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.typeLabel,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: probColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('~${r.probabiliteEstimee.toStringAsFixed(0)}% réussite',
                        style: TextStyle(color: probColor, fontSize: 11)),
                  ),
                  const SizedBox(width: 6),
                  Text('Mise : ${r.mise.toStringAsFixed(0)}€',
                      style: const TextStyle(color: Colors.white38, fontSize: 11)),
                  if (r.type == TypePariCalc.gagnantEtPlace)
                    const Text(' (×2)',
                        style: TextStyle(color: Color(0xFFFFB74D), fontSize: 11, fontWeight: FontWeight.bold)),
                ]),
              ]),
            ),
            // Gain principal (fourchette pour combinés, gain exact pour simples)
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              if (r.estFourchette) ...[
                Text(
                  r.labelFourchetteDesordre,
                  style: const TextStyle(color: Color(0xFFFFB74D), fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const Text('fourchette', style: TextStyle(color: Colors.white30, fontSize: 10)),
              ] else ...[
                Text(
                  GainCalculator.formatGain(r.gainNet),
                  style: TextStyle(
                    color: isPositif ? _gold : const Color(0xFFEF5350),
                    fontWeight: FontWeight.bold, fontSize: 18,
                  ),
                ),
                Text('×${r.coteUtilisee.toStringAsFixed(2)}',
                    style: const TextStyle(color: Colors.white38, fontSize: 11)),
              ],
            ]),
          ]),

          // ── Scénarios détaillés selon le type
          if (r.type == TypePariCalc.gagnantEtPlace && r.gainSiPlace != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(children: [
                _cardScenarioRow('🏆 Si 1er (Gagnant+Placé)', GainCalculator.formatGain(r.gainNet), Colors.greenAccent),
                _cardScenarioRow('🥈 Si 2e/3e (Placé seul)',  GainCalculator.formatGain(r.gainSiPlace!),
                    r.gainSiPlace! >= 0 ? const Color(0xFFFFB74D) : const Color(0xFFEF5350)),
                _cardScenarioRow('❌ Si 4e+', GainCalculator.formatGain(r.scenarioPessimiste), const Color(0xFFEF5350)),
              ]),
            ),
          ] else if (r.estFourchette && (r.type == TypePariCalc.tierce || r.type == TypePariCalc.quarte || r.type == TypePariCalc.quinte)) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFFB74D).withValues(alpha: 0.25)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Text('⚠️ ', style: TextStyle(fontSize: 12)),
                  const Expanded(child: Text('Dividende fixé par PMU après la course',
                      style: TextStyle(color: Color(0xFFFFB74D), fontSize: 11, fontWeight: FontWeight.bold))),
                ]),
                const SizedBox(height: 6),
                // Dans l'ordre
                _cardScenarioFourchette(
                  '🏆 Dans l\'ordre',
                  r.labelFourchetteOrdre,
                  Colors.greenAccent,
                ),
                const SizedBox(height: 2),
                // Dans le désordre
                _cardScenarioFourchette(
                  '🥈 Dans le désordre',
                  r.labelFourchetteDesordre,
                  const Color(0xFFFFB74D),
                ),
                // Bonus 4/5 pour Quinté
                if (r.type == TypePariCalc.quinte && r.fourchetteMin4sur5 != null) ...[
                  const SizedBox(height: 2),
                  _cardScenarioFourchette(
                    '⭐ Consolation 4/5',
                    r.labelFourchette4sur5,
                    const Color(0xFF64B5F6),
                  ),
                ],
                const SizedBox(height: 2),
                _cardScenarioRow('❌ Perdu', GainCalculator.formatGain(r.scenarioPessimiste), const Color(0xFFEF5350)),
                const SizedBox(height: 4),
                const Text('Récupération automatique du vrai dividende PMU après l\'arrivée.',
                    style: TextStyle(color: Colors.white24, fontSize: 10)),
              ]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _cardScenarioRow(String label, String val, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Expanded(child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12))),
        Text(val, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
      ]),
    );
  }

  /// Affiche une ligne fourchette min → max pour les paris combinés
  Widget _cardScenarioFourchette(String label, String fourchette, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Expanded(child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12))),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(fourchette, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
          const Text('estimé PMU', style: TextStyle(color: Colors.white24, fontSize: 9)),
        ]),
      ]),
    );
  }

  // ── Sélection manuelle de numéros (Tiercé / Quarté+ / Quinté+) ─────────────

  Widget _buildSelectionManuelleHeader() {
    final typePari = _typesPari[_typePariIndex];
    final nbReq    = _nbChevauxRequis;
    final nbSel    = _modeManuel ? _numerosManuelsSel.length : _numerosFinaux.length;
    final autoNums = _numerosFinaux;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF111F30),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _modeManuel
              ? _gold.withValues(alpha: 0.6)
              : _green.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // En-tête avec toggle
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _gold.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '🎯 $typePari — $nbReq chevaux',
                style: const TextStyle(color: _gold, fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
            const Spacer(),
            // Toggle auto/manuel
            GestureDetector(
              onTap: () => setState(() {
                _modeManuel = !_modeManuel;
                if (!_modeManuel) _numerosManuelsSel.clear();
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _modeManuel
                      ? _gold.withValues(alpha: 0.20)
                      : _dgreen.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _modeManuel ? _gold : _green,
                  ),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(
                    _modeManuel ? Icons.edit : Icons.auto_awesome,
                    size: 14,
                    color: _modeManuel ? _gold : _green,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    _modeManuel ? 'Manuel' : 'Auto IA',
                    style: TextStyle(
                      color: _modeManuel ? _gold : _green,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ]),
              ),
            ),
          ]),
          const SizedBox(height: 10),

          if (!_modeManuel) ...[
            // Affichage auto IA
            Row(children: [
              const Icon(Icons.auto_awesome, color: Color(0xFF00C853), size: 15),
              const SizedBox(width: 6),
              const Text('Sélection IA automatique :', style: TextStyle(color: Colors.white60, fontSize: 13)),
            ]),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8, runSpacing: 6,
              children: autoNums.asMap().entries.map((entry) {
                final i = entry.key;
                final n = entry.value;
                final colors = [_gold, _green, const Color(0xFF42A5F5),
                    const Color(0xFFFF9800), const Color(0xFFCE93D8)];
                final col = colors[i % colors.length];
                return Container(
                  width: 40, height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: col.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                    border: Border.all(color: col, width: 2),
                  ),
                  child: Text('$n', style: TextStyle(color: col, fontWeight: FontWeight.bold, fontSize: 15)),
                );
              }).toList(),
            ),
            const SizedBox(height: 6),
            Text(
              'Appuyez sur "Manuel" pour choisir vos propres numéros',
              style: TextStyle(color: Colors.white30, fontSize: 11),
            ),
          ] else ...[
            // Sélection manuelle - compteur
            Row(children: [
              const Icon(Icons.touch_app, color: _gold, size: 15),
              const SizedBox(width: 6),
              Text(
                'Sélectionnez exactement $nbReq numéros ($nbSel/$nbReq) :',
                style: TextStyle(
                  color: nbSel == nbReq ? _green : _gold,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ]),
            if (_numerosManuelsSel.length > nbReq) ...[
              const SizedBox(height: 4),
              Text(
                '⚠️ Trop de numéros — les $nbReq premiers seront utilisés',
                style: const TextStyle(color: Colors.orange, fontSize: 11),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildGrilleNumeros() {
    final partants  = widget.course.partants;
    final partIAMap = {
      for (final p in widget.course.partantsParRangIA) p.numero: p
    };
    final nbReq = _nbChevauxRequis;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B2A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _gold.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Boutons rapides
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => setState(() {
                  _numerosManuelsSel.clear();
                  // Pré-remplir avec le top IA
                  for (final p in widget.course.partantsParRangIA.take(nbReq)) {
                    final n = int.tryParse(p.numero);
                    if (n != null) _numerosManuelsSel.add(n);
                  }
                }),
                icon: const Icon(Icons.auto_awesome, size: 13),
                label: const Text('Remplir IA', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _green,
                  side: BorderSide(color: _green.withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _numerosManuelsSel.clear()),
                icon: const Icon(Icons.clear, size: 13),
                label: const Text('Tout effacer', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: BorderSide(color: Colors.red.withValues(alpha: 0.3)),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          // Grille de tous les numéros
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: partants.map((p) {
              final num     = int.tryParse(p.numero) ?? 0;
              final isSelec = _numerosManuelsSel.contains(num);
              final rang    = partIAMap[p.numero]?.rang ?? 99;
              final score   = partIAMap[p.numero]?.scoreIA ?? 0;
              final isTop3  = rang <= 3;
              final isTop5  = rang <= 5;

              // Couleur de fond selon le rang IA
              Color ringColor;
              if (isSelec) {
                ringColor = _gold;
              } else if (isTop3) {
                ringColor = _green;
              } else if (isTop5) {
                ringColor = const Color(0xFF42A5F5);
              } else {
                ringColor = Colors.white24;
              }

              return GestureDetector(
                onTap: () {
                  setState(() {
                    if (isSelec) {
                      _numerosManuelsSel.remove(num);
                    } else {
                      _numerosManuelsSel.add(num);
                    }
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 52,
                  height: 58,
                  decoration: BoxDecoration(
                    color: isSelec
                        ? _gold.withValues(alpha: 0.25)
                        : isTop3
                            ? _green.withValues(alpha: 0.12)
                            : const Color(0xFF111F30),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: ringColor,
                      width: isSelec ? 2.5 : 1.5,
                    ),
                    boxShadow: isSelec
                        ? [BoxShadow(color: _gold.withValues(alpha: 0.3), blurRadius: 8)]
                        : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Numéro
                      Text(
                        p.numero,
                        style: TextStyle(
                          color: isSelec ? _gold : Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                        ),
                      ),
                      // Badge rang IA
                      if (isTop3)
                        Text(
                          rang == 1 ? '⭐IA' : rang == 2 ? '2nd' : '3rd',
                          style: TextStyle(
                            color: isSelec ? _gold : _green,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      else if (score > 0)
                        Text(
                          '${score.toStringAsFixed(0)}',
                          style: TextStyle(
                            color: isSelec ? _gold.withValues(alpha: 0.8) : Colors.white30,
                            fontSize: 9,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          // Récapitulatif de sélection
          if (_numerosManuelsSel.isNotEmpty) ...[
            const Divider(color: Colors.white12),
            Row(children: [
              const Text('Votre combinaison : ', style: TextStyle(color: Colors.white54, fontSize: 12)),
              Expanded(
                child: Wrap(
                  spacing: 4,
                  children: _numerosManuelsSel.toList()
                      .take(nbReq)
                      .map((n) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _gold.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: _gold.withValues(alpha: 0.5)),
                        ),
                        child: Text('N°$n', style: const TextStyle(color: _gold, fontSize: 11, fontWeight: FontWeight.bold)),
                      )).toList(),
                ),
              ),
            ]),
          ],
        ],
      ),
    );
  }

  // ── Sélecteur de type de pari ────────────────────────────────────────────────

  Widget _buildTypePariSelector() {
    // Cotes à afficher sous chaque bouton de type
    String _coteLabelForType(String type) {
      switch (type) {
        case 'Simple Gagnant':  return '×${_coteGagnant.toStringAsFixed(1)}';
        case 'Simple Placé':   return '×${_cotePlacee.toStringAsFixed(1)}';
        case 'Gagnant+Placé':   return 'mise ×2';
        case 'Couplé Gagnant':  return '2 chevaux';
        case 'Couplé Placé':    return '2 chevaux';
        case 'Tiercé':          return 'combi 3';
        case 'Quarté+':         return 'combi 4';
        case 'Quinté+':         return 'combi 5';
        default:                return '';
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Type de pari', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: List.generate(_typesPari.length, (i) {
              final sel = i == _typePariIndex;
              final coteLabel = _coteLabelForType(_typesPari[i]);
              return GestureDetector(
                onTap: () => setState(() => _typePariIndex = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: sel ? _dgreen.withValues(alpha: 0.25) : _card,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: sel ? _green : Colors.white.withValues(alpha: 0.15),
                      width: sel ? 1.5 : 1.0,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _typesPari[i],
                        style: TextStyle(
                          color: sel ? _green : Colors.white54,
                          fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                          fontSize: 13,
                        ),
                      ),
                      if (coteLabel.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          coteLabel,
                          style: TextStyle(
                            color: sel ? _gold : Colors.white30,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  // ── Accès rapide bookmakers avec cotes ──────────────────────────────────────

  Widget _buildAccesRapideBookmakers() {
    // Récupérer les cotes estimées pour le cheval sélectionné
    final coteRef = _coteAffichee;
    final cotes = BookmakerService.getCotesTriees(coteRef);

    // Données des bookmakers avec URL
    final bmUrls = {
      'PMU':       'https://www.pmu.fr/turf/offre/courses',
      'Betclic':   'https://www.betclic.fr/hippisme-s7',
      'Winamax':   'https://www.winamax.fr/paris-sportifs/sports/16',
      'Unibet':    'https://www.unibet.fr/sport/horse-racing',
      'ZEbet':     'https://www.zebet.fr/fr/sport/52-horse_racing',
      'ParionsSport': 'https://www.enligne.parionssport.fdj.fr/paris-hippiques',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Icon(Icons.compare_arrows, color: Colors.white38, size: 13),
          const SizedBox(width: 6),
          const Text('Cotes estimées — Parier maintenant',
              style: TextStyle(color: Colors.white54, fontSize: 14, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: cotes.map((bc) {
              final url = bmUrls[bc.bookmaker.nom] ?? bc.bookmaker.urlBase;
              final col = Color(bc.bookmaker.couleur);
              return GestureDetector(
                onTap: () async {
                  final uri = Uri.parse(url);
                  if (await canLaunchUrl(uri)) launchUrl(uri, mode: LaunchMode.externalApplication);
                },
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: bc.isMeilleure
                        ? const Color(0xFFFFD700).withValues(alpha: 0.12)
                        : col.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: bc.isMeilleure
                          ? const Color(0xFFFFD700).withValues(alpha: 0.7)
                          : col.withValues(alpha: 0.35),
                      width: bc.isMeilleure ? 1.5 : 1.0,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(children: [
                        Text(bc.bookmaker.emoji, style: const TextStyle(fontSize: 13)),
                        const SizedBox(width: 4),
                        Text(bc.bookmaker.nom,
                            style: TextStyle(
                                color: bc.isMeilleure ? const Color(0xFFFFD700) : col,
                                fontSize: 14,
                                fontWeight: FontWeight.bold)),
                        if (bc.isMeilleure) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.star, color: Color(0xFFFFD700), size: 10),
                        ],
                        const SizedBox(width: 4),
                        Icon(Icons.open_in_new, color: Colors.white30, size: 10),
                      ]),
                      const SizedBox(height: 3),
                      Text(
                        '×${bc.cote.toStringAsFixed(2)}',
                        style: TextStyle(
                            color: bc.isMeilleure
                                ? const Color(0xFFFFD700)
                                : const Color(0xFF4CAF7D),
                            fontSize: 13,
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  // ── Sélecteur de cheval ──────────────────────────────────────────────────────

  Widget _buildChevalSelector() {
    final partants = widget.course.partantsParRangIA;
    if (partants.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Cheval sélectionné', style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        ...partants.take(5).map((p) {
          final isSel = _chevalSelectionne?.numero == p.numero;
          final rang = p.rang;
          Color rangColor;
          String rangLabel;
          if (rang == 1) { rangColor = _gold; rangLabel = '⭐ Favori IA'; }
          else if (rang == 2) { rangColor = _green; rangLabel = '✅ 2ème choix'; }
          else if (rang == 3) { rangColor = const Color(0xFF42A5F5); rangLabel = '3ème choix'; }
          else { rangColor = Colors.white38; rangLabel = '${rang}ème'; }

          return GestureDetector(
            onTap: () => setState(() => _chevalSelectionne = p),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.only(bottom: 7),
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
              decoration: BoxDecoration(
                color: isSel ? _dgreen.withValues(alpha: 0.25) : _card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSel ? _green : Colors.white.withValues(alpha: 0.1),
                  width: isSel ? 1.5 : 1.0,
                ),
              ),
              child: Row(children: [
                Container(
                  width: 30, height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isSel ? _dgreen : Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(p.numero, style: TextStyle(color: isSel ? Colors.white : Colors.white70, fontWeight: FontWeight.bold, fontSize: 13)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.nom, style: TextStyle(color: isSel ? Colors.white : Colors.white70, fontWeight: FontWeight.w600, fontSize: 14)),
                      Row(children: [
                        Flexible(child: Text(rangLabel, style: TextStyle(color: rangColor, fontSize: 14), overflow: TextOverflow.ellipsis)),
                        if (p.driver.isNotEmpty) ...[
                          const Text(' · ', style: TextStyle(color: Colors.white24, fontSize: 14)),
                          Flexible(child: Text(p.driver, style: const TextStyle(color: Colors.white38, fontSize: 14), overflow: TextOverflow.ellipsis)),
                        ],
                      ]),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _scoreColor(p.scoreIA).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _scoreColor(p.scoreIA).withValues(alpha: 0.4)),
                  ),
                  child: Text('${p.scoreIA.round()}pts', style: TextStyle(color: _scoreColor(p.scoreIA), fontWeight: FontWeight.bold, fontSize: 14)),
                ),
                const SizedBox(width: 8),
                if (p.coteDecimale < 90)
                  Text('c.${p.cote}', style: const TextStyle(color: Colors.white38, fontSize: 14)),
                const SizedBox(width: 6),
                Icon(isSel ? Icons.check_circle : Icons.radio_button_unchecked, color: isSel ? _green : Colors.white24, size: 20),
              ]),
            ),
          );
        }),
      ],
    );
  }

  // ── Sélecteur de mise ────────────────────────────────────────────────────────

  Widget _buildMiseSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Montant de la mise', style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _gold.withValues(alpha: 0.4)),
          ),
          child: Column(children: [
            Text('${_mise.toStringAsFixed(0)} €', style: const TextStyle(color: _gold, fontSize: 36, fontWeight: FontWeight.bold, letterSpacing: 1)),
            Builder(builder: (_) {
              final tp = _typesPari[_typePariIndex];
              final isMulti = tp == 'Tiercé' || tp == 'Quarté+' || tp == 'Quinté+';
              final isCouple = tp == 'Couplé Gagnant' || tp == 'Couplé Placé';
              final isGP = tp == 'Gagnant+Placé';
              String sousTitre;
              if (isMulti) {
                // Tiercé/Quarté+/Quinté+ : afficher ordre + désordre, pas la cote du cheval
                final res = tp == 'Tiercé'
                    ? GainCalculator.tierce(_mise, _getCotes3(), _nbPartants)
                    : tp == 'Quarté+'
                        ? GainCalculator.quarte(_mise, _getCotes4(), _nbPartants)
                        : GainCalculator.quinte(_mise, _getCotes5(), _nbPartants);
                // gainNet = gain en ordre (net), gainSiDesordre = gain désordre (net)
                final retourOrdre    = res.gainNet + _mise;
                final retourDesordre = (res.gainSiDesordre ?? 0) + _mise;
                sousTitre = 'Ordre ~${fmtEuros(retourOrdre)} €  •  Désordre ~${fmtEuros(retourDesordre)} €';
              } else if (isCouple) {
                sousTitre = 'Retour estimé : ~${fmtEuros(_retourTotal)} €  (≈×${_coteAffichee.toStringAsFixed(1)})';
              } else if (isGP) {
                sousTitre = 'Retour billet : ~${fmtEuros(_retourTotal)} €  (×2 mise)';
              } else {
                // Simple Gagnant / Simple Placé : cote du cheval, cohérente
                sousTitre = 'Retour billet : ~${fmtEuros(_retourTotal)} €  (cote ×${_coteAffichee.toStringAsFixed(1)})';
              }
              return Text(sousTitre, style: const TextStyle(color: Colors.white38, fontSize: 13));
            }),
          ]),
        ),
        const SizedBox(height: 10),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: _gold,
            inactiveTrackColor: const Color(0xFF1A3A2A),
            thumbColor: _gold,
            overlayColor: _gold.withValues(alpha: 0.15),
          ),
          child: Slider(value: _mise.clamp(2.0, 200.0).roundToDouble(), min: 2, max: 200, divisions: 99, onChanged: (v) => setState(() => _mise = v.roundToDouble())),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: const [
            Text('2 €', style: TextStyle(color: Colors.white24, fontSize: 14)),
            Text('100 €', style: TextStyle(color: Colors.white24, fontSize: 14)),
            Text('200 €', style: TextStyle(color: Colors.white24, fontSize: 14)),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8, runSpacing: 8,
          children: [2.0, 5.0, 10.0, 20.0, 50.0, 100.0, 200.0].map((v) {
            final sel = (_mise - v).abs() < 0.5;
            return GestureDetector(
              onTap: () => setState(() => _mise = v),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: sel ? _gold.withValues(alpha: 0.2) : _card,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: sel ? _gold : Colors.white.withValues(alpha: 0.15), width: sel ? 1.5 : 1.0),
                ),
                child: Text('${v.toInt()} €', style: TextStyle(color: sel ? _gold : Colors.white60, fontWeight: sel ? FontWeight.bold : FontWeight.normal, fontSize: 13)),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ── Aperçu du gain (récapitulatif honnête selon chaque type) ────────────────

  Widget _buildGainPreview() {
    if (_chevalSelectionne == null && !_sansPartants) return const SizedBox.shrink();
    final p = _chevalSelectionne;
    final typePari = _typesPari[_typePariIndex];
    final isGagnantPlace  = typePari == 'Gagnant+Placé';
    final isPlace         = typePari == 'Simple Placé';
    final isCouple        = typePari == 'Couplé Gagnant' || typePari == 'Couplé Placé';
    final isCoupleGagnant = typePari == 'Couplé Gagnant';
    final isCouplePlace   = typePari == 'Couplé Placé';
    final isMulti         = typePari == 'Tiercé' || typePari == 'Quarté+' || typePari == 'Quinté+';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _dgreen.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _green.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── En-tête
          Row(children: [
            const Text('Récapitulatif du pari',
                style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _dgreen.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(typePari,
                  style: TextStyle(color: _green, fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ]),
          const SizedBox(height: 10),

          // ── Cheval(s) sélectionné(s)
          if (isCouple) ...[
            // Afficher les 2 chevaux du couplé
            ...() {
              final nums = _numerosFinaux.take(2).toList();
              final partants = widget.course.partants;
              return nums.map((num) {
                final cheval = partants.where((x) => int.tryParse(x.numero) == num).firstOrNull;
                final nom = cheval?.nom ?? '?';
                return _summaryRow('🐎 Cheval', 'N°$num — $nom');
              }).toList();
            }(),
          ] else if (p != null)
            _summaryRow('🐎 Cheval', 'N°${p.numero} — ${p.nom}'),

          // ── Mise (double si Gagnant+Placé)
          if (isGagnantPlace) ...[
            _summaryRow('💰 Mise engagée', '${_mise.toStringAsFixed(0)} × 2 = ${(_mise*2).toStringAsFixed(0)} €',
                highlight: true, color: const Color(0xFFFFB74D)),
            _summaryRow('  ↳ Gagnant', '${_mise.toStringAsFixed(0)} €'),
            _summaryRow('  ↳ Placé',   '${_mise.toStringAsFixed(0)} €'),
          ] else
            _summaryRow('💰 Mise', '${_mise.toStringAsFixed(0)} €'),

          const SizedBox(height: 6),

          // ── Cote(s) selon le type
          if (isPlace) ...[
            _summaryRow('📊 Cote Gagnant (info)', '× ${_coteGagnant.toStringAsFixed(2)}',
                color: Colors.white38),
            _summaryRow('📊 Cote Placé (÷${_nbPartants >= 8 ? "4" : "3"})',
                '× ${_cotePlacee.toStringAsFixed(2)}', highlight: true),
          ] else if (isGagnantPlace) ...[
            _summaryRow('📊 Cote Gagnant', '× ${_coteGagnant.toStringAsFixed(2)}'),
            _summaryRow('📊 Cote Placé',   '× ${_cotePlacee.toStringAsFixed(2)}'),
          ] else if (isCoupleGagnant) ...[
            _summaryRow('📊 Cote estimée Couplé', '≈ ×${_getCoupleGagnantEstime().toStringAsFixed(1)}',
                highlight: true),
            _summaryRow('ℹ️ Top 2 dans n\'importe quel ordre', '',
                color: Colors.white38),
          ] else if (isCouplePlace) ...[
            _summaryRow('📊 Cote estimée Couplé Placé', '≈ ×${_getCouplePlaceEstime().toStringAsFixed(1)}',
                highlight: true),
            _summaryRow('ℹ️ Les 2 chevaux dans le top 3', '',
                color: Colors.white38),
          ] else if (!isMulti && !isCouple)
            _summaryRow('📊 Cote', '× ${_coteGagnant.toStringAsFixed(2)}'),

          const Divider(color: Colors.white12, height: 16),

          // ── Scénarios selon le type
          if (typePari == 'Simple Gagnant') ...[
            _scenarioRow('🏆 Si 1er', '${fmtEuros(_retourTotal)} €', Colors.greenAccent),
            _scenarioRow('❌ Si 2e+', '-${_mise.toStringAsFixed(0)} €', const Color(0xFFEF5350)),
          ] else if (isPlace) ...[
            _scenarioRow('🎯 Si top 3', '${fmtEuros(_retourTotal)} €', Colors.greenAccent),
            _scenarioRow('❌ Si 4e+',   '-${_mise.toStringAsFixed(0)} €', const Color(0xFFEF5350)),
          ] else if (isCoupleGagnant) ...[
            _scenarioRow('🏆 Si les 2 dans le top 2',
                '+${fmtEuros(_gainEstime)} €', Colors.greenAccent),
            _scenarioRow('🥈 Si 1 seul dans le top 2',
                '-${_mise.toStringAsFixed(0)} € (perdu)', const Color(0xFFEF5350)),
            _scenarioRow('❌ Aucun dans le top 2',
                '-${_mise.toStringAsFixed(0)} €', const Color(0xFFEF5350)),
          ] else if (isCouplePlace) ...[
            _scenarioRow('🏆 Si les 2 dans le top 3',
                '+${fmtEuros(_gainEstime)} €', Colors.greenAccent),
            _scenarioRow('❌ Si 1 seul dans le top 3',
                '-${_mise.toStringAsFixed(0)} € (perdu)', const Color(0xFFEF5350)),
          ] else if (isGagnantPlace) ...[
            _scenarioRow('🏆 Si 1er (Gagnant + Placé)',
                '+${fmtEuros(_mise*_coteGagnant + _mise*_cotePlacee - _mise*2)} €',
                Colors.greenAccent),
            _scenarioRow('🥈 Si 2e/3e (Placé seul)',
                '${(_mise*_cotePlacee - _mise*2) >= 0 ? "+" : ""}${fmtEuros(_mise*_cotePlacee - _mise*2)} €',
                (_mise*_cotePlacee - _mise*2) >= 0
                    ? const Color(0xFFFFB74D) : const Color(0xFFEF5350)),
            _scenarioRow('❌ Si 4e+', '-${(_mise*2).toStringAsFixed(0)} €', const Color(0xFFEF5350)),
          ] else if (typePari == 'Tiercé') ...[
            () {
              final r = GainCalculator.tierce(_mise, _getCotes3(), _nbPartants);
              return Column(children: [
                _scenarioRow('🏆 Dans l\'ordre',   '+${fmtEuros(r.gainNet)} €', Colors.greenAccent),
                _scenarioRow('🥈 Dans le désordre','+${fmtEuros(r.gainSiDesordre ?? 0)} €', const Color(0xFFFFB74D)),
                _scenarioRow('❌ Perdu',            '-${_mise.toStringAsFixed(0)} €', const Color(0xFFEF5350)),
              ]);
            }(),
          ] else if (typePari == 'Quarté+') ...[
            () {
              final r = GainCalculator.quarte(_mise, _getCotes4(), _nbPartants);
              return Column(children: [
                _scenarioRow('🏆 Dans l\'ordre',   '+${fmtEuros(r.gainNet)} €', Colors.greenAccent),
                _scenarioRow('🥈 Dans le désordre','+${fmtEuros(r.gainSiDesordre ?? 0)} €', const Color(0xFFFFB74D)),
                _scenarioRow('❌ Perdu',            '-${_mise.toStringAsFixed(0)} €', const Color(0xFFEF5350)),
              ]);
            }(),
          ] else if (typePari == 'Quinté+') ...[
            () {
              final r = GainCalculator.quinte(_mise, _getCotes5(), _nbPartants);
              return Column(children: [
                _scenarioRow('🏆 Dans l\'ordre',   '+${fmtEuros(r.gainNet)} €', Colors.greenAccent),
                _scenarioRow('🥈 Dans le désordre','+${fmtEuros(r.gainSiDesordre ?? 0)} €', const Color(0xFFFFB74D)),
                _scenarioRow('⭐ Bonus 4/5 bons',  '+${fmtEuros(r.gainBonus4sur5 ?? 0)} €', const Color(0xFF64B5F6)),
                _scenarioRow('❌ Perdu',            '-${_mise.toStringAsFixed(0)} €', const Color(0xFFEF5350)),
              ]);
            }(),
          ],

          const SizedBox(height: 8),

          // ── Score IA
          if (p != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _scoreColor(p.scoreIA).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                Icon(Icons.psychology, color: _scoreColor(p.scoreIA), size: 14),
                const SizedBox(width: 6),
                Text('Score IA : ${p.scoreIA.round()}/100 — ${p.labelIA}',
                    style: TextStyle(color: _scoreColor(p.scoreIA),
                        fontSize: 14, fontWeight: FontWeight.w600)),
              ]),
            ),

          // ── Avertissement gains estimés pour les combis
          if (isMulti) ...[
            const SizedBox(height: 6),
            const Text(
              '⚠️ Gains estimés — le dividende réel est fixé par PMU après la course',
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  Widget _scenarioRow(String label, String valeur, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(label, style: const TextStyle(color: Colors.white60, fontSize: 13))),
          Text(valeur, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value, {bool highlight = false, Color? color}) {
    final valueColor = color ?? (highlight ? _gold : Colors.white);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13))),
          Text(value, style: TextStyle(
            color: valueColor,
            fontWeight: highlight ? FontWeight.bold : FontWeight.w500,
            fontSize: highlight ? 15 : 13,
          )),
        ],
      ),
    );
  }

  // ── Bouton Valider ───────────────────────────────────────────────────────────

  Widget _buildValiderBtn(BuildContext ctx) {
    final miseAffichee = _miseReelle;
    final typePariCurrent = _typesPari[_typePariIndex];
    final suffixeMise = typePariCurrent == 'Gagnant+Placé'
        ? '${_mise.toStringAsFixed(0)}×2=${miseAffichee.toStringAsFixed(0)} €'
        : '${miseAffichee.toStringAsFixed(0)} €';

    // Label adapté selon le type de pari
    final String label;
    if (_sansPartants) {
      label = 'Valider — $suffixeMise (Mise confirmée)';
    } else if (_estCouple) {
      final nums = _numerosFinaux.take(2).toList();
      final numsStr = nums.map((n) => 'N°$n').join(' + ');
      label = nums.length >= 2
          ? 'Valider — $suffixeMise — $numsStr'
          : 'Sélectionnez 2 chevaux pour le Couplé';
    } else if (_estPariCombi) {
      final nums = _numerosFinaux;
      label = nums.isNotEmpty
          ? 'Valider — $suffixeMise — ${nums.map((n) => "N°$n").join(" · ")}'
          : 'Valider — $suffixeMise';
    } else {
      label = 'Valider — $suffixeMise sur N°${_chevalSelectionne?.numero ?? "?"}';
    }

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        icon: const Icon(Icons.check_circle, size: 20),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        style: ElevatedButton.styleFrom(
          backgroundColor: _peutValider ? _dgreen : Colors.grey.shade800,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: _peutValider ? 3 : 0,
        ),
        onPressed: _peutValider ? () => _valider(ctx) : null,
      ),
    );
  }

  // ── Déjà suivi (bandeau informatif non bloquant) ────────────────────────────
  // ★ Fix écran gris v9.44 : ce widget n'est plus un remplacement du contenu.
  // Il s'affiche comme une bannière compacte AU-DESSUS des onglets, sans les masquer.

  Widget _buildDejasuiviBanner(BuildContext ctx) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: _gold.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _gold.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.bookmark, color: _gold, size: 18),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Course déjà suivie — vous pouvez tout de même modifier votre pari.',
              style: TextStyle(color: _gold, fontSize: 12),
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () { Navigator.pop(ctx); widget.onBetPlaced(); },
            child: const Text('Mes Paris', style: TextStyle(color: _gold, fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    final c = widget.course;
    final r = widget.reunion;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
      decoration: BoxDecoration(
        color: _card,
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _dgreen.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _green.withValues(alpha: 0.5)),
              ),
              child: Text('💰 Placer un pari', style: TextStyle(color: _green, fontSize: 14, fontWeight: FontWeight.bold)),
            ),
            const Spacer(),
            Text('${r.code} · C${c.numCourse}', style: const TextStyle(color: Colors.white38, fontSize: 14)),
          ]),
          const SizedBox(height: 8),
          Text(c.nom.isNotEmpty ? c.nom : 'Course ${c.numCourse}', style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Row(children: [
            const Icon(Icons.location_on, color: Colors.white38, size: 13),
            const SizedBox(width: 3),
            Text(r.lieu, style: const TextStyle(color: Colors.white54, fontSize: 13)),
            const SizedBox(width: 12),
            const Icon(Icons.access_time, color: Colors.white38, size: 13),
            const SizedBox(width: 3),
            Text(c.heure, style: const TextStyle(color: Colors.white54, fontSize: 13)),
            const SizedBox(width: 12),
            Text(c.distance, style: const TextStyle(color: Colors.white38, fontSize: 14)),
            if (c.isQuinte) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: _gold.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: _gold.withValues(alpha: 0.5)),
                ),
                child: const Text('QUINTÉ+', style: TextStyle(color: _gold, fontSize: 13, fontWeight: FontWeight.bold)),
              ),
            ],
          ]),
        ],
      ),
    );
  }

  // ── Ouverture bookmaker ──────────────────────────────────────────────────────

  Future<void> _ouvrirBookmaker(BookmakerInfo bm, String? horseName) async {
    // Construire l'URL avec le cheval pré-rempli si possible
    String urlStr = bm.urlApp;

    // PMU : recherche spécifique hippisme
    if (bm.nom == 'PMU') {
      urlStr = 'https://www.pmu.fr/turf/offre/courses';
    }

    final url = Uri.parse(urlStr);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Impossible d\'ouvrir ${bm.nom}. Vérifiez votre connexion.'),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
    }
  }

  // ── Validation ───────────────────────────────────────────────────────────────

  void _valider(BuildContext ctx) {
    ZtPartant partant;

    if (_chevalSelectionne != null) {
      partant = _chevalSelectionne!;
    } else {
      // Pas de partants (grande course fictive)
      partant = ZtPartant(
        numero: '?', nom: 'Sélection IA', driver: '', musique: '',
        gains: '', record: '', cote: '', proprietaire: '', entraineur: '',
        ageSexe: '',
      );
    }

    final c = widget.course;
    final r = widget.reunion;

    final (int numR, int numC) = widget.overrideKey != null
        ? (99, widget.course.numCourse + 1000)
        : (_numReunion, c.numCourse);

    // ── Construire la liste complète des numéros joués ──────────────────────
    final typePariLabel = _typesPari[_typePariIndex];
    final numPrincipal  = int.tryParse(partant.numero);

    // Utiliser le getter _numerosFinaux (manuel ou auto-IA)
    final numerosJoues = _numerosFinaux;

    // Résumé de la sélection pour le SnackBar
    final modeLabel = (_modeManuel && _estPariCombi) ? '✋ Manuel' : '🤖 IA auto';

    // ── Construire la clé mémoire IA (identique à celle du résultat) ────────
    // Format : R{numReunion}C{numCourse}_{JJ}{MM}{AAAA} — padding 0 pour cohérence
    final dep = c.heureDateTime;
    final bj = dep.day.toString().padLeft(2, '0');
    final bm = dep.month.toString().padLeft(2, '0');
    final iaMemKey = widget.overrideKey != null
        ? '${widget.overrideKey}_ia'
        : 'R${numR}C${numC}_$bj$bm${dep.year}';

    // ── Enregistrer le pronostic IA avec les scores par critère ─────────────
    // C'est ici que l'IA « mémorise » ce qu'elle a prédit AVANT la course,
    // avec les valeurs détaillées de chaque critère pour permettre
    // l'apprentissage par gradient descent une fois le résultat connu.
    final partantsClasses = widget.course.partantsParRangIA;
    if (partantsClasses.isNotEmpty) {
      // Extraire les scores bruts par critère pour chaque partant
      final scoresCriteres = IaPronosticEngine.extraireScoresCriteres(widget.course);

      // Calcul de la confiance : écart entre le 1er et le 2ème
      double confiancePredite = 65.0;
      if (partantsClasses.length >= 2) {
        final ecart = partantsClasses[0].scoreIA - partantsClasses[1].scoreIA;
        confiancePredite = (65.0 + ecart * 0.5).clamp(40.0, 95.0);
      }

      // Récupérer le type de pari IA conseillé au moment de la validation
      // (utilise _conseilIA qui calcule le type selon les scores actuels)
      final typePariPourIA = _conseilIA['label'] as String? ?? _typesPari[_typePariIndex];

      IaMemoryService.instance.enregistrerPronostic(
        courseKey: iaMemKey,
        course: widget.course,
        partantsClasses: partantsClasses,
        scoresCriteresMap: scoresCriteres,
        confiancePredite: confiancePredite,
        typePariConseille: typePariPourIA,
      );
    }

    final tracked = TrackedCourse(
      numReunion: numR,
      numCourse: numC,
      nomCourse: c.nom.isNotEmpty ? c.nom : 'Course ${c.numCourse}',
      hippodrome: r.lieu,
      heureDepart: c.heureDateTime,
      nomCheval: partant.nom.isNotEmpty ? partant.nom : 'Favori IA',
      numeroCheval: numPrincipal,
      miseEngagee: _mise,
      typePari: typePariLabel,
      numerosJoues: numerosJoues,
      iaMemKey: iaMemKey,   // ← lien vers le pronostic IA mémorisé
      scoreIA: _chevalSelectionne?.scoreIA ?? 0.0,
      cote: _coteAffichee > 0 ? _coteAffichee : (_chevalSelectionne?.coteDecimale ?? 0.0),   // ← cote du TYPE DE PARI (Tiercé, Quinté...) pas la cote brute du cheval
    );

    widget.alertService.ajouterSuivi(tracked, overrideKey: widget.overrideKey);

    // ── Enregistrer le pari dans le profil utilisateur (PmuProvider) ─────────
    // C'est ce qui alimente les statistiques du tableau de bord.
    try {
      final dep = c.heureDateTime;
      final dateStr =
          '${dep.year}-${dep.month.toString().padLeft(2, '0')}-${dep.day.toString().padLeft(2, '0')}';

      // Identifiant unique : courseKey + timestamp pour éviter les doublons
      final predId = '${_courseKey}_${DateTime.now().millisecondsSinceEpoch}';

      // Numéro principal du cheval (ou 0 pour paris combinés sans cheval unique)
      final numChevalPred = numPrincipal ?? 0;

      // Cote utilisée selon le type de pari
      final coteForPred = _coteAffichee;

      // Score IA du cheval sélectionné (ou 0 si non dispo)
      final scoreIAForPred = _chevalSelectionne?.scoreIA ?? 0.0;

      final prediction = UserPrediction(
        id: predId,
        dateStr: dateStr,
        numReunion: numR,
        numCourse: numC,
        nomCourse: c.nom.isNotEmpty ? c.nom : 'Course ${c.numCourse}',
        hippodrome: r.lieu,
        numeroCheval: numChevalPred,
        nomCheval: partant.nom.isNotEmpty ? partant.nom : 'Favori IA',
        cote: coteForPred > 0 ? coteForPred : 2.5,
        typePari: typePariLabel,
        createdAt: DateTime.now(),
        isCorrect: null,
        scoreIA: scoreIAForPred,
        montantMise: _mise,
        gainRealise: null,
        // Numéros joués (essentiels pour retrouver le bon dividende PMU post-course)
        numerosJoues: numerosJoues,
        dividendePmuReel: null,
        combinaisonPmu: null,
      );

      // ignore: use_build_context_synchronously
      if (ctx.mounted) {
        ctx.read<PmuProvider>().addPrediction(prediction);
      }
      // ★ v9.4 : stopper les alertes favori dès qu'un pari est placé sur cette course
      widget.alertService.marquerFavoriCommeParI(numR, numC);
    } catch (e) {
      // Ne pas bloquer si la sauvegarde échoue
      if (kDebugMode) debugPrint('Erreur sauvegarde UserPrediction: $e');
    }

    Navigator.pop(ctx);

    // Message adapté selon simple ou combiné
    final msgPari = _estPariCombi
        ? '✅ $typePariLabel ($modeLabel) — ${numerosJoues.map((n) => "N°$n").join(" · ")} — ${_mise.toStringAsFixed(0)} €'
        : '✅ Pari placé : ${_mise.toStringAsFixed(0)} € sur N°${partant.numero} — ${partant.nom}';

    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Row(children: [
          const Icon(Icons.check_circle, color: Colors.white, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(msgPari, style: const TextStyle(fontSize: 13)),
          ),
        ]),
        backgroundColor: const Color(0xFF1B5E20),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(label: 'Voir', textColor: _gold, onPressed: widget.onBetPlaced),
      ),
    );

    widget.onBetPlaced();
  }
}
