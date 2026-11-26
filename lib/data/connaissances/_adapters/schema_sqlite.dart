/// Schéma physique de la base structurée (SQLite).
///
/// Consigne §5 : SQLite pour les catégories volumineuses et structurées, avec
/// index, relations et écritures individuelles. Consigne D-17 : SQLite comme
/// technologie privilégiée, avec justification par compatibilité, fiabilité,
/// maintenance, transactions et testabilité.
///
/// Règles de conception appliquées ici :
///
/// 1. **Aucune donnée source n'est perdue.** Les tables qui reçoivent un contenu
///    d'origine (`courses`, `participations`, `rapports`, `bilans`,
///    `observations`) conservent le contenu brut dans une colonne texte. Une
///    migration ne remplace jamais l'original par une projection.
/// 2. **Aucun plafond.** Aucune table ne porte de limite de volume ni de purge
///    automatique (§11).
/// 3. **Aucune déduplication par date.** Les rapports sont identifiés par
///    empreinte de contenu (§13). La date reste un attribut indexé, jamais une
///    clé.
/// 4. **`fnum2` n'est jamais supprimé.** Il reste dans le contenu conservé ; la
///    version normalisée est une colonne séparée, ce qui rend la normalisation
///    réversible (§13).
/// 5. **Les références de bilan pointent la version EXACTE du rapport utilisé**
///    (§13), avec `ordre` pour préserver ordre et multiplicité.
/// 6. **Les ratings ELO conservent leur clé d'origine verbatim** (`id`), de
///    sorte que la valeur restaurée est identique bit à bit (§12).
library;

/// Version du schéma. Toute évolution incrémente cette valeur et ajoute les
/// instructions de migration correspondantes.
const int kVersionSchema = 1;

/// Instructions de création, dans l'ordre d'exécution.
const List<String> kInstructionsCreation = <String>[
  // ---------------------------------------------------------------- métadonnées
  '''
CREATE TABLE meta (
  cle     TEXT PRIMARY KEY,
  valeur  TEXT NOT NULL,
  maj_le  TEXT NOT NULL
)
''',

  // ------------------------------------------------------------------- chevaux
  // Identité permanente (§7). `nom_normalise` est un attribut, pas une preuve.
  '''
CREATE TABLE chevaux (
  id                TEXT PRIMARY KEY,
  nom_normalise     TEXT NOT NULL,
  nom_affichage     TEXT NOT NULL,
  niveau_identite   TEXT NOT NULL,
  id_fournisseur    TEXT,
  annee_naissance   INTEGER,
  sexe              TEXT,
  cree_le           TEXT NOT NULL,
  maj_le            TEXT NOT NULL
)
''',
  'CREATE INDEX idx_chevaux_nom ON chevaux(nom_normalise)',
  // Un identifiant fournisseur attesté ne peut désigner qu'un seul cheval.
  // L'unicité est partielle (les identifiants internes provisoires n'en ont pas).
  'CREATE UNIQUE INDEX idx_chevaux_fournisseur ON chevaux(id_fournisseur) '
      'WHERE id_fournisseur IS NOT NULL',

  // Alias : un nom corrigé ou une graphie différente n'est jamais une fusion
  // automatique, mais une trace conservée (D-11, §7).
  '''
CREATE TABLE chevaux_alias (
  id_cheval       TEXT NOT NULL,
  alias_normalise TEXT NOT NULL,
  provenance      TEXT NOT NULL,
  cree_le         TEXT NOT NULL,
  PRIMARY KEY (id_cheval, alias_normalise),
  FOREIGN KEY (id_cheval) REFERENCES chevaux(id) ON DELETE RESTRICT
)
''',
  'CREATE INDEX idx_alias_nom ON chevaux_alias(alias_normalise)',

  // Entités nommées : jockeys, drivers, entraîneurs, hippodromes.
  // Le rôle sépare jockey et driver (§9) : un même patronyme peut exercer les
  // deux, et un hippodrome n'est pas une personne.
  '''
CREATE TABLE entites_nommees (
  id             TEXT PRIMARY KEY,
  role           TEXT NOT NULL,
  nom_normalise  TEXT NOT NULL,
  nom_affichage  TEXT NOT NULL,
  cree_le        TEXT NOT NULL
)
''',
  'CREATE UNIQUE INDEX idx_entites_role_nom '
      'ON entites_nommees(role, nom_normalise)',

  // ------------------------------------------------------------------- courses
  // Fait hippique authentique. `empreinte_source` permet de détecter qu'une
  // nouvelle réponse PMU est identique à celle déjà connue (§10) sans relire
  // le contenu complet.
  '''
CREATE TABLE courses (
  id               TEXT PRIMARY KEY,
  date_course      TEXT NOT NULL,
  reunion          INTEGER NOT NULL,
  course           INTEGER NOT NULL,
  hippodrome       TEXT NOT NULL DEFAULT '',
  libelle          TEXT,
  discipline       TEXT,
  distance         INTEGER,
  categorie        TEXT,
  etat_terrain     TEXT,
  type_piste       TEXT,
  nb_participants  INTEGER,
  arrivee          TEXT,
  statut           TEXT NOT NULL DEFAULT 'connue',
  source           TEXT NOT NULL,
  charge_brute     TEXT,
  empreinte_source TEXT,
  cree_le          TEXT NOT NULL,
  maj_le           TEXT NOT NULL,
  UNIQUE (date_course, reunion, course, hippodrome)
)
''',
  'CREATE INDEX idx_courses_date ON courses(date_course)',
  'CREATE INDEX idx_courses_date_reunion ON courses(date_course, reunion)',
  'CREATE INDEX idx_courses_discipline ON courses(discipline)',
  'CREATE INDEX idx_courses_hippodrome ON courses(hippodrome)',
  'CREATE INDEX idx_courses_empreinte ON courses(empreinte_source)',

  // ------------------------------------------------------------- participations
  // Le contexte (discipline, terrain, poids, place) vit ici, pas sur le cheval
  // (D-19). `nom_cheval_brut` est conservé même quand l'identité est résolue :
  // c'est la trace qui permet de contester une résolution.
  '''
CREATE TABLE participations (
  id                TEXT PRIMARY KEY,
  id_course         TEXT NOT NULL,
  id_cheval         TEXT,
  nom_cheval_brut   TEXT NOT NULL,
  numero_programme  INTEGER NOT NULL,
  id_jockey         TEXT,
  id_entraineur     TEXT,
  nom_jockey_brut   TEXT,
  nom_entraineur_brut TEXT,
  discipline        TEXT,
  place_officielle  INTEGER,
  place_depart      INTEGER,
  poids_kg          REAL,
  reduction_km      REAL,
  gains_carriere    REAL,
  gains_annee       REAL,
  musique           TEXT,
  deferre           TEXT,
  charge_brute      TEXT,
  cree_le           TEXT NOT NULL,
  maj_le            TEXT NOT NULL,
  UNIQUE (id_course, numero_programme),
  FOREIGN KEY (id_course) REFERENCES courses(id) ON DELETE RESTRICT
)
''',
  'CREATE INDEX idx_part_course ON participations(id_course)',
  'CREATE INDEX idx_part_cheval ON participations(id_cheval)',
  'CREATE INDEX idx_part_jockey ON participations(id_jockey)',
  'CREATE INDEX idx_part_entraineur ON participations(id_entraineur)',

  // -------------------------------------------------------------- performances
  // Performance individuelle authentique issue du PMU (une ligne par
  // participation passée reconnue). Distincte de la participation : elle peut
  // exister sans que la course correspondante soit connue en détail (§8).
  '''
CREATE TABLE performances (
  id               TEXT PRIMARY KEY,
  id_cheval        TEXT,
  nom_cheval_brut  TEXT NOT NULL,
  discipline       TEXT,
  date_perf        TEXT,
  hippodrome       TEXT,
  place            INTEGER,
  reduction_km     REAL,
  gains            REAL,
  musique          TEXT,
  source           TEXT NOT NULL,
  charge_brute     TEXT,
  cree_le          TEXT NOT NULL,
  UNIQUE (id_cheval, date_perf, hippodrome, source)
)
''',
  'CREATE INDEX idx_perf_cheval ON performances(id_cheval)',
  'CREATE INDEX idx_perf_date ON performances(date_perf)',
  'CREATE INDEX idx_perf_discipline ON performances(discipline)',

  // ------------------------------------------------------- observations locales
  // Connaissance NON rediffusée par le PMU (cote horodatée, composition connue
  // à un instant donné). Sa perte est irréversible : conservation permanente.
  '''
CREATE TABLE observations (
  id          TEXT PRIMARY KEY,
  type        TEXT NOT NULL,
  id_course   TEXT,
  id_cheval   TEXT,
  horodatage  TEXT NOT NULL,
  contenu     TEXT NOT NULL,
  empreinte   TEXT NOT NULL,
  source      TEXT NOT NULL,
  cree_le     TEXT NOT NULL,
  UNIQUE (empreinte)
)
''',
  'CREATE INDEX idx_obs_course ON observations(id_course)',
  'CREATE INDEX idx_obs_type ON observations(type)',
  'CREATE INDEX idx_obs_horodatage ON observations(horodatage)',

  // --------------------------------------------------------------- ratings ELO
  // `id` = clé d'origine verbatim (« NOM|DISCIPLINE »), ce qui garantit que la
  // valeur restaurée est exactement celle d'avant migration (§12).
  // `id_cheval` reste NULLABLE : un rating d'identité non résolue est conservé
  // et jamais supprimé (D-20).
  '''
CREATE TABLE elo_ratings (
  id             TEXT PRIMARY KEY,
  nom_origine    TEXT NOT NULL,
  nom_normalise  TEXT NOT NULL,
  discipline     TEXT NOT NULL,
  rating         REAL NOT NULL,
  nb             INTEGER NOT NULL,
  var            REAL NOT NULL,
  id_cheval      TEXT,
  cree_le        TEXT NOT NULL,
  maj_le         TEXT NOT NULL,
  UNIQUE (nom_normalise, discipline)
)
''',
  'CREATE INDEX idx_elo_discipline ON elo_ratings(discipline)',
  'CREATE INDEX idx_elo_cheval ON elo_ratings(id_cheval)',
  'CREATE INDEX idx_elo_nom ON elo_ratings(nom_normalise)',

  // États d'apprentissage ELO (marqueurs de format, registre, horodatage).
  // Conservés tels quels : aucune valeur n'est recalculée ni fusionnée.
  '''
CREATE TABLE elo_etats (
  cle     TEXT PRIMARY KEY,
  valeur  TEXT NOT NULL,
  maj_le  TEXT NOT NULL
)
''',

  // ------------------------------------------------------------------ rapports
  // Identifié par l'empreinte de son CONTENU, jamais par sa date (§13).
  // `contenu` = contenu d'origine intégral (donc `fnum2` inclus).
  // `contenu_normalise` = projection réversible destinée à la comparaison.
  '''
CREATE TABLE rapports (
  id                TEXT PRIMARY KEY,
  date_rapport      TEXT NOT NULL,
  empreinte         TEXT NOT NULL UNIQUE,
  schema_version    INTEGER NOT NULL DEFAULT 1,
  contenu           TEXT NOT NULL,
  contenu_normalise TEXT NOT NULL,
  taille_origine    INTEGER NOT NULL,
  cree_le           TEXT NOT NULL
)
''',
  'CREATE INDEX idx_rapports_date ON rapports(date_rapport)',
  'CREATE INDEX idx_rapports_schema ON rapports(schema_version)',

  // Une ligne par copie physique rencontrée, toutes sources confondues
  // (collection principale, bilans hebdomadaires, bilans mensuels). C'est la
  // preuve de redondance qui autorise, et seulement ensuite, l'élimination des
  // copies excédentaires (§13).
  '''
CREATE TABLE rapports_sources (
  empreinte  TEXT NOT NULL,
  source     TEXT NOT NULL,
  position   INTEGER NOT NULL DEFAULT -1,
  chemin     TEXT,
  cree_le    TEXT NOT NULL,
  PRIMARY KEY (empreinte, source, position)
)
''',
  'CREATE INDEX idx_rapports_sources_source ON rapports_sources(source)',

  // -------------------------------------------------------------------- bilans
  // Agrégats historiques conservés. La référence vers un rapport vise une
  // EMPREINTE, donc une version exacte : un bilan ne repointe jamais vers la
  // dernière version disponible (§13).
  '''
CREATE TABLE bilans (
  id              TEXT PRIMARY KEY,
  type            TEXT NOT NULL,
  periode_debut   TEXT,
  periode_fin     TEXT,
  annee           INTEGER,
  mois            INTEGER,
  semaine         INTEGER,
  contenu         TEXT NOT NULL,
  empreinte       TEXT NOT NULL,
  schema_version  INTEGER NOT NULL DEFAULT 1,
  cree_le         TEXT NOT NULL,
  UNIQUE (empreinte)
)
''',
  'CREATE INDEX idx_bilans_type ON bilans(type)',
  'CREATE INDEX idx_bilans_periode ON bilans(periode_debut, periode_fin)',

  // Références d'un bilan vers les versions exactes de rapports utilisées.
  // `ordre` conserve l'ordre et la multiplicité, qui influencent les résultats.
  '''
CREATE TABLE bilans_references (
  id_bilan   TEXT NOT NULL,
  role       TEXT NOT NULL,
  empreinte  TEXT NOT NULL,
  ordre      INTEGER NOT NULL,
  PRIMARY KEY (id_bilan, role, ordre),
  FOREIGN KEY (id_bilan) REFERENCES bilans(id) ON DELETE RESTRICT
)
''',
  'CREATE INDEX idx_bilans_ref_empreinte ON bilans_references(empreinte)',

  // ---------------------------------------------------------------- pronostics
  // Pronostic figé. `resultat_officiel` non nul ⇒ conservation permanente.
  // Aucune colonne de score n'est recalculée par la migration (§3, §17).
  '''
CREATE TABLE pronostics (
  id                 TEXT PRIMARY KEY,
  cle_course         TEXT,
  date_course        TEXT,
  contenu            TEXT NOT NULL,
  empreinte          TEXT NOT NULL,
  resultat_officiel  TEXT,
  archive            INTEGER NOT NULL DEFAULT 0,
  cree_le            TEXT NOT NULL,
  maj_le             TEXT NOT NULL,
  UNIQUE (empreinte)
)
''',
  'CREATE INDEX idx_pronostics_date ON pronostics(date_course)',
  'CREATE INDEX idx_pronostics_archive ON pronostics(archive)',
  'CREATE INDEX idx_pronostics_resultat ON pronostics(resultat_officiel)',

  // ------------------------------------------------------------- données financières
  '''
CREATE TABLE tickets (
  id         TEXT PRIMARY KEY,
  date_ticket TEXT,
  contenu    TEXT NOT NULL,
  empreinte  TEXT NOT NULL,
  cree_le    TEXT NOT NULL,
  UNIQUE (empreinte)
)
''',
  'CREATE INDEX idx_tickets_date ON tickets(date_ticket)',

  // ------------------------------------------------------------------- conflits
  // Trace des divergences rencontrées (identité, état d'apprentissage, valeur
  // divergente). Un conflit n'est jamais résolu silencieusement (§16, D-24) :
  // il est conservé pour traitement explicite.
  '''
CREATE TABLE conflits (
  id             TEXT PRIMARY KEY,
  categorie      TEXT NOT NULL,
  cle_entite     TEXT,
  description    TEXT NOT NULL,
  valeur_locale  TEXT,
  valeur_distante TEXT,
  resolution     TEXT NOT NULL DEFAULT 'en_attente',
  cree_le        TEXT NOT NULL
)
''',
  'CREATE INDEX idx_conflits_categorie ON conflits(categorie)',
  'CREATE INDEX idx_conflits_resolution ON conflits(resolution)',

  // ------------------------------------------------------------------ journal
  // Trace des opérations de migration, restauration et sauvegarde. Permet la
  // reprise après interruption et l'idempotence (§14).
  '''
CREATE TABLE journal_operations (
  id           TEXT PRIMARY KEY,
  operation    TEXT NOT NULL,
  etape        TEXT NOT NULL,
  statut       TEXT NOT NULL,
  detail       TEXT,
  horodatage   TEXT NOT NULL
)
''',
  'CREATE INDEX idx_journal_operation ON journal_operations(operation)',
];

/// Tables dont le contenu est **permanent** : aucune purge automatique n'est
/// autorisée. Cette liste est vérifiée par les tests.
const List<String> kTablesPermanentes = <String>[
  'chevaux',
  'chevaux_alias',
  'entites_nommees',
  'courses',
  'participations',
  'performances',
  'observations',
  'elo_ratings',
  'elo_etats',
  'rapports',
  'rapports_sources',
  'bilans',
  'bilans_references',
  'tickets',
  'conflits',
];

/// Tables dont une partie est purgable selon une règle **explicite**.
/// Seuls les pronostics sans résultat officiel sont concernés (§11).
const List<String> kTablesAPurgeExplicite = <String>['pronostics'];
