#!/usr/bin/env python3
"""
Pronostic Hippique — Serveur combiné Flutter Web + Proxy API
Port unique 5060 : sert les fichiers Flutter ET les routes /api/*
"""

import http.server
import socketserver
import socket
import urllib.request
import urllib.error
import gzip
import re
import json
import os
import sys
from datetime import datetime

PORT = 5060
WEB_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'build', 'web')
PMU_BASE = 'https://turfinfo.api.pmu.fr/rest/client/7'
PMU_SPEC = 'specialisation=INTERNET'
ZT_BASE  = 'https://www.zone-turf.fr'

CORS_HEADERS = {
    'Access-Control-Allow-Origin':  '*',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Accept',
    'X-Frame-Options':              'ALLOWALL',
    'Content-Security-Policy':      "frame-ancestors *; default-src * 'unsafe-inline' 'unsafe-eval' data: blob:",
}

ZT_HEADERS = {
    'User-Agent':      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
    'Accept':          'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
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
        raw = r.read()
        enc = r.headers.get('Content-Encoding', '')
        if enc == 'gzip':
            raw = gzip.decompress(raw)
        return raw.decode('utf-8', errors='replace')

def _fetch_json(url):
    req = urllib.request.Request(url, headers=PMU_HEADERS)
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.loads(r.read().decode('utf-8', errors='replace'))

def _date_to_zt_url(ddmmyyyy):
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
    if 'MONTÉ' in r or 'MONTE' in r:   return 'TROT_MONTE'
    if 'ATTELÉ' in r or 'ATTELE' in r: return 'ATTELE'
    if 'PLAT' in r:                     return 'PLAT'
    if 'HAIE' in r:                     return 'HAIE'
    if 'STEEPLE' in r:                  return 'STEEPLECHASE'
    return raw.strip()

def _specialite(disc):
    if disc in ('ATTELE', 'TROT_MONTE'): return 'TROT'
    if disc in ('HAIE', 'STEEPLECHASE', 'CROSS'): return 'OBSTACLE'
    return 'PLAT'

def _is_french(lieu):
    foreign = ['Aus ','Gb ','USA ','Arg ','SAF ','UAE ','CHL ','Be ','HOL ',
               'IRE ','GER ','ITA ','SWE ','Wolvega','Aintree','Gulfstream',
               'Randwick','Caulfield','Perth','Greyville','Santiago','Geelong',
               'Murray','Cranbourne','Gold Coast','Abu Dhabi','Fonner',
               'San Isidro','Chile','Mons','Wolverhampton','Fairview','Al Ain',
               'Funabashi','Dayton','Penn National','Pinjarra','Taunton','Aby','Vaal']
    lieu_up = lieu.upper()
    return not any(f.upper() in lieu_up for f in foreign)

# ─── Parser partants ──────────────────────────────────────────────────────────

def _parse_partants(section):
    partants = []
    tr_blocks = re.split(r'<tr[\s>]', section)
    chevaux_vus = set()

    for tr in tr_blocks:
        if '/cheval/' not in tr:
            continue
        num_m = re.search(r'<span>\s*(\d+)\s*</span>', tr)
        num = num_m.group(1) if num_m else '?'

        cheval_m = re.search(r'/cheval/[^"]*"\s+class="link"\s+title="([^"]+)"', tr)
        if not cheval_m:
            cheval_m = re.search(r'/cheval/[^"]*"[^>]*title="([^"]+)"', tr)
        cheval = cheval_m.group(1) if cheval_m else '?'

        if cheval == '?' or cheval in chevaux_vus:
            continue
        chevaux_vus.add(cheval)

        drv_m = re.search(r'/(?:jockey|driver)/[^"]*"[^>]*title="([^"]+)"', tr)
        driver = drv_m.group(1) if drv_m else ''

        ent_m = re.search(r'/entraineur/[^"]*"[^>]*title="([^"]+)"', tr)
        entraineur = ent_m.group(1) if ent_m else ''

        prop_m = re.search(r'/proprietaire/[^"]*"[^>]*title="([^"]+)"', tr)
        proprietaire = prop_m.group(1) if prop_m else ''

        gains_all = re.findall(r'([\d\s]{3,})\s*€', tr)
        gains = gains_all[-1].strip().replace(' ', '') if gains_all else ''

        rec_m = re.search(r"(\d'\d{2}[\"']?\d*)", tr)
        record = rec_m.group(1) if rec_m else ''

        tr_text = re.sub(r'<[^>]+>', ' ', tr)
        tr_text = re.sub(r'\s+', ' ', tr_text).strip()
        music_m = re.search(r'\b((?:(?:Da|Dm|\d+[amp])\s+){3,})', tr_text)
        musique = music_m.group(1).strip() if music_m else ''

        cote_m = re.search(r'class="[^"]*(?:cote|odds)[^"]*"[^>]*>([\d.,]+)<', tr, re.IGNORECASE)
        cote = cote_m.group(1) if cote_m else ''

        age_m = re.search(r'\b([HMFGhmfg]\d)\b', tr_text)
        age_sexe = age_m.group(1).upper() if age_m else ''

        partants.append({
            'num': num, 'cheval': cheval, 'driver': driver,
            'entraineur': entraineur, 'proprietaire': proprietaire,
            'gains': gains, 'record': record, 'musique': musique,
            'cote': cote, 'age_sexe': age_sexe,
        })

    partants.sort(key=lambda p: int(p['num']) if p['num'].isdigit() else 999)
    return partants

# ─── Parser réunion complète ──────────────────────────────────────────────────

def _parse_reunion_page(html, code, lieu, discipline, ddmmyyyy):
    """Parse une page de réunion ZT → liste de courses avec partants."""
    anchors = re.findall(r'name="(\d+|quinte)"', html)
    
    # Map ancre → numéro course
    anchor_map = {}
    for m in re.finditer(r'name="(\d+|quinte)".*?Course\s+N°(\d+)', html, re.DOTALL):
        anchor_map[m.group(1)] = int(m.group(2))

    courses = []
    for i, anchor in enumerate(anchors):
        pos1 = html.find(f'name="{anchor}"')
        pos2 = html.find(f'name="{anchors[i+1]}"', pos1+10) if i+1 < len(anchors) else len(html)
        section = html[pos1:pos2]

        cnum = anchor_map.get(anchor, i+1)

        nom_m = re.search(r'Course\s+N°\d+[^:]*:\s*([^<\n]+)', section[:800])
        nom = _strip(nom_m.group(1))[:60] if nom_m else f'Course {cnum}'
        nom = re.sub(r'^[:\-\s]+', '', nom).strip()

        heure_m = re.search(r'(\d{2})h(\d{2})', section[:3000])
        heure = f"{heure_m.group(1)}:{heure_m.group(2)}" if heure_m else '?'

        dist_m = re.search(r'(\d[\d\s]{1,5})\s*m(?:\s|<|,|&)', section[:2000])
        distance = (dist_m.group(1).strip().replace(' ', '').replace('\xa0', '') + 'm') if dist_m else '?'

        prix_m = re.search(r'([\d\s&;nbspa]{4,})\s*€', section[:2000])
        prix_raw = prix_m.group(0) if prix_m else '0'
        prix = re.sub(r'[^\d]', '', prix_raw.replace('&nbsp;', '').replace('&euro;', ''))
        if not prix: prix = '0'

        type_m = re.search(r'\b(Plat|Haies|Steeple|Attelé|Monté|Cross|Obstacle)\b',
                           section[:2000], re.IGNORECASE)
        type_c = type_m.group(1) if type_m else discipline

        is_quinte = (anchor == 'quinte')

        prono_m = re.search(r'(?:Pronostic|Prono)[^:]*:\s*([\d\s,\-]+)', section[:5000], re.IGNORECASE)
        pronostic_zt = []
        if prono_m:
            nums = re.findall(r'\d+', prono_m.group(1)[:50])
            pronostic_zt = [int(n) for n in nums[:7]]

        partants = _parse_partants(section)

        courses.append({
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

    return courses

# ─── Récupérer programme complet ─────────────────────────────────────────────

def get_programme(ddmmyyyy):
    """Récupère toutes les réunions françaises avec leurs courses et partants."""
    main_url = _date_to_zt_url(ddmmyyyy)
    print(f'[ZT] Programme {ddmmyyyy} → {main_url}')
    main_html = _fetch_html(main_url)

    # Trouver les liens de réunions
    reunion_links = re.findall(
        r'/programmes/(([rRzZ]\d+)-([^/]+)-(\d+))\.html',
        main_html
    )

    seen_ids = set()
    reunions = []
    for full_path, code_dash, venue_slug, race_id in reunion_links:
        if race_id in seen_ids:
            continue
        seen_ids.add(race_id)

        code = re.match(r'[rRzZ]\d+', full_path)
        code_str = code.group(0).upper() if code else full_path[:3].upper()
        lieu = venue_slug.replace('-', ' ').title()
        is_french = _is_french(lieu)

        disc = 'Plat'
        slug_low = venue_slug.lower()
        if 'vincennes' in slug_low:
            disc = 'Trot'
        elif 'pau' in slug_low:
            disc = 'Obstacle'

        r_url = f'https://www.zone-turf.fr/programmes/{full_path}.html'

        if not is_french:
            # Exclure complètement les réunions étrangères
            continue

        print(f'[ZT] Fetching {code_str} {lieu}: {r_url}')
        try:
            html = _fetch_html(r_url)
            courses = _parse_reunion_page(html, code_str, lieu, disc, ddmmyyyy)
            reunions.append({'code': code_str, 'lieu': lieu, 'discipline': disc,
                             'date': ddmmyyyy, 'courses': courses})
            print(f'[ZT] {code_str} {lieu}: {len(courses)} courses, '
                  f'{sum(len(c["partants"]) for c in courses)} partants')
        except Exception as e:
            print(f'[ZT ERROR] {code_str} {lieu}: {e}')
            reunions.append({'code': code_str, 'lieu': lieu, 'discipline': disc,
                             'date': ddmmyyyy, 'courses': []})

    return reunions

# ─── Handler HTTP ─────────────────────────────────────────────────────────────

class CombinedHandler(http.server.SimpleHTTPRequestHandler):

    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=WEB_DIR, **kwargs)

    def log_message(self, fmt, *args):
        msg = fmt % args if args else fmt
        if '/api/' in str(msg):
            print(f'[API] {msg}')

    def send_cors(self):
        for k, v in CORS_HEADERS.items():
            self.send_header(k, v)

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_cors()
        self.end_headers()

    def end_headers(self):
        self.send_cors()
        super().end_headers()

    def do_GET(self):
        if self.path.startswith('/api/'):
            self._handle_api()
        else:
            # Servir les fichiers Flutter
            super().do_GET()

    def _json(self, data, status=200):
        body = json.dumps(data, ensure_ascii=False).encode('utf-8')
        self.send_response(status)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(body)))
        self.send_cors()
        self.end_headers()
        self.wfile.write(body)

    def _err(self, msg, status=500):
        self._json({'error': msg}, status)

    def _handle_api(self):
        path = self.path[len('/api/'):]
        try:
            # ── /api/zt/programme/<ddmmyyyy> ──────────────────────
            m = re.match(r'^zt/programme/(\d{8})$', path)
            if m:
                ddmmyyyy = m.group(1)
                reunions = get_programme(ddmmyyyy)
                self._json({
                    'reunions':   reunions,
                    'source':     'zone-turf.fr',
                    'date':       ddmmyyyy,
                    'nbReunions': len(reunions),
                })
                return

            # ── /api/zt/participants/<date>/<R>/<C> ───────────────
            m = re.match(r'^zt/participants/(\d{8})/(\d+)/(\d+)$', path)
            if m:
                d, r, c = m.group(1), int(m.group(2)), int(m.group(3))
                pmu_url = f'{PMU_BASE}/programme/{d}/R{r}/C{c}/participants?{PMU_SPEC}'
                print(f'[PMU] Participants R{r}C{c}')
                data = _fetch_json(pmu_url)
                partants = [p for p in (data.get('participants') or [])
                            if p.get('statut') != 'NON_PARTANT']
                partants.sort(key=lambda p: p.get('numPmu', p.get('numero', 0)))
                self._json({'participants': partants, 'count': len(partants), 'source': 'pmu-api'})
                return

            # ── /api/pmu/<path> ───────────────────────────────────
            if path.startswith('pmu/'):
                pmu_path = path[3:]
                sep = '&' if '?' in pmu_path else '?'
                pmu_url = f'{PMU_BASE}{pmu_path}{sep}{PMU_SPEC}'
                req = urllib.request.Request(pmu_url, headers=PMU_HEADERS)
                with urllib.request.urlopen(req, timeout=20) as resp:
                    body = resp.read()
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.send_header('Content-Length', str(len(body)))
                self.send_cors()
                self.end_headers()
                self.wfile.write(body)
                return

            self._err(f'Route inconnue: {path}', 404)

        except urllib.error.HTTPError as e:
            print(f'[HTTP ERROR {e.code}] {e.url}')
            self._err(f'HTTP {e.code}', 502)
        except urllib.error.URLError as e:
            print(f'[URL ERROR] {e.reason}')
            self._err(f'Injoignable: {e.reason}', 502)
        except Exception as e:
            import traceback; traceback.print_exc()
            self._err(str(e), 500)


# ─── Main ─────────────────────────────────────────────────────────────────────

if __name__ == '__main__':
    if not os.path.exists(WEB_DIR):
        print(f'❌ Dossier build/web introuvable: {WEB_DIR}')
        sys.exit(1)

    socketserver.TCPServer.allow_reuse_address = True
    print(f'🚀 Pronostic Hippique — Serveur combiné Flutter+API — Port {PORT}')
    print(f'   📁 Fichiers web:  {WEB_DIR}')
    print(f'   🌐 App Flutter:   http://localhost:{PORT}/')
    print(f'   🔌 API Programme: http://localhost:{PORT}/api/zt/programme/DDMMYYYY')
    print()
    server = socketserver.TCPServer(('0.0.0.0', PORT), CombinedHandler)
    server.socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    with server:
        server.serve_forever()
