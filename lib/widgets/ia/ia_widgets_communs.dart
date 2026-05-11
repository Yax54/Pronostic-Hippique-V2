import 'package:flutter/material.dart';

/// Widget utilitaire partagé entre les onglets de IaPerformanceScreen.
/// Extrait lors du découpage v9.90 — un seul endroit à modifier si le style change.

Widget iaSectionTitle(String title) {
  return Text(
    title,
    style: const TextStyle(
      color: Colors.white,
      fontSize: 15,
      fontWeight: FontWeight.bold,
    ),
  );
}
