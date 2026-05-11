import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// ══════════════════════════════════════════════════════════════════════════
///  PhotoCropScreen — Recadrage circulaire interactif
///  Permet de déplacer et zoomer la photo pour centrer le visage
/// ══════════════════════════════════════════════════════════════════════════
class PhotoCropScreen extends StatefulWidget {
  final String imagePath;

  const PhotoCropScreen({super.key, required this.imagePath});

  /// Ouvre l'écran de recadrage et retourne le chemin du fichier recadré
  static Future<String?> show(BuildContext context, String imagePath) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => PhotoCropScreen(imagePath: imagePath),
      ),
    );
  }

  @override
  State<PhotoCropScreen> createState() => _PhotoCropScreenState();
}

class _PhotoCropScreenState extends State<PhotoCropScreen> {
  // Transformation de l'image
  Offset _offset = Offset.zero;
  double _scale = 1.0;

  // Pour le suivi des gestes
  Offset _startFocalPoint = Offset.zero;
  Offset _startOffset = Offset.zero;
  double _startScale = 1.0;

  // Clé pour capturer le rendu
  final GlobalKey _repaintKey = GlobalKey();

  bool _isSaving = false;

  static const double _cropSize = 280.0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A1628),
        title: const Text(
          'Centrer la photo',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(null),
        ),
        actions: [
          TextButton.icon(
            onPressed: _isSaving ? null : _confirmer,
            icon: _isSaving
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check, color: Color(0xFF4CAF7D)),
            label: Text(
              _isSaving ? 'Enregistrement…' : 'Confirmer',
              style: const TextStyle(
                  color: Color(0xFF4CAF7D), fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Instructions ──────────────────────────────────────────────
          Container(
            color: const Color(0xFF0A1F12),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
            child: Row(
              children: const [
                Icon(Icons.touch_app, color: Color(0xFF4CAF7D), size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Faites glisser pour centrer • Pincez pour zoomer',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),

          // ── Zone de recadrage ─────────────────────────────────────────
          Expanded(
            child: Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Image interactive (hors du RepaintBoundary pour les gestes)
                  GestureDetector(
                    onScaleStart: _onScaleStart,
                    onScaleUpdate: _onScaleUpdate,
                    child: Container(
                      width: _cropSize + 80,
                      height: _cropSize + 80,
                      color: Colors.black,
                      child: ClipRect(
                        child: RepaintBoundary(
                          key: _repaintKey,
                          child: SizedBox(
                            width: _cropSize + 80,
                            height: _cropSize + 80,
                            child: Transform(
                              transform: Matrix4.translationValues(
                                _offset.dx + (_cropSize + 80) / 2,
                                _offset.dy + (_cropSize + 80) / 2,
                                0,
                              )..scale(_scale, _scale, 1.0),
                              alignment: Alignment.center,
                              child: Image.file(
                                File(widget.imagePath),
                                fit: BoxFit.contain,
                                width: _cropSize + 80,
                                height: _cropSize + 80,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Overlay sombre autour du cercle
                  IgnorePointer(
                    child: CustomPaint(
                      size: Size(_cropSize + 80, _cropSize + 80),
                      painter: _CircleMaskPainter(cropSize: _cropSize),
                    ),
                  ),

                  // Cercle de guide (bordure verte)
                  IgnorePointer(
                    child: Container(
                      width: _cropSize,
                      height: _cropSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF4CAF7D),
                          width: 2.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Bouton reset ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: TextButton.icon(
              onPressed: _reset,
              icon: const Icon(Icons.refresh, color: Colors.white54, size: 18),
              label: const Text(
                'Réinitialiser',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _onScaleStart(ScaleStartDetails details) {
    _startFocalPoint = details.focalPoint;
    _startOffset = _offset;
    _startScale = _scale;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    setState(() {
      // Translation
      final delta = details.focalPoint - _startFocalPoint;
      _offset = _startOffset + delta;

      // Zoom (entre 0.5x et 5x)
      _scale = (_startScale * details.scale).clamp(0.5, 5.0);
    });
  }

  void _reset() {
    setState(() {
      _offset = Offset.zero;
      _scale = 1.0;
    });
  }

  Future<void> _confirmer() async {
    setState(() => _isSaving = true);

    try {
      // Capturer le rendu du RepaintBoundary
      final boundary = _repaintKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;

      // Calculer le ratio pixel pour une bonne résolution
      final pixelRatio = MediaQuery.of(context).devicePixelRatio;
      final ui.Image fullImage = await boundary.toImage(pixelRatio: pixelRatio);

      // Convertir en bytes PNG
      final ByteData? byteData =
          await fullImage.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final Uint8List pngBytes = byteData.buffer.asUint8List();

      // Recadrer le cercle central
      final cropped = await _cropCircle(pngBytes, fullImage.width, fullImage.height, pixelRatio);

      // Sauvegarder dans un fichier temporaire
      final tempDir = Directory.systemTemp;
      final outFile = File(
          '${tempDir.path}/profil_crop_${DateTime.now().millisecondsSinceEpoch}.png');
      await outFile.writeAsBytes(cropped);

      if (mounted) {
        Navigator.of(context).pop(outFile.path);
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur lors du recadrage : $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Recadre l'image pour ne garder que le cercle central
  Future<Uint8List> _cropCircle(
      Uint8List pngBytes, int imgW, int imgH, double pixelRatio) async {
    // Taille du carré de sortie (haute résolution)
    final outputSize = (_cropSize * pixelRatio).round();
    final containerSize = ((_cropSize + 80) * pixelRatio).round();

    // Décoder l'image capturée
    final codec = await ui.instantiateImageCodec(pngBytes);
    final frame = await codec.getNextFrame();
    final src = frame.image;

    // Créer un canvas circulaire
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final center = Offset(outputSize / 2, outputSize / 2);
    final radius = outputSize / 2;

    // Clip circulaire
    final path = Path()..addOval(Rect.fromCircle(center: center, radius: radius));
    canvas.clipPath(path);

    // Calculer la position de recadrage depuis le centre du conteneur
    final srcLeft = (containerSize - outputSize) / 2;
    final srcTop = (containerSize - outputSize) / 2;

    final srcRect = Rect.fromLTWH(
      srcLeft.clamp(0, src.width.toDouble()),
      srcTop.clamp(0, src.height.toDouble()),
      math.min(outputSize.toDouble(), src.width - srcLeft),
      math.min(outputSize.toDouble(), src.height - srcTop),
    );

    final dstRect = Rect.fromLTWH(0, 0, outputSize.toDouble(), outputSize.toDouble());

    canvas.drawImageRect(src, srcRect, dstRect, Paint());

    final picture = recorder.endRecording();
    final croppedImage = await picture.toImage(outputSize, outputSize);
    final croppedBytes = await croppedImage.toByteData(format: ui.ImageByteFormat.png);

    return croppedBytes!.buffer.asUint8List();
  }
}

/// Peint un masque sombre autour du cercle de recadrage
class _CircleMaskPainter extends CustomPainter {
  final double cropSize;

  const _CircleMaskPainter({required this.cropSize});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = cropSize / 2;

    // Peindre le fond sombre
    final bgPaint = Paint()..color = Colors.black.withValues(alpha: 0.65);

    // Chemin avec trou circulaire
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addOval(Rect.fromCircle(center: center, radius: radius))
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(path, bgPaint);
  }

  @override
  bool shouldRepaint(covariant _CircleMaskPainter oldDelegate) =>
      oldDelegate.cropSize != cropSize;
}
