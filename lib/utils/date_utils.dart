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

// ═══════════════════════════════════════════════════════════════════════════
//  ★ A-2 — Extraction de la date RÉELLE d'une courseKey
//
//  POURQUOI : `IaMemoryService.enregistrerPronosticsPremiumDuJour()` rangeait
//  chaque entrée premium sous `_todayKey()` (date du TÉLÉPHONE) alors que le
//  lecteur `donneesCalendrierJour()` (ia_memory_service.dart:856) lit sous la
//  date du PRONOSTIC. Quand les deux divergent, l'entrée existe sur le disque
//  mais n'est jamais lue → perte silencieuse et définitive de l'étoile ⭐.
//
//  CE QUE FONT CES FONCTIONS : elles extraient la date portée par la clé
//  elle-même, et REFUSENT tout ce qui n'est pas une date calendaire réelle.
//  Aucune date de remplacement n'est jamais fabriquée (§ « ne jamais inventer
//  une étoile ») : en cas de doute, on retourne `null`.
//
//  CE QU'ELLES NE FONT PAS :
//    • elles ne modifient AUCUNE clé : l'identité complète (`courseKey`, y
//      compris ses suffixes) est préservée telle quelle par l'appelant, ce qui
//      maintient la correspondance exacte avec `_pronostics` et les résultats
//      (`_estPremiumExactGagnantStrict` compare `premium.courseKey` à
//      `prono.courseKey`, ia_memory_service.dart:5470) ;
//    • elles n'imposent aucun plancher/plafond d'ANNÉE : ce serait une règle
//      inventée. Seule la validité CALENDAIRE est contrôlée ;
//    • un suffixe (`_ia`, `_<millisecondes>` — voir alert_service.dart:713) est
//      TOLÉRÉ et non rejeté : une clé légitime ne doit pas être écartée parce
//      qu'elle porte un suffixe.
// ═══════════════════════════════════════════════════════════════════════════

/// `R{numR}C{numC}_{JJMMAAAA}[_suffixe]` — format produit par `buildCourseKey()`
/// (arrivee_reelle_widget.dart:24) et par `TrackedCourse.key` (alert_service.dart:2936).
final RegExp _reCourseKeyDdMmYyyy =
    RegExp(r'^R(\d+)C(\d+)_(\d{2})(\d{2})(\d{4})(?:_.*)?$');

/// `R{numR}C{numC}_{AAAA-MM-JJ}[_suffixe]` — format ISO déjà présent dans les
/// données et les tests (v26/v27 utilisent `R1C1_2026-01-05`).
final RegExp _reCourseKeyIso =
    RegExp(r'^R(\d+)C(\d+)_(\d{4})-(\d{2})-(\d{2})(?:_.*)?$');

/// Valide une date de course au format `djmmaaaa` (ex. `23042026`).
///
/// Refuse tout ce qui n'est pas une date RÉELLE du calendrier grégorien.
/// Aucune tolérance : `31022026`, `29022025`, `32012026`, `''`, `abcdefgh`
/// sont tous rejetés.
///
/// ⚠️ Le constructeur Dart est `DateTime(année, mois, jour)` — l'ordre des
///    arguments est impératif. Une inversion mois/jour ferait passer `23042026`
///    pour le 23ᵉ mois (normalisé silencieusement) et le contrôle par
///    aller-retour est justement là pour l'attraper.
bool estDateCourseCalendaireValide(String dateCoursedjmmaaaa) {
  final s = dateCoursedjmmaaaa;
  if (s.length != 8) return false;
  if (!RegExp(r'^\d{8}$').hasMatch(s)) return false;

  final jour  = int.parse(s.substring(0, 2));
  final mois  = int.parse(s.substring(2, 4));
  final annee = int.parse(s.substring(4, 8));

  // Bornes explicites — redondantes avec le contrôle par aller-retour, mais
  // conservées pour l'auditabilité (une valeur hors bornes est normalisée en
  // silence par DateTime : `DateTime(2026, 32, 1)` → 2027-08-01).
  if (mois < 1 || mois > 12) return false;
  if (jour < 1 || jour > 31) return false;

  // Contrôle par ALLER-RETOUR : la seule façon fiable de rejeter 31/02,
  // 29/02 d'une année non bissextile, etc.
  final reconstruite = DateTime(annee, mois, jour);
  return reconstruite.year == annee &&
      reconstruite.month == mois &&
      reconstruite.day == jour;
}

/// Extrait la date RÉELLE portée par une `courseKey`.
///
/// Retourne la date au format `YYYY-MM-DD` — exactement le format de clé du
/// lecteur (`donneesCalendrierJour`, ia_memory_service.dart:856) et de
/// `premiumsPourDate()` (ia_memory_service.dart:5561).
///
/// Retourne `null` si la clé ne porte pas de date calendairement valide.
/// **Aucune date de remplacement n'est jamais produite.**
///
/// Formats acceptés (les deux réellement présents dans les données) :
///   • `R1C5_23042026`            → `2026-04-23`
///   • `R99C1005_23042026_ia`     → `2026-04-23`  (suffixe toléré)
///   • `R4C7_23042026_1745000…`   → `2026-04-23`  (suffixe toléré)
///   • `R1C1_2026-01-05`          → `2026-01-05`  (ISO)
///
/// Rejetés : `R1C3_` (dateStr vide), `R1C3`, `KEY_PERSONNALISEE`,
/// `R1C1_31022026`, `R1C1_29022025`, `R1C1_32012026`.
///
/// La clé n'est JAMAIS réécrite : seule sa date est lue.
String? dateDepuisCourseKey(String courseKey) {
  final cle = courseKey.trim();
  if (cle.isEmpty) return null;

  // Format principal : djmmaaaa
  final m = _reCourseKeyDdMmYyyy.firstMatch(cle);
  if (m != null) {
    final dd = m.group(3)!;
    final mm = m.group(4)!;
    final aaaa = m.group(5)!;
    if (!estDateCourseCalendaireValide('$dd$mm$aaaa')) return null;
    return '$aaaa-$mm-$dd';
  }

  // Format ISO : aaaa-mm-jj (déjà présent dans les données v26/v27)
  final mIso = _reCourseKeyIso.firstMatch(cle);
  if (mIso != null) {
    final aaaa = mIso.group(3)!;
    final mm = mIso.group(4)!;
    final dd = mIso.group(5)!;
    if (!estDateCourseCalendaireValide('$dd$mm$aaaa')) return null;
    return '$aaaa-$mm-$dd';
  }

  return null;
}
