#!/usr/bin/env python3
"""
Pronostic Hippique — Proxy Hybride Zone-Turf + PMU API
═══════════════════════════════════════════════════
Routes disponibles:
  GET /api/zt/programme/<date>         → Programme complet du jour (Zone-Turf)
                                          Toutes réunions + courses + pronostics ZT
                                          date format: DDMMYYYY (ex: 11042026)

  GET /api/zt/participants/<date>/<R>/<C>  → Partants d'une course (PMU API)
                                              ex: /api/zt/participants/11042026/1/4

  GET /api/pmu/<path>                  → Proxy direct vers API PMU (legacy)

Architecture hybride:
  - Programme/courses:  Zone-Turf (données plus fiables, complètes, FR+Étranger)
  - Partants/Cotes:    PMU API officielle (données complètes, toujours à jour)
  - Pronostics ZT:     Zone-Turf (parsés depuis page réunion, exclusif)
"""

import http.server
import socketserver
import urllib.request
import urllib.error
import gzip
import re
import json
import os
from datetime import datetime

PORT  = 5060
PMU_BASE       = 'https://turfinfo.api.pmu.fr/rest/client/7'
PMU_SPEC       = 'specialisation=INTERNET'
ZT_BASE        = 'https://www.zone-turf.fr'

CORS_HEADERS = {
    'Access-Control-Allow-Origin':  '*',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Accept',
    'X-Frame-Options':             'ALLOWALL',
    'Content-Security-Policy':     "frame-ancestors *; default-src * 'unsafe-inline' 'unsafe-eval' data: blob:",
}

ZT_HEADERS = {
    'User-Agent':      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
    'Accept':          'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
    'Accept-Language': 'fr-FR,fr;q=0.9',
    'Accept-Encoding': 'gzip, deflate',
    'Connection':      'keep-alive',
}

PMU_HEADERS = {
    'Accept':     'application/json',
    'User-Agent': 'RacePredictor/10.0',
}

# ─── Utilitaires ──────────────────────────────────────────────────────────────

def _strip(html):
    text = re.sub(r'<[^>]+>', ' ', html)
    return re.sub(r'\s+', ' ', text
                  .replace('&nbsp;', ' ')
                  .replace('&euro;', '€')
                  .replace('&amp;', '&')
                  .replace('&lt;', '<')
                  .replace('&gt;', '>')
                  .replace('&quot;', '"')
                  ).strip()

def _fetch_html(url):
    req = urllib.request.Request(url, headers=ZT_HEADERS)
    with urllib.request.urlopen(req, timeout=30) as r:
        raw  = r.read()
        enc  = r.headers.get('Content-Encoding', '')
        if enc == 'gzip':
            raw = gzip.decompress(raw)
        return raw.decode('utf-8', errors='replace')

def _fetch_json(url):
    req = urllib.request.Request(url, headers=PMU_HEADERS)
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.loads(r.read().decode('utf-8', errors='replace'))

def _date_to_zt_url(ddmmyyyy):
    """DDMMYYYY → URL Zone-Turf du programme du jour."""
    MONTHS = {1:'janvier',2:'fevrier',3:'mars',4:'avril',5:'mai',6:'juin',
               7:'juillet',8:'aout',9:'septembre',10:'octobre',
               11:'novembre',12:'decembre'}
    DAYS   = {0:'lundi',1:'mardi',2:'mercredi',3:'jeudi',
               4:'vendredi',5:'samedi',6:'dimanche'}
    d  = int(ddmmyyyy[0:2])
    m  = int(ddmmyyyy[2:4])
    y  = int(ddmmyyyy[4:8])
    dt = datetime(y, m, d)
    return f'{ZT_BASE}/programmes/{DAYS[dt.weekday()]}-{d}-{MONTHS[m]}-{y}/'

def _heure_ts(heure_str, ddmmyyyy):
    """'15h23' + '11042026' → timestamp ms."""
    try:
        h_part = heure_str.replace('h', ':').replace('.', ':')
        parts  = h_part.split(':')
        h, mn  = int(parts[0]), int(parts[1]) if len(parts) > 1 else 0
        d, mo, y = int(ddmmyyyy[:2]), int(ddmmyyyy[2:4]), int(ddmmyyyy[4:8])
        dt = datetime(y, mo, d, h, mn, 0)
        return int(dt.timestamp() * 1000)
    except Exception:
        return 0

def _disc_norm(raw):
    r = raw.upper()
    if 'MONTÉ' in r or 'MONTE' in r:  return 'TROT_MONTE'
    if 'ATTELÉ' in r or 'ATTELE' in r: return 'ATTELE'
    if 'PLAT'   in r:                  return 'PLAT'
    if 'HAIE'   in r:                  return 'HAIE'
    if 'STEEPLE' in r:                 return 'STEEPLECHASE'
    return raw.strip()

def _specialite(disc):
    if disc in ('ATTELE', 'TROT_MONTE'): return 'TROT'
    if disc in ('HAIE', 'STEEPLECHASE', 'CROSS'): return 'OBSTACLE'
    return 'PLAT'

def _is_french(lieu):
    """Renvoie True si l'hippodrome est en France."""
    foreign = ['Aus-','Gb-','GB-','USA-','Arg-','ARG-','SAF-','UAE-',
               'CHL-','Be-','BE-','HOL-','Hol-','IRE-','GER-','ITA-','SWE-',
               'Wolvega','Aintree','Gulfstream','Randwick','Caulfield','Perth',
               'Greyville','Narrogin','Santiago','Geelong','Murray','Cranbourne',
               'Gold Coast','Abu Dhabi','Fonner','San Isidro','Chile','Mons',
               'Wolverhampton','Fairview','Al Ain']
    lieu_up = lieu.upper()
    return not any(f.upper() in lieu_up for f in foreign)

# ─── Parser Zone-Turf ─────────────────────────────────────────────────────────

def parse_programme_zt(html, ddmmyyyy):
    """
    Parse la page /programmes/jour/ de Zone-Turf.
    Retourne une liste de réunions au format Flutter.
    """
    # ── 1. Navigation des réunions (nav horizontale) ──────────────────────────
    nav_items = re.findall(
        r'href="/programmes/((?:r|z)\d+[^"]+\.html)"[^>]*>\s*'
        r'<span class="date">([^<]+)</span>\s*<span class="reunion">'
        r'((?:R|Z)\d+)[^<]*<span class="lieu">([^<]+)</span>',
        html
    )

    reunions_meta = {}  # slug → dict
    for slug_full, heure, rnum, lieu in nav_items:
        slug = slug_full.replace('.html', '')
        m    = re.match(r'(r|z)(\d+)', slug)
        if not m:
            continue
        num_off = int(m.group(2))
        reunions_meta[slug] = {
            'slug':       slug,
            'numOfficiel': num_off,
            'prefix':     m.group(1).upper(),
            'hippodrome': lieu.strip().title(),
            'heureStr':   heure.strip(),
            'isFrench':   _is_french(lieu),
            'dateStr':    ddmmyyyy,
            'courses':    [],
        }

    # ── 2. Tableau des courses de la réunion affichée (R1 = active) ──────────
    # Ancre active (premier li.pmu.active)
    active_m = re.search(r'class="pmu active"[^>]*>\s*<a href="/programmes/([^"]+\.html)"', html)
    active_slug = ''
    if active_m:
        active_slug = active_m.group(1).replace('.html', '').split('/')[-1]

    # Cours du tableau général
    course_rows = re.findall(
        r'<td>(\d+)</td>\s*<td>\s*<a[^>]+title="([^"]+)"[^>]*/>\s*'  # avec img quinte
        r'?-\s*<em>([\d&nbsp;]+)&euro;</em>\s*</td>\s*'
        r'<td>([^<]+)</td>\s*<td>([\d&nbsp;]+m)</td>\s*'
        r'<td>(\d+)</td>\s*<td>([^<]+)</td>',
        html
    )
    if not course_rows:
        # Sans img quinte
        course_rows = re.findall(
            r'<td>(\d+)</td>\s*<td>\s*<a[^>]+title="([^"]+)"[^>]*>[^<]+</a>'
            r'(?:[^<]*<img[^>]*/?>)?\s*-\s*<em>([\d&nbsp;]+)&euro;</em>\s*</td>\s*'
            r'<td>([^<]+)</td>\s*<td>([\d&nbsp;]+m)</td>\s*'
            r'<td>(\d+)</td>\s*<td>([^<]+)</td>',
            html
        )

    # Ancres de sections (pour les pronostics)
    anchor_course_map = re.findall(
        r'(?:name|id)="(quinte|\d{7})".*?'
        r'R1 Course N°(\d+)',
        html, re.DOTALL
    )
    anchor_to_coursenum = {anc: int(cnum) for anc, cnum in anchor_course_map}

    # Pronostics par ancre
    pronostics_by_coursenum = {}
    for anchor, cnum in anchor_to_coursenum.items():
        idx  = html.find(f'name="{anchor}"')
        if idx < 0:
            idx = html.find(f'id="{anchor}"')
        if idx < 0:
            continue
        snip = html[idx:idx+20000]
        # Chercher "Retrouvez les chevaux du jour" → nums
        prono_idx = snip.find('Retrouvez les chevaux du jour')
        if prono_idx >= 0:
            prono_snip = snip[prono_idx:prono_idx+2000]
            nums = re.findall(r'<strong>(\d+)</strong>', prono_snip)
            if nums:
                pronostics_by_coursenum[cnum] = [int(n) for n in nums[:5]]

    # Construire la liste de courses
    courses = []
    for row in course_rows:
        num_str, nom, prix_raw, heure_str, dist_raw, nb_str, disc_raw = row
        num    = int(num_str)
        prix_clean = re.sub(r'[^\d]', '', prix_raw.replace('&nbsp;', ''))
        prix   = int(prix_clean) if prix_clean else 0
        dist_clean = re.sub(r'[^\d]', '', dist_raw.replace('&nbsp;', ''))
        dist   = int(dist_clean) if dist_clean else 0
        disc   = _disc_norm(disc_raw)
        ts_ms  = _heure_ts(heure_str.strip(), ddmmyyyy)

        # Statut PMU depuis l'heure
        now_ms = int(datetime.now().timestamp() * 1000)
        if ts_ms > 0 and ts_ms < now_ms - 3600000:
            statut = 'ARRIVEE_DEFINITIVE_COMPLETE'
        else:
            statut = 'PROGRAMME'

        courses.append({
            'numReunion':             1,            # sera mis à jour par réunion
            'numOrdre':               num,
            'libelle':                nom,
            'libelleCourt':           nom[:25],
            'heureDepart':            ts_ms,
            'heureStr':               heure_str.strip(),
            'distance':               dist,
            'discipline':             disc,
            'specialite':             _specialite(disc),
            'montantPrix':            prix,
            'nombreDeclaresPartants': int(nb_str),
            'statut':                 statut,
            'isQuinte':               False,
            'pronosticZT':            pronostics_by_coursenum.get(num, []),
            'participants':           [],
            'participantsLoaded':     False,
        })

    # Marquer le Quinté (présence de l'ancre 'quinte' → course numéro associé)
    quinte_num = anchor_to_coursenum.get('quinte')
    for c in courses:
        if quinte_num and c['numOrdre'] == quinte_num:
            c['isQuinte'] = True

    # Assigner les courses à la réunion active
    if active_slug in reunions_meta:
        num_r = reunions_meta[active_slug]['numOfficiel']
        for c in courses:
            c['numReunion'] = num_r
        reunions_meta[active_slug]['courses'] = courses
    elif courses and reunions_meta:
        first_key = list(reunions_meta.keys())[0]
        num_r = reunions_meta[first_key]['numOfficiel']
        for c in courses:
            c['numReunion'] = num_r
        reunions_meta[first_key]['courses'] = courses

    # ── 3. Convertir en format Flutter PmuReunion.fromJson ───────────────────
    result = []
    for slug, r in reunions_meta.items():
        flutter_r = {
            'numOfficiel': r['numOfficiel'],
            'hippodrome': {
                'libelleCourt': r['hippodrome'],
                'libelleLong':  r['hippodrome'],
                'code':         slug,
            },
            'courses':  r['courses'],
            'slug':     slug,
            'isFrench': r['isFrench'],
            'dateStr':  r['dateStr'],
            'heureStr': r['heureStr'],
        }
        result.append(flutter_r)

    return result

# ─── Parser pronostics d'une page réunion ─────────────────────────────────────

def parse_pronostics_reunion(html):
    """
    Parse les pronostics Zone-Turf depuis une page de réunion.
    Retourne: {numOrdre: [num1, num2, num3, num4, num5]}
    """
    result = {}
    anchor_course_map = re.findall(
        r'(?:name|id)="(quinte|\d{7})".*?R1 Course N°(\d+)',
        html, re.DOTALL
    )
    for anchor, cnum in anchor_course_map:
        idx = html.find(f'name="{anchor}"')
        if idx < 0:
            idx = html.find(f'id="{anchor}"')
        if idx < 0:
            continue
        snip = html[idx:idx+20000]
        prono_idx = snip.find('Retrouvez les chevaux du jour')
        if prono_idx >= 0:
            prono_snip = snip[prono_idx:prono_idx+2000]
            nums = re.findall(r'<strong>(\d+)</strong>', prono_snip)
            if nums:
                result[int(cnum)] = [int(n) for n in nums[:5]]
    return result

# ─── Parser COMPLET ZtReunion (nouveau format Flutter) ────────────────────────

def _parse_partants_from_section(section):
    """Extrait les partants d'une section HTML d'une course."""
    partants = []
    tr_blocks = re.split(r'<tr[\s>]', section)
    chevaux_vus = set()

    for tr in tr_blocks:
        if '/cheval/' not in tr:
            continue

        # Numéro
        num_m = re.search(r'<td[^>]*>\s*<span>\s*(\d+)\s*</span>', tr)
        if not num_m:
            num_m = re.search(r'<span>\s*(\d+)\s*</span>', tr)
        num = num_m.group(1) if num_m else '?'

        # Cheval (dans title=)
        cheval_m = re.search(r'href="/cheval/[^"]*"\s+class="link"\s+title="([^"]+)"', tr)
        if not cheval_m:
            cheval_m = re.search(r'/cheval/[^"]*"[^>]*title="([^"]+)"', tr)
        cheval = cheval_m.group(1) if cheval_m else '?'

        if cheval == '?' or cheval in chevaux_vus:
            continue
        chevaux_vus.add(cheval)

        # Driver/Jockey
        drv_m = re.search(r'/(?:jockey|driver)/[^"]*"[^>]*title="([^"]+)"', tr)
        driver = drv_m.group(1) if drv_m else ''

        # Entraîneur
        ent_m = re.search(r'/entraineur/[^"]*"[^>]*title="([^"]+)"', tr)
        entraineur = ent_m.group(1) if ent_m else ''

        # Propriétaire
        prop_m = re.search(r'/proprietaire/[^"]*"[^>]*title="([^"]+)"', tr)
        proprietaire = prop_m.group(1) if prop_m else ''

        # Gains
        gains_all = re.findall(r'([\d\s]{3,})\s*€', tr)
        gains = gains_all[-1].strip().replace(' ', '') if gains_all else ''

        # Record
        rec_m = re.search(r"(\d'\d{2}[\"']?\d*)", tr)
        record = rec_m.group(1) if rec_m else ''

        # Musique
        tr_text = re.sub(r'<[^>]+>', ' ', tr)
        tr_text = re.sub(r'\s+', ' ', tr_text).strip()
        music_m = re.search(r'\b((?:(?:Da|Dm|\d+[amp])\s+){3,})', tr_text)
        musique = music_m.group(1).strip() if music_m else ''

        # Cote
        cote_m = re.search(r'class="[^"]*(?:cote|odds)[^"]*"[^>]*>([\d.,]+)<', tr, re.IGNORECASE)
        cote = cote_m.group(1) if cote_m else ''

        partants.append({
            'num': num,
            'cheval': cheval,
            'driver': driver,
            'entraineur': entraineur,
            'proprietaire': proprietaire,
            'gains': gains,
            'record': record,
            'musique': musique,
            'cote': cote,
            'age_sexe': '',
        })

    # Trier par numéro
    def _sort_key(p):
        try: return int(p['num'])
        except: return 999
    partants.sort(key=_sort_key)
    return partants


def parse_zt_reunions_full(main_html, ddmmyyyy):
    """
    Parse le programme complet depuis la page principale Zone-Turf.
    Pour chaque réunion française, fetch la page individuelle et extrait les partants.
    Retourne une liste de ZtReunion (nouveau format Flutter).
    """
    # 1. Trouver toutes les réunions sur la page principale
    reunion_links = re.findall(
        r'/programmes/(([rRzZ]\d+)-([^/]+)-(\d+))\.html',
        main_html
    )
    seen_ids = set()
    reunions_list = []
    for full_path, code, venue_slug, race_id in reunion_links:
        if race_id in seen_ids:
            continue
        seen_ids.add(race_id)
        venue = venue_slug.replace('-', ' ').title()
        code_upper = code.upper()
        is_french = _is_french(venue)
        # Détecter discipline depuis le venue slug
        disc = 'Plat'
        if 'vincennes' in venue_slug.lower():
            disc = 'Trot'
        elif 'cagnes' in venue_slug.lower():
            disc = 'Plat'
        reunions_list.append({
            'code': code_upper,
            'lieu': venue,
            'discipline': disc,
            'date': ddmmyyyy,
            'is_french': is_french,
            'slug': full_path,
            'url': f'https://www.zone-turf.fr/programmes/{full_path}.html',
            'courses': [],
        })

    # 2. Pour chaque réunion française, fetch sa page et parse les courses
    zt_reunions = []
    for r in reunions_list:
        if not r['is_french']:
            # Inclure les réunions étrangères sans partants
            zt_reunions.append({
                'code': r['code'],
                'lieu': r['lieu'],
                'discipline': r['discipline'],
                'date': r['date'],
                'courses': [],
            })
            continue

        print(f"[ZT] Fetching {r['code']} {r['lieu']}: {r['url']}")
        try:
            html = _fetch_html(r['url'])
            courses = _parse_courses_from_reunion_page(html, r)
            zt_reunions.append({
                'code': r['code'],
                'lieu': r['lieu'],
                'discipline': r['discipline'],
                'date': r['date'],
                'courses': courses,
            })
        except Exception as e:
            print(f"[ZT ERROR] {r['code']}: {e}")
            zt_reunions.append({
                'code': r['code'],
                'lieu': r['lieu'],
                'discipline': r['discipline'],
                'date': r['date'],
                'courses': [],
            })

    return zt_reunions


def _parse_courses_from_reunion_page(html, reunion_meta):
    """Parse une page de réunion Zone-Turf pour extraire courses + partants."""
    anchors = re.findall(r'name="(\d+|quinte)"', html)
    # Map ancre → numéro de course
    anchor_to_coursenum = {}
    course_headers = re.findall(
        r'name="(\d+|quinte)"[^>]*>.*?Course\s+N°(\d+)',
        html, re.DOTALL
    )
    for anc, cnum in course_headers:
        anchor_to_coursenum[anc] = int(cnum)

    courses_out = []
    for i, anchor in enumerate(anchors):
        pos1 = html.find(f'name="{anchor}"')
        pos2 = html.find(f'name="{anchors[i+1]}"', pos1+10) if i+1 < len(anchors) else len(html)
        section = html[pos1:pos2]

        # Numéro de course
        cnum = anchor_to_coursenum.get(anchor, i+1)

        # Nom de la course
        nom_m = re.search(r'Course\s+N°\d+[^:]*:\s*([^<\n]+)', section[:800])
        nom = _strip(nom_m.group(1))[:60] if nom_m else f'Course {cnum}'
        nom = re.sub(r'^[:\-\s]+', '', nom).strip()

        # Heure
        heure_m = re.search(r'(\d{2})h(\d{2})', section[:3000])
        heure = f"{heure_m.group(1)}:{heure_m.group(2)}" if heure_m else '?'

        # Distance
        dist_m = re.search(r'(\d[\d\s]{2,5})\s*m(?:\s|<|,)', section[:2000])
        distance = dist_m.group(1).strip().replace(' ', '') + 'm' if dist_m else '?'

        # Prix
        prix_m = re.search(r'([\d\s]{4,})\s*€', section[:2000])
        prix = prix_m.group(0).strip().replace(' ', '') if prix_m else '?'

        # Type
        type_m = re.search(r'\b(Plat|Haies|Steeple|Attelé|Monté|Cross|Obstacle)\b', section[:2000], re.IGNORECASE)
        type_c = type_m.group(1) if type_m else reunion_meta.get('discipline', '')

        # Quinté
        is_quinte = (anchor == 'quinte')

        # Pronostic ZT
        prono_m = re.search(r'(?:Pronostic|Prono)[^:]*:\s*([\d\s,\-]+)', section[:5000], re.IGNORECASE)
        pronostic_zt = []
        if prono_m:
            nums = re.findall(r'\d+', prono_m.group(1)[:50])
            pronostic_zt = [int(n) for n in nums[:7]]

        # Partants
        partants = _parse_partants_from_section(section)

        courses_out.append({
            'num': cnum,
            'anchor': anchor,
            'nom': nom,
            'heure': heure,
            'distance': distance,
            'prix': prix,
            'type': type_c,
            'piste': '',
            'categorie': '',
            'is_quinte': is_quinte,
            'pronostic_zt': pronostic_zt,
            'partants': partants,
        })

    return courses_out


# ─── Handler HTTP ─────────────────────────────────────────────────────────────

class ProxyHandler(http.server.SimpleHTTPRequestHandler):

    def log_message(self, fmt, *args):
        msg = fmt % args if args else fmt
        if '/api/' in str(msg):
            print(f'[PROXY] {msg}')

    def send_cors_headers(self):
        for k, v in CORS_HEADERS.items():
            self.send_header(k, v)

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_cors_headers()
        self.end_headers()

    def do_GET(self):
        if self.path.startswith('/api/zt/'):
            self._handle_zt()
        elif self.path.startswith('/api/pmu/'):
            self._handle_pmu()
        else:
            super().do_GET()

    def end_headers(self):
        self.send_cors_headers()
        super().end_headers()

    # ── JSON helpers ──────────────────────────────────────────────────────────

    def _json(self, data, status=200):
        body = json.dumps(data, ensure_ascii=False).encode('utf-8')
        self.send_response(status)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(body)))
        self.send_cors_headers()
        self.end_headers()
        self.wfile.write(body)

    def _err(self, msg, status=500):
        self._json({'error': msg}, status)

    # ── Route /api/zt/* ───────────────────────────────────────────────────────

    def _handle_zt(self):
        path = self.path[len('/api/zt/'):]
        try:
            # ── GET /api/zt/programme/<date> ──────────────────────────────
            m = re.match(r'^programme/(\d{8})', path)
            if m:
                self._zt_programme(m.group(1))
                return

            # ── GET /api/zt/participants/<date>/<R>/<C> ───────────────────
            m = re.match(r'^participants/(\d{8})/(\d+)/(\d+)', path)
            if m:
                self._zt_participants(m.group(1), int(m.group(2)), int(m.group(3)))
                return

            # ── GET /api/zt/pronostics/<slug> ─────────────────────────────
            m = re.match(r'^pronostics/(.+)$', path)
            if m:
                self._zt_pronostics(m.group(1))
                return

            self._err(f'Route inconnue: {path}', 404)

        except urllib.error.HTTPError as e:
            print(f'[ZT HTTP {e.code}] {e.url}')
            self._err(f'Zone-Turf HTTP {e.code}', 502)
        except urllib.error.URLError as e:
            print(f'[ZT URL ERROR] {e.reason}')
            self._err(f'Zone-Turf injoignable: {e.reason}', 502)
        except Exception as e:
            import traceback; traceback.print_exc()
            self._err(str(e), 500)

    def _zt_programme(self, ddmmyyyy):
        """
        Retourne le programme complet du jour depuis Zone-Turf.
        Format dual : ancien format PMU + nouveau format ZtReunion pour Flutter.
        """
        url  = _date_to_zt_url(ddmmyyyy)
        print(f'[ZT] Programme {ddmmyyyy} → {url}')
        html = _fetch_html(url)

        # Nouveau format ZtReunion (pour ZoneTurfService Flutter)
        zt_reunions = parse_zt_reunions_full(html, ddmmyyyy)

        # Ancien format PMU pour compatibilité
        reunions_pmu = parse_programme_zt(html, ddmmyyyy)

        self._json({
            'reunions':   zt_reunions,        # ← nouveau format ZtReunion
            'programme':  {'reunions': reunions_pmu},  # ← ancien format PMU
            'source':    'zone-turf.fr',
            'date':      ddmmyyyy,
            'nbReunions': len(zt_reunions),
        })

    def _zt_participants(self, ddmmyyyy, num_r, num_c):
        """
        Retourne les participants via PMU API officielle.
        Enrichit avec les pronostics Zone-Turf si dispo en cache.
        """
        pmu_url = f'{PMU_BASE}/programme/{ddmmyyyy}/R{num_r}/C{num_c}/participants?{PMU_SPEC}'
        print(f'[PMU] Participants R{num_r}C{num_c} → {pmu_url}')

        data = _fetch_json(pmu_url)
        participants = (data.get('participants') or [])

        # Filtrer les non-partants
        partants = [p for p in participants if p.get('statut') != 'NON_PARTANT']
        partants.sort(key=lambda p: p.get('numPmu') or p.get('numero') or 0)

        print(f'[PMU] R{num_r}C{num_c}: {len(partants)} partants réels')
        self._json({
            'participants': partants,
            'count':        len(partants),
            'source':       'pmu-api',
        })

    def _zt_pronostics(self, slug):
        """
        Retourne les pronostics Zone-Turf pour une réunion.
        """
        url  = f'{ZT_BASE}/programmes/{slug}.html'
        print(f'[ZT] Pronostics {slug} → {url}')
        html = _fetch_html(url)
        pronos = parse_pronostics_reunion(html)
        self._json({
            'pronostics': pronos,
            'source':     'zone-turf.fr',
            'slug':       slug,
        })

    # ── Route /api/pmu/* (proxy legacy) ──────────────────────────────────────

    def _handle_pmu(self):
        pmu_path = self.path[len('/api/pmu'):]
        sep      = '&' if '?' in pmu_path else '?'
        pmu_url  = f'{PMU_BASE}{pmu_path}{sep}{PMU_SPEC}'
        print(f'[PMU PROXY] → {pmu_url}')
        try:
            req = urllib.request.Request(pmu_url, headers=PMU_HEADERS)
            with urllib.request.urlopen(req, timeout=20) as resp:
                body = resp.read()
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(body)))
            self.send_cors_headers()
            self.end_headers()
            self.wfile.write(body)
        except urllib.error.HTTPError as e:
            body = json.dumps({'error': f'PMU HTTP {e.code}'}).encode()
            self.send_response(e.code)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(body)))
            self.send_cors_headers()
            self.end_headers()
            self.wfile.write(body)
        except Exception as e:
            body = json.dumps({'error': str(e)}).encode()
            self.send_response(502)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(body)))
            self.send_cors_headers()
            self.end_headers()
            self.wfile.write(body)


# ─── Main ─────────────────────────────────────────────────────────────────────

if __name__ == '__main__':
    web_dir = os.path.dirname(os.path.abspath(__file__))
    os.chdir(web_dir)
    socketserver.TCPServer.allow_reuse_address = True
    print(f'🚀 Pronostic Hippique Proxy (Hybride ZT+PMU) — Port {PORT}')
    print(f'   GET /api/zt/programme/<ddmmyyyy>          → Programme Zone-Turf')
    print(f'   GET /api/zt/participants/<date>/<R>/<C>   → Partants PMU API')
    print(f'   GET /api/zt/pronostics/<slug>             → Pronostics Zone-Turf')
    print(f'   GET /api/pmu/<path>                       → Proxy PMU direct')
    print()
    with socketserver.TCPServer(('0.0.0.0', PORT), ProxyHandler) as httpd:
        httpd.serve_forever()
