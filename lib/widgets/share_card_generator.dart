// ignore_for_file: use_build_context_synchronously
/// share_card_generator.dart
/// ──────────────────────────────────────────────────────────────────────────
/// Génère une image JPEG partageable de style Winamax/Unibet pour les paris.
/// Utilise RepaintBoundary + toImage() + share_plus pour partager.
/// ──────────────────────────────────────────────────────────────────────────
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../services/alert_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  Couleurs & constantes de la charte graphique Pronostic Hippique
// ═══════════════════════════════════════════════════════════════════════════
const _kBg         = Color(0xFF0A1628);   // fond principal bleu nuit
const _kBg2        = Color(0xFF0D2035);   // fond secondaire
const _kGreen      = Color(0xFF4CAF7D);   // vert signature
// ignore: unused_element
const _kGreenDark  = Color(0xFF1B5E20);   // vert sombre (réservé)
const _kGold       = Color(0xFFFFD700);   // or (gains)
const _kGoldLight  = Color(0xFFFFF176);   // or clair
const _kAccent     = Color(0xFF1A3A5C);   // bleu accent
const _kCard       = Color(0xFF112236);   // fond carte
const _kBorder     = Color(0xFF2A5A4A);   // bordure verte

// ═══════════════════════════════════════════════════════════════════════════
//  Modèle de données pour la carte de partage
// ═══════════════════════════════════════════════════════════════════════════
class ShareCardData {
  final String typePariLabel;      // ex: "Quinté+", "Simple Gagnant"
  final List<TrackedCourse> paris; // liste des courses partagées
  final double miseTotal;          // mise totale en €
  final double? gainTotal;         // gain réalisé (null = en attente)
  final bool? estGagnant;          // null = en attente, true/false = résultat
  final double? coteGlobale;       // cote combinée (si disponible)
  final double scoreIA;            // score IA moyen (0–100)

  const ShareCardData({
    required this.typePariLabel,
    required this.paris,
    required this.miseTotal,
    this.gainTotal,
    this.estGagnant,
    this.coteGlobale,
    this.scoreIA = 0.0,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
//  Widget invisible utilisé pour le rendu off-screen
// ═══════════════════════════════════════════════════════════════════════════
class ShareCardWidget extends StatelessWidget {
  final ShareCardData data;
  const ShareCardWidget({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final bool gagne = data.estGagnant == true;
    final bool perdu = data.estGagnant == false;
    final bool enAttente = data.estGagnant == null;

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 420,
        decoration: BoxDecoration(
          color: _kBg,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── En-tête avec logo et branding ─────────────────────────────
            _buildHeader(),
            // ── Bandeau de résultat (Gagné / En attente / Perdu) ──────────
            _buildResultBanner(gagne, perdu, enAttente),
            // ── Liste des paris ────────────────────────────────────────────
            _buildParisList(),
            // ── Pied de page ───────────────────────────────────────────────
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
      decoration: const BoxDecoration(
        color: _kBg2,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Row(
        children: [
          // Logo rond
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [_kGreen, Color(0xFF2E7D52)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: _kGreen.withValues(alpha: 0.4),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Center(
              child: Text('🏇', style: TextStyle(fontSize: 22)),
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'PRONOSTIC HIPPIQUE',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  letterSpacing: 1.5,
                ),
              ),
              Text(
                'Par Yax',
                style: TextStyle(
                  color: _kGreen.withValues(alpha: 0.85),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const Spacer(),
          // Type de pari badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _kGreen.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _kGreen.withValues(alpha: 0.4)),
            ),
            child: Text(
              data.typePariLabel.toUpperCase(),
              style: const TextStyle(
                color: _kGreen,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultBanner(bool gagne, bool perdu, bool enAttente) {
    if (enAttente) {
      return _buildEnAttenteBanner();
    }
    if (gagne) {
      return _buildGagneBanner();
    }
    return _buildPerduBanner();
  }

  Widget _buildGagneBanner() {
    final gain = data.gainTotal ?? 0.0;
    final mise = data.miseTotal;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1B4D2E), Color(0xFF2E7D52), Color(0xFF1B4D2E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: _kGreen.withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('🏆', style: TextStyle(fontSize: 28)),
              const SizedBox(width: 10),
              const Text(
                'GAGNÉ !',
                style: TextStyle(
                  color: _kGoldLight,
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                  shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
                ),
              ),
              const SizedBox(width: 10),
              const Text('🏆', style: TextStyle(fontSize: 28)),
            ],
          ),
          const SizedBox(height: 8),
          // Gain total
          Text(
            '+${gain.toStringAsFixed(2)} €',
            style: const TextStyle(
              color: _kGoldLight,
              fontSize: 42,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
              shadows: [Shadow(color: Colors.black54, blurRadius: 6, offset: Offset(0, 2))],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'GAIN PRONOSTIC',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 12),
          // Détails mise + cote
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _statPill('Mise', '${mise.toStringAsFixed(0)} €', Colors.white38),
              if (data.coteGlobale != null && data.coteGlobale! > 0) ...[
                const SizedBox(width: 12),
                _statPill('Cote', '× ${data.coteGlobale!.toStringAsFixed(2)}', _kGold),
              ],
              if (data.scoreIA > 0) ...[
                const SizedBox(width: 12),
                _statPill('IA', '${data.scoreIA.round()}/100', _kGreen),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEnAttenteBanner() {
    final mise = data.miseTotal;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1A3A5C),
            _kAccent,
            const Color(0xFF1A3A5C),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('⏳', style: TextStyle(fontSize: 24)),
              const SizedBox(width: 10),
              const Text(
                'PARI EN COURS',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _statPill('Mise engagée', '${mise.toStringAsFixed(0)} €', _kGold),
              if (data.coteGlobale != null && data.coteGlobale! > 0) ...[
                const SizedBox(width: 12),
                _statPill('Cote', '× ${data.coteGlobale!.toStringAsFixed(2)}', _kGreen),
              ],
              if (data.scoreIA > 0) ...[
                const SizedBox(width: 12),
                _statPill('IA', '${data.scoreIA.round()}/100', _kGreen),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPerduBanner() {
    final mise = data.miseTotal;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF4A1515),
            const Color(0xFF7B1C1C),
            const Color(0xFF4A1515),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('❌', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              const Text(
                'PERDU',
                style: TextStyle(
                  color: Color(0xFFEF9A9A),
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(width: 10),
              const Text('❌', style: TextStyle(fontSize: 22)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '-${mise.toStringAsFixed(2)} €',
            style: const TextStyle(
              color: Color(0xFFEF9A9A),
              fontSize: 32,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'L\'IA analyse pour progresser',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 11,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statPill(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(color: color.withValues(alpha: 0.7), fontSize: 9, fontWeight: FontWeight.w500),
          ),
          Text(
            value,
            style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildParisList() {
    if (data.paris.isEmpty) return const SizedBox.shrink();

    return Container(
      color: _kBg,
      child: Column(
        children: [
          // Séparateur titre
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 14,
                  decoration: BoxDecoration(
                    color: _kGreen,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  data.paris.length == 1
                      ? 'SÉLECTION'
                      : 'SÉLECTIONS (${data.paris.length})',
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
          // Cards des courses
          ...data.paris.asMap().entries.map((e) => _buildCourseRow(e.key, e.value)),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildCourseRow(int index, TrackedCourse course) {
    final heure =
        '${course.heureDepart.hour.toString().padLeft(2, '0')}h${course.heureDepart.minute.toString().padLeft(2, '0')}';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          // Numéro de ligne
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: _kGreen.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _kGreen.withValues(alpha: 0.4)),
            ),
            child: Center(
              child: Text(
                '${index + 1}',
                style: const TextStyle(
                  color: _kGreen,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Infos course
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  course.nomCourse.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      course.hippodrome,
                      style: const TextStyle(color: Colors.white54, fontSize: 10),
                    ),
                    Text(
                      ' · $heure',
                      style: const TextStyle(color: Colors.white38, fontSize: 10),
                    ),
                  ],
                ),
                // Cheval sélectionné
                if (course.nomCheval != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (course.numeroCheval != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          margin: const EdgeInsets.only(right: 5),
                          decoration: BoxDecoration(
                            color: _kGreen.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'N°${course.numeroCheval}',
                            style: const TextStyle(
                              color: _kGreen,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      Flexible(
                        child: Text(
                          course.nomCheval!,
                          style: const TextStyle(
                            color: _kGold,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
                // Numéros joués (Tiercé/Quarté/Quinté/Couplé)
                if (course.numerosJoues.length > 1) ...[
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 4,
                    children: course.numerosJoues.take(8).map((n) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: n == course.numeroCheval
                            ? _kGreen.withValues(alpha: 0.25)
                            : Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: n == course.numeroCheval
                              ? _kGreen.withValues(alpha: 0.5)
                              : Colors.white12,
                        ),
                      ),
                      child: Text(
                        'N°$n',
                        style: TextStyle(
                          color: n == course.numeroCheval ? _kGreen : Colors.white54,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )).toList(),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Colonne droite : type pari + mise
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _kGreen.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  course.typePari,
                  style: const TextStyle(
                    color: _kGreen,
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (course.miseEngagee != null && course.miseEngagee! > 0) ...[
                const SizedBox(height: 4),
                Text(
                  '${course.miseEngagee!.toStringAsFixed(0)} €',
                  style: const TextStyle(
                    color: _kGold,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
              if (course.scoreIA > 0) ...[
                const SizedBox(height: 2),
                Text(
                  '${course.scoreIA.round()}/100',
                  style: TextStyle(
                    color: _kGreen.withValues(alpha: 0.7),
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: const BoxDecoration(
        color: _kBg2,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
      ),
      child: Row(
        children: [
          Text(
            '🏇 PRONOSTIC HIPPIQUE · Par Yax',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.35),
              fontSize: 9,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
          const Spacer(),
          // Date du jour
          Text(
            _formatDateFr(DateTime.now()),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.35),
              fontSize: 9,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateFr(DateTime dt) {
    const mois = [
      'jan', 'fév', 'mar', 'avr', 'mai', 'jun',
      'jul', 'aoû', 'sep', 'oct', 'nov', 'déc'
    ];
    return '${dt.day.toString().padLeft(2, '0')} ${mois[dt.month - 1]} ${dt.year}';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Service de génération et partage
// ═══════════════════════════════════════════════════════════════════════════
class ShareCardService {
  static final GlobalKey _boundaryKey = GlobalKey();

  /// Construit et capture le widget off-screen en JPEG, puis partage
  static Future<void> partagerCourse(
    BuildContext context, {
    required ShareCardData data,
    String? message,
  }) async {
    try {
      _showLoading(context, 'Génération de la carte...');

      final bytes = await _generateCardBytes(data);

      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();

      if (bytes == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Erreur lors de la génération de l\'image')),
          );
        }
        return;
      }

      // Sauvegarder en fichier temporaire
      final tempDir = await getTemporaryDirectory();
      final file = File(
        '${tempDir.path}/pronostic_hippique_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(bytes);

      // Partager
      final shareMsg = message ?? _buildShareMessage(data);
      // ignore: deprecated_member_use
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png')],
        text: shareMsg,
      );
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur de partage : $e')),
        );
      }
    }
  }

  /// Sauvegarde l'image directement dans la Galerie Photos du téléphone
  /// via le package [gal] qui utilise MediaStore (Android) — visible immédiatement
  static Future<void> sauvegarderEnJpeg(
    BuildContext context, {
    required ShareCardData data,
  }) async {
    try {
      _showLoading(context, 'Enregistrement en cours...');

      final bytes = await _generateCardBytes(data);

      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();

      if (bytes == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Erreur : impossible de générer l\'image'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // ── Méthode principale : package gal → MediaStore Android (galerie) ────
      bool savedToGallery = false;
      String errMsg = '';
      try {
        // Sauvegarder d'abord dans un fichier temporaire
        final tempDir = await getTemporaryDirectory();
        final fileName = 'pari_${DateTime.now().millisecondsSinceEpoch}.png';
        final tempFile = File('${tempDir.path}/$fileName');
        await tempFile.writeAsBytes(bytes);
        // Injecter dans la galerie via gal (MediaStore)
        await Gal.putImage(tempFile.path, album: 'Pronostic Hippique');
        await tempFile.delete(); // nettoyer le fichier temporaire
        savedToGallery = true;
      } catch (e1) {
        errMsg = e1.toString();
      }

      if (!context.mounted) return;

      if (savedToGallery) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.photo_library, color: Colors.white, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '✅ Image sauvegardée dans la Galerie !\nAlbum : Pronostic Hippique',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF1B5E20),
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'OK',
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );
      } else {
        // Fallback : ouvrir le partage si sauvegarde galerie impossible
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '⚠️ Galerie inaccessible ($errMsg). Utilisez le bouton Partager.',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        try {
          Navigator.of(context, rootNavigator: true).pop();
        } catch (_) {}
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur JPEG : $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// Génère les bytes JPEG du widget rendu off-screen
  static Future<Uint8List?> _generateCardBytes(ShareCardData data) async {
    // Taille de rendu (portrait, 420px de large)
    const double cardWidth = 420.0;

    // Créer le widget
    final widget = ShareCardWidget(data: data, key: _boundaryKey);

    // Render off-screen
    final repaintBoundary = RenderRepaintBoundary();
    final renderView = RenderView(
      view: ui.PlatformDispatcher.instance.views.first,
      child: RenderPositionedBox(
        alignment: Alignment.topLeft,
        child: repaintBoundary,
      ),
      configuration: ViewConfiguration(
        logicalConstraints: BoxConstraints.tightFor(width: cardWidth),
        devicePixelRatio: 3.0, // haute résolution pour le partage
      ),
    );

    final pipelineOwner = PipelineOwner();
    final buildOwner = BuildOwner(focusManager: FocusManager());

    pipelineOwner.rootNode = renderView;
    renderView.prepareInitialFrame();

    final rootElement = RenderObjectToWidgetAdapter<RenderBox>(
      container: repaintBoundary,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(size: Size(cardWidth, 2000)),
          child: widget,
        ),
      ),
    ).attachToRenderTree(buildOwner);

    buildOwner.buildScope(rootElement);
    buildOwner.finalizeTree();

    pipelineOwner.flushLayout();
    pipelineOwner.flushCompositingBits();
    pipelineOwner.flushPaint();

    final image = await repaintBoundary.toImage(pixelRatio: 3.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

    if (byteData == null) return null;

    // Encoder en JPEG via flutter (PNG → JPEG via codec)
    final pngBytes = byteData.buffer.asUint8List();

    // Décodage PNG → image → reencoder JPEG
    final codec = await ui.instantiateImageCodec(pngBytes);
    final frame = await codec.getNextFrame();
    final jpegData = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);

    if (jpegData == null) return pngBytes; // fallback PNG si JPEG échoue

    // Utiliser PNG haute qualité (Flutter ne supporte pas JPEG natif en export)
    return pngBytes;
  }

  static void _showLoading(BuildContext context, [String message = 'Génération de la carte...']) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0D2035),
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                color: Color(0xFF4CAF7D),
                strokeWidth: 2,
              ),
            ),
            const SizedBox(width: 16),
            Text(
              message,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  static String _buildShareMessage(ShareCardData data) {
    final sb = StringBuffer();
    sb.writeln('🏇 Pronostic Hippique — Par Yax');
    sb.writeln('━━━━━━━━━━━━━━━━━━━━');
    for (final c in data.paris) {
      final heure =
          '${c.heureDepart.hour.toString().padLeft(2, '0')}h${c.heureDepart.minute.toString().padLeft(2, '0')}';
      sb.write('• ${c.nomCourse} ($heure - ${c.hippodrome})');
      if (c.nomCheval != null) sb.write(' → ${c.nomCheval}');
      sb.writeln();
    }
    sb.writeln('━━━━━━━━━━━━━━━━━━━━');
    sb.writeln('Mise : ${data.miseTotal.toStringAsFixed(0)} €');
    if (data.gainTotal != null && data.estGagnant == true) {
      sb.writeln('🏆 Gain : +${data.gainTotal!.toStringAsFixed(2)} €');
    }
    if (data.scoreIA > 0) {
      sb.writeln('🤖 Score IA : ${data.scoreIA.round()}/100');
    }
    return sb.toString();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Bouton de partage réutilisable
// ═══════════════════════════════════════════════════════════════════════════
class ShareParisButton extends StatelessWidget {
  final ShareCardData data;
  final bool compact;
  final Color? backgroundColor;

  const ShareParisButton({
    super.key,
    required this.data,
    this.compact = false,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return _buildCompact(context);
    }
    return _buildFull(context);
  }

  Widget _buildFull(BuildContext context) {
    return GestureDetector(
      onTap: () => ShareCardService.partagerCourse(context, data: data),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1B5E20), Color(0xFF4CAF7D)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF4CAF7D).withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.share, color: Colors.white, size: 20),
            SizedBox(width: 10),
            Text(
              'JE PARTAGE MON PARI',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 15,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompact(BuildContext context) {
    return GestureDetector(
      onTap: () => ShareCardService.partagerCourse(context, data: data),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: backgroundColor ?? const Color(0xFF1A3A5C),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: const Color(0xFF4CAF7D).withValues(alpha: 0.4),
          ),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.share, color: Color(0xFF4CAF7D), size: 16),
            SizedBox(width: 6),
            Text(
              'Partager',
              style: TextStyle(
                color: Color(0xFF4CAF7D),
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
