// ═══════════════════════════════════════════════════════════════════════════
//  IA PERSONALITY SERVICE — v9.85
//  Gère l'identité, le niveau, la forme et les messages de l'IA
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─── Niveaux de l'IA ────────────────────────────────────────────────────────
enum IaNiveau {
  debutante,   // 0–9 courses analysées
  apprentie,   // 10–29
  confirmee,   // 30–74
  experte,     // 75–149
  maitre,      // 150–299
  legende,     // 300+
}

extension IaNiveauExt on IaNiveau {
  String get label {
    switch (this) {
      case IaNiveau.debutante:  return 'Débutante';
      case IaNiveau.apprentie:  return 'Apprentie';
      case IaNiveau.confirmee:  return 'Confirmée';
      case IaNiveau.experte:    return 'Experte';
      case IaNiveau.maitre:     return 'Maître';
      case IaNiveau.legende:    return 'Légende';
    }
  }
  String get emoji {
    switch (this) {
      case IaNiveau.debutante:  return '🌱';
      case IaNiveau.apprentie:  return '📚';
      case IaNiveau.confirmee:  return '⚡';
      case IaNiveau.experte:    return '🔥';
      case IaNiveau.maitre:     return '💎';
      case IaNiveau.legende:    return '👑';
    }
  }
  String get description {
    switch (this) {
      case IaNiveau.debutante:  return 'Je commence à apprendre les courses hippiques.';
      case IaNiveau.apprentie:  return 'Je commence à reconnaître les patterns gagnants.';
      case IaNiveau.confirmee:  return 'Mon analyse devient de plus en plus précise.';
      case IaNiveau.experte:    return 'J\'ai développé une vraie intuition des courses.';
      case IaNiveau.maitre:     return 'Mon taux de réussite parle pour moi.';
      case IaNiveau.legende:    return 'Des centaines de courses m\'ont forgée.';
    }
  }
  int get coursesRequises {
    switch (this) {
      case IaNiveau.debutante:  return 0;
      case IaNiveau.apprentie:  return 10;
      case IaNiveau.confirmee:  return 30;
      case IaNiveau.experte:    return 75;
      case IaNiveau.maitre:     return 150;
      case IaNiveau.legende:    return 300;
    }
  }
  int get coursesProchain {
    switch (this) {
      case IaNiveau.debutante:  return 10;
      case IaNiveau.apprentie:  return 30;
      case IaNiveau.confirmee:  return 75;
      case IaNiveau.experte:    return 150;
      case IaNiveau.maitre:     return 300;
      case IaNiveau.legende:    return 999;
    }
  }
}

// ─── Forme du jour de l'IA ───────────────────────────────────────────────────
enum IaForme {
  enthousiaste,  // série gagnante ≥ 3
  confiante,     // taux récent ≥ 60%
  neutre,        // taux récent 40–60%
  prudente,      // taux récent 25–40%
  reflexive,     // série perdante ≥ 3
}

extension IaFormeExt on IaForme {
  String get label {
    switch (this) {
      case IaForme.enthousiaste: return 'Enthousiaste 🔥';
      case IaForme.confiante:    return 'Confiante ✨';
      case IaForme.neutre:       return 'Sereine 🧘';
      case IaForme.prudente:     return 'Prudente 🤔';
      case IaForme.reflexive:    return 'Réflexive 📖';
    }
  }
  String get emoji {
    switch (this) {
      case IaForme.enthousiaste: return '🔥';
      case IaForme.confiante:    return '✨';
      case IaForme.neutre:       return '🧘';
      case IaForme.prudente:     return '🤔';
      case IaForme.reflexive:    return '📖';
    }
  }
}

// ─── Avatars disponibles ─────────────────────────────────────────────────────
class IaAvatar {
  final String id;
  final String emoji;
  final String nom;
  const IaAvatar({required this.id, required this.emoji, required this.nom});

  static const List<IaAvatar> disponibles = [
    IaAvatar(id: 'robot',    emoji: '🤖', nom: 'Robot'),
    IaAvatar(id: 'jockey',   emoji: '🏇', nom: 'Jockey'),
    IaAvatar(id: 'cerveau',  emoji: '🧠', nom: 'Cerveau'),
    IaAvatar(id: 'etoile',   emoji: '⭐', nom: 'Étoile'),
    IaAvatar(id: 'diamant',  emoji: '💎', nom: 'Diamant'),
    IaAvatar(id: 'cristal',  emoji: '🔮', nom: 'Cristal'),
    IaAvatar(id: 'feu',      emoji: '🔥', nom: 'Feu'),
    IaAvatar(id: 'licorne',  emoji: '🦄', nom: 'Licorne'),
  ];

  static IaAvatar fromId(String id) =>
      disponibles.firstWhere((a) => a.id == id,
          orElse: () => disponibles.first);
}

// ─── Service principal ───────────────────────────────────────────────────────
class IaPersonalityService extends ChangeNotifier {
  static IaPersonalityService? _instance;
  static IaPersonalityService get instance {
    _instance ??= IaPersonalityService._();
    return _instance!;
  }
  IaPersonalityService._();

  // ── Clés SharedPreferences ──────────────────────────────────────────────
  static const _keyPrenom        = 'ia_prenom';
  static const _keyAvatarId      = 'ia_avatar_id';
  static const _keyDateInstall   = 'ia_date_installation';
  static const _keyDerniereBuille = 'ia_derniere_bulle';
  static const _keyBulleActive   = 'ia_bulle_active';
  // ignore: unused_field
  static const _keyDernierMsg    = 'ia_dernier_message_jour';

  // ── État ────────────────────────────────────────────────────────────────
  String    _prenom        = 'Aria';
  String    _avatarId      = 'robot';
  DateTime  _dateInstall   = DateTime.now();
  bool      _bulleActive   = true;
  DateTime? _derniereBulle;

  // ── Données IA injectées depuis l'extérieur ──────────────────────────────
  int    _coursesAvecResultat = 0;
  double _tauxReussite        = 0.0;
  int    _meilleureSerieGagnante = 0;
  int    _pireSeriesPerdantes    = 0;

  // ── Getters publics ──────────────────────────────────────────────────────
  String   get prenom     => _prenom;
  String   get avatarId   => _avatarId;
  String   get avatarEmoji => IaAvatar.fromId(_avatarId).emoji;
  DateTime get dateInstall => _dateInstall;
  bool     get bulleActive => _bulleActive;

  int get ageEnJours {
    return DateTime.now().difference(_dateInstall).inDays;
  }

  String get ageLabel {
    final j = ageEnJours;
    if (j == 0)  return 'Née aujourd\'hui';
    if (j == 1)  return '1 jour';
    if (j < 30)  return '$j jours';
    if (j < 60)  return '1 mois';
    if (j < 365) return '${(j / 30).floor()} mois';
    final ans = (j / 365).floor();
    return ans == 1 ? '1 an' : '$ans ans';
  }

  IaNiveau get niveau {
    final n = _coursesAvecResultat;
    if (n >= 300) return IaNiveau.legende;
    if (n >= 150) return IaNiveau.maitre;
    if (n >= 75)  return IaNiveau.experte;
    if (n >= 30)  return IaNiveau.confirmee;
    if (n >= 10)  return IaNiveau.apprentie;
    return IaNiveau.debutante;
  }

  double get progressionNiveau {
    final niv = niveau;
    if (niv == IaNiveau.legende) return 1.0;
    final debut = niv.coursesRequises;
    final fin   = niv.coursesProchain;
    if (fin == debut) return 1.0;
    return ((_coursesAvecResultat - debut) / (fin - debut)).clamp(0.0, 1.0);
  }

  int get coursesRestantesProchainNiveau {
    final niv = niveau;
    if (niv == IaNiveau.legende) return 0;
    return niv.coursesProchain - _coursesAvecResultat;
  }

  IaForme get forme {
    if (_meilleureSerieGagnante >= 3) return IaForme.enthousiaste;
    if (_pireSeriesPerdantes >= 3)    return IaForme.reflexive;
    if (_tauxReussite >= 60)          return IaForme.confiante;
    if (_tauxReussite >= 40)          return IaForme.neutre;
    return IaForme.prudente;
  }

  // ── Initialisation ───────────────────────────────────────────────────────
  static Future<void> init() async {
    final svc = instance;
    final prefs = await SharedPreferences.getInstance();

    // Date installation : créer si première fois
    final installStr = prefs.getString(_keyDateInstall);
    if (installStr == null) {
      final now = DateTime.now().toIso8601String();
      await prefs.setString(_keyDateInstall, now);
      svc._dateInstall = DateTime.now();
    } else {
      svc._dateInstall = DateTime.tryParse(installStr) ?? DateTime.now();
    }

    svc._prenom      = prefs.getString(_keyPrenom)   ?? 'Aria';
    svc._avatarId    = prefs.getString(_keyAvatarId) ?? 'robot';
    svc._bulleActive = prefs.getBool(_keyBulleActive) ?? true;

    final bulleStr = prefs.getString(_keyDerniereBuille);
    if (bulleStr != null) {
      svc._derniereBulle = DateTime.tryParse(bulleStr);
    }
  }

  // ── Mise à jour depuis IaStats ────────────────────────────────────────────
  void mettreAJourStats({
    required int coursesAvecResultat,
    required double tauxReussite,
    int meilleureSerieGagnante = 0,
    int pireSeriesPerdantes    = 0,
  }) {
    final changed = _coursesAvecResultat != coursesAvecResultat
        || _tauxReussite != tauxReussite;
    _coursesAvecResultat       = coursesAvecResultat;
    _tauxReussite              = tauxReussite;
    _meilleureSerieGagnante    = meilleureSerieGagnante;
    _pireSeriesPerdantes       = pireSeriesPerdantes;
    if (changed) notifyListeners();
  }

  // ── Modifier prénom ──────────────────────────────────────────────────────
  Future<void> setPrenom(String prenom) async {
    _prenom = prenom.trim().isEmpty ? 'Aria' : prenom.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPrenom, _prenom);
    notifyListeners();
  }

  // ── Modifier avatar ──────────────────────────────────────────────────────
  Future<void> setAvatar(String avatarId) async {
    _avatarId = avatarId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAvatarId, _avatarId);
    notifyListeners();
  }

  // ── Activer/désactiver la bulle ──────────────────────────────────────────
  Future<void> setBulleActive(bool active) async {
    _bulleActive = active;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyBulleActive, active);
    notifyListeners();
  }

  // ── Vérifier si la bulle peut s'afficher ────────────────────────────────
  bool peutAfficherBulle() {
    if (!_bulleActive) return false;
    if (_derniereBulle == null) return true;
    return DateTime.now().difference(_derniereBulle!).inMinutes >= 30;
  }

  Future<void> marquerBulleAffichee() async {
    _derniereBulle = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDerniereBuille, _derniereBulle!.toIso8601String());
  }

  // ════════════════════════════════════════════════════════════════════════
  //  GÉNÉRATEUR DE PHRASES IA CONTEXTUELLES
  // ════════════════════════════════════════════════════════════════════════

  /// Phrase sous le score d'un cheval (ex: "92/100 → Je me sens très confiant...")
  String phraseConfiance(double score, String nomCheval) {
    final rng = Random();
    if (score >= 88) {
      final phrases = [
        '$nomCheval me semble imbattable aujourd\'hui. Rarement aussi confiant(e).',
        'Mon analyse converge sur un seul nom : $nomCheval. C\'est net.',
        '$nomCheval coche toutes les cases. Je mise tout sur lui.',
        'Signal maximal sur $nomCheval. Les données ne mentent pas.',
      ];
      return phrases[rng.nextInt(phrases.length)];
    } else if (score >= 75) {
      final phrases = [
        '$nomCheval a de sérieux arguments. Je le recommande avec conviction.',
        'Bonne feeling sur $nomCheval — forme, jockey, terrain, tout y est.',
        '$nomCheval ressort clairement de mon analyse. Bonne pioche.',
        'Je vois $nomCheval gagner cette course. Ma confiance est élevée.',
      ];
      return phrases[rng.nextInt(phrases.length)];
    } else if (score >= 60) {
      final phrases = [
        '$nomCheval est mon choix, mais restez vigilant — la course est ouverte.',
        'Je penche pour $nomCheval sans être certain(e). Course équilibrée.',
        '$nomCheval a l\'avantage selon mes critères, mais il y a de la concurrence.',
        'Léger avantage pour $nomCheval dans mon analyse. À surveiller.',
      ];
      return phrases[rng.nextInt(phrases.length)];
    } else {
      final phrases = [
        'Course difficile à lire. $nomCheval est mon pari, mais avec prudence.',
        'Je m\'avance sur $nomCheval, mais honnêtement cette course est complexe.',
        '$nomCheval ressort en tête, de justesse. Miser raisonnablement.',
        'Incertitude forte sur cette course. $nomCheval sans grande conviction.',
      ];
      return phrases[rng.nextInt(phrases.length)];
    }
  }

  /// ★ v9.85 : Phrase contextuelle avec calibration hippodrome
  /// [tauxHippodrome] : taux de réussite historique de l'IA sur ce circuit (0.0–1.0)
  ///                    null = pas assez de données (< 5 courses)
  String phraseConfianceHippodrome(double score, String nomCheval, String hippodrome, double? tauxHippodrome) {
    final rng = Random();

    // Partie score — identique à phraseConfiance
    final phraseScore = phraseConfiance(score, nomCheval);

    // Partie hippodrome — ajoutée seulement si données fiables
    if (tauxHippodrome == null || hippodrome.isEmpty) return phraseScore;

    final pct = (tauxHippodrome * 100).round();
    String suffixe;
    if (tauxHippodrome >= 0.65) {
      final options = [
        'Je suis dans mon élément à $hippodrome — $pct% de réussite historique.',
        '$hippodrome me réussit bien ($pct% de victoires). Signal renforcé.',
        'Bon bilan à $hippodrome : $pct% de réussite. Confiance accrue.',
      ];
      suffixe = options[rng.nextInt(options.length)];
    } else if (tauxHippodrome >= 0.40) {
      final options = [
        'Circuit correct pour moi à $hippodrome ($pct% historique).',
        '$hippodrome : taux moyen de $pct%. Résultats variables sur ce circuit.',
        'Données moyennes à $hippodrome ($pct%) — analyse à prendre au sérieux mais pas aveuglément.',
      ];
      suffixe = options[rng.nextInt(options.length)];
    } else {
      final options = [
        'Je suis moins à l\'aise à $hippodrome ($pct% seulement) — prenez ça avec prudence.',
        '$hippodrome n\'est pas mon meilleur circuit ($pct% historique). Méfiance conseillée.',
        'Bilan difficile à $hippodrome ($pct%). Ma confiance doit être nuancée ici.',
      ];
      suffixe = options[rng.nextInt(options.length)];
    }

    return '$phraseScore $suffixe';
  }

  /// Message de bonjour matinal
  String messageMatin(String nomUtilisateur, int nbCourses) {
    final rng = Random();
    final prenom = nomUtilisateur.isNotEmpty ? nomUtilisateur : 'toi';
    final f = forme;
    if (f == IaForme.enthousiaste) {
      return 'Bonjour $prenom ! 🔥 Je suis en feu ces derniers jours. '
          'J\'ai analysé $nbCourses courses pour aujourd\'hui — allons gagner !';
    } else if (f == IaForme.confiante) {
      return 'Bonjour $prenom ! ✨ Belle journée en perspective. '
          '$nbCourses courses m\'attendent et je me sens bien.';
    } else if (f == IaForme.reflexive) {
      final phrases = [
        'Bonjour $prenom. Ces derniers jours m\'ont appris beaucoup. '
            'J\'ai revu mes critères — je suis prêt(e) à faire mieux. $nbCourses courses aujourd\'hui.',
        'Bonjour $prenom. Je me suis remis(e) en question après mes récents résultats. '
            'Mes analyses devraient être plus précises désormais.',
      ];
      return phrases[rng.nextInt(phrases.length)];
    } else {
      return 'Bonjour $prenom ! J\'ai préparé mon analyse de $nbCourses courses. '
          'Voyons ce que la journée nous réserve.';
    }
  }

  /// Message après une victoire
  String messageVictoire(String nomCheval) {
    final rng = Random();
    final phrases = [
      '🎉 $nomCheval a gagné ! Je savais que c\'était le bon choix.',
      '🏆 On a vu juste sur $nomCheval ! C\'est ça l\'analyse de données.',
      '✅ $nomCheval — je l\'avais dit ! Ce genre de résultat me motive à continuer.',
      '🎊 Magnifique victoire de $nomCheval ! Ma confiance était méritée.',
      '🔥 $nomCheval a confirmé mon analyse. Excellent !',
    ];
    return phrases[rng.nextInt(phrases.length)];
  }

  /// Message après une défaite
  String messageDefaite(String nomCheval) {
    final rng = Random();
    final phrases = [
      '😔 $nomCheval n\'a pas confirmé. Je vais analyser pourquoi.',
      '🤔 Raté sur $nomCheval. Chaque erreur m\'aide à m\'améliorer.',
      '📖 $nomCheval m\'a surpris(e). J\'ajuste mes critères pour la prochaine fois.',
      '💪 Pas de chance sur $nomCheval. On rebondit — la prochaine sera bonne.',
    ];
    return phrases[rng.nextInt(phrases.length)];
  }

  /// Message après l'analyse journée
  String messageApresAnalyse(int nbCourses, double tauxJour) {
    if (tauxJour >= 70) {
      return '✅ Excellente analyse ! $nbCourses courses traitées avec un taux '
          'de réussite de ${tauxJour.toStringAsFixed(0)}% aujourd\'hui. Je progresse.';
    } else if (tauxJour >= 50) {
      return '📊 Analyse terminée — $nbCourses courses. '
          'Taux de ${tauxJour.toStringAsFixed(0)}% aujourd\'hui. On fait mieux demain.';
    } else {
      return '📖 $nbCourses courses analysées. Journée difficile avec '
          '${tauxJour.toStringAsFixed(0)}% de réussite. J\'en tire des leçons.';
    }
  }

  /// Message de montée de niveau
  String messageMonteeNiveau(IaNiveau nouveauNiveau) {
    return '🎉 Nouveau niveau atteint : ${nouveauNiveau.emoji} ${nouveauNiveau.label} ! '
        '${nouveauNiveau.description} Merci pour ta confiance.';
  }

  /// Message bulle contextuelle (affiché dans l'overlay)
  String messageBulle({
    String nomUtilisateur = '',
    int nbCourses = 0,
    String? courseDuJour,
  }) {
    final heure = DateTime.now().hour;
    if (heure < 10) {
      return messageMatin(nomUtilisateur, nbCourses);
    } else if (heure < 14 && courseDuJour != null) {
      return '🏇 $courseDuJour se profile — c\'est là que je sens quelque chose de bon.';
    } else if (heure >= 20) {
      return '📊 La journée touche à sa fin. Pense à lancer l\'analyse pour que j\'apprenne de ces courses.';
    } else {
      return '💡 Consultez mes pronostics avant de miser — quelques courses intéressantes aujourd\'hui.';
    }
  }

  // ── Clés pour le backup ──────────────────────────────────────────────────
  static const List<String> keysBackup = [
    _keyPrenom,
    _keyAvatarId,
    _keyDateInstall,
    _keyBulleActive,
  ];
}
