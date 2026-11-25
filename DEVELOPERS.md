# Tether: developer and owner guide

This page is for the person who builds, hosts and administers Tether. Using the app: see [README.md](README.md).

Tether lets **your own AI assistant** see your Windows laptop screen and use the mouse and keyboard, but only while you have the app open, only after you approved that exact assistant on the laptop, and with a way to stop it at any moment.

It is a Windows desktop app (Flutter) plus a small static web console, on top of a Supabase project (auth, database, realtime). The app never listens on a port, so nothing needs to be opened on your network.

Arabic notes: [README.ar.md](README.ar.md). End-user steps: [README.md](README.md).

## How it works

```
 assistant (lk.py)  --signed action-->  Supabase  --realtime-->  Tether app on the laptop
        ^                               (relay only)                  |
        +---------- screenshot  <-------------------------------------+
```

1. You open the app and sign in. A **session** starts. A green bar stays on top of the screen while it is live.
2. Your assistant submits one action at a time (screenshot, move, click, scroll, type, key, open_url, open_app, wait). Actions can be batched with `then`.
3. The app checks the action, runs it, takes a fresh screenshot (800 px wide JPEG) and uploads it. The assistant downloads it and the cloud copy is deleted.
4. **PAUSE** on the bar (or Pause in the tray menu) keeps the session and the pairing but makes the app refuse every action until you press **RESUME**. The bar turns grey while paused. Only the person at the laptop can resume.
5. The session has no time limit. It ends on **STOP**, on **Ctrl+Alt+Shift+S**, or when you close the app.

Typical round trip for one action is about 2 to 3 seconds. A batch of up to 16 actions costs about one round trip.

## Control modes

Pick the mode in the window (required on first run) or in the tray menu. Only the person at the laptop can change it. The choice is remembered.

| Mode | Behaviour |
|---|---|
| ASK | Asks before every click, typing, key press, opening a link and opening an app. Screenshots, waits, scrolling and moving the mouse never ask. |
| AUTO | Never asks. |
| SMART | Asks only for important actions (below). Everything else runs directly. |

Questions are shown and answered on the laptop only (an orange bar with Allow / Deny). **No answer in 60 seconds means Deny.** A denied step is not run and the assistant receives `rejected: denied ...`.

What SMART treats as important (best effort, based on the action and the title of the window in front, not on understanding the screen):

- Keys: Alt+F4, Ctrl+W, Ctrl+Q, Delete, Shift+Delete, Ctrl+Shift+Delete, Ctrl+Shift+Esc, Win+R, and Enter or Space when the window title mentions delete, remove, install, uninstall, purchase, payment, checkout, confirm, send, transfer, unsaved changes, administrator, password, format, reset and similar.
- Clicks in a window whose title mentions those same words.
- Typing: text that mentions passwords, PINs, OTP, CVV, seed phrases, secrets, or looks like a card number; destructive commands (rm -rf, del, format, shutdown, reg delete, PowerShell); typing in a sign-in or admin window.
- Opening links: plain http, download links (.exe, .msi, .zip, .bat, .ps1 and similar), bank, payment, checkout or account pages.
- Opening apps: PowerShell, cmd, terminal, regedit, installers, services, disk tools.

This is a safety net, not a guarantee. Use ASK when you want to see everything.

## Security model

- **Pairing is decided on the laptop only.** Each assistant has its own Ed25519 key. It registers a *request* in the cloud, the laptop shows a red card with a short code (like `AB12-CD34`), and you tap Allow only if the code matches the one your assistant told you. The approved list is stored in a local file on the laptop. The cloud cannot add to it.
- **Every action is signed** by an approved key. Unsigned or badly signed actions are rejected and logged.
- **Per-user isolation** with row level security: one account cannot read or write another account's sessions, actions or screenshots. `scripts/isolation_test.py` tries to break this and prints PASS or FAIL for each check.
- **Invite-only sign-up.** (Keep real emails out of the repo: `supabase/invites.sql` only has placeholders.) Only emails in the `invites` table can create an account. Email confirmation is required.
- **Transient cloud data.** A screenshot is deleted as soon as the assistant fetches it, after 60 seconds, and when the session ends. Actions are deleted after the result is read or after 10 minutes. A `pg_cron` job (`lk_cleanup`) runs every minute as a backstop. The full history exists only in the local log on the laptop (`laptop_link.log`).
- **No passwords are ever typed** by the assistant. Do not ask it to.
- **Limits you should know:** the Supabase project owner is the administrator of the relay and can see data while it passes through (screenshots live for seconds). The app is not code-signed, so Windows SmartScreen shows a warning on first run.
- The Supabase URL and the publishable key in the code are public by design. The service role key must never be put in the app, the site or this repo.

## Install (users, no Flutter needed)

1. Download `Tether-windows.zip` from the Releases page, unzip it, run `Tether.exe`. If Windows reports a missing DLL, install the Microsoft Visual C++ Redistributable (x64).
2. Read the first-run notice and tap "I understand".
3. Create an account inside the app with an invited email. Click the link in the confirmation email (it opens a page that says "Email confirmed"), then return to the app and sign in.
4. Pair your assistant (see below).

The app has an English / Arabic switch in the header. The choice is remembered.

## Pair an assistant

The assistant needs Python 3 and `pip install cryptography`, plus `scripts/lk.py` (also shipped as `assistant-kit.zip` in each release).

```
export LK_USER_FILE=/path/to/email.txt    # file with the account email
export LK_PASS_FILE=/path/to/password.txt # file with the account password (never put it in chat)
python3 scripts/lk.py pair
```

It prints a code. The Tether window on the laptop turns red with the same code. Tap **Allow** if they match, **Deny** if not. After one Allow the key is remembered. You can remove an approved device under Advanced > Approved devices.

## Drive the laptop

```
python3 scripts/lk.py frame
python3 scripts/lk.py send '{"type":"screenshot"}'
python3 scripts/lk.py send '{"type":"click","x":480,"y":270,"then":[{"type":"type","text":"hello"},{"type":"key","combo":"enter"}]}'
```

Coordinates are screenshot pixels. The latest screenshot is saved to `/tmp/lk_frame.jpg`. Action types and limits are in [ASSISTANT.md](ASSISTANT.md).

## Friends

A friend does not use the website.

1. The owner adds the friend's email to `invites` (see setup).
2. The friend installs the app, signs up and signs in inside the app.
3. The friend's own assistant uses the same email and password (given to it through a private vault link, never in chat), runs `lk.py pair`, and tells the friend the code in their own chat.
4. The friend compares the code with the red card on the laptop and taps Allow.

The friend can stop it with the STOP button or the hotkey, and can remove the assistant in Advanced.

## Owner setup (Supabase)

1. Create a Supabase project. In the SQL Editor run `supabase/schema.sql`, then `supabase/invites.sql` (edit the emails first).
2. Authentication > URL Configuration: set Site URL to your web console URL and add it under Redirect URLs.
3. Authentication > Providers > Email: keep "Confirm email" on.
4. Put the project URL and the publishable key in `lib/src/config.dart` and `site/config.js`.
5. To add a user later: `insert into invites(email) values ('friend@example.com');`
6. Optional, enable the `pg_cron` extension (Database > Extensions) for the one-minute cleanup.

**Email limits.** The default Supabase mailer only sends to members of your Supabase organization and is limited to about 2 emails per hour, so friends' confirmation emails will fail. Configure custom SMTP under Authentication > Emails > SMTP Settings before inviting people.

### Owner alert emails (optional)

`supabase/alerts.sql` emails you when a new assistant asks to pair and on the first sign-in from a new app or browser. It uses `pg_net` and the Resend API. Run the file, set the recipient in `lk_alert_settings`, then store the Resend key in Supabase Vault from your own SQL editor: `select vault.create_secret('<key>','resend_api_key');`. The key is never stored in this repo. Without a verified domain, Resend only delivers to the email of its own account.

## Build from source

```
flutter pub get
flutter run -d windows --release
flutter build windows --release      # output: build\windows\x64\runner\Release
```

The repo has no `windows/` runner folder. Create it once with `flutter create --platforms=windows --project-name laptop_link .`. Then run `powershell -ExecutionPolicy Bypass -File scripts\rename-exe.ps1` once so the program is called `Tether.exe` (data folder and pairing are not touched; the package name stays `laptop_link`). To stop a running copy: `taskkill /IM Tether.exe /F` (older builds: `laptop_link.exe`). Builds are light on purpose.

### Releases

`release/release.yml` is a GitHub Actions workflow that builds on `windows-latest` when you push a tag like `v1.0.0` and publishes `Tether-windows.zip`, `assistant-kit.zip`, `lk.py` and `ASSISTANT.md` to the Releases page of this repo. Move it to `.github/workflows/release.yml` to enable it, and give Actions read and write permission under Settings > Actions > General. Release notes come from `release/RELEASE_NOTES.md`.

### Web console

`site/` is a static page (HTML and JS, no build) with sign-in, status and a console for the assistant side. Deploy with Firebase Hosting:

```
firebase deploy --only hosting --project <your-project> --config firebase.hosting.json
```

## Repository layout

| Path | What |
|---|---|
| `lib/` | Flutter desktop app (session, pairing, tray, native Windows input and capture, UI) |
| `assets/` | icons, logo, PowerShell fallback scripts, command allowlist |
| `site/` | static web page |
| `supabase/` | SQL: schema and policies, invites, alerts, cleanup |
| `scripts/` | `lk.py` assistant client, `isolation_test.py` |
| `release/` | release workflow and release notes |
| `ASSISTANT.md` | instructions for an assistant that drives a laptop |

## License

MIT, see [LICENSE](LICENSE).


First run: no session starts until the person at the laptop picks a control mode in the main window (no silent default). It stays changeable afterwards.

First run: after sign-in the session does not start by itself. Pick a control mode, then press Connect once. From then on the session and bar start when the app opens.

Approval keys (physical keys only, the assistant can never send them): Ctrl+Alt+Y = Allow, Ctrl+Alt+N = Deny. The orange bar shows only Allow and Deny buttons; the keys are explained in the app window before you start. A short sound plays when a question opens and the bar stays on top. While a question is open no other assistant step runs. No answer in 60 seconds = Deny.

The green bar has one fixed size and stays on top: no maximize button, no drag-resize, and Win+Up, title double-click or full screen are undone. The assistant cannot resize it.
