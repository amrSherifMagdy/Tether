// Controller key for this browser (Ed25519). The private seed stays in this browser's localStorage.
import * as ed from 'https://cdn.jsdelivr.net/npm/@noble/ed25519@2.1.0/+esm';

const b64 = (u8) => btoa(String.fromCharCode(...u8));
const unb64 = (s) => Uint8Array.from(atob(s), (c) => c.charCodeAt(0));

export async function identity() {
  let seed = localStorage.getItem('lk_controller_seed');
  if (!seed) {
    seed = b64(crypto.getRandomValues(new Uint8Array(32)));
    localStorage.setItem('lk_controller_seed', seed);
  }
  const priv = unb64(seed);
  const pub = await ed.getPublicKeyAsync(priv);
  return { priv, pubBytes: pub, pub: b64(pub) };
}

/** Short code compared on the laptop: AB12-CD34 */
export async function fingerprint(pubBytes) {
  const h = new Uint8Array(await crypto.subtle.digest('SHA-256', pubBytes));
  const x = [...h.slice(0, 4)].map((b) => b.toString(16).padStart(2, '0')).join('').toUpperCase();
  return x.slice(0, 4) + '-' + x.slice(4);
}

/** Signs exactly: id|session_id|ts|payload (the laptop verifies these bytes). */
export async function signAction(idn, id, sid, ts, payload) {
  const msg = new TextEncoder().encode(`${id}|${sid}|${ts}|${payload}`);
  return b64(await ed.signAsync(msg, idn.priv));
}
