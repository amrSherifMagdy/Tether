#!/usr/bin/env python3
"""Two-account isolation test for Tether on Supabase.
Env: LK_SUPABASE_URL, LK_SUPABASE_KEY, A_USER_FILE, A_PASS_FILE, B_USER_FILE, B_PASS_FILE.
Creates one temporary session for user A, tries to break the rules as B and as A, then stops the session.
Prints PASS/FAIL per check. Never prints credentials."""
import json, os, sys, urllib.request, urllib.error
URL = os.environ['LK_SUPABASE_URL'].rstrip('/'); KEY = os.environ['LK_SUPABASE_KEY']

def call(path, body=None, tok=None, method=None, prefer=None):
    h = {'apikey': KEY, 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + (tok or KEY)}
    if prefer: h['Prefer'] = prefer
    r = urllib.request.Request(URL + path, data=None if body is None else json.dumps(body).encode(), headers=h, method=method)
    try:
        with urllib.request.urlopen(r, timeout=30) as f:
            raw = f.read(); return f.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try: return e.code, json.loads(raw)
        except Exception: return e.code, raw

def login(uf, pf):
    s, r = call('/auth/v1/token?grant_type=password', {'email': open(os.environ[uf]).read().strip(), 'password': open(os.environ[pf]).read().strip()})
    if s != 200: sys.exit(f'login failed for {uf}: {s}')
    return r['access_token'], r['user']['id']

A, ua = login('A_USER_FILE', 'A_PASS_FILE'); B, ub = login('B_USER_FILE', 'B_PASS_FILE')
fails = 0
def check(name, ok):
    global fails
    print(('PASS ' if ok else 'FAIL ') + name)
    if not ok: fails += 1

assert ua != ub, 'A and B must be different users'
s, r = call('/rest/v1/sessions', {'status': 'active'}, A, 'POST', 'return=representation'); check('A creates a session', s == 201)
sid = r[0]['id']
s, r = call('/rest/v1/actions', {'session_id': sid, 'type': 'screenshot', 'params': {}}, A, 'POST', 'return=representation'); check('A creates an action in own session', s == 201)
aid = r[0]['id']
s, r = call('/rest/v1/frames', {'session_id': sid, 'image_b64': 'AAAA', 'width': 1, 'height': 1}, A, 'POST'); check('A uploads a frame', s == 201)

for t in ('sessions', 'actions', 'frames'):
    s, r = call(f'/rest/v1/{t}?select=*', tok=B); check(f'B sees none of A\'s {t}', s == 200 and r == [])
s, r = call('/rest/v1/actions', {'session_id': sid, 'type': 'screenshot', 'params': {}}, B, 'POST'); check('B cannot add an action to A\'s session', s >= 400)
s, r = call(f'/rest/v1/sessions?id=eq.{sid}', {'status': 'stopped'}, B, 'PATCH', 'return=representation'); check('B cannot stop A\'s session', s >= 400 or r == [])
s, r = call(f'/rest/v1/actions?id=eq.{aid}', {'status': 'running'}, B, 'PATCH', 'return=representation'); check('B cannot claim A\'s action', s >= 400 or r == [])
s, r = call(f'/rest/v1/frames?session_id=eq.{sid}', {'image_b64': 'BBBB'}, B, 'PATCH', 'return=representation'); check('B cannot overwrite A\'s frame', s >= 400 or r == [])
s, r = call('/rest/v1/frames', {'session_id': sid, 'image_b64': 'x', 'width': 1, 'height': 1}, B, 'POST'); check('B cannot create a frame in A\'s session', s >= 400)

s, r = call(f'/rest/v1/actions?id=eq.{aid}', {'status': 'done'}, A, 'PATCH', 'return=representation'); check('A cannot skip pending -> done', s >= 400)
s, r = call(f'/rest/v1/actions?id=eq.{aid}', {'type': 'click'}, A, 'PATCH', 'return=representation'); check('A cannot change a request after creating it', s >= 400)
s, r = call(f'/rest/v1/actions?id=eq.{aid}', {'user_id': ub}, A, 'PATCH', 'return=representation'); check('A cannot hand the action to another user', s >= 400)
s, r = call('/rest/v1/actions', {'session_id': sid, 'type': 'shell', 'params': {}}, A, 'POST'); check('A cannot use an unknown action type', s >= 400)
s, r = call(f'/rest/v1/actions?id=eq.{aid}', {'status': 'running'}, A, 'PATCH', 'return=representation'); check('A can claim own pending action', s == 200 and len(r) == 1)
s, r = call(f'/rest/v1/actions?id=eq.{aid}&status=eq.pending', {'status': 'running'}, A, 'PATCH', 'return=representation'); check('a second claim finds nothing', s == 200 and r == [])
s, r = call('/rest/v1/sessions', {'status': 'active', 'expires_at': '2999-01-01T00:00:00Z', 'duration_minutes': 5}, A, 'POST'); check('A cannot make a far-future expiry', s >= 400)

s, r = call(f'/rest/v1/sessions?id=eq.{sid}', {'status': 'stopped'}, A, 'PATCH', 'return=representation'); check('A stops own session', s == 200 and len(r) == 1)
s, r = call('/rest/v1/actions', {'session_id': sid, 'type': 'screenshot', 'params': {}}, A, 'POST'); check('no new actions in a stopped session', s >= 400)
import base64 as _b
s, r = call('/rest/v1/controllers', {'name': 'iso-test', 'public_key': _b.b64encode(b'\x01' * 32).decode()}, A, 'POST', 'return=representation'); check('A registers a controller (pairing request)', s == 201)
cid = r[0]['id'] if s == 201 else None
s, r = call('/rest/v1/controllers?select=*', tok=B); check('B sees none of A\'s controllers', s == 200 and r == [])
s, r = call('/rest/v1/controllers', {'name': 'x', 'public_key': 'short'}, A, 'POST'); check('A cannot register a malformed key', s >= 400)
s, r = call(f'/rest/v1/controllers?id=eq.{cid}', {'name': 'renamed'}, A, 'PATCH', 'return=representation'); check('nobody can edit a controller row', s >= 400 or r == [])
s, r = call(f'/rest/v1/controllers?id=eq.{cid}', tok=B, method='DELETE'); check('B cannot delete A\'s controller', True)
s, r = call(f'/rest/v1/controllers?id=eq.{cid}&select=id', tok=A); check('...and it is still there', s == 200 and len(r) == 1)
call(f'/rest/v1/controllers?id=eq.{cid}', tok=A, method='DELETE')
print('FAILED' if fails else 'ALL PASSED'); sys.exit(1 if fails else 0)
