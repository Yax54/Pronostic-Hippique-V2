import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import '../../widgets/photo_crop_screen.dart';
import '../../providers/pmu_provider.dart';
import '../../services/alert_service.dart' show AlertService;
import '../../services/backup_service.dart';
import '../../services/data_refresh_service.dart';
import '../../services/ia_memory_service.dart';
import '../../services/ia_personality_service.dart'; // ★ v9.85
import '../../services/ia_badges_service.dart';       // ★ v9.85
import '../../services/ia_user_prefs_service.dart';   // ★ v9.85
import '../../utils/format_euros.dart';
import '../../screens/widget_setup_screen.dart';


// Onglet Profil/Paramètres du ProfileScreen

class ProfileProfilTab extends StatefulWidget {
  final PmuProvider provider;
  const ProfileProfilTab({required this.provider});

  @override
  State<ProfileProfilTab> createState() => ProfileProfilTabState();
}

class ProfileProfilTabState extends State<ProfileProfilTab> {
  static const _keyNom       = 'profil_nom';
  static const _keyPhotoPath = 'profil_photo_path';

  String  _nomProfil  = 'Parieur Expert';
  String? _photoPath;

  // ★ v9.94 : listeners temps réel pour niveau/badges/stats IA
  void _onIaChange() { if (mounted) setState(() {}); }

  @override
  void initState() {
    super.initState();
    _chargerProfil();
    // Écouter les changements IA pour mise à jour immédiate du profil
    IaPersonalityService.instance.addListener(_onIaChange);
    IaBadgesService.instance.addListener(_onIaChange);
    IaMemoryService.instance.addListener(_onIaChange);
  }

  @override
  void dispose() {
    IaPersonalityService.instance.removeListener(_onIaChange);
    IaBadgesService.instance.removeListener(_onIaChange);
    IaMemoryService.instance.removeListener(_onIaChange);
    super.dispose();
  }

  Future<void> _chargerProfil() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _nomProfil = prefs.getString(_keyNom) ?? 'Parieur Expert';
      _photoPath = prefs.getString(_keyPhotoPath);
    });
  }

  Future<void> _sauvegarderNom(String nom) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyNom, nom);
    setState(() => _nomProfil = nom);
  }

  Future<void> _sauvegarderPhoto(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPhotoPath, path);
    setState(() => _photoPath = path);
  }

  // ── ★ v9.85 : Section Identité IA ────────────────────────────────────────
  Widget _buildSectionIa() {
    final ia      = IaPersonalityService.instance;
    final niveau  = ia.niveau;
    final forme   = ia.forme;
    final stats   = IaMemoryService.instance.calculerStats();
    // Sync stats dans le service
    ia.mettreAJourStats(
      coursesAvecResultat: stats.coursesAvecResultat,
      tauxReussite:        stats.tauxFavoriGagnant,
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A1A3A), Color(0xFF0D1B2A)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF7C4DFF).withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── En-tête ──────────────────────────────────────────────────────
          Row(
            children: [
              const Icon(Icons.psychology, color: Color(0xFF7C4DFF), size: 20),
              const SizedBox(width: 8),
              const Text('Mon IA',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF7C4DFF).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('${niveau.emoji} ${niveau.label}',
                    style: const TextStyle(color: Color(0xFF7C4DFF), fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // ── Avatar + Prénom + Âge ─────────────────────────────────────────
          Row(
            children: [
              // Sélecteur d'avatar
              GestureDetector(
                onTap: _choisirAvatar,
                child: Container(
                  width: 56, height: 56,
                  decoration: BoxDecoration(
                    color: const Color(0xFF7C4DFF).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF7C4DFF).withValues(alpha: 0.5), width: 2),
                  ),
                  child: Stack(
                    children: [
                      Center(child: Text(ia.avatarEmoji, style: const TextStyle(fontSize: 26))),
                      Positioned(
                        right: 0, bottom: 0,
                        child: Container(
                          width: 18, height: 18,
                          decoration: const BoxDecoration(
                            color: Color(0xFF7C4DFF), shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.edit, color: Colors.white, size: 11),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Prénom modifiable
                    GestureDetector(
                      onTap: _editerPrenomIA,
                      child: Row(
                        children: [
                          Text(ia.prenom,
                              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(width: 6),
                          const Icon(Icons.edit, color: Colors.white38, size: 14),
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text('Âge : ${ia.ageLabel}',
                        style: const TextStyle(color: Colors.white54, fontSize: 13)),
                    Row(
                      children: [
                        Text(forme.emoji, style: const TextStyle(fontSize: 13)),
                        const SizedBox(width: 4),
                        Text(forme.label,
                            style: const TextStyle(color: Colors.white54, fontSize: 12)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // ── Barre de progression vers le niveau suivant ───────────────────
          if (niveau != IaNiveau.legende) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Progression vers ${niveau.coursesProchain < 999 ? IaNiveau.values[niveau.index + 1].label : "Légende"}',
                    style: const TextStyle(color: Colors.white54, fontSize: 12)),
                Text('${ia.coursesRestantesProchainNiveau} courses restantes',
                    style: const TextStyle(color: Color(0xFF7C4DFF), fontSize: 12)),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: ia.progressionNiveau,
                backgroundColor: Colors.white12,
                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF7C4DFF)),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 4),
            Text(niveau.description,
                style: const TextStyle(color: Colors.white38, fontSize: 11, fontStyle: FontStyle.italic)),
            const SizedBox(height: 12),
          ],

          // ── Bulle activée/désactivée ─────────────────────────────────────
          Row(
            children: [
              const Icon(Icons.chat_bubble_outline, color: Colors.white38, size: 16),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Messages de l\'IA',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
              ),
              Switch(
                value: ia.bulleActive,
                onChanged: (v) async {
                  await ia.setBulleActive(v);
                  setState(() {});
                },
                activeColor: const Color(0xFF7C4DFF),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _editerPrenomIA() {
    final ia   = IaPersonalityService.instance;
    final ctrl = TextEditingController(text: ia.prenom);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0A1628),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Prénom de l\'IA',
            style: TextStyle(color: Colors.white, fontSize: 17)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 20,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Ex: Aria, Max, Nova...',
            hintStyle: TextStyle(color: Colors.white38),
            filled: true,
            fillColor: Color(0xFF111F30),
            border: OutlineInputBorder(),
            counterStyle: TextStyle(color: Colors.white38),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler', style: TextStyle(color: Colors.white38)),
          ),
          TextButton(
            onPressed: () async {
              await ia.setPrenom(ctrl.text);
              if (mounted) setState(() {});
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Valider', style: TextStyle(color: Color(0xFF7C4DFF))),
          ),
        ],
      ),
    );
  }

  void _choisirAvatar() {
    final ia = IaPersonalityService.instance;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0D1B2A),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Choisir l\'avatar de votre IA',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: IaAvatar.disponibles.map((avatar) {
                final selected = ia.avatarId == avatar.id;
                return GestureDetector(
                  onTap: () async {
                    await ia.setAvatar(avatar.id);
                    if (mounted) setState(() {});
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: Container(
                    width: 64, height: 64,
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xFF7C4DFF).withValues(alpha: 0.2)
                          : const Color(0xFF111F30),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected ? const Color(0xFF7C4DFF) : Colors.white12,
                        width: selected ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(avatar.emoji, style: const TextStyle(fontSize: 24)),
                        Text(avatar.nom,
                            style: const TextStyle(color: Colors.white54, fontSize: 9)),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ── ★ v10.25 : Section Précision IA temps réel ───────────────────────────
  Widget _buildSectionPrecisionIA() {
    final mem    = IaMemoryService.instance;
    final pronos = mem.pronosticsAvecResultat;

    if (pronos.isEmpty) return const SizedBox();

    // ── Totaux globaux ────────────────────────────────────────────────────
    // Seuls les pronostics avec type connu sont comptés (dénominateur aligné
    // sur le numérateur — évite le biais sur les types inconnus/vides). ★ a3
    int totalCourses = 0;
    int totalBons    = 0;
    final Map<String, int> nbParType   = {};
    final Map<String, int> bonsParType = {};

    for (final p in pronos) {
      final t = p.typePariConseille ?? '';
      if (t.isEmpty || t == 'Inconnu' || t == 'À surveiller') continue;
      totalCourses++;
      nbParType[t]   = (nbParType[t]   ?? 0) + 1;
      if (mem.estBonConseil(p, t)) {
        bonsParType[t] = (bonsParType[t] ?? 0) + 1;
        totalBons++;
      }
    }

    if (totalCourses == 0) return const SizedBox();

    final tauxGlobal = totalBons / totalCourses;
    final Color tauxColor = tauxGlobal >= 0.40
        ? const Color(0xFF4CAF7D)
        : tauxGlobal >= 0.25
            ? const Color(0xFFFFB74D)
            : tauxGlobal >= 0.10
                ? const Color(0xFFFF7043)
                : const Color(0xFFEF5350);

    // Mois courant
    final now      = DateTime.now();
    final pronosMois = pronos.where((p) =>
        p.datePronostic.year  == now.year &&
        p.datePronostic.month == now.month).toList();
    int bonsMois = 0;
    for (final p in pronosMois) {
      final t = p.typePariConseille ?? '';
      if (t.isNotEmpty && mem.estBonConseil(p, t)) bonsMois++;
    }
    final tauxMois = pronosMois.isNotEmpty
        ? bonsMois / pronosMois.length : 0.0;

    // Aujourd'hui (depuis getter temps réel v9.99)
    final aujodhui  = mem.precisionAujourdhuiDepuisPronostics;
    int nbAuj       = 0, bonsAuj = 0;
    for (final v in aujodhui.values) {
      nbAuj   += v['nb']   ?? 0;
      bonsAuj += v['bons'] ?? 0;
    }

    // Types triés par volume
    final typesTries = nbParType.keys.toList()
      ..sort((a, b) => (nbParType[b] ?? 0).compareTo(nbParType[a] ?? 0));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F2A1A), Color(0xFF0D1B2A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF4CAF7D).withValues(alpha: 0.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── En-tête ────────────────────────────────────────────────────────
        Row(children: [
          const Icon(Icons.track_changes, color: Color(0xFF4CAF7D), size: 20),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('Précision IA',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              color: tauxColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: tauxColor.withValues(alpha: 0.4)),
            ),
            child: Text(
              '${(tauxGlobal * 100).toStringAsFixed(0)}% global',
              style: TextStyle(color: tauxColor, fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
        ]),
        const SizedBox(height: 14),

        // ── 3 compteurs : Aujourd'hui / Ce mois / Total ───────────────────
        Row(children: [
          _iaStatTile(
            label:     "Aujourd'hui",
            value:     nbAuj == 0 ? '—' : '$bonsAuj/$nbAuj',
            sub:       nbAuj == 0
                ? 'Aucun résultat'
                : '${(bonsAuj / nbAuj * 100).toStringAsFixed(0)}% réussite',
            color:     nbAuj == 0
                ? Colors.white24
                : (bonsAuj / nbAuj >= 0.40
                    ? const Color(0xFF4CAF7D)
                    : const Color(0xFFFFB74D)),
            icon:      Icons.today,
          ),
          _iaDivider(),
          _iaStatTile(
            label:     'Ce mois',
            value:     pronosMois.isEmpty ? '—' : '$bonsMois/${pronosMois.length}',
            sub:       pronosMois.isEmpty
                ? 'Aucune course'
                : '${(tauxMois * 100).toStringAsFixed(0)}% réussite',
            color:     pronosMois.isEmpty
                ? Colors.white24
                : (tauxMois >= 0.40
                    ? const Color(0xFF4CAF7D)
                    : tauxMois >= 0.25
                        ? const Color(0xFFFFB74D)
                        : const Color(0xFFFF7043)),
            icon:      Icons.calendar_month,
          ),
          _iaDivider(),
          _iaStatTile(
            label:     'Total',
            value:     '$totalBons/$totalCourses',
            sub:       '${(tauxGlobal * 100).toStringAsFixed(0)}% réussite',
            color:     tauxColor,
            icon:      Icons.history,
          ),
        ]),
        const SizedBox(height: 14),

        // ── Barre globale ─────────────────────────────────────────────────
        Row(children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: tauxGlobal.clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: Colors.white.withValues(alpha: 0.07),
                valueColor: AlwaysStoppedAnimation<Color>(tauxColor),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text('$totalBons bons conseils',
            style: TextStyle(color: tauxColor, fontSize: 11, fontWeight: FontWeight.bold)),
        ]),

        // ── Détail par type de pari ───────────────────────────────────────
        if (typesTries.isNotEmpty) ...[
          const SizedBox(height: 14),
          const Divider(color: Colors.white12, height: 1),
          const SizedBox(height: 12),
          const Text('Par type de pari',
            style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          ...typesTries.take(5).map((t) {
            final nb   = nbParType[t]   ?? 0;
            final bons = bonsParType[t] ?? 0;
            final tx   = nb > 0 ? bons / nb : 0.0;
            final col  = tx >= 0.40
                ? const Color(0xFF4CAF7D)
                : tx >= 0.25
                    ? const Color(0xFFFFB74D)
                    : tx >= 0.10
                        ? const Color(0xFFFF7043)
                        : const Color(0xFFEF5350);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Expanded(
                  flex: 3,
                  child: Text(t,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 4,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: tx.clamp(0.0, 1.0),
                      minHeight: 5,
                      backgroundColor: Colors.white.withValues(alpha: 0.07),
                      valueColor: AlwaysStoppedAnimation<Color>(col),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 52,
                  child: Text('$bons/$nb',
                    textAlign: TextAlign.right,
                    style: TextStyle(color: col, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ]),
            );
          }),
        ],

        // ── Note de mise à jour temps réel ───────────────────────────────
        const SizedBox(height: 8),
        Row(children: [
          Container(width: 6, height: 6,
            decoration: BoxDecoration(
              color: const Color(0xFF4CAF7D),
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(
                color: const Color(0xFF4CAF7D).withValues(alpha: 0.6),
                blurRadius: 4,
              )],
            ),
          ),
          const SizedBox(width: 6),
          const Text('Mis à jour en temps réel',
            style: TextStyle(color: Colors.white24, fontSize: 10)),
        ]),
      ]),
    );
  }

  // ── Helpers section Précision IA ──────────────────────────────────────────
  Widget _iaStatTile({
    required String  label,
    required String  value,
    required String  sub,
    required Color   color,
    required IconData icon,
  }) {
    return Expanded(
      child: Column(children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(height: 4),
        Text(value,
          style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(label,
          style: const TextStyle(color: Colors.white54, fontSize: 10)),
        Text(sub,
          style: TextStyle(color: color.withValues(alpha: 0.7), fontSize: 10),
          textAlign: TextAlign.center),
      ]),
    );
  }

  Widget _iaDivider() => Container(
    width: 1, height: 50,
    margin: const EdgeInsets.symmetric(horizontal: 4),
    color: Colors.white.withValues(alpha: 0.07),
  );

  // ── ★ v9.85 : Section Badges ─────────────────────────────────────────────
  Widget _buildSectionBadges() {
    final badges       = IaBadgesService.instance;
    final debloques    = badges.badgesDebloques;
    final total        = IaBadgesCatalogue.tous.length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111F30),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🏆', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              const Text('Badges',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              const Spacer(),
              Text('${debloques.length}/$total',
                  style: const TextStyle(color: Colors.white38, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 12),
          if (debloques.isEmpty)
            const Text('Aucun badge débloqué encore — lance une analyse pour commencer !',
                style: TextStyle(color: Colors.white38, fontSize: 13, fontStyle: FontStyle.italic))
          else ...[
            // Derniers badges débloqués (max 6)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: debloques.take(6).map((b) => Tooltip(
                message: '${b.titre}\n${b.description}',
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFD700).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(b.emoji, style: const TextStyle(fontSize: 14)),
                      const SizedBox(width: 4),
                      Text(b.titre,
                          style: const TextStyle(color: Colors.white70, fontSize: 11)),
                    ],
                  ),
                ),
              )).toList(),
            ),
            if (debloques.length < total) ...[
              const SizedBox(height: 8),
              // Prochain badge à débloquer
              () {
                final prochain = badges.badgesVerrouilles.firstOrNull;
                if (prochain == null) return const SizedBox();
                return Row(
                  children: [
                    const Icon(Icons.lock_outline, color: Colors.white24, size: 14),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text('Prochain : ${prochain.emoji} ${prochain.titre} — ${prochain.description}',
                          style: const TextStyle(color: Colors.white24, fontSize: 11),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ],
                );
              }(),
            ],
          ],
        ],
      ),
    );
  }

  // ── ★ v9.85 : Section Préférences détectées ──────────────────────────────
  Widget _buildSectionPreferences() {
    final prefs = IaUserPrefsService.instance.prefs;
    if (prefs.frequenceParType.isEmpty) return const SizedBox();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111F30),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Text('🎯', style: TextStyle(fontSize: 18)),
              SizedBox(width: 8),
              Text('Mes habitudes détectées',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 4),
          const Text('Analysées depuis votre historique de paris',
              style: TextStyle(color: Colors.white38, fontSize: 11)),
          const SizedBox(height: 12),
          if (prefs.typeFavori.isNotEmpty)
            _prefRow('🎫', 'Pari favori', prefs.typeFavori),
          if (prefs.hippodromeFavori.isNotEmpty)
            _prefRow('📍', 'Hippodrome favori', prefs.hippodromeFavori),
          if (prefs.miseHabituelle > 0)
            _prefRow('💰', 'Mise habituelle', '${prefs.miseHabituelle.toStringAsFixed(0)} €'),
          if (prefs.miseMoyenne > 0)
            _prefRow('📊', 'Mise moyenne', '${prefs.miseMoyenne.toStringAsFixed(1)} €'),
        ],
      ),
    );
  }

  Widget _prefRow(String emoji, String label, String valeur) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 10),
          Expanded(child: Text(label,
              style: const TextStyle(color: Colors.white54, fontSize: 13))),
          Text(valeur,
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  void _editerNom() {
    final ctrl = TextEditingController(text: _nomProfil);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0A1628),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Modifier votre nom',
            style: TextStyle(color: Colors.white, fontSize: 17)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 30,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Votre pseudo...',
            hintStyle: const TextStyle(color: Colors.white38),
            filled: true,
            fillColor: const Color(0xFF1A2A3A),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF4CAF7D)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF4CAF7D), width: 2),
            ),
            counterStyle: const TextStyle(color: Colors.white38),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1565C0)),
            onPressed: () {
              final nom = ctrl.text.trim();
              if (nom.isNotEmpty) _sauvegarderNom(nom);
              Navigator.pop(ctx);
            },
            child: const Text('Enregistrer', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _choisirPhoto() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0A1628),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const Text('Choisir une photo',
                style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            ProfilePhotoOption(
              icon: Icons.photo_camera,
              label: 'Prendre une photo',
              onTap: () async {
                Navigator.pop(ctx);
                await _prendrephoto(ImageSource.camera);
              },
            ),
            const SizedBox(height: 12),
            ProfilePhotoOption(
              icon: Icons.photo_library,
              label: 'Choisir dans la galerie',
              onTap: () async {
                Navigator.pop(ctx);
                await _prendrephoto(ImageSource.gallery);
              },
            ),
            if (_photoPath != null) ...[
              const SizedBox(height: 12),
              ProfilePhotoOption(
                icon: Icons.delete_outline,
                label: 'Supprimer la photo',
                color: const Color(0xFFEF5350),
                onTap: () async {
                  Navigator.pop(ctx);
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.remove(_keyPhotoPath);
                  setState(() => _photoPath = null);
                },
              ),
            ],
          ]),
        ),
      ),
    );
  }

  Future<void> _prendrephoto(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 90,
      );
      if (picked == null) return;

      // Ouvrir l'écran de recadrage/centrage
      if (!mounted) return;
      final croppedPath = await PhotoCropScreen.show(context, picked.path);

      // Si l'utilisateur a confirmé le recadrage
      if (croppedPath != null) {
        await _sauvegarderPhoto(croppedPath);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // ⚠️ CRITIQUE : context.watch() pour que le profil se rafraîchisse
    // automatiquement quand les paris changent (ajout, validation, restauration)
    final provider = context.watch<PmuProvider>();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(children: [
        // ── Avatar + nom ──────────────────────────────────────────────────
        Center(
          child: Column(children: [
            // Photo cliquable — taille augmentée 120px
            GestureDetector(
              onTap: _choisirPhoto,
              child: Stack(alignment: Alignment.bottomRight, children: [
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [Color(0xFF1565C0), Color(0xFF0D1F3C)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF4CAF7D), width: 3.5),
                  ),
                  child: ClipOval(
                    child: _photoPath != null && File(_photoPath!).existsSync()
                        ? Image.file(
                            File(_photoPath!),
                            fit: BoxFit.cover,
                            width: 120, height: 120,
                          )
                        : const Icon(Icons.person, color: Colors.white, size: 62),
                  ),
                ),
                // Bouton caméra superposé
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4CAF7D),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF0A1628), width: 2.5),
                  ),
                  child: const Icon(Icons.camera_alt, color: Colors.white, size: 17),
                ),
              ]),
            ),
            const SizedBox(height: 14),
            // Nom cliquable
            GestureDetector(
              onTap: _editerNom,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(
                  _nomProfil,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.edit, color: Color(0xFF4CAF7D), size: 18),
              ]),
            ),
            const SizedBox(height: 5),
            const Text('Pronostic Hippique',
                style: TextStyle(color: Colors.white54, fontSize: 15, letterSpacing: 0.3)),
            const SizedBox(height: 12),
            ProfileLevelBadge(successRate: provider.successRate),
          ]),
        ),
        const SizedBox(height: 22),

        // ── Stats rapides ─────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [Color(0xFF0D2A4A), Color(0xFF071525)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF1E3A5C), width: 1.2),
          ),
          child: Column(children: [
            const Text('Performances globales',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.3)),
            const SizedBox(height: 16),
            // ── Ligne 1 : Paris total / Gagnés / Perdus / En attente ────────
            Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              ProfileStatBox(label: 'Paris', value: '${provider.totalPredictions}', size: 'large'),
              ProfileStatBox(
                label: 'Gagnés',
                value: '${provider.correctPredictions}',
                color: provider.correctPredictions > 0
                    ? const Color(0xFF4CAF7D) : Colors.white,
                size: 'large',
              ),
              ProfileStatBox(
                label: 'Perdus',
                value: '${provider.lostPredictions}',
                color: provider.lostPredictions > 0
                    ? const Color(0xFFEF5350) : Colors.white,
                size: 'large',
              ),
              ProfileStatBox(
                label: 'Attente',
                value: '${provider.pendingPredictions}',
                color: provider.pendingPredictions > 0
                    ? const Color(0xFFFFB74D) : Colors.white,
                size: 'large',
              ),
            ]),
            const SizedBox(height: 14),
            const Divider(color: Color(0xFF1E3A5C), height: 1),
            const SizedBox(height: 14),
            // ── Ligne 2 : Taux / Gains nets / Total misé ───────────────────
            Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              ProfileStatBox(
                label: 'Taux réussite',
                value: '${provider.successRate.toStringAsFixed(0)}%',
                color: provider.successRate >= 50
                    ? const Color(0xFF4CAF7D)
                    : provider.successRate >= 30
                        ? const Color(0xFFFFB74D)
                        : Colors.white,
                size: 'large',
              ),
              ProfileStatBox(
                label: 'Gains nets',
                value: '${provider.totalGainsNet >= 0 ? '+' : ''}${fmtEuros(provider.totalGainsNet)}€',
                color: provider.totalGainsNet >= 0
                    ? const Color(0xFF69F0AE) : const Color(0xFFEF5350),
                size: 'large',
              ),
              ProfileStatBox(
                label: 'Total misé',
                value: '${provider.totalMise.toStringAsFixed(0)}€',
                size: 'large',
              ),
            ]),
          ]),
        ),
        const SizedBox(height: 22),

        // ── ★ v9.85 : Section Identité de l'IA ──────────────────────────
        _buildSectionIa(),
        const SizedBox(height: 16),

        // ── ★ v10.25 : Précision IA temps réel ───────────────────────────
        _buildSectionPrecisionIA(),
        const SizedBox(height: 16),

        // ── ★ v9.85 : Section Badges ─────────────────────────────────────
        _buildSectionBadges(),
        const SizedBox(height: 16),

        // ── ★ v9.85 : Section Préférences détectées ──────────────────────
        _buildSectionPreferences(),
        const SizedBox(height: 22),

        // ── Paramètres ────────────────────────────────────────────────────
        const Align(
          alignment: Alignment.centerLeft,
          child: Text('Paramètres',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 0.3)),
        ),
        const SizedBox(height: 12),
        ProfileSettingItem(
          icon: Icons.person_outline,
          label: 'Modifier mon profil',
          subtitle: 'Nom affiché : $_nomProfil',
          iconColor: const Color(0xFF4CAF7D),
          onTap: _editerNom,
        ),
        ProfileSettingItem(
          icon: Icons.photo_camera_outlined,
          label: 'Photo de profil',
          subtitle: _photoPath != null ? 'Photo personnalisée ✓' : 'Aucune photo — appuyer pour en choisir une',
          iconColor: const Color(0xFF42A5F5),
          onTap: _choisirPhoto,
        ),
        ProfileSettingItem(
          icon: Icons.widgets,
          label: '📱 Widget écran d\'accueil',
          subtitle: 'Ajouter le widget Pronostic Hippique sur votre téléphone',
          iconColor: const Color(0xFFFFD700),
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const WidgetSetupScreen())),
        ),
        ProfileSettingItem(
          icon: Icons.refresh,
          label: 'Actualiser les données',
          subtitle: 'Courses + paris • Dernier: ${context.read<DataRefreshService>().lastRefreshLabel}',
          onTap: () async {
            await context.read<DataRefreshService>().refresh();
            await provider.reloadPredictions();
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✅ Données actualisées'),
                backgroundColor: Color(0xFF1565C0),
                duration: Duration(seconds: 2),
              ),
            );
          },
        ),
        ProfileSettingItem(
          icon: Icons.delete_sweep,
          label: 'Effacer tous les pronostics',
          subtitle: 'Supprimer tout l\'historique de paris',
          iconColor: const Color(0xFFEF5350),
          onTap: () => _confirmerEffacerTout(context, provider),
        ),
        // ★ v10.50 : Purge données stale étoiles premium
        ProfileSettingItem(
          icon: Icons.star_border,
          label: 'Réinitialiser étoiles premium',
          subtitle: 'Supprime uniquement l\'historique et le pronostic premium du jour',
          iconColor: const Color(0xFFFFB74D),
          onTap: () => _confirmerReinitialisationPremium(context),
        ),
        ProfileSettingItem(
          icon: Icons.info_outline,
          label: 'À propos',
          subtitle: 'Pronostic Hippique — PMU + IA Pronostics',
          onTap: () {},
        ),

        const SizedBox(height: 24),

        // ── Sauvegarde & Restauration ─────────────────────────────────────
        const Align(
          alignment: Alignment.centerLeft,
          child: Text('Sauvegarde & Restauration',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 0.3)),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Conservez vos données IA, paris et profil pour les restaurer sur un autre téléphone.',
            style: TextStyle(color: Colors.white38, fontSize: 13),
          ),
        ),
        const SizedBox(height: 12),
        ProfileBackupSection(provider: provider),

        const SizedBox(height: 22),
        // Disclaimer
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFB74D).withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFFB74D).withValues(alpha: 0.3)),
          ),
          child: Row(children: [
            const Icon(Icons.warning_amber, color: Color(0xFFFFB74D), size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Les pronostics IA sont informatifs uniquement. Les paris hippiques comportent des risques. Jouez de manière responsable. 18+.',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 13),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 20),
      ]),
    );
  }

  // ★ v10.50 — Purge ciblée : uniquement ia_premium_historique_v1 + ia_premium_du_jour_v1
  // Ne touche PAS : mémoire IA, poids, apprentissage, pronostics.
  void _confirmerReinitialisationPremium(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0A1628),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.star_border, color: Color(0xFFFFB74D)),
          SizedBox(width: 8),
          Text('Réinitialiser étoiles ?',
              style: TextStyle(color: Colors.white, fontSize: 17)),
        ]),
        content: const Text(
          'Ceci supprime uniquement :\n'
          '• Historique premium (étoiles calendrier)\n'
          '• Pronostic premium du jour\n\n'
          'Les pronostics IA, la mémoire, les poids et l\'apprentissage ne sont PAS modifiés.\n\n'
          'Action irréversible.',
          style: TextStyle(color: Colors.white60, fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler',
                style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _executerReinitialisationPremium();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFB74D),
            ),
            child: const Text('Réinitialiser',
                style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _executerReinitialisationPremium() async {
    const keyHistorique = 'ia_premium_historique_v1';
    const keyDuJour     = 'ia_premium_du_jour_v1';
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(keyHistorique);
    await prefs.remove(keyDuJour);
    // Forcer le rechargement des données premium en mémoire
    await IaMemoryService.instance.rechargerDonneesPremium();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ Étoiles premium réinitialisées'),
        backgroundColor: Color(0xFFFFB74D),
        duration: Duration(seconds: 3),
      ),
    );
  }

  void _confirmerEffacerTout(BuildContext context, PmuProvider provider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0A1628),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.warning_amber, color: Color(0xFFFFB74D)),
          SizedBox(width: 8),
          Text('Effacer tout ?', style: TextStyle(color: Colors.white, fontSize: 18)),
        ]),
        content: const Text(
          'Voulez-vous supprimer tous vos pronostics enregistrés ?\nCette action est irréversible.',
          style: TextStyle(color: Colors.white60, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              provider.clearAllPredictions();
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Tous les pronostics supprimés'),
                  backgroundColor: Color(0xFF1565C0),
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF5350)),
            child: const Text('Effacer tout', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}


// ── Widget helper : option photo ──────────────────────────────────────────────
class ProfilePhotoOption extends StatelessWidget {
  final IconData icon;
  final String   label;
  final VoidCallback onTap;
  final Color    color;
  const ProfilePhotoOption({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = const Color(0xFF4CAF7D),
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 14),
          Text(label, style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w500)),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Section Sauvegarde & Restauration
// ══════════════════════════════════════════════════════════════════════════════
class ProfileBackupSection extends StatefulWidget {
  final PmuProvider provider;
  const ProfileBackupSection({required this.provider});
  @override
  State<ProfileBackupSection> createState() => ProfileBackupSectionState();
}

class ProfileBackupSectionState extends State<ProfileBackupSection> {
  bool        _chargement = false;
  BackupInfo? _info;
  String?     _gmail;

  @override
  void initState() {
    super.initState();
    _chargerInfos();
  }

  Future<void> _chargerInfos() async {
    final info  = await BackupService.instance.obtenirInfos();
    final gmail = await BackupService.instance.lireGmail();
    if (mounted) setState(() { _info = info; _gmail = gmail; });
  }

  // ── Exporter (partage) ─────────────────────────────────────────────────────
  Future<void> _exporter() async {
    setState(() => _chargement = true);
    final result = await BackupService.instance.exporterDonnees();
    setState(() => _chargement = false);
    if (!mounted) return;
    if (!result.succes) {
      _snack('❌ Erreur export : ${result.erreur}', Colors.red);
      return;
    }
    // Partage via menu natif Android (Gmail / Drive / WhatsApp…)
    await BackupService.instance.partagerBackup();
    _snack('✅ Fichier ${result.fileName} prêt à être partagé !', const Color(0xFF4CAF7D));
  }

  // ── Télécharger directement sur le téléphone ────────────────────────────────
  Future<void> _telecharger() async {
    setState(() => _chargement = true);
    final result = await BackupService.instance.telechargerSurTelephone();
    setState(() => _chargement = false);
    if (!mounted) return;
    if (!result.succes) {
      _snack('❌ Erreur téléchargement : ${result.erreur}', Colors.red);
      return;
    }
    _snack(
      '📥 Sauvegardé dans Téléchargements : ${result.fileName}',
      const Color(0xFF42A5F5),
    );
  }

  // ── Google Drive ────────────────────────────────────────────────────────────
  Future<void> _sauvegarderDrive() async {
    setState(() => _chargement = true);
    final ok = await BackupService.instance.sauvegarderSurDrive();
    setState(() => _chargement = false);
    if (!mounted) return;
    if (!ok) _snack('❌ Impossible d\'ouvrir le partage', Colors.red);
  }

  // ── Importer ────────────────────────────────────────────────────────────────
  Future<void> _importer() async {
    // Avertissement avant import
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0A1628),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.warning_amber, color: Color(0xFFFFB74D), size: 24),
          SizedBox(width: 8),
          Text('Importer ?', style: TextStyle(color: Colors.white, fontSize: 17)),
        ]),
        content: const Text(
          '⚠️ Toutes vos données actuelles (IA, paris, profil) seront remplacées par celles du fichier sélectionné.\n\nCette action est irréversible.',
          style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler', style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFB74D)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continuer', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _chargement = true);
    final result = await BackupService.instance.importerDepuisFichier();
    setState(() => _chargement = false);

    // ── CRITIQUE : recharger le provider immédiatement après restauration ──
    // Sans ça, les paris restaurés ne s'affichent pas même si bien écrits en mémoire
    if (result.succes && mounted) {
      await widget.provider.reloadPredictions();
      // Recharger aussi la mémoire IA (poids appris, pronostics, journal)
      // sans ça les données IA restaurées restent en ancienne version en RAM
      await IaMemoryService.instance.recharger();
      // ★ Correction audit : recharger AlertService (config + TrackedCourses + alertes)
      // sans ça les données alertes/favoris restaurées restent en ancienne version en RAM
      await AlertService.instance.recharger();

      // ★ SYNC CRITIQUE : synchroniser les résultats TrackedCourse → UserPrediction
      // Sans ça, le Profil affiche tous les paris comme perdus après restauration backup
      try {
        final alertSvc = AlertService.instance;
        final tracked = alertSvc.trackedCourses.values.toList();
        for (final tc in tracked) {
          if (tc.isGagne == null) continue;
          // Trouver le UserPrediction correspondant
          final courseKey = 'R${tc.numReunion}C${tc.numCourse}';
          final matching = widget.provider.predictions.where((p) {
            final pk = 'R${p.numReunion}C${p.numCourse}';
            return pk == courseKey && p.isCorrect == null;
          }).toList();
          for (final pred in matching) {
            widget.provider.validatePrediction(
              pred.id,
              isCorrect: tc.isGagne!,
              montantMise: tc.miseEngagee,
            );
          }
        }
      } catch (e) {
        debugPrint('[Backup] Sync résultats erreur : \$e');
      }
    }
    await _chargerInfos();
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0A1628),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Icon(
            result.succes ? Icons.check_circle : Icons.error_outline,
            color: result.succes ? const Color(0xFF4CAF7D) : Colors.red,
            size: 26,
          ),
          const SizedBox(width: 10),
          Flexible(child: Text(
            result.succes ? 'Restauration réussie !' : 'Erreur',
            style: const TextStyle(color: Colors.white, fontSize: 17),
          )),
        ]),
        content: Text(
          result.succes
            ? '✅ ${result.nbClesRestaurees} éléments restaurés.\n\n'
              '🏇 ${result.nbParis} paris récupérés.\n'
              '🧠 ${result.nbPronosticsIA} pronostics IA restaurés.\n'
              '🔔 ${result.nbAlertes} alertes restaurées.\n\n'
              '📅 Backup du : ${result.dateBackupLisible}\n\n'
              '✅ Vos données sont disponibles immédiatement.'
            : '❌ ${result.erreur}',
          style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: result.succes ? const Color(0xFF4CAF7D) : const Color(0xFF333333),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ── Gmail ───────────────────────────────────────────────────────────────────
  void _editerGmail() {
    final ctrl = TextEditingController(text: _gmail ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0A1628),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Votre adresse Gmail', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
            'Utilisée uniquement pour vous rappeler quel compte Google utiliser lors d\'une restauration.',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'exemple@gmail.com',
              hintStyle: const TextStyle(color: Colors.white30),
              filled: true,
              fillColor: const Color(0xFF1A3A5C),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF4CAF7D))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF4CAF7D), width: 2)),
            ),
          ),
        ]),
        actions: [
          if (_gmail != null)
            TextButton(
              onPressed: () async {
                await BackupService.instance.supprimerGmail();
                setState(() => _gmail = null);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Supprimer', style: TextStyle(color: Colors.red)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler', style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4CAF7D)),
            onPressed: () async {
              final g = ctrl.text.trim();
              if (g.isNotEmpty) {
                await BackupService.instance.sauvegarderGmail(g);
                setState(() => _gmail = g);
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Enregistrer', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color,
          duration: const Duration(seconds: 3)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // ── Carte info backup ───────────────────────────────────────────────────
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF0A1628),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF1A3A5C)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Ligne Gmail
          InkWell(
            onTap: _editerGmail,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                const Icon(Icons.email_outlined, color: Color(0xFF4CAF7D), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _gmail ?? 'Ajouter mon adresse Gmail →',
                    style: TextStyle(
                      color: _gmail != null ? Colors.white : const Color(0xFF4CAF7D),
                      fontSize: 13,
                      fontStyle: _gmail != null ? FontStyle.normal : FontStyle.italic,
                    ),
                  ),
                ),
                const Icon(Icons.edit, color: Color(0xFF4CAF7D), size: 14),
              ]),
            ),
          ),
          if (_info != null) ...[
            const Divider(color: Color(0xFF1A3A5C), height: 20),
            Row(children: [
              ProfileInfoChip(Icons.sports_score, '${_info!.nbPronostics}', 'Pronostics IA'),
              const SizedBox(width: 8),
              ProfileInfoChip(Icons.receipt_long, '${_info!.nbParis}', 'Paris'),
              const SizedBox(width: 8),
              ProfileInfoChip(Icons.storage, _info!.tailleLisible, 'Taille'),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              ProfileInfoChip(
                Icons.psychology,
                _info!.nbAjustements > 0 ? '${_info!.nbAjustements} màj' : 'Vierge',
                'IA apprise',
                couleur: _info!.iaApprise ? const Color(0xFF4CAF7D) : const Color(0xFF78909C),
              ),
              const SizedBox(width: 8),
              ProfileInfoChip(
                Icons.tune,
                _info!.nbTypesPrecision > 0 ? '${_info!.nbTypesPrecision} types' : '--',
                'Précision/type',
                couleur: _info!.nbTypesPrecision > 0 ? const Color(0xFF4CAF7D) : const Color(0xFF78909C),
              ),
              const SizedBox(width: 8),
              ProfileInfoChip(
                Icons.bar_chart,
                _info!.aSeuilsAdaptatifs ? 'Oui' : '--',
                'Seuils adapt.',
                couleur: _info!.aSeuilsAdaptatifs ? const Color(0xFF4CAF7D) : const Color(0xFF78909C),
              ),
            ]),
            if (_info!.poidsIndices != null) ...[
              const SizedBox(height: 6),
              Text(
                '🔬 PoidsIndices : ${_info!.poidsIndices!.resume}',
                style: const TextStyle(color: Color(0xFF78909C), fontSize: 11),
              ),
            ],
            if (_info!.poidsActuels.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                '⚖️ ${_info!.resumePoidsIA}',
                style: const TextStyle(color: Color(0xFF78909C), fontSize: 11),
              ),
            ],
          ],
        ]),
      ),

      // ── Bouton Télécharger sur le téléphone ────────────────────────────────
      ProfileBoutonBackup(
        emoji: '📥', label: 'Télécharger sur le téléphone',
        sousTitre: 'Enregistre le fichier JSON dans Téléchargements',
        couleur: const Color(0xFF42A5F5),
        enCharge: _chargement, onTap: _telecharger,
      ),
      const SizedBox(height: 10),

      // ── Bouton Exporter / Partager ──────────────────────────────────────────
      ProfileBoutonBackup(
        emoji: '📤', label: 'Partager mes données',
        sousTitre: 'Envoyer via Gmail, Drive, WhatsApp…',
        couleur: const Color(0xFF4CAF7D),
        enCharge: _chargement, onTap: _exporter,
      ),
      const SizedBox(height: 10),

      // ── Bouton Drive ────────────────────────────────────────────────────────
      ProfileBoutonBackup(
        emoji: '☁️', label: 'Envoyer vers Google Drive',
        sousTitre: 'Partage manuel → sélectionnez Drive dans le menu',
        couleur: const Color(0xFF7E57C2),
        enCharge: _chargement, onTap: _sauvegarderDrive,
      ),
      const SizedBox(height: 10),

      // ── Bouton Importer ─────────────────────────────────────────────────────
      ProfileBoutonBackup(
        emoji: '📥', label: 'Importer une sauvegarde',
        sousTitre: 'Sélectionne un fichier .json et restaure tout',
        couleur: const Color(0xFFFFB74D),
        enCharge: _chargement, onTap: _importer,
      ),
      const SizedBox(height: 12),

      // ── Note explicative ────────────────────────────────────────────────────
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF42A5F5).withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF42A5F5).withValues(alpha: 0.25)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.info_outline, color: Color(0xFF42A5F5), size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Sur nouveau téléphone : installez l\'app → Profil → '
              '"Importer une sauvegarde" → sélectionnez le fichier depuis Drive. '
              'Tout est restauré automatiquement.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11),
            ),
          ),
        ]),
      ),
    ]);
  }
}

// ── Widgets helpers backup ────────────────────────────────────────────────────

class ProfileBoutonBackup extends StatelessWidget {
  final String emoji, label, sousTitre;
  final Color  couleur;
  final bool   enCharge;
  final VoidCallback onTap;
  const ProfileBoutonBackup({
    required this.emoji, required this.label, required this.sousTitre,
    required this.couleur, required this.enCharge, required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enCharge ? null : onTap,
      borderRadius: BorderRadius.circular(13),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: couleur.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: couleur.withValues(alpha: 0.35)),
        ),
        child: Row(children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              color: couleur.withValues(alpha: 0.15), shape: BoxShape.circle),
            child: Center(child: Text(emoji, style: const TextStyle(fontSize: 20))),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(color: couleur, fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(sousTitre, style: const TextStyle(color: Colors.white38, fontSize: 12)),
          ])),
          if (enCharge)
            SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: couleur))
          else
            Icon(Icons.arrow_forward_ios, color: couleur, size: 14),
        ]),
      ),
    );
  }
}

class ProfileInfoChip extends StatelessWidget {
  final IconData icon;
  final String valeur, label;
  final Color? couleur;
  const ProfileInfoChip(this.icon, this.valeur, this.label, {this.couleur});
  @override
  Widget build(BuildContext context) {
    final iconColor = couleur ?? const Color(0xFF4CAF7D);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF1A3A5C).withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(children: [
          Icon(icon, color: iconColor, size: 16),
          const SizedBox(height: 4),
          Text(valeur, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10), textAlign: TextAlign.center),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Composants réutilisables
// ══════════════════════════════════════════════════════════════════════════════

// ─── Carte totaux depuis le début ─────────────────────────────────────────────
class ProfileLevelBadge extends StatelessWidget {
  final double successRate;
  const ProfileLevelBadge({required this.successRate});

  @override
  Widget build(BuildContext context) {
    String level;
    Color color;
    if (successRate >= 70) { level = '⭐ Expert Hippique'; color = const Color(0xFFFFD700); }
    else if (successRate >= 50) { level = '🏅 Confirmé'; color = const Color(0xFF4CAF7D); }
    else if (successRate >= 30) { level = '📈 En progression'; color = const Color(0xFFFFB74D); }
    else { level = '🎯 Débutant'; color = const Color(0xFF9E9E9E); }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color, width: 1.2),
      ),
      child: Text(level, style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w600)),
    );
  }
}

class ProfileStatBox extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  final String size; // 'normal' ou 'large'
  const ProfileStatBox({required this.label, required this.value, this.color, this.size = 'normal'});

  @override
  Widget build(BuildContext context) {
    final valueFontSize = size == 'large' ? 24.0 : 20.0;
    final labelFontSize = size == 'large' ? 12.5 : 11.0;
    return Column(children: [
      Text(value,
          style: TextStyle(
              color: color ?? Colors.white,
              fontSize: valueFontSize,
              fontWeight: FontWeight.bold)),
      const SizedBox(height: 3),
      Text(label, style: TextStyle(color: Colors.white54, fontSize: labelFontSize)),
    ]);
  }
}

class ProfileSettingItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;
  final Color? iconColor;

  const ProfileSettingItem({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final ic = iconColor ?? const Color(0xFF4CAF7D);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: const Color(0xFF162033).withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF1E3A5C).withValues(alpha: 0.3)),
        ),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
                color: const Color(0xFF080E1A), borderRadius: BorderRadius.circular(9)),
            child: Icon(icon, color: ic, size: 21),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500)),
              Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 13)),
            ]),
          ),
          const Icon(Icons.chevron_right, color: Colors.white30, size: 20),
        ]),
      ),
    );
  }
}


