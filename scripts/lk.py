#!/usr/bin/env python3
"""Assistant-side client for Tether session mode on Supabase (no browser UI).
Same login and same row level security as the web console. Credentials are read from two files
(LK_USER_FILE, LK_PASS_FILE), never printed. Needs LK_SUPABASE_URL and LK_SUPABASE_KEY (the public anon key).

  lk.py send '<action json>' [--wait SECS]   submit one action (may include "then": [...]), wait for result, save frame
  lk.py frame                                just save the latest frame
  lk.py pair                                 register this controller's key; prints the code to compare on the laptop
Every action is signed with this controller's Ed25519 key (LK_KEY_FILE, default ~/.lk/controller.seed, created on first use).
The laptop only runs actions from controllers approved there once (Allow button in the red bar). Needs the `cryptography` package.
Output: one result line, and the frame path /tmp/lk_frame.jpg
"""
import base64, hashlib, json, os, sys, time, uuid, urllib.parse, urllib.request, urllib.error
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives import serialization as _S

# Public values (safe to embed): the project URL and the publishable (anon) key.
URL = os.environ.get('LK_SUPABASE_URL', 'https://ymtahnystphyueoqgqko.supabase.co').rstrip('/')
KEY = os.environ.get('LK_SUPABASE_KEY', 'sb_publishable_nMT4XsdfthMBja2WMCVckA_ng6uf1pq')

_conn = None

def http(path, body=None, token=None, method=None, prefer=None):
    """One reused HTTPS connection (keep-alive): no new TCP/TLS handshake per request."""
    global _conn
    import http.client
    h = {'apikey': KEY, 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + (token or KEY)}
    if prefer: h['Prefer'] = prefer
    data = None if body is None else json.dumps(body).encode()
    m = method or ('GET' if data is None else 'POST')
    host = urllib.parse.urlparse(URL).netloc
    for attempt in (0, 1):
        try:
            if _conn is None: _conn = http.client.HTTPSConnection(host, timeout=30)
            _conn.request(m, urllib.parse.urlparse(URL).path + path, body=data, headers=h)
            r = _conn.getresponse(); raw = r.read()
            break
        except (http.client.HTTPException, OSError):
            try: _conn.close()
            except Exception: pass
            _conn = None
            if attempt: raise
    if r.status >= 400: raise SystemExit(f'HTTP {r.status}: {raw.decode()[:400]}')
    return json.loads(raw) if raw else None

def login():
    tf = '/tmp/lk_token.json'
    try:
        t = json.load(open(tf))
        if t['exp'] > time.time() + 120: return t['token']
    except Exception: pass
    u = open(os.environ['LK_USER_FILE']).read().strip(); p = open(os.environ['LK_PASS_FILE']).read().strip()
    r = http('/auth/v1/token?grant_type=password', {'email': u, 'password': p})
    json.dump({'token': r['access_token'], 'exp': time.time() + min(r.get('expires_in', 3600), 3000)}, open(tf, 'w')); os.chmod(tf, 0o600)
    return r['access_token']

KEYFILE = os.environ.get('LK_KEY_FILE', os.path.expanduser('~/.lk/controller.seed'))

def key():
    try: seed = base64.b64decode(open(KEYFILE).read().strip())
    except FileNotFoundError:
        seed = os.urandom(32); os.makedirs(os.path.dirname(KEYFILE), exist_ok=True)
        fd = os.open(KEYFILE, os.O_WRONLY | os.O_CREAT, 0o600); os.write(fd, base64.b64encode(seed)); os.close(fd)
    k = Ed25519PrivateKey.from_private_bytes(seed)
    pub = k.public_key().public_bytes(_S.Encoding.Raw, _S.PublicFormat.Raw)
    return k, base64.b64encode(pub).decode(), hashlib.sha256(pub).hexdigest()[:8].upper()

def register(tok):
    """Make sure this key is registered as a controller (a request only: the laptop decides). Returns (controller_id, code)."""
    k, pub, fp = key()
    rows = http('/rest/v1/controllers?public_key=eq.' + urllib.parse.quote(pub) + '&select=id', token=tok)
    if rows: cid = rows[0]['id']
    else: cid = http('/rest/v1/controllers', {'name': 'Instinct assistant', 'public_key': pub}, tok, 'POST', 'return=representation')[0]['id']
    return cid, f'{fp[:4]}-{fp[4:]}'

CACHE = os.path.expanduser('~/.lk/cache.json')

def cached(name, ttl, fetch):
    """Small file cache so repeated actions skip lookups (session id, controller id)."""
    try:
        c = json.load(open(CACHE))
    except Exception:
        c = {}
    e = c.get(name)
    if e and time.time() - e['t'] < ttl: return e['v']
    v = fetch()
    c[name] = {'t': time.time(), 'v': v}
    os.makedirs(os.path.dirname(CACHE), exist_ok=True)
    json.dump(c, open(CACHE, 'w')); os.chmod(CACHE, 0o600)
    return v

def forget(name):
    try:
        c = json.load(open(CACHE)); c.pop(name, None); json.dump(c, open(CACHE, 'w'))
    except Exception: pass

def session(tok):
    rows = http('/rest/v1/sessions?status=eq.active&order=created_at.desc&limit=1', token=tok)
    if not rows: raise SystemExit('NO ACTIVE SESSION')
    return rows[0]['id'], rows[0].get('expires_at') or 'none (no time limit)'

def frame(tok, sid, aid=None, delete=True):
    rows = []
    for _ in range(10):
        rows = http(f'/rest/v1/frames?session_id=eq.{sid}', token=tok)
        if rows and (aid is None or rows[0].get('action_id') == aid): break
        time.sleep(0.1)
    if not rows: print('no frame yet'); return
    d = rows[0]
    open('/tmp/lk_frame.jpg', 'wb').write(base64.b64decode(d['image_b64']))
    print('frame saved /tmp/lk_frame.jpg', f"{d['width']}x{d['height']}", 'captured', d['captured_at'], 'action', d.get('action_id') or '')
    if delete: http(f'/rest/v1/frames?session_id=eq.{sid}', token=tok, method='DELETE')   # transient: remove the cloud copy now

def main():
    a = sys.argv[1:]
    if not a: raise SystemExit(__doc__)
    tok = login()
    if a[0] == 'pair':
        cid, code = register(tok)
        print(f'controller {cid} registered. Code to compare on the laptop: {code}. Approve it with Allow in the red bar.'); return
    if a[0] == 'frame':
        sid, exp = session(tok)
        print('session', sid, 'expires', exp)
        return frame(tok, sid)
    sid = cached('sid', 120, lambda: session(tok)[0])
    cid = cached('cid:' + key()[1], 3600, lambda: register(tok)[0])
    code = key()[2]; code = f'{code[:4]}-{code[4:]}'
    act = json.loads(a[1]); typ = act.pop('type')
    wait = float(a[a.index('--wait') + 1]) if '--wait' in a else 40
    t0 = time.time()
    k = key()[0]

    def submit(sid):
        aid = str(uuid.uuid4()); ts = int(time.time())
        payload = json.dumps({'type': typ, 'params': act}, separators=(',', ':'))
        sig = base64.b64encode(k.sign(f'{aid}|{sid}|{ts}|{payload}'.encode())).decode()
        http('/rest/v1/actions', {'id': aid, 'session_id': sid, 'type': typ, 'params': act, 'controller_id': cid,
                                  'payload': payload, 'sig': sig, 'sig_ts': ts}, tok, 'POST')
        return aid

    def cleanup(aid, also_frame):
        # Fire and forget in a child process: the cloud copies are removed without making the caller wait.
        try:
            if os.fork() == 0:
                try:
                    http(f'/rest/v1/actions?id=eq.{aid}', token=tok, method='DELETE')
                    if also_frame: http(f'/rest/v1/frames?session_id=eq.{sid}', token=tok, method='DELETE')
                finally:
                    os._exit(0)
        except Exception: pass

    aid = submit(sid)
    st = 'pending'; rechecked = False
    while time.time() - t0 < wait:
        f = http(f'/rest/v1/actions?id=eq.{aid}&select=status,result', token=tok)[0]
        st = f['status']
        if st == 'rejected' and 'controller' in (f.get('result') or ''):
            print(f"rejected: {f['result']}. Code of this controller: {code}. Approve it on the laptop (Allow in the red bar), then retry.")
            forget('cid:' + key()[1]); cleanup(aid, False); return
        if st in ('done', 'failed', 'rejected'):
            print(f"{st} in {time.time()-t0:.1f}s:", f.get('result') or '')
            if st == 'done': frame(tok, sid, aid, delete=False)
            cleanup(aid, st == 'done')
            return
        if st == 'pending' and not rechecked and time.time() - t0 > 6:
            # Nobody picked it up: the cached session may be old. Look it up fresh and resend once.
            rechecked = True
            forget('sid'); sid2 = session(tok)[0]
            if sid2 != sid:
                http(f'/rest/v1/actions?id=eq.{aid}', token=tok, method='DELETE')
                sid = sid2; cached('sid', 0, lambda: sid); aid = submit(sid)
        time.sleep(0.05)
    print(f'timeout after {wait}s (still {st})')

if __name__ == "__main__":
    main()
