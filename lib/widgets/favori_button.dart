import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../services/alert_service.dart';

// ══════════════════════════════════════════════════════════════════════════════
// FavoriButton v2 — Bouton étoile ⭐ avec bottom sheet dorée
// ══════════════════════════════════════════════════════════════════════════════

class FavoriButton extends StatefulWidget {
  // ★ Notifier global — accessible depuis _FavorisTab pour se rafraîchir
  static final ValueNotifier<int> syncNotifier = ValueNotifier(0);

  final int numR;
  final int numC;
  final String nomCourse;
  final String hippodrome;
  final double scoreIA;
  final String heure;
  final String distance;
  final String prix;
  final double size;
  final bool showLabel;

  const FavoriButton({
    super.key,
    required this.numR,
    required this.numC,
    required this.nomCourse,
    required this.hippodrome,
    this.scoreIA = 0.0,
    this.heure = '',
    this.distance = '',
    this.prix = '',
    this.size = 22,
    this.showLabel = false,
  });

  @override
  State<FavoriButton> createState() => _FavoriButtonState();
}

class _FavoriButtonState extends State<FavoriButton>
    with SingleTickerProviderStateMixin, RouteAware {

  // Clé centralisée dans AlertService — cohérence avec mes_paris_screen et HippiqueWorker
  static const _prefsKey = AlertService.favoritesKey;
  bool _isFavori = false;
  bool _loading  = true;
  late AnimationController _anim;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _scaleAnim = Tween<double>(begin: 1.0, end: 1.4).animate(
      CurvedAnimation(parent: _anim, curve: Curves.elasticOut));
    _chargerStatut();
    // ★ S'abonner au notifier global — si une autre étoile change → se rafraîchir
    FavoriButton.syncNotifier.addListener(_onSyncChanged);
  }

  void _onSyncChanged() {
    if (mounted) _chargerStatut();
  }

  @override
  void dispose() {
    FavoriButton.syncNotifier.removeListener(_onSyncChanged);
    _anim.dispose();
    super.dispose();
  }

  Future<void> _chargerStatut() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey) ?? '[]';
      final list = json.decode(raw) as List<dynamic>;
      final estFavori = list.any((e) =>
          (e as Map)['numR'] == widget.numR && e['numC'] == widget.numC);
      if (mounted) setState(() { _isFavori = estFavori; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleFavori() async {
    if (_loading) return;
    _anim.forward().then((_) => _anim.reverse());

    if (!_isFavori) {
      // Ajouter → montrer la belle bottom sheet
      _showFavoriSheet();
    } else {
      // Retirer directement
      setState(() => _isFavori = false);
      await _retirerFavori();
      // ★ Notifier toutes les autres étoiles de la même course
      FavoriButton.syncNotifier.value++;
    }
  }

  Future<void> _retirerFavori() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey) ?? '[]';
      final list = json.decode(raw) as List<dynamic>;
      list.removeWhere((e) =>
          (e as Map)['numR'] == widget.numR && e['numC'] == widget.numC);
      await prefs.setString(_prefsKey, json.encode(list));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Retiré des favoris'),
          backgroundColor: const Color(0xFF1A1A2E),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    } catch (_) {
      if (mounted) setState(() => _isFavori = true);
    }
  }

  void _showFavoriSheet() {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: _FavoriConfirmSheet(
        numR: widget.numR,
        numC: widget.numC,
        nomCourse: widget.nomCourse,
        hippodrome: widget.hippodrome,
        heure: widget.heure,
        distance: widget.distance,
        prix: widget.prix,
        scoreIA: widget.scoreIA,
        onConfirm: () async {
          // ★ Fix double tap : écrire AVANT de notifier
          await AlertService.instance.ajouterFavoriPourWorker(
            numR: widget.numR, numC: widget.numC,
            nomCourse: widget.nomCourse, hippodrome: widget.hippodrome,
            scoreIA: widget.scoreIA,
          );
          setState(() => _isFavori = true);
          FavoriButton.syncNotifier.value++;
        },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return SizedBox(
        width: widget.size + 8, height: widget.size + 8,
        child: const Center(child: SizedBox(width: 14, height: 14,
            child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white30))),
      );
    }
    return GestureDetector(
      onTap: _toggleFavori,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ScaleTransition(
              scale: _scaleAnim,
              child: Icon(
                _isFavori ? Icons.star_rounded : Icons.star_outline_rounded,
                color: _isFavori ? const Color(0xFFFFD700) : Colors.white38,
                size: widget.size,
              ),
            ),
            if (widget.showLabel) ...[
              const SizedBox(height: 2),
              Text(_isFavori ? 'Favori' : '  ',
                style: TextStyle(
                  color: _isFavori ? const Color(0xFFFFD700) : Colors.transparent,
                  fontSize: 9, fontWeight: FontWeight.bold)),
            ],
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _FavoriConfirmSheet — Bottom sheet dorée de confirmation
// ══════════════════════════════════════════════════════════════════════════════
class _FavoriConfirmSheet extends StatelessWidget {
  final int numR, numC;
  final String nomCourse, hippodrome, heure, distance, prix;
  final double scoreIA;
  final VoidCallback onConfirm;

  const _FavoriConfirmSheet({
    required this.numR, required this.numC,
    required this.nomCourse, required this.hippodrome,
    required this.heure, required this.distance, required this.prix,
    required this.scoreIA, required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0D1B2A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Poignée
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2)),
          ),

          // En-tête doré
          Container(
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFFFFD700).withValues(alpha: 0.18),
                  const Color(0xFFFFA000).withValues(alpha: 0.08),
                ],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFD700), Color(0xFFFFA000)]),
                    boxShadow: [BoxShadow(
                      color: const Color(0xFFFFD700).withValues(alpha: 0.35),
                      blurRadius: 10)],
                  ),
                  child: const Center(child: Text('⭐', style: TextStyle(fontSize: 22))),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(nomCourse,
                        style: const TextStyle(
                          color: Color(0xFFFFD700), fontSize: 16,
                          fontWeight: FontWeight.bold),
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Text(hippodrome,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6), fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Infos course
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _infoChip(Icons.access_time_rounded, heure.isNotEmpty ? heure : '--:--', const Color(0xFF4CAF7D)),
                if (distance.isNotEmpty)
                  _infoChip(Icons.straighten_rounded, distance, const Color(0xFF80DEEA)),
                if (prix.isNotEmpty)
                  _infoChip(Icons.monetization_on_outlined, '$prix€', const Color(0xFFFFB74D)),
                if (scoreIA > 0)
                  _infoChip(Icons.psychology_rounded, '${scoreIA.round()}/100', const Color(0xFFCE93D8)),
              ],
            ),
          ),

          // Message info
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.notifications_active_rounded,
                    color: Color(0xFFFFD700), size: 18),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Vous recevrez une alerte 10 minutes avant le départ et dès que les cotes PMU seront disponibles.',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Boutons
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white24),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Annuler',
                        style: TextStyle(color: Colors.white54, fontSize: 15)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      onConfirm();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFD700),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 4,
                      shadowColor: const Color(0xFFFFD700).withValues(alpha: 0.4),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.star_rounded, size: 18),
                        SizedBox(width: 8),
                        Text('Ajouter aux favoris',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
