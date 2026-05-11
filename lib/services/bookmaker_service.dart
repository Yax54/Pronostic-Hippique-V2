// ─────────────────────────────────────────────────────────────────────────────
// Comparateur de cotes bookmakers — Pronostic Hippique
///
/// Fournit les cotes estimées de chaque bookmaker pour un cheval donné,
/// ainsi que des liens d'affiliation vers leurs apps / sites mobiles.
///
/// NOTE : Les cotes bookmakers ne sont pas accessibles via API publique.
/// On calcule une estimation réaliste basée sur la cote PMU de référence :
///   - Chaque bookmaker applique une marge différente (overround)
///   - PMU : marge ~15–20% → cotes les plus basses
///   - Betclic / Winamax : marge ~8–12% → cotes plus élevées
///   - Unibet / ZEbet : marge ~10–14% → intermédiaire
///
/// Ces estimations sont indicatives. Les vraies cotes varient en temps réel.
/// ─────────────────────────────────────────────────────────────────────────────

class BookmakerService {

  /// Calcule les cotes estimées de chaque bookmaker à partir de la cote PMU
  static List<BookmakerCote> estimerCotes(double cotePmu) {
    if (cotePmu <= 1.0) return [];

    // Marge PMU ≈ 18% → probability implicite = 1/cotePmu
    // On convertit la probabilité "vraie" estimée
    // puis on applique la marge de chaque bookmaker
    return _bookmakers.map((bm) {
      // Cote estimée = 1 / (probBrute * (1 + marge))
      // Plus la marge est faible, plus la cote est haute → avantageux
      final coteEstimee = _estimerCote(cotePmu, bm.facteurMarge);
      return BookmakerCote(
        bookmaker: bm,
        cote: coteEstimee,
        isMeilleure: false, // calculé après
      );
    }).toList()
      ..sort((a, b) => b.cote.compareTo(a.cote))
      ..[0] = BookmakerCote(
          bookmaker: _bookmakers.firstWhere(
            (bm) {
              final c = _estimerCote(cotePmu, bm.facteurMarge);
              final best = _bookmakers
                  .map((b2) => _estimerCote(cotePmu, b2.facteurMarge))
                  .reduce((a, b) => a > b ? a : b);
              return (c - best).abs() < 0.01;
            },
            orElse: () => _bookmakers.first,
          ),
          cote: _bookmakers
              .map((bm) => _estimerCote(cotePmu, bm.facteurMarge))
              .reduce((a, b) => a > b ? a : b),
          isMeilleure: true);
  }

  /// Recalcule proprement et retourne la liste triée par cote décroissante
  static List<BookmakerCote> getCotesTriees(double cotePmu) {
    if (cotePmu <= 1.0) return [];

    final result = _bookmakers.map((bm) {
      final cote = _estimerCote(cotePmu, bm.facteurMarge);
      return BookmakerCote(bookmaker: bm, cote: cote, isMeilleure: false);
    }).toList();

    // Trier par cote décroissante
    result.sort((a, b) => b.cote.compareTo(a.cote));

    // Marquer la meilleure
    if (result.isNotEmpty) {
      result[0] = BookmakerCote(
        bookmaker: result[0].bookmaker,
        cote: result[0].cote,
        isMeilleure: true,
      );
    }

    return result;
  }

  /// Gain estimé pour chaque bookmaker
  static double gainEstime(double cote, double mise) {
    return (cote * mise) - mise;
  }

  /// Différence en % entre la meilleure cote bookmaker et PMU
  static double bonusCoteVsPmu(double cotePmu, double meilleureAutre) {
    if (cotePmu <= 0) return 0;
    return ((meilleureAutre - cotePmu) / cotePmu * 100);
  }

  // ─── Calcul interne ───────────────────────────────────────────────────────

  /// facteurMarge > 1.0 = bonus vs PMU
  /// PMU référence = 1.0 (pas de bonus)
  /// Betclic = 1.08 → cote 8% plus haute que PMU
  static double _estimerCote(double cotePmu, double facteurMarge) {
    // Modèle simplifié : cote_bm = cotePmu * facteurMarge
    // avec un plafonnement raisonnable pour les favoris
    final cote = cotePmu * facteurMarge;
    // Arrondi au "standard" bookmaker (0.05 près)
    return _arrondir(cote.clamp(1.01, cotePmu * 1.25));
  }

  static double _arrondir(double cote) {
    // Bookmakers affichent en quarts : 1.75, 2.00, 2.25...
    // ou en dixièmes : 3.5, 4.0, 4.5...
    if (cote < 3.0) {
      return (cote * 4).round() / 4; // quarts
    } else if (cote < 10.0) {
      return (cote * 2).round() / 2; // demis
    } else {
      return cote.round().toDouble(); // entiers
    }
  }

  // ─── Liste des bookmakers ─────────────────────────────────────────────────

  static const List<BookmakerInfo> _bookmakers = [
    BookmakerInfo(
      nom: 'PMU',
      emoji: '🇫🇷',
      couleur: 0xFF1B5E20,
      facteurMarge: 1.00, // référence — pas de bonus
      urlBase: 'https://www.pmu.fr',
      urlApp: 'https://www.pmu.fr/turf/offre/courses',
      description: 'Opérateur officiel français',
      bonus: '',
    ),
    BookmakerInfo(
      nom: 'Betclic',
      emoji: '🔵',
      couleur: 0xFF1565C0,
      facteurMarge: 1.08,
      urlBase: 'https://www.betclic.fr',
      urlApp: 'https://www.betclic.fr/hippisme-s7',
      description: 'Meilleures cotes hippisme',
      bonus: 'Jusqu\'à 100€ offerts',
    ),
    BookmakerInfo(
      nom: 'Winamax',
      emoji: '🃏',
      couleur: 0xFFE53935,
      facteurMarge: 1.07,
      urlBase: 'https://www.winamax.fr',
      urlApp: 'https://www.winamax.fr/paris-sportifs/sports/16',
      description: 'Cotes compétitives',
      bonus: '1er pari remboursé',
    ),
    BookmakerInfo(
      nom: 'Unibet',
      emoji: '🟢',
      couleur: 0xFF2E7D32,
      facteurMarge: 1.06,
      urlBase: 'https://www.unibet.fr',
      urlApp: 'https://www.unibet.fr/sport/horse-racing',
      description: 'Leader européen',
      bonus: '100€ de bonus',
    ),
    BookmakerInfo(
      nom: 'ZEbet',
      emoji: '⚡',
      couleur: 0xFFF57F17,
      facteurMarge: 1.09,
      urlBase: 'https://www.zebet.fr',
      urlApp: 'https://www.zebet.fr/fr/sport/52-horse_racing',
      description: 'Spécialiste hippisme',
      bonus: '100€ offerts',
    ),
    BookmakerInfo(
      nom: 'ParionsSport',
      emoji: '🏅',
      couleur: 0xFF4527A0,
      facteurMarge: 1.05,
      urlBase: 'https://www.enligne.parionssport.fdj.fr',
      urlApp: 'https://www.enligne.parionssport.fdj.fr/paris-hippiques',
      description: 'FDJ officiel',
      bonus: '150€ de bonus',
    ),
  ];
}

// ─── Modèles ──────────────────────────────────────────────────────────────────

class BookmakerInfo {
  final String nom;
  final String emoji;
  final int couleur;
  final double facteurMarge;
  final String urlBase;
  final String urlApp;
  final String description;
  final String bonus;

  const BookmakerInfo({
    required this.nom,
    required this.emoji,
    required this.couleur,
    required this.facteurMarge,
    required this.urlBase,
    required this.urlApp,
    required this.description,
    required this.bonus,
  });
}

class BookmakerCote {
  final BookmakerInfo bookmaker;
  final double cote;
  final bool isMeilleure;

  BookmakerCote({
    required this.bookmaker,
    required this.cote,
    required this.isMeilleure,
  });

  double gainPour(double mise) => (cote * mise) - mise;
}
