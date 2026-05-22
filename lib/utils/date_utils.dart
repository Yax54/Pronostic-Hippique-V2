// ═══════════════════════════════════════════════════════════════════════════
//  date_utils.dart — Helpers date stables v10.76
//
//  Règle : toutes les comparaisons de dates dans l'app (IA Stats, Calendrier,
//  Mémoire IA, Précision par type) doivent passer par ces helpers.
//  Aucun écran ne doit comparer des dates localement sans ces fonctions.
// ═══════════════════════════════════════════════════════════════════════════

/// Retourne le début de journée (minuit) d'une date donnée.
DateTime debutJour(DateTime d) => DateTime(d.year, d.month, d.day);

/// Retourne la fin de journée (23:59:59.999) d'une date donnée.
DateTime finJour(DateTime d) =>
    DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

/// Retourne la date de référence stable pour un pronostic ou une course.
/// Priorité : dateCourse > datePronostic > dateAnalyse > now.
/// Normalise au jour (sans heure) pour comparaisons stables.
DateTime dateFiltreStable({
  DateTime? dateCourse,
  DateTime? datePronostic,
  DateTime? dateAnalyse,
}) {
  final d = dateCourse ?? datePronostic ?? dateAnalyse ?? DateTime.now();
  return DateTime(d.year, d.month, d.day);
}

/// Vérifie si une date se trouve dans une période [debut, fin] incluse.
/// Utilise des comparaisons au jour près (sans heure) pour la stabilité.
bool dateDansPeriodeStable({
  required DateTime date,
  required DateTime debut,
  required DateTime fin,
}) {
  final d     = DateTime(date.year, date.month, date.day);
  final start = DateTime(debut.year, debut.month, debut.day);
  final end   = DateTime(fin.year, fin.month, fin.day, 23, 59, 59, 999);
  return !d.isBefore(start) && !d.isAfter(end);
}

/// Vérifie si une date correspond à aujourd'hui.
bool estAujourdhui(DateTime date) {
  final now = DateTime.now();
  return date.year == now.year &&
      date.month == now.month &&
      date.day == now.day;
}

/// Vérifie si une date se trouve dans les N derniers jours (depuis aujourd'hui).
bool estDansLesNDerniersjours(DateTime date, int nbJours) {
  final debut = debutJour(DateTime.now().subtract(Duration(days: nbJours - 1)));
  final fin   = finJour(DateTime.now());
  return dateDansPeriodeStable(date: date, debut: debut, fin: fin);
}
