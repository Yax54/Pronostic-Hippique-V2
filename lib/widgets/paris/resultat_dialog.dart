import 'package:flutter/material.dart';
import '../../services/alert_service.dart';

// ══════════════════════════════════════════════════════════════════════════════
//  Widget : Dialog saisie résultat d'une course
// ══════════════════════════════════════════════════════════════════════════════

class ResultatDialog extends StatefulWidget {
  final TrackedCourse course;
  final AlertService alertSvc;
  final bool? preselectedGagnant;
  final List<int>? prefilledArrivee;

  const ResultatDialog({
    super.key,
    required this.course,
    required this.alertSvc,
    this.preselectedGagnant,
    this.prefilledArrivee,
  });

  @override
  State<ResultatDialog> createState() => _ResultatDialogState();
}

class _ResultatDialogState extends State<ResultatDialog> {
  late bool? _gagnant;
  final _gainCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _gagnant = widget.preselectedGagnant;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF0A1628),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text('Résultat de la course',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(widget.course.nomCourse,
            style: const TextStyle(color: Colors.white60, fontSize: 15)),
        if (widget.course.nomCheval != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Cheval : ${widget.course.nomCheval}',
                style: const TextStyle(color: Color(0xFF4CAF7D), fontSize: 15)),
          ),
        if (widget.prefilledArrivee != null &&
            widget.prefilledArrivee!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF1A2F3D),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white12),
            ),
            child: Text(
              'Arrivée PMU : ${widget.prefilledArrivee!.take(5).map((n) => 'N°$n').join(' - ')}',
              style:
                  const TextStyle(color: Color(0xFF64B5F6), fontSize: 12),
            ),
          ),
        ],
        if (widget.preselectedGagnant != null) ...[
          const SizedBox(height: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: (widget.preselectedGagnant!
                      ? const Color(0xFF1B5E20)
                      : const Color(0xFF7F1919))
                  .withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              widget.preselectedGagnant!
                  ? '✅ Résultat IA : Gagné — confirmez ci-dessous'
                  : '❌ Résultat IA : Perdu — confirmez ci-dessous',
              style: TextStyle(
                color: widget.preselectedGagnant!
                    ? const Color(0xFF69F0AE)
                    : const Color(0xFFEF9A9A),
                fontSize: 12,
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _gagnant = true),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: _gagnant == true
                      ? const Color(0xFFFFD700).withValues(alpha: 0.2)
                      : Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _gagnant == true
                        ? const Color(0xFFFFD700)
                        : Colors.white24,
                    width: _gagnant == true ? 2 : 1,
                  ),
                ),
                child: const Column(children: [
                  Text('🎉', style: TextStyle(fontSize: 24)),
                  SizedBox(height: 4),
                  Text('Gagnant !',
                      style: TextStyle(
                          color: Color(0xFFFFD700),
                          fontWeight: FontWeight.bold)),
                ]),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _gagnant = false),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: _gagnant == false
                      ? const Color(0xFFEF5350).withValues(alpha: 0.15)
                      : Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _gagnant == false
                        ? const Color(0xFFEF5350)
                        : Colors.white24,
                    width: _gagnant == false ? 2 : 1,
                  ),
                ),
                child: const Column(children: [
                  Text('😔', style: TextStyle(fontSize: 24)),
                  SizedBox(height: 4),
                  Text('Perdu',
                      style: TextStyle(
                          color: Color(0xFFEF5350),
                          fontWeight: FontWeight.bold)),
                ]),
              ),
            ),
          ),
        ]),
        if (_gagnant == true) ...[
          const SizedBox(height: 16),
          TextField(
            controller: _gainCtrl,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Gain reçu (€)',
              labelStyle: const TextStyle(color: Colors.white38),
              prefixText: '+',
              prefixStyle: const TextStyle(color: Color(0xFFFFD700)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF2E7D52)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFFFD700)),
              ),
            ),
          ),
        ],
      ]),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child:
              const Text('Annuler', style: TextStyle(color: Colors.white38)),
        ),
        if (_gagnant != null)
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  _gagnant! ? const Color(0xFFFFD700) : const Color(0xFFEF5350),
              foregroundColor:
                  _gagnant! ? const Color(0xFF0A1628) : Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              final gain = double.tryParse(_gainCtrl.text);
              if (widget.preselectedGagnant == null) {
                widget.alertSvc.signalerResultat(
                  courseKey: widget.course.key,
                  nomCourse: widget.course.nomCourse,
                  hippodrome: widget.course.hippodrome,
                  gagnant: _gagnant!,
                  position: null,
                  gainEstime: gain,
                );
              }
              Navigator.pop(context);
            },
            child: const Text('Enregistrer'),
          ),
      ],
    );
  }
}
