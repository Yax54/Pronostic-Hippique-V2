import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show listEquals, kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../services/backtesting_service.dart';
import '../../services/ia_memory_service.dart';
import '../../main.dart' show NavigationNotifier;
import 'package:shared_preferences/shared_preferences.dart';

// ══════════════════════════════════════════════════════════════════════════════
//  IaTabBacktesting — Onglet "Backtesting" de IaPerformanceScreen
//  v10.20 : Bug freeze fix + bulles cliquables Comparaison
//           + filtres Discipline / Hippodrome
//  v10.67 : Export image complet (RepaintBoundary, pixelRatio 2.5, fallback visible)
// ══════════════════════════════════════════════════════════════════════════════

class IaTabBacktesting extends StatefulWidget {
  const IaTabBacktesting({super.key});

  @override
  State<IaTabBacktesting> createState() => _IaTabBacktestingState();
}

class _IaTabBacktestingState extends State<IaTabBacktesting> {
  BacktestResult? _btResult;
  bool   _btEnCours      = false;
  bool   _btShowAll      = false;

  // ── ★ v10.67 : Export image complet ──────────────────────────────────────
  final GlobalKey _backtestingExportKey = GlobalKey();
  bool _exportBacktestingEnCours = false;
  double _btMise         = 10.0;
  int    _btJours        = 30;
  String _btType         = 'Conseil IA';
  double _btConfianceMin = 0.0;

  // ★ v10.20 : filtres Discipline + Hippodrome
  String? _btDiscipline;   // null = toutes
  String? _btHippodrome;   // null = tous

  // ★ v10.24 : simulation Martingale
  _MartingaleResult? _martingaleResult;

  // ★ v10.25 : saisie manuelle de la mise
  late final TextEditingController _miseController;

  @override
  void initState() {
    super.initState();
    _miseController = TextEditingController(text: _btMise.toStringAsFixed(0));
    _chargerPrefs();
  }

  @override
  void dispose() {
    _miseController.dispose();
    super.dispose();
  }

  Future<void> _chargerPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    // ★ v10.29 : mettre à jour le controller HORS du setState
    // pour éviter le rebuild complet du TextField (= curseur reset + clignotement)
    final mise = (prefs.getDouble('bt_mise') ?? 10.0).clamp(2.0, 200.0);
    final miseStr = mise.toStringAsFixed(0);
    if (_miseController.text != miseStr) {
      _miseController.value = TextEditingValue(
        text: miseStr,
        selection: TextSelection.collapsed(offset: miseStr.length),
      );
    }
    setState(() {
      _btMise         = mise;
      _btJours        = (prefs.getInt   ('bt_jours')         ?? 30  ).clamp(7, 90);
      _btType         =  prefs.getString('bt_type')          ?? 'Conseil IA';
      _btConfianceMin = (prefs.getDouble('bt_confiance_min') ?? 0.0 ).clamp(0.0, 95.0);
      _btDiscipline   =  prefs.getString('bt_discipline');
      _btHippodrome   =  prefs.getString('bt_hippodrome');
    });
  }

  Future<void> _sauvegarderPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('bt_mise',          _btMise);
    await prefs.setInt   ('bt_jours',         _btJours);
    await prefs.setString('bt_type',          _btType);
    await prefs.setDouble('bt_confiance_min', _btConfianceMin);
    if (_btDiscipline != null) {
      await prefs.setString('bt_discipline', _btDiscipline!);
    } else {
      await prefs.remove('bt_discipline');
    }
    if (_btHippodrome != null) {
      await prefs.setString('bt_hippodrome', _btHippodrome!);
    } else {
      await prefs.remove('bt_hippodrome');
    }
  }

  // ★ v10.20 — FIX FREEZE : _btEnCours TOUJOURS remis à false dans tous les chemins
  Future<void> _lancerBacktest({String? typeOverride}) async {
    if (_btEnCours) return;
    setState(() { _btEnCours = true; _btShowAll = false; });
    try {
      final type = typeOverride ?? _btType;
      final result = await BacktestingService.instance.lancer(
        mise:         _btMise,
        typePari:     type,
        nbJours:      _btJours,
        confianceMin: _btConfianceMin,
        discipline:   _btDiscipline,
        hippodrome:   _btHippodrome,
      );
      if (!mounted) return;
      if (result.nbTotal == 0) {
        // ★ FIX : _btEnCours = false AVANT le return
        setState(() { _btResult = null; _btEnCours = false; });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            _btConfianceMin > 0
              ? 'Aucune course avec confiance ≥ ${_btConfianceMin.toInt()} pts sur ${_btJours}j.\nBaisse le filtre Confiance IA ou augmente la période.'
              : 'Aucune course avec résultat réel sur ${_btJours}j.\nEnregistre des pronostics et attends les résultats PMU.',
          ),
          backgroundColor: const Color(0xFF7C4DFF),
          duration: const Duration(seconds: 5),
          action: _btConfianceMin > 0
            ? SnackBarAction(
                label: 'Réinitialiser',
                textColor: Colors.white,
                onPressed: () {
                  setState(() { _btConfianceMin = 0; _btResult = null; });
                  _sauvegarderPrefs();
                },
              )
            : null,
        ));
        return; // _btEnCours déjà false dans le setState ci-dessus
      }
      if (typeOverride != null) {
        // Appel depuis bulle Comparaison → changer le type actif ET afficher résultat
        setState(() {
          _btType   = typeOverride;
          _btResult = result;
          _btEnCours = false;
        });
        _sauvegarderPrefs();
      } else {
        setState(() { _btResult = result; _btEnCours = false; });
      }
    } catch (e) {
      if (mounted) {
        setState(() { _btEnCours = false; _btResult = null; });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur backtesting : $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _lancerComparaison() async {
    if (_btEnCours) return;
    setState(() => _btEnCours = true);
    try {
      const types = ['Simple Gagnant', 'Simple Placé', 'Gagnant+Placé',
                     'Couplé Gagnant', 'Tiercé', 'Quarté+', 'Quinté+'];
      final futures = types.map((t) => BacktestingService.instance.lancer(
        mise: _btMise, typePari: t, nbJours: _btJours,
        confianceMin: _btConfianceMin,
        discipline: _btDiscipline, hippodrome: _btHippodrome,
      ));
      final results = await Future.wait(futures);
      if (!mounted) return;
      final totalCourses = results.fold<int>(0, (s, r) => s + r.nbTotal);
      if (totalCourses == 0) {
        setState(() => _btEnCours = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            _btConfianceMin > 0
              ? 'Aucune course avec confiance ≥ ${_btConfianceMin.toInt()} pts.\nBaisse le filtre Confiance IA.'
              : 'Aucune course avec résultat sur ${_btJours}j.',
          ),
          backgroundColor: const Color(0xFF7C4DFF),
          duration: const Duration(seconds: 4),
        ));
        return;
      }
      setState(() => _btEnCours = false);
      if (mounted) _showComparaisonDialog(types.toList(), results);
    } catch (e) {
      if (mounted) setState(() => _btEnCours = false);
    }
  }

  // ★ v10.20 — Bulles cliquables : tap → rebascule simulation avec ce type
  void _showComparaisonDialog(List<String> types, List<BacktestResult> results) {
    final sorted = List.generate(types.length, (i) => (type: types[i], r: results[i]))
      ..sort((a, b) => b.r.roi.compareTo(a.r.roi));

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0D1B2A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.60,
        minChildSize: 0.35,
        maxChildSize: 0.90,
        expand: false,
        builder: (_, scrollCtrl) => Column(
          children: [
            // ── Poignée ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 6),
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // ── En-tête fixe ────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('📊 Comparaison des stratégies',
                      style: TextStyle(color: Colors.white, fontSize: 17,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                    'Mêmes paramètres · ${_btJours}j · mise ${_btMise.toStringAsFixed(0)} €/course'
                    '${_btDiscipline != null ? " · $_btDiscipline" : ""}'
                    '${_btHippodrome != null ? " · $_btHippodrome" : ""}',
                    style: const TextStyle(color: Colors.white38, fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '👆 Touche une stratégie pour relancer la simulation avec ce type',
                    style: TextStyle(color: Color(0xFF7C4DFF), fontSize: 16,
                        fontStyle: FontStyle.italic),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
            // ── Liste scrollable ─────────────────────────────────────────
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                children: sorted.map((item) {
                  final roi    = item.r.roi;
                  final isPos  = roi >= 0;
                  final color  = isPos
                      ? const Color(0xFF4CAF7D)
                      : Colors.redAccent;
                  final roiStr = '${roi >= 0 ? "+" : ""}${roi.toStringAsFixed(1)}%';
                  final gainStr= '${item.r.gainNet >= 0 ? "+" : ""}${item.r.gainNet.toStringAsFixed(0)} €';
                  final isActif = item.type == _btType;

                  return GestureDetector(
                    // ★ tap → fermer dialog + relancer simulation avec ce type
                    onTap: () {
                      Navigator.of(ctx).pop();
                      _lancerBacktest(typeOverride: item.type);
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: isActif
                            ? color.withValues(alpha: 0.15)
                            : color.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isActif ? color : color.withValues(alpha: 0.25),
                          width: isActif ? 1.5 : 1.0,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Ligne 1 : type + ROI + indicateur actif
                          Row(children: [
                            Expanded(
                              child: Row(children: [
                                if (isActif) ...[
                                  Icon(Icons.play_arrow, color: color, size: 14),
                                  const SizedBox(width: 4),
                                ],
                                Text(item.type,
                                    style: TextStyle(
                                        color: isActif ? color : Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700)),
                              ]),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text('ROI $roiStr',
                                  style: TextStyle(
                                      color: color,
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold)),
                            ),
                          ]),
                          const SizedBox(height: 6),
                          // Ligne 2 : détails chiffrés + icône "tap"
                          Row(children: [
                            _cmpStat('Gain net', gainStr, color),
                            const SizedBox(width: 20),
                            _cmpStat('Réussite',
                                '${item.r.tauxReussite.toStringAsFixed(0)}%',
                                Colors.white60),
                            const SizedBox(width: 20),
                            _cmpStat('Courses',
                                '${item.r.nbTotal}',
                                Colors.white38),
                            const Spacer(),
                            const Icon(Icons.touch_app, color: Colors.white24, size: 14),
                          ]),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── ★ v10.24 : Simulation Martingale ──────────────────────────────────────
  // Principe : mise initiale doublée après chaque perte, reset à la mise de base après un gain.
  // On simule sur les pronostics avec résultat de la période sélectionnée.
  Future<void> _lancerMartingale() async {
    if (_btEnCours) return;
    setState(() { _btEnCours = true; _martingaleResult = null; });
    try {
      final limiteDate = DateTime.now().subtract(Duration(days: _btJours));
      final pronostics = IaMemoryService.instance.pronosticsAvecResultat
          .where((p) => p.datePronostic.isAfter(limiteDate))
          .where((p) {
            if (_btDiscipline != null && p.discipline != _btDiscipline) return false;
            if (_btHippodrome != null && p.hippodrome != _btHippodrome) return false;
            if (_btConfianceMin > 0 && (p.confiancePredite ?? 0) < _btConfianceMin) return false;
            return true;
          })
          .toList()
        ..sort((a, b) => a.datePronostic.compareTo(b.datePronostic));

      if (pronostics.isEmpty) {
        setState(() => _btEnCours = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Pas assez de données pour simuler la martingale.'),
            backgroundColor: Color(0xFFFF9800),
          ));
        }
        return;
      }

      // Simulation séquentielle
      double mise       = _btMise;
      double capital    = 0.0;   // gain/perte cumulé
      int    nbGagnes   = 0;
      int    nbPerdus   = 0;
      int    seriePerte = 0;
      int    seriePertMax = 0;
      double miseTotale = 0.0;
      double capitalMin = 0.0;  // capital minimum atteint (pour calculer bankroll requise)
      int    doublementsMax = 0;
      int    doublementsCourants = 0;

      for (final p in pronostics) {
        final gagne = p.rangFavoriIaDansArrivee == 1;
        // Cote approximative : coteFavoriPmu si disponible, sinon 2.5 par défaut
        final cote = (p.coteFavoriPmu != null && p.coteFavoriPmu! > 1.0) ? p.coteFavoriPmu! : 2.5;

        miseTotale += mise;
        if (gagne) {
          capital += mise * (cote - 1.0);
          nbGagnes++;
          seriePerte = 0;
          doublementsCourants = 0;
          mise = _btMise; // reset
        } else {
          capital -= mise;
          nbPerdus++;
          seriePerte++;
          if (seriePerte > seriePertMax) seriePertMax = seriePerte;
          doublementsCourants++;
          if (doublementsCourants > doublementsMax) doublementsMax = doublementsCourants;
          mise = mise * 2; // doublement
        }
        if (capital < capitalMin) capitalMin = capital;
      }

      // Capital minimum nécessaire pour survivre à la pire série de pertes
      // = mise_initiale × (2^serie_perdante_max - 1)
      final bankrollRequise = _btMise * ((1 << seriePertMax) - 1).toDouble();

      setState(() {
        _martingaleResult = _MartingaleResult(
          nbTotal:          pronostics.length,
          nbGagnes:         nbGagnes,
          nbPerdus:         nbPerdus,
          gainNet:          capital,
          miseTotale:       miseTotale,
          seriePertMax:     seriePertMax,
          doublementsMax:   doublementsMax,
          bankrollRequise:  bankrollRequise,
          miseFinale:       mise,
        );
        _btEnCours = false;
      });
    } catch (e) {
      if (mounted) setState(() => _btEnCours = false);
    }
  }

  Widget _buildMartingaleResultats(_MartingaleResult r) {
    final isPos = r.gainNet >= 0;
    final color = isPos ? const Color(0xFFFFB74D) : const Color(0xFFEF5350);
    final gainStr = '${r.gainNet >= 0 ? "+" : ""}${r.gainNet.toStringAsFixed(0)} €';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF111F30),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFB74D).withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.trending_up, color: Color(0xFFFFB74D), size: 20),
            const SizedBox(width: 8),
            const Text('Simulation Martingale',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(gainStr,
                  style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14)),
            ),
          ]),
          const SizedBox(height: 12),
          // Stats en grille 2×2
          Row(children: [
            _btStatBox('Réussite', '${(r.nbGagnes / r.nbTotal * 100).round()}%', const Color(0xFF4CAF7D)),
            const SizedBox(width: 8),
            _btStatBox('Courses', '${r.nbTotal}', Colors.white60),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            _btStatBox('Série perte max', '${r.seriePertMax}', const Color(0xFFEF5350)),
            const SizedBox(width: 8),
            _btStatBox('Doublements max', '${r.doublementsMax}', const Color(0xFFFFB74D)),
          ]),
          const SizedBox(height: 12),
          // Mise finale en cours
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFB74D).withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFFB74D).withValues(alpha: 0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.warning_amber, color: Color(0xFFFFB74D), size: 15),
                  const SizedBox(width: 6),
                  Text(
                    'Bankroll minimale requise : ${r.bankrollRequise.toStringAsFixed(0)} €',
                    style: const TextStyle(color: Color(0xFFFFB74D), fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ]),
                const SizedBox(height: 4),
                Text(
                  'Pour survivre à la pire série de ${r.seriePertMax} pertes consécutives avec mise initiale de ${_btMise.toStringAsFixed(0)} €.',
                  style: const TextStyle(color: Colors.white38, fontSize: 16, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '⚠️ La martingale présente un risque de perte illimitée. Jouez de façon responsable.',
            style: TextStyle(color: Colors.white24, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _btStatBox(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 16)),
          const SizedBox(height: 3),
          Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16)),
        ]),
      ),
    );
  }

  // ── ★ v10.67 : Bouton Export pill/outline ──────────────────────────────────
  Widget _buildExportButton() {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: _exportBacktestingEnCours ? null : _exporterBacktestingComplet,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0x3329B6F6),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: const Color(0xFF7C4DFF).withValues(alpha: 0.7),
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_exportBacktestingEnCours)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF8E7CFF),
                ),
              )
            else
              const Icon(
                Icons.download_rounded,
                size: 16,
                color: Color(0xFF8E7CFF),
              ),
            const SizedBox(width: 6),
            Text(
              _exportBacktestingEnCours ? 'Export...' : 'Export',
              style: const TextStyle(
                color: Color(0xFFB6A8FF),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── ★ v10.67 : Export image complète du Backtesting ───────────────────────
  /// Capture le RepaintBoundary complet (y compris le contenu off-screen).
  /// Fallback automatique vers le viewport visible si la capture complète échoue.
  Future<void> _exporterBacktestingComplet() async {
    if (_exportBacktestingEnCours) return;
    setState(() => _exportBacktestingEnCours = true);
    try {
      // Attendre la fin du layout et du rendu
      await Future.delayed(const Duration(milliseconds: 150));
      await WidgetsBinding.instance.endOfFrame;

      final ctx = _backtestingExportKey.currentContext;
      if (ctx == null) {
        if (kDebugMode) debugPrint('[Export] Context null — annulation');
        return;
      }

      final boundary = ctx.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        if (kDebugMode) debugPrint('[Export] RenderRepaintBoundary null — annulation');
        return;
      }

      // Capture complète avec pixelRatio raisonnable (2.5 = qualité sans OOM)
      ui.Image? image;
      try {
        image = await boundary.toImage(pixelRatio: 2.5);
      } catch (e) {
        if (kDebugMode) debugPrint('[Export] toImage(2.5) échoué → fallback 2.0 : $e');
        // Fallback : pixelRatio réduit si OOM
        try {
          image = await boundary.toImage(pixelRatio: 2.0);
        } catch (e2) {
          if (kDebugMode) debugPrint('[Export] toImage(2.0) échoué aussi : $e2');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Export impossible sur cet appareil.'),
                backgroundColor: Color(0xFF7C4DFF),
              ),
            );
          }
          return;
        }
      }

      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final pngBytes = byteData.buffer.asUint8List();
      final dir  = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/backtesting_ia_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(pngBytes);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: 'Export Backtesting IA Stats',
        ),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[Export] Erreur export backtesting : $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur export : $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _exportBacktestingEnCours = false);
    }
  }

  void _exporterResultats(BacktestResult r) {
    final roiStr  = '${r.roi >= 0 ? "+" : ""}${r.roi.toStringAsFixed(1)}%';
    final gainStr = '${r.gainNet >= 0 ? "+" : ""}${r.gainNet.toStringAsFixed(0)} €';
    final buf = StringBuffer()
      ..writeln('🔬 BACKTESTING — Pronostic Hippique IA')
      ..writeln('Période : $_btJours jours | Type : $_btType | Mise : ${_btMise.toStringAsFixed(0)} €/course')
      ..writeln('${_btDiscipline != null ? "Discipline : $_btDiscipline | " : ""}'
                '${_btHippodrome != null ? "Hippodrome : $_btHippodrome" : ""}')
      ..writeln('')
      ..writeln('📊 RÉSULTATS')
      ..writeln('ROI : $roiStr')
      ..writeln('Gain net : $gainStr')
      ..writeln('Réussite : ${r.tauxReussite.toStringAsFixed(0)}%')
      ..writeln('Courses : ${r.nbTotal} (${r.nbGagnes} gagnées / ${r.nbPerdus} perdues)')
      ..writeln('Misé au total : ${r.miseTotal.toStringAsFixed(0)} €')
      ..writeln('')
      ..writeln('📈 SÉRIES')
      ..writeln('Meilleure série gagnante : ${r.meilleureSerieGagnante}')
      ..writeln('Pire série perdante : ${r.pireSeriesPerdantes}');
    if (r.parDiscipline.isNotEmpty) {
      buf.writeln('\n🏇 PAR DISCIPLINE');
      r.parDiscipline.forEach((disc, stat) {
        buf.writeln('  $disc : ${stat.taux.toStringAsFixed(0)}% réussite — ${stat.gainNet >= 0 ? "+" : ""}${stat.gainNet.toStringAsFixed(0)}€');
      });
    }
    buf.writeln('\nGénéré par Pronostic Hippique IA v10.20');
    SharePlus.instance.share(ShareParams(text: buf.toString()));
  }

  // ── Listes de disciplines & hippodromes disponibles dans la mémoire IA ──────
  List<String> _getDisciplinesDisponibles() {
    final pronostics = IaMemoryService.instance.pronostics
        .where((p) => p.resultatsReels && p.arriveeReelle != null);
    final set = <String>{};
    for (final p in pronostics) {
      if (p.discipline.isNotEmpty) set.add(p.discipline);
    }
    final list = set.toList()..sort();
    return list;
  }

  List<String> _getHippodromesDisponibles() {
    final limiteDate = DateTime.now().subtract(Duration(days: _btJours));
    final pronostics = IaMemoryService.instance.pronostics
        .where((p) => p.resultatsReels && p.arriveeReelle != null
                   && p.datePronostic.isAfter(limiteDate));
    final map = <String, int>{};
    for (final p in pronostics) {
      if (p.hippodrome.isNotEmpty) {
        map[p.hippodrome] = (map[p.hippodrome] ?? 0) + 1;
      }
    }
    // Trier par fréquence décroissante, retenir les 10 premiers
    final list = map.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return list.take(10).map((e) => e.key).toList();
  }

  @override
  Widget build(BuildContext context) {
    final plage   = BacktestingService.instance.plageDisponible;
    final nbDispo = BacktestingService.instance.nbCoursesDisponibles;
    final disciplines  = _getDisciplinesDisponibles();
    final hippodromes  = _getHippodromesDisponibles();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── ★ v10.67 : RepaintBoundary englobant tout le contenu exportable ──
        RepaintBoundary(
          key: _backtestingExportKey,
          child: Container(
            color: const Color(0xFF0F1722), // fond opaque = pas de glitch PNG
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

        // ── En-tête ────────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1A1A2E), Color(0xFF0D1B2A)],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF7C4DFF).withValues(alpha: 0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ★ v10.67 : Header avec bouton Export en haut à droite
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Icon(Icons.science_rounded, color: Color(0xFF7C4DFF), size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Simulateur historique',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  _buildExportButton(),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Rejoue les journées passées pour mesurer ce que vous auriez gagné ou perdu en suivant l\'IA avec une mise fixe.',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Row(children: [
                const Icon(Icons.bar_chart, color: Color(0xFF7C4DFF), size: 15),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    nbDispo == 0
                      ? 'Aucune course avec résultat disponible'
                      : '$nbDispo course${nbDispo > 1 ? "s" : ""} avec résultats'
                        '${plage.debut != null ? " · du ${plage.debut!.day.toString().padLeft(2,"0")}/${plage.debut!.month.toString().padLeft(2,"0")} au ${plage.fin!.day.toString().padLeft(2,"0")}/${plage.fin!.month.toString().padLeft(2,"0")}" : ""}',
                    style: const TextStyle(color: Color(0xFF7C4DFF), fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
              ]),
            ],
          ),
        ),

        const SizedBox(height: 16),

        if (nbDispo == 0) ...[
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: const Color(0xFF111F30), borderRadius: BorderRadius.circular(14)),
            child: const Column(children: [
              Icon(Icons.hourglass_empty, color: Colors.white38, size: 48),
              SizedBox(height: 12),
              Text('Pas encore assez de données',
                  style: TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.bold)),
              SizedBox(height: 6),
              Text(
                'L\'IA a besoin de pronostics avec résultats officiels pour simuler. Revenez après quelques journées de courses.',
                style: TextStyle(color: Colors.white38, fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ]),
          ),
        ] else ...[

          // ── Paramètres ────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: const Color(0xFF111F30), borderRadius: BorderRadius.circular(14)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('⚙️ Paramètres',
                    style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                const SizedBox(height: 14),

                // ── Période ──────────────────────────────────────────────
                const Text('Période', style: TextStyle(color: Colors.white54, fontSize: 14)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8, runSpacing: 8,
                  children: [7, 14, 30, 60, 90].map((j) {
                    final sel = _btJours == j;
                    return GestureDetector(
                      onTap: () { setState(() => _btJours = j); _sauvegarderPrefs(); },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: sel ? const Color(0xFF7C4DFF) : const Color(0xFF0D1B2A),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: sel ? const Color(0xFF7C4DFF) : Colors.white24),
                        ),
                        child: Text('${j}j', style: TextStyle(
                            color: sel ? Colors.white : Colors.white54,
                            fontWeight: FontWeight.bold, fontSize: 14)),
                      ),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 14),

                // ── Type de pari ──────────────────────────────────────────
                const Text('Type de pari simulé', style: TextStyle(color: Colors.white54, fontSize: 14)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8, runSpacing: 8,
                  children: ['Conseil IA', 'Simple Gagnant', 'Simple Placé', 'Gagnant+Placé',
                             'Couplé Gagnant', 'Couplé Placé', 'Tiercé', 'Quarté+', 'Quinté+'].map((t) {
                    final sel = _btType == t;
                    return GestureDetector(
                      onTap: () { setState(() => _btType = t); _sauvegarderPrefs(); },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: sel ? const Color(0xFF004D40) : const Color(0xFF0D1B2A),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: sel ? const Color(0xFF00BCD4) : Colors.white24),
                        ),
                        child: Text(t, style: TextStyle(
                            color: sel ? const Color(0xFF00BCD4) : Colors.white54,
                            fontSize: 14, fontWeight: FontWeight.w600)),
                      ),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 14),

                // ── Mise par course (saisie manuelle v10.25) ───────────
                const Text('Mise par course',
                    style: TextStyle(color: Colors.white54, fontSize: 14)),
                const SizedBox(height: 8),
                // Champ texte + raccourcis rapides
                Row(
                  children: [
                    // Champ de saisie
                    Expanded(
                      child: Container(
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFF0D1B2A),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.5)),
                        ),
                        child: Row(
                          children: [
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _miseController,
                                keyboardType: TextInputType.number,
                                style: const TextStyle(
                                    color: Color(0xFFFFD700),
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold),
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                ),
                                // ★ v10.29 : onChanged = mise à jour silencieuse SANS setState ni save
                                // Pas de setState = pas de rebuild = pas de clignotement
                                onChanged: (v) {
                                  final val = double.tryParse(v);
                                  if (val != null) {
                                    _btMise = val.clamp(1.0, 9999.0);
                                    // Pas de setState, pas de save — on attend la validation
                                  }
                                },
                                // ★ v10.29 : onSubmitted = validation finale avec clamp + save
                                onSubmitted: (v) {
                                  final val = double.tryParse(v);
                                  final clamped = (val ?? _btMise).clamp(1.0, 9999.0);
                                  final clampedStr = clamped.toStringAsFixed(0);
                                  // Mettre à jour controller AVANT setState
                                  if (_miseController.text != clampedStr) {
                                    _miseController.value = TextEditingValue(
                                      text: clampedStr,
                                      selection: TextSelection.collapsed(offset: clampedStr.length),
                                    );
                                  }
                                  setState(() => _btMise = clamped);
                                  _sauvegarderPrefs();
                                },
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.only(right: 10),
                              child: Text('€', style: TextStyle(
                                  color: Color(0xFFFFD700),
                                  fontSize: 18, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Raccourcis rapides
                Wrap(
                  spacing: 6, runSpacing: 6,
                  children: [2, 5, 10, 20, 50, 100, 200].map((montant) {
                    final sel = _btMise.toStringAsFixed(0) == montant.toString();
                    return GestureDetector(
                      onTap: () {
                        _btMise = montant.toDouble();
                        // ★ v10.28 : mise à jour propre du controller sans reset cursor
                        _miseController.value = TextEditingValue(
                          text: montant.toString(),
                          selection: TextSelection.collapsed(offset: montant.toString().length),
                        );
                        setState(() {});
                        _sauvegarderPrefs();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: sel
                              ? const Color(0xFFFFD700).withValues(alpha: 0.18)
                              : const Color(0xFF0D1B2A),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: sel
                                  ? const Color(0xFFFFD700)
                                  : Colors.white24),
                        ),
                        child: Text('$montant€',
                            style: TextStyle(
                                color: sel ? const Color(0xFFFFD700) : Colors.white54,
                                fontSize: 14,
                                fontWeight: sel ? FontWeight.bold : FontWeight.normal)),
                      ),
                    );
                  }).toList(),
                ),

                // ── Confiance IA ──────────────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Confiance IA minimale', style: TextStyle(color: Colors.white54, fontSize: 14)),
                    Text('${_btConfianceMin.toStringAsFixed(0)} pts',
                        style: const TextStyle(color: Color(0xFF00BCD4), fontSize: 15, fontWeight: FontWeight.bold)),
                  ],
                ),
                Slider(
                  value: _btConfianceMin, min: 0, max: 95, divisions: 19,
                  activeColor: const Color(0xFF00BCD4),
                  inactiveColor: Colors.white12,
                  onChanged: (v) { setState(() => _btConfianceMin = v.roundToDouble()); _sauvegarderPrefs(); },
                ),
                if (_btConfianceMin > 0)
                  Text(
                    'Seules les courses avec confiance ≥ ${_btConfianceMin.toStringAsFixed(0)} pts seront simulées',
                    style: const TextStyle(color: Colors.white38, fontSize: 14),
                  ),

                // ══════════════════════════════════════════════════════════
                // ★ v10.20 — FILTRE DISCIPLINE
                // ══════════════════════════════════════════════════════════
                if (disciplines.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const Text('Discipline', style: TextStyle(color: Colors.white54, fontSize: 14)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: [
                      // Puce "Toutes" — visible uniquement si aucun filtre actif
                      if (_btDiscipline == null)
                        GestureDetector(
                          onTap: () { setState(() => _btDiscipline = null); _sauvegarderPrefs(); },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF3E2A6E),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: const Color(0xFF7C4DFF)),
                            ),
                            child: const Text('Toutes', style: TextStyle(
                                color: Color(0xFF7C4DFF),
                                fontSize: 14, fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ...disciplines.map((d) {
                        final sel = _btDiscipline == d;
                        return GestureDetector(
                          onTap: () { setState(() => _btDiscipline = d); _sauvegarderPrefs(); },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: sel ? const Color(0xFF3E2A6E) : const Color(0xFF0D1B2A),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: sel ? const Color(0xFF7C4DFF) : Colors.white24),
                            ),
                            child: Text(d, style: TextStyle(
                                color: sel ? const Color(0xFF7C4DFF) : Colors.white54,
                                fontSize: 14, fontWeight: FontWeight.w600)),
                          ),
                        );
                      }),
                    ],
                  ),
                ],

                // ══════════════════════════════════════════════════════════
                // ★ v10.20 — FILTRE HIPPODROME
                // ══════════════════════════════════════════════════════════
                if (hippodromes.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const Text('Hippodrome', style: TextStyle(color: Colors.white54, fontSize: 14)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: [
                      // Puce "Tous" — visible uniquement si aucun filtre actif
                      if (_btHippodrome == null)
                        GestureDetector(
                          onTap: () { setState(() => _btHippodrome = null); _sauvegarderPrefs(); },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A3A2E),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: const Color(0xFF4CAF7D)),
                            ),
                            child: const Text('Tous', style: TextStyle(
                                color: Color(0xFF4CAF7D),
                                fontSize: 14, fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ...hippodromes.map((h) {
                        final sel = _btHippodrome == h;
                        return GestureDetector(
                          onTap: () { setState(() => _btHippodrome = h); _sauvegarderPrefs(); },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: sel ? const Color(0xFF1A3A2E) : const Color(0xFF0D1B2A),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: sel ? const Color(0xFF4CAF7D) : Colors.white24),
                            ),
                            child: Text(h, style: TextStyle(
                                color: sel ? const Color(0xFF4CAF7D) : Colors.white54,
                                fontSize: 14, fontWeight: FontWeight.w600)),
                          ),
                        );
                      }),
                    ],
                  ),
                  if (_btDiscipline != null || _btHippodrome != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF7C4DFF).withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFF7C4DFF).withValues(alpha: 0.25)),
                            ),
                            child: Row(children: [
                              const Icon(Icons.filter_alt, color: Color(0xFF7C4DFF), size: 14),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Filtre actif : ${[
                                    if (_btDiscipline != null) _btDiscipline!,
                                    if (_btHippodrome != null) _btHippodrome!,
                                  ].join(" · ")}',
                                  style: const TextStyle(color: Color(0xFF7C4DFF), fontSize: 14),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              GestureDetector(
                                onTap: () {
                                  setState(() { _btDiscipline = null; _btHippodrome = null; });
                                  _sauvegarderPrefs();
                                },
                                child: const Icon(Icons.close, color: Colors.white38, size: 14),
                              ),
                            ]),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ],
            ),
          ),

          const SizedBox(height: 14),

          // ── Boutons Simuler + Comparer ────────────────────────────────────
          Row(children: [
            Expanded(
              flex: 3,
              child: GestureDetector(
                onTap: _btEnCours ? null : () => _lancerBacktest(),
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: _btEnCours
                        ? const LinearGradient(colors: [Color(0xFF263238), Color(0xFF1C2A38)])
                        : const LinearGradient(colors: [Color(0xFF7C4DFF), Color(0xFF512DA8)]),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: _btEnCours ? [] : [
                      BoxShadow(color: const Color(0xFF7C4DFF).withValues(alpha: 0.4),
                          blurRadius: 12, offset: const Offset(0, 4))
                    ],
                  ),
                  child: Center(
                    child: _btEnCours
                      ? const Row(mainAxisSize: MainAxisSize.min, children: [
                          SizedBox(width: 18, height: 18,
                              child: CircularProgressIndicator(color: Colors.white70, strokeWidth: 2)),
                          SizedBox(width: 10),
                          Text('En cours…',
                              style: TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.bold)),
                        ])
                      : const Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.play_circle_fill, color: Colors.white, size: 20),
                          SizedBox(width: 8),
                          Text('Simuler',
                              style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                        ]),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: GestureDetector(
                onTap: _btEnCours ? null : _lancerComparaison,
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(
                    color: const Color(0xFF111F30),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF7C4DFF).withValues(alpha: 0.5)),
                  ),
                  child: const Center(
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.compare_arrows, color: Color(0xFF7C4DFF), size: 18),
                      SizedBox(width: 6),
                      Text('Comparer',
                          style: TextStyle(color: Color(0xFF7C4DFF), fontSize: 14, fontWeight: FontWeight.bold)),
                    ]),
                  ),
                ),
              ),
            ),
          ]),

          // ★ v10.24 — Bouton Martingale
          const SizedBox(height: 10),
          GestureDetector(
            onTap: _btEnCours ? null : _lancerMartingale,
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: _btEnCours
                    ? const Color(0xFF1C2A38)
                    : const Color(0xFF1A1000),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _btEnCours
                      ? Colors.white12
                      : const Color(0xFFFFB74D).withValues(alpha: 0.6),
                ),
              ),
              child: Center(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.trending_up,
                      color: _btEnCours ? Colors.white24 : const Color(0xFFFFB74D),
                      size: 18),
                  const SizedBox(width: 8),
                  Text('Simuler Martingale',
                      style: TextStyle(
                          color: _btEnCours ? Colors.white24 : const Color(0xFFFFB74D),
                          fontSize: 14,
                          fontWeight: FontWeight.bold)),
                ]),
              ),
            ),
          ),

          // ── Résultats ──────────────────────────────────────────────────────
          if (_btResult != null) ...[
            const SizedBox(height: 20),
            _buildBtResultats(_btResult!),
            const SizedBox(height: 12),
            _buildBoutonAppliquerConseils(),
          ],

          // ★ v10.24 — Résultat Martingale
          if (_martingaleResult != null) ...[
            const SizedBox(height: 20),
            _buildMartingaleResultats(_martingaleResult!),
          ],
        ],

              const SizedBox(height: 24),

              ], // Column children (RepaintBoundary)
            ),  // Column
          ),    // Container fond opaque
        ),      // RepaintBoundary
      ],
    );
  }

  // ── Helper chip pour le dialog de confirmation ───────────────────────────
  Widget _dialogChip(String label, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Container(width: 8, height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // ── Bouton "Appliquer vers Conseils IA" ──────────────────────────────────
  Widget _buildBoutonAppliquerConseils() {
    // Construire la description des filtres actifs
    final List<String> lignes = [];
    if (_btType != 'Conseil IA') lignes.add('Type : $_btType');
    if (_btConfianceMin > 0)     lignes.add('Confiance ≥ ${_btConfianceMin.round()}%');
    if (_btDiscipline != null)   lignes.add('Discipline : $_btDiscipline');
    if (_btHippodrome != null)   lignes.add('Hippodrome : $_btHippodrome');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0D2535),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF4CAF7D).withValues(alpha: 0.45), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Titre
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF4CAF7D).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('✨', style: TextStyle(fontSize: 16)),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Appliquer vers Conseils IA',
                        style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                    Text('Pré-configurer les filtres depuis ce backtesting',
                        style: TextStyle(color: Colors.white38, fontSize: 16)),
                  ],
                ),
              ),
            ],
          ),

          // Résumé des critères
          if (lignes.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6, runSpacing: 6,
              children: lignes.map((l) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF4CAF7D).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF4CAF7D).withValues(alpha: 0.3)),
                ),
                child: Text(l, style: const TextStyle(color: Color(0xFF4CAF7D), fontSize: 14, fontWeight: FontWeight.w600)),
              )).toList(),
            ),
          ] else ...[
            const SizedBox(height: 8),
            Text('Aucun filtre spécifique — transfert des critères par défaut.',
                style: TextStyle(color: Colors.white38, fontSize: 14)),
          ],

          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                // Injecter les filtres dans SharedPreferences
                // ConseilsScreen les lira automatiquement à son prochain focus
                final prefs = await SharedPreferences.getInstance();
                // Types de paris : convertir depuis le type backtesting
                final List<String> types = _btType != 'Conseil IA' ? [_btType] : [];
                await prefs.setStringList('conseils_filtres_types_paris', types);
                await prefs.setStringList('conseils_filtres_hippodromes',
                    _btHippodrome != null ? [_btHippodrome!] : []);
                await prefs.setStringList('conseils_filtres_disciplines',
                    _btDiscipline != null ? [_btDiscipline!] : []);
                await prefs.setInt('conseils_filtres_confiance_min',
                    _btConfianceMin.round());
                // Flag pour signaler qu'un inject est en attente
                await prefs.setBool('conseils_inject_pending', true);

                if (!mounted) return;

                final nbFiltres = [
                  if (types.isNotEmpty) types.length,
                  if (_btHippodrome != null) 1,
                  if (_btDiscipline != null) 1,
                  if (_btConfianceMin > 0) 1,
                ].fold(0, (a, b) => a + b);

                // ★ v10.27 : Dialog de confirmation lisible avant navigation
                await showDialog<void>(
                  context: context,
                  barrierDismissible: true,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: const Color(0xFF0D1B2A),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    title: const Row(
                      children: [
                        Text('✨', style: TextStyle(fontSize: 20)),
                        SizedBox(width: 8),
                        Text('Filtres appliqués',
                            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          nbFiltres > 0
                              ? '$nbFiltres critère${nbFiltres > 1 ? "s" : ""} transféré${nbFiltres > 1 ? "s" : ""} vers Conseils IA :'
                              : 'Filtres réinitialisés dans Conseils IA.',
                          style: const TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                        if (nbFiltres > 0) ...[  
                          const SizedBox(height: 10),
                          if (types.isNotEmpty)
                            _dialogChip('Type : ${types.join(", ")}', const Color(0xFF7C4DFF)),
                          if (_btConfianceMin > 0)
                            _dialogChip('Confiance ≥ ${_btConfianceMin.round()}%', const Color(0xFF00BCD4)),
                          if (_btDiscipline != null)
                            _dialogChip('Discipline : $_btDiscipline', const Color(0xFF4CAF7D)),
                          if (_btHippodrome != null)
                            _dialogChip('Hippodrome : $_btHippodrome', const Color(0xFFFFD700)),
                        ],
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text('Annuler', style: TextStyle(color: Colors.white38)),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          // ★ v10.27 : Conseils est maintenant à l'index 1
                          context.read<NavigationNotifier>().goTo(1);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF7C4DFF),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text('Ouvrir Conseils IA', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                );
              },
              icon: const Icon(Icons.arrow_forward, size: 16),
              label: const Text('Appliquer vers Conseils IA',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D52),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '💡 Les filtres sont appliqués automatiquement à l\'ouverture de Conseils IA.',
            style: TextStyle(color: Colors.white24, fontSize: 16),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildBtResultats(BacktestResult r) {
    final gainColor = r.gainNet >= 0 ? const Color(0xFF4CAF7D) : Colors.redAccent;
    final mise      = _btMise;
    final miseParcours = (_btType == 'Gagnant+Placé') ? mise * 2 : mise;
    final coussin      = r.pireSeriesPerdantes * miseParcours;
    final gainMoyenGagne = r.nbGagnes > 0
        ? (r.gainNet + r.nbPerdus * miseParcours) / r.nbGagnes
        : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        // ═══════════════════════════════════════════════════════════════════
        // BLOC 1 — VERDICT EN UNE PHRASE
        // ═══════════════════════════════════════════════════════════════════
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: r.estRentable
                  ? [const Color(0xFF1B3A2B), const Color(0xFF0D1B2A)]
                  : [const Color(0xFF3A1B1B), const Color(0xFF0D1B2A)],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: r.estRentable
                  ? const Color(0xFF4CAF7D).withValues(alpha: 0.5)
                  : Colors.redAccent.withValues(alpha: 0.4),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(children: [
                    Icon(
                      r.estRentable ? Icons.trending_up : Icons.trending_down,
                      color: gainColor, size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      r.estRentable ? '✅ Stratégie rentable' : '❌ Stratégie déficitaire',
                      style: TextStyle(color: gainColor, fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ]),
                  GestureDetector(
                    onTap: () => _exporterResultats(r),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.share_rounded, color: Colors.white54, size: 14),
                        SizedBox(width: 4),
                        Text('Partager', style: TextStyle(color: Colors.white54, fontSize: 14)),
                      ]),
                    ),
                  ),
                ],
              ),

              // Badge filtre actif dans les résultats
              if (_btDiscipline != null || _btHippodrome != null) ...[
                const SizedBox(height: 6),
                Wrap(spacing: 6, children: [
                  if (_btDiscipline != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF7C4DFF).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('📍 $_btDiscipline',
                          style: const TextStyle(color: Color(0xFF7C4DFF), fontSize: 16)),
                    ),
                  if (_btHippodrome != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4CAF7D).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('🏟️ $_btHippodrome',
                          style: const TextStyle(color: Color(0xFF4CAF7D), fontSize: 16)),
                    ),
                ]),
              ],

              const SizedBox(height: 14),

              // PHRASE RÉSUMÉ INTUITIVE
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  r.estRentable
                    ? 'Sur ${_btJours}j, en jouant ${mise.toStringAsFixed(0)} € sur chaque course recommandée par l\'IA, '
                      'tu aurais misé ${r.miseTotal.toStringAsFixed(0)} € au total '
                      'et récupéré ${(r.miseTotal + r.gainNet).toStringAsFixed(0)} € — '
                      'soit ${r.gainNet >= 0 ? "+" : ""}${r.gainNet.toStringAsFixed(0)} € de bénéfice net.'
                    : 'Sur ${_btJours}j, en jouant ${mise.toStringAsFixed(0)} € sur chaque course recommandée par l\'IA, '
                      'tu aurais misé ${r.miseTotal.toStringAsFixed(0)} € au total '
                      'et récupéré ${(r.miseTotal + r.gainNet).toStringAsFixed(0)} € — '
                      'soit ${r.gainNet.toStringAsFixed(0)} € de perte nette.',
                  style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
                ),
              ),

              const SizedBox(height: 14),

              // 4 métriques clés
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _btMetrique(
                    '${r.roi >= 0 ? "+" : ""}${r.roi.toStringAsFixed(1)}%',
                    'ROI',
                    'Pour 100 € misés\ntu récupères\n${(100 + r.roi).toStringAsFixed(0)} €',
                    r.roi >= 0 ? const Color(0xFF4CAF7D) : Colors.redAccent,
                  ),
                  _btDivider(),
                  _btMetrique(
                    '${r.gainNet >= 0 ? "+" : ""}${r.gainNet.toStringAsFixed(0)} €',
                    'Gain net',
                    '${r.miseTotal.toStringAsFixed(0)} € misés\n→ ${(r.miseTotal + r.gainNet).toStringAsFixed(0)} € récupérés',
                    gainColor,
                  ),
                  _btDivider(),
                  _btMetrique(
                    '${r.tauxReussite.toStringAsFixed(0)}%',
                    '1 pari sur ${r.tauxReussite > 0 ? (100 / r.tauxReussite).toStringAsFixed(0) : "?"}',
                    '${r.nbGagnes} gagnés\n${r.nbPerdus} perdus\nsur ${r.nbTotal} courses',
                    Colors.white,
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // ═══════════════════════════════════════════════════════════════════
        // BLOC 2 — RÉSISTANCE
        // ═══════════════════════════════════════════════════════════════════
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF111F30),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.redAccent.withValues(alpha: 0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(children: [
                Icon(Icons.shield_outlined, color: Colors.redAccent, size: 16),
                SizedBox(width: 6),
                Text('Résistance — pire séquence vécue',
                    style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 12),

              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 4, runSpacing: 4,
                      children: [
                        ...List.generate(
                          r.pireSeriesPerdantes.clamp(0, 15),
                          (_) => const Icon(Icons.close, color: Colors.redAccent, size: 14),
                        ),
                        if (r.pireSeriesPerdantes > 15)
                          Text('…+${r.pireSeriesPerdantes - 15}',
                              style: const TextStyle(color: Colors.redAccent, fontSize: 14)),
                        const Icon(Icons.check_circle, color: Color(0xFF4CAF7D), size: 18),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RichText(
                      text: TextSpan(
                        style: const TextStyle(color: Colors.white60, fontSize: 14, height: 1.6),
                        children: [
                          const TextSpan(text: 'Pire série perdante : '),
                          TextSpan(
                            text: '${r.pireSeriesPerdantes} paris perdus d\'affilée',
                            style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
                          ),
                          const TextSpan(text: '\nMise par course : '),
                          TextSpan(
                            text: '${miseParcours.toStringAsFixed(0)} €',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                          const TextSpan(text: '\n\n'),
                          TextSpan(
                            text: '${r.pireSeriesPerdantes} × ${miseParcours.toStringAsFixed(0)} € = ${coussin.toStringAsFixed(0)} € partis avant le prochain gain',
                            style: const TextStyle(
                              color: Colors.redAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    RichText(
                      text: TextSpan(
                        style: const TextStyle(color: Colors.white38, fontSize: 14, height: 1.5),
                        children: [
                          const TextSpan(text: '→ Juste après, un gain de '),
                          TextSpan(
                            text: '+${gainMoyenGagne.toStringAsFixed(0)} € en moyenne',
                            style: const TextStyle(color: Color(0xFF4CAF7D), fontWeight: FontWeight.bold),
                          ),
                          const TextSpan(
                            text: ' te rembourse ces pertes en quelques courses.\n'
                                'Si tu arrêtes pendant la série, tu rates ce rebond. 💡',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 10),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF4CAF7D).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF4CAF7D).withValues(alpha: 0.2)),
                ),
                child: Row(children: [
                  const Icon(Icons.savings_outlined, color: Color(0xFF4CAF7D), size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Réserve conseillée : au moins ${coussin.toStringAsFixed(0)} € '
                      '(= ${r.pireSeriesPerdantes} × ${miseParcours.toStringAsFixed(0)} €) '
                      'pour ne jamais être forcé d\'arrêter.',
                      style: const TextStyle(color: Color(0xFF4CAF7D), fontSize: 14, height: 1.4),
                    ),
                  ),
                ]),
              ),

              const SizedBox(height: 10),
              Row(children: [
                const Icon(Icons.local_fire_department, color: Color(0xFFFFD700), size: 15),
                const SizedBox(width: 6),
                Text(
                  'Meilleure série gagnante : ${r.meilleureSerieGagnante} paris consécutifs gagnés'
                  ' (= +${(r.meilleureSerieGagnante * gainMoyenGagne).toStringAsFixed(0)} € d\'affilée)',
                  style: const TextStyle(color: Colors.white38, fontSize: 14),
                ),
              ]),

              // ★ Amél. 5 : MaxDrawdown — perte max sur la période
              if (r.maxDrawdown > 0) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.withValues(alpha: 0.25)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Icon(Icons.trending_down, color: Colors.orange, size: 15),
                        const SizedBox(width: 6),
                        RichText(
                          text: TextSpan(
                            style: const TextStyle(fontSize: 14, height: 1.5),
                            children: [
                              const TextSpan(
                                text: 'Perte max sur la période : ',
                                style: TextStyle(color: Colors.white60),
                              ),
                              TextSpan(
                                text: '−${r.maxDrawdown.toStringAsFixed(0)} €',
                                style: const TextStyle(
                                  color: Colors.orange,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ]),
                      const SizedBox(height: 4),
                      Text(
                        'Creux maximal entre un pic et le point le plus bas suivant.\n'
                        'Indicateur de risque réel pendant la simulation.',
                        style: TextStyle(
                          color: Colors.orange.withValues(alpha: 0.65),
                          fontSize: 16,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 12),

        // ═══════════════════════════════════════════════════════════════════
        // BLOC 3 — COURBE
        // ═══════════════════════════════════════════════════════════════════
        if (r.courbeGains.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF111F30),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(children: [
                  Icon(Icons.show_chart, color: Color(0xFF7C4DFF), size: 16),
                  SizedBox(width: 6),
                  Text('Évolution de ta cagnotte',
                      style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold)),
                ]),
                const SizedBox(height: 4),
                const Text(
                  'Chaque montée = un pari gagné  ·  Chaque descente = une perte',
                  style: TextStyle(color: Colors.white30, fontSize: 16),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 90,
                  child: CustomPaint(
                    size: const Size(double.infinity, 90),
                    painter: _CourbePainter(r.courbeGains),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Début\n0 €',
                        style: TextStyle(color: Colors.white24, fontSize: 16), textAlign: TextAlign.center),
                    Column(children: [
                      Text(
                        '${r.gainNet >= 0 ? "+" : ""}${r.gainNet.toStringAsFixed(0)} €',
                        style: TextStyle(
                          color: gainColor, fontSize: 15, fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Text('résultat final',
                          style: TextStyle(color: Colors.white30, fontSize: 16)),
                    ]),
                    const Text('Fin',
                        style: TextStyle(color: Colors.white24, fontSize: 16)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // ═══════════════════════════════════════════════════════════════════
        // BLOC 4 — PAR DISCIPLINE
        // ═══════════════════════════════════════════════════════════════════
        if (r.parDiscipline.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF111F30),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(children: [
                  Icon(Icons.sports, color: Color(0xFF7C4DFF), size: 16),
                  SizedBox(width: 6),
                  Text('Par discipline — où jouer, où éviter',
                      style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold)),
                ]),
                const SizedBox(height: 12),
                ...(() {
                  final entries = r.parDiscipline.entries.toList()
                    ..sort((a, b) => b.value.gainNet.compareTo(a.value.gainNet));
                  return entries.map((e) {
                    final stat  = e.value;
                    final color = stat.gainNet >= 0 ? const Color(0xFF4CAF7D) : Colors.redAccent;
                    final emoji = stat.gainNet >= 0 ? '✅' : '❌';
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: color.withValues(alpha: 0.2)),
                      ),
                      child: Row(children: [
                        Text(emoji, style: const TextStyle(fontSize: 14)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(e.key,
                                  style: const TextStyle(color: Colors.white,
                                      fontSize: 14, fontWeight: FontWeight.w600)),
                              Text(
                                '${stat.nbTotal} courses · ${stat.taux.toStringAsFixed(0)}% gagnées',
                                style: const TextStyle(color: Colors.white38, fontSize: 16),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '${stat.gainNet >= 0 ? "+" : ""}${stat.gainNet.toStringAsFixed(0)} €',
                          style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                      ]),
                    );
                  }).toList();
                })(),
                const SizedBox(height: 4),
                Builder(builder: (ctx) {
                  final rentables = r.parDiscipline.entries
                      .where((e) => e.value.gainNet > 0).map((e) => e.key).toList();
                  final perdantes = r.parDiscipline.entries
                      .where((e) => e.value.gainNet < 0).map((e) => e.key).toList();
                  if (rentables.isEmpty && perdantes.isEmpty) return const SizedBox();
                  return Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF7C4DFF).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '💡 ${rentables.isNotEmpty ? "Joue en priorité : ${rentables.join(", ")}." : ""}'
                      '${perdantes.isNotEmpty ? " Évite : ${perdantes.join(", ")}." : ""}',
                      style: const TextStyle(color: Color(0xFF7C4DFF), fontSize: 14, height: 1.4),
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // ═══════════════════════════════════════════════════════════════════
        // BLOC 4b — PAR TYPE DE PARI (★ v10.35 synergie vrais critères PMU)
        // ═══════════════════════════════════════════════════════════════════
        if (r.parTypePari.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF111F30),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(children: [
                  Icon(Icons.casino_outlined, color: Color(0xFFFFD700), size: 16),
                  SizedBox(width: 6),
                  Text('Par type de pari — taux et Kelly optimal',
                      style: TextStyle(color: Colors.white70, fontSize: 14,
                          fontWeight: FontWeight.bold)),
                ]),
                const SizedBox(height: 4),
                const Text(
                  'Basé sur les vrais critères PMU (Couplé = 2 chevaux dans le top 2, etc.)',
                  style: TextStyle(color: Colors.white38, fontSize: 16),
                ),
                const SizedBox(height: 12),
                ...(() {
                  // Ordre des types de paris du plus joué au moins joué
                  final entries = r.parTypePari.entries.toList()
                    ..sort((a, b) => b.value.nbTotal.compareTo(a.value.nbTotal));
                  return entries.map((e) {
                    final stat   = e.value;
                    final color  = stat.gainNet >= 0
                        ? const Color(0xFF4CAF7D) : Colors.redAccent;
                    final emoji  = stat.gainNet >= 0 ? '✅' : '❌';
                    final kelly  = stat.kellyFraction();
                    final kellyTxt = kelly > 0
                        ? '🎯 Kelly : ${(kelly * 100).toStringAsFixed(0)}% bankroll'
                        : '⛔ Ne pas jouer (Kelly = 0)';
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: color.withValues(alpha: 0.2)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Text(emoji, style: const TextStyle(fontSize: 14)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(e.key,
                                style: const TextStyle(color: Colors.white,
                                    fontSize: 14, fontWeight: FontWeight.w600)),
                            ),
                            Text(
                              '${stat.gainNet >= 0 ? "+" : ""}${stat.gainNet.toStringAsFixed(0)} €',
                              style: TextStyle(color: color, fontSize: 14,
                                  fontWeight: FontWeight.bold),
                            ),
                          ]),
                          const SizedBox(height: 6),
                          Row(children: [
                            // Taux de réussite
                            Expanded(child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${stat.taux.toStringAsFixed(0)}% de réussite',
                                    style: const TextStyle(color: Colors.white54,
                                        fontSize: 16)),
                                Text('${stat.nbGagnes}/${stat.nbTotal} gagnés',
                                    style: const TextStyle(color: Colors.white38,
                                        fontSize: 16)),
                              ],
                            )),
                            // ROI
                            Expanded(child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Text('ROI ${stat.roi >= 0 ? "+" : ""}${stat.roi.toStringAsFixed(0)}%',
                                    style: TextStyle(
                                      color: stat.roi >= 0
                                          ? const Color(0xFF4CAF7D)
                                          : Colors.redAccent,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    )),
                                Text('Série max : ${stat.maxSerie}',
                                    style: const TextStyle(color: Colors.white38,
                                        fontSize: 16)),
                              ],
                            )),
                            // Kelly
                            Expanded(child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  kelly > 0
                                      ? '${(kelly * 100).toStringAsFixed(0)}%'
                                      : '0%',
                                  style: TextStyle(
                                    color: kelly > 0
                                        ? const Color(0xFFFFD700)
                                        : Colors.white24,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  )),
                                const Text('Kelly',
                                    style: TextStyle(color: Colors.white38,
                                        fontSize: 14)),
                              ],
                            )),
                          ]),
                          if (stat.nbTotal >= 5) ...[
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF7C4DFF).withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(kellyTxt,
                                style: const TextStyle(
                                    color: Color(0xFFB39DDB),
                                    fontSize: 16)),
                            ),
                          ],
                        ],
                      ),
                    );
                  }).toList();
                })(),
                // Conseil global
                const SizedBox(height: 4),
                Builder(builder: (ctx) {
                  final meilleur = r.parTypePari.entries
                      .where((e) => e.value.nbTotal >= 5 && e.value.roi > 0)
                      .toList()
                    ..sort((a, b) => b.value.roi.compareTo(a.value.roi));
                  final eviter = r.parTypePari.entries
                      .where((e) => e.value.nbTotal >= 5 && e.value.roi < -20)
                      .toList()
                    ..sort((a, b) => a.value.roi.compareTo(b.value.roi));
                  if (meilleur.isEmpty && eviter.isEmpty) return const SizedBox();
                  return Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF7C4DFF).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '💡 ${meilleur.isNotEmpty ? "Privilégie : ${meilleur.take(2).map((e) => e.key).join(", ")}." : ""}'
                      '${eviter.isNotEmpty ? " Évite : ${eviter.take(2).map((e) => e.key).join(", ")}." : ""}',
                      style: const TextStyle(color: Color(0xFF7C4DFF),
                          fontSize: 14, height: 1.4),
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // ═══════════════════════════════════════════════════════════════════
        // BLOC 5 — PAR HIPPODROME
        // ═══════════════════════════════════════════════════════════════════
        if (r.parHippodrome.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF111F30),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(children: [
                  Icon(Icons.location_on, color: Color(0xFF7C4DFF), size: 16),
                  SizedBox(width: 6),
                  Text('Par hippodrome — Top 5',
                      style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold)),
                ]),
                const SizedBox(height: 12),
                ...(() {
                  final entries = r.parHippodrome.entries.toList()
                    ..sort((a, b) => b.value.gainNet.compareTo(a.value.gainNet));
                  return entries.map((e) {
                    final stat  = e.value;
                    final color = stat.gainNet >= 0 ? const Color(0xFF4CAF7D) : Colors.redAccent;
                    final maxGain = entries
                        .map((x) => x.value.gainNet.abs())
                        .fold(0.0, (a, b) => a > b ? a : b);
                    final ratio = maxGain > 0 ? (stat.gainNet.abs() / maxGain).clamp(0.0, 1.0) : 0.0;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Expanded(
                              child: Text(e.key,
                                  style: const TextStyle(color: Colors.white70, fontSize: 14)),
                            ),
                            Text('${stat.nbTotal} courses',
                                style: const TextStyle(color: Colors.white30, fontSize: 16)),
                            const SizedBox(width: 10),
                            Text(
                              '${stat.gainNet >= 0 ? "+" : ""}${stat.gainNet.toStringAsFixed(0)} €',
                              style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                          ]),
                          const SizedBox(height: 4),
                          Stack(children: [
                            Container(
                              height: 4,
                              decoration: BoxDecoration(
                                color: Colors.white10,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            FractionallySizedBox(
                              widthFactor: ratio,
                              child: Container(
                                height: 4,
                                decoration: BoxDecoration(
                                  color: color,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                          ]),
                          Text(
                            '${stat.taux.toStringAsFixed(0)}% de réussite',
                            style: const TextStyle(color: Colors.white30, fontSize: 16),
                          ),
                        ],
                      ),
                    );
                  }).toList();
                })(),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // ═══════════════════════════════════════════════════════════════════
        // BLOC 6 — DÉTAIL COURSES (accordéon)
        // ═══════════════════════════════════════════════════════════════════
        if (r.courses.isNotEmpty) ...[
          Theme(
            data: ThemeData(dividerColor: Colors.transparent),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF111F30),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                title: Text(
                  '📋 Détail des ${r.courses.length} courses simulées',
                  style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  '✅ ${r.nbGagnes} gagnées  ❌ ${r.nbPerdus} perdues',
                  style: const TextStyle(color: Colors.white30, fontSize: 16),
                ),
                iconColor: Colors.white38,
                collapsedIconColor: Colors.white24,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    child: Column(children: [
                      ...(() {
                        final liste     = r.courses.reversed.toList();
                        final affichees = _btShowAll ? liste : liste.take(20).toList();
                        return affichees.map((c) {
                          final dateStr = '${c.date.day.toString().padLeft(2,"0")}/${c.date.month.toString().padLeft(2,"0")}';
                          final color   = c.gagne ? const Color(0xFF4CAF7D) : Colors.redAccent;
                          final gainStr = '${c.gainNet >= 0 ? "+" : ""}${c.gainNet.toStringAsFixed(0)}€';
                          return Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0D1B2A),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: c.gagne
                                    ? const Color(0xFF4CAF7D).withValues(alpha: 0.2)
                                    : Colors.redAccent.withValues(alpha: 0.12),
                              ),
                            ),
                            child: Row(children: [
                              Icon(
                                c.gagne ? Icons.check_circle_outline : Icons.highlight_off,
                                color: color, size: 16,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('$dateStr · ${c.hippodrome}',
                                        style: const TextStyle(color: Colors.white38, fontSize: 16)),
                                    Text(c.nomCourse,
                                        style: const TextStyle(color: Colors.white70, fontSize: 14),
                                        maxLines: 1, overflow: TextOverflow.ellipsis),
                                  ],
                                ),
                              ),
                              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                Text(gainStr,
                                    style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold)),
                                Text(c.typePariConseille,
                                    style: const TextStyle(color: Colors.white30, fontSize: 16)),
                              ]),
                            ]),
                          );
                        }).toList();
                      })(),
                      if (r.courses.length > 20)
                        GestureDetector(
                          onTap: () => setState(() => _btShowAll = !_btShowAll),
                          child: Container(
                            margin: const EdgeInsets.only(top: 4, bottom: 8),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0D1B2A),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: Center(
                              child: Text(
                                _btShowAll
                                  ? '▲ Réduire'
                                  : '▼ Voir tout (${r.courses.length - 20} autres)',
                                style: const TextStyle(
                                  color: Colors.white54, fontSize: 14, fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ]),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _btMetrique(String valeur, String label, String tooltip, Color color) {
    return Expanded(
      child: GestureDetector(
        onLongPress: () {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('$label : $tooltip'),
            duration: const Duration(seconds: 3),
            backgroundColor: const Color(0xFF1A1A3E),
          ));
        },
        child: Column(children: [
          Text(valeur,
              style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 3),
          Text(label,
              style: const TextStyle(color: Colors.white38, fontSize: 16),
              textAlign: TextAlign.center),
          const SizedBox(height: 2),
          const Icon(Icons.touch_app, color: Colors.white12, size: 10),
        ]),
      ),
    );
  }

  Widget _btDivider() {
    return Container(width: 1, height: 48, color: Colors.white10);
  }

  Widget _cmpStat(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(color: Colors.white30, fontSize: 16)),
      ],
    );
  }
}

// ── Courbe gains cumulés ──────────────────────────────────────────────────────
class _CourbePainter extends CustomPainter {
  final List<double> gains;
  const _CourbePainter(this.gains);

  @override
  void paint(Canvas canvas, Size size) {
    if (gains.isEmpty) return;
    final minV  = gains.reduce((a, b) => a < b ? a : b);
    final maxV  = gains.reduce((a, b) => a > b ? a : b);
    final range = (maxV - minV).abs();
    if (range == 0) return;

    final paintLine = Paint()..strokeWidth = 2..style = PaintingStyle.stroke;
    final paintFill = Paint()..style = PaintingStyle.fill;
    final path      = Path();
    final fillPath  = Path();
    final n = gains.length;

    double x(int i)    => size.width * i / (n - 1);
    double y(double v) => size.height - ((v - minV) / range) * size.height;

    path.moveTo(x(0), y(gains[0]));
    fillPath.moveTo(x(0), size.height);
    fillPath.lineTo(x(0), y(gains[0]));
    for (int i = 1; i < n; i++) {
      path.lineTo(x(i), y(gains[i]));
      fillPath.lineTo(x(i), y(gains[i]));
    }
    fillPath.lineTo(x(n - 1), size.height);
    fillPath.close();

    final isPositive = gains.last >= 0;
    final color      = isPositive ? const Color(0xFF4CAF7D) : Colors.redAccent;
    paintFill.color  = color.withValues(alpha: 0.12);
    paintLine.color  = color;
    canvas.drawPath(fillPath, paintFill);
    canvas.drawPath(path, paintLine);

    if (minV < 0 && maxV > 0) {
      final zeroPaint = Paint()..color = Colors.white24..strokeWidth = 1;
      final zy = y(0);
      canvas.drawLine(Offset(0, zy), Offset(size.width, zy), zeroPaint);
    }
  }

  @override
  bool shouldRepaint(_CourbePainter old) => !listEquals(old.gains, gains);
}

// ── ★ v10.24 : Résultat simulation Martingale ─────────────────────────────────
class _MartingaleResult {
  final int    nbTotal;
  final int    nbGagnes;
  final int    nbPerdus;
  final double gainNet;
  final double miseTotale;
  final int    seriePertMax;
  final int    doublementsMax;
  final double bankrollRequise;
  final double miseFinale;

  const _MartingaleResult({
    required this.nbTotal,
    required this.nbGagnes,
    required this.nbPerdus,
    required this.gainNet,
    required this.miseTotale,
    required this.seriePertMax,
    required this.doublementsMax,
    required this.bankrollRequise,
    required this.miseFinale,
  });
}
