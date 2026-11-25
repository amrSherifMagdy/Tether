# How the assistant drives a session

## Setup for a friend's assistant (no website needed for the friend)

1. The friend installs the desktop app and signs up/in INSIDE the app (their email must be on the owner's invite list). The assistant uses the SAME email and password to act as controller. The password goes to the assistant only through a vault link, never chat.
2. Get the project: `git clone https://github.com/amrSherifMagdy/laptop-link` (needs access from the owner) or just the `scripts/lk.py` file. Needs Python 3 and `pip install cryptography`.
3. Set env: LK_SUPABASE_URL (see lib/src/config.dart), LK_SUPABASE_KEY (the publishable key in the same file), LK_USER_FILE and LK_PASS_FILE (files holding the friend's email and password).
4. Run `python3 scripts/lk.py pair`. Tell the friend the printed code (AB12-CD34) in chat. They check it matches the red Allow card on the laptop and tap Allow.
5. Then drive with `lk.py send` / `lk.py frame` as below. The web console is optional and only an alternative for the assistant side.

(The sections below describe the actions; "web console" steps are the same as lk.py.)


1. Sign in at the web console, open the "Session" tab. It shows the latest laptop screenshot with a
   magenta grid labelled in screenshot pixels, and the time left. If there is no active session, stop:
   only the user can start one on the laptop.
2. Type ONE JSON object into the action box and press Send. Coordinates are screenshot pixels
   (the grid numbers). The desktop converts them to real screen pixels.

| type | params | notes |
|---|---|---|
| screenshot | none | refreshes the picture |
| move | x, y | |
| click | x, y, button (left/right), count (1/2) | |
| scroll | x, y, dy (-50..50, positive scrolls down) | |
| type | text (1-500 chars) | typed as keystrokes into the focused control |
| key | combo, e.g. "ctrl+c", "alt+tab", "enter" | max 4 keys; the stop hotkey is blocked |
| open_url | url (http/https) | opened with the OS URL API |
| open_app | name | presses Win, types the name, presses Enter |
| wait | ms (0-5000) | |

Examples: `{"type":"click","x":480,"y":270}`  `{"type":"type","text":"hello"}`  `{"type":"key","combo":"ctrl+l"}`

Each action is claimed once by the desktop, run, followed by a fresh screenshot. Status shows pending, running, done, failed or rejected with a result text.
Never type passwords or secrets. Stop when the task is done; the user can end the session any time.

## Fast path: batches and no browser UI

Any session action may carry `"then": [ ...up to 15 more actions... ]`. They run in order (about 120 ms apart), each validated like a single action, with ONE result frame at the end. A failure stops the batch and the result says which step failed and what finished. Example:

    {"type":"click","x":200,"y":300,"then":[{"type":"type","text":"hello"},{"type":"key","combo":"enter"}]}

`scripts/lk.py` submits actions and fetches the latest frame over the Supabase REST API with the same login and rules as the web console (credentials read from two files, never printed):

    LK_SUPABASE_URL=... LK_SUPABASE_KEY=<anon> LK_USER_FILE=... LK_PASS_FILE=... python3 scripts/lk.py send '<action json>' --wait 30   # prints result, saves /tmp/lk_frame.jpg
    python3 scripts/lk.py frame

## Pause

The person at the laptop can press PAUSE on the bar (or Pause in the tray menu). While paused every action, including screenshot, comes back `rejected: paused ...`. Do not retry in a loop: tell the user and wait. Only they can press Resume.

## Control modes (set by the person at the laptop only)

The laptop owner picks one of three modes in the window or in the tray: ASK (asks before every click, typing, key press, link or app opening), AUTO (never asks), SMART (asks only for important actions: delete or close keys, sign-in, payment, install or admin windows, sensitive typing, installers and system tools, downloads, bank or payment links). Questions appear on the laptop only and no answer in 60 seconds means Deny. You cannot see or change the mode.
If an action comes back `rejected: denied ...`, nothing was done for that step. Do not retry unless the user tells you to. In a batch the steps before the denied one already ran. Allow up to 30 s for an action that may need approval (`--wait 40` is the default).

## Sessions have no time limit

The desktop app starts a session when it opens. It ends only on STOP, Ctrl+Alt+Shift+S, or closing the app. The green bar shows LIVE. Needs supabase/schema.sql run once in the Supabase SQL Editor.

## Pairing (required)

The laptop app only runs actions signed by a controller that was approved ON the laptop. `lk.py` signs every action with
its own Ed25519 key (`~/.lk/controller.seed`, created on first use; needs the `cryptography` Python package).
First time: run `python3 scripts/lk.py pair`. It prints a code like AB12-CD34. The green bar on the laptop turns red with
the same code and Allow / Deny. After he taps Allow once it is remembered. Until then actions come back "rejected: controller not approved".
Never send secrets; if the key file is lost, pair again (he approves a new one).

Approval questions: the person at the laptop answers with the Allow/Deny buttons or the physical keys Ctrl+Alt+Y / Ctrl+Alt+N (explained in the app window). You cannot send those keys; a refused step returns "denied".

The green bar is a fixed-size, always-on-top window. It cannot be resized or maximized, so do not try.

The program on the laptop is Tether.exe (older builds: laptop_link.exe).
