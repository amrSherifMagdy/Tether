# Tether

Tether lets **your own AI assistant** see your Windows laptop screen and use the mouse and keyboard, **only while the app is open**, only after **you** said Allow on your laptop, and with a big STOP button always there.

You do **not** need to be technical. No terminal, no Flutter, no Git. Arabic: [README.ar.md](README.ar.md).

## What you need

- A Windows 10 or 11 laptop.
- An email address the owner of Tether invited (ask the person who sent you here).
- An AI assistant that works with Tether. It does the technical part for you.

## 1. Download

Open the **Releases** page of this repository (right side of the repo page, "Releases", then the newest one). Under **Assets**, click **Tether-windows.zip** (about 20 MB). Save it.

You also need an invite: sign-up is closed to everyone except people the owner added.

## 2. Install (there is nothing to install)

1. Open your **Downloads** folder, right-click `Tether-windows.zip` and choose **Extract All**, then **Extract**.
2. Move the new `Tether-windows` folder somewhere you will keep it, for example your Documents. Do not run it from inside the zip.
3. Open the folder and double-click **Tether.exe**.

If Windows shows a blue "Windows protected your PC" window: click **More info**, then **Run anyway**. This appears because the app is new and not code-signed.
If it says a DLL is missing: install the free "Microsoft Visual C++ Redistributable (x64)" from Microsoft, then open Tether again.

## 3. First start

1. Read the short notice and click **I understand**.
2. Choose **Create account**. Use the invited email and a password you make up. Do not share this password in a chat.
3. Open the confirmation email, click the link (a page says "Email confirmed", you can close it), go back to Tether and sign in.
4. Pick a **control mode** and click **Connect**:
   - **ASK**: Tether asks you before every click and every typing. Safest. Start here.
   - **SMART**: asks only for risky things (payments, deleting, passwords).
   - **AUTO**: never asks. Use only if you fully trust your assistant.
5. A **green bar** appears at the top of the screen. That means your assistant can connect.

## 4. Connect your assistant

Send your assistant the file `assistant-kit.zip` from the same Releases page, and tell it your Tether email. It asks you for the password through a **private secure link** (never type your password in a chat). Then it shows you a short code like `AB12-CD34`.

Tether turns **red** and shows a code. **If the two codes are the same, click Allow. If not, click Deny.** You only do this once.

## While it runs

- The orange bar asks "Allow ...?". Click **Allow** or **Deny**. Keyboard: **Ctrl+Alt+Y** = Allow, **Ctrl+Alt+N** = Deny. No answer in 60 seconds = Deny.
- **PAUSE** on the green bar freezes everything until you press RESUME.
- **STOP** (or **Ctrl+Alt+Shift+S**) ends it immediately. Closing the app ends it too.
- Your assistant never types your passwords.
- Tether can start with Windows if you switch it on in its window or in its tray icon (bottom right, near the clock).

## Remove

Close Tether, delete the folder. To remove an assistant only: open Tether, **Advanced > Approved devices > Remove**.

## Privacy in one paragraph

Screenshots pass through the owner's cloud service for a few seconds and are deleted right away. The full list of what your assistant did stays **only on your laptop**. Nobody can control your laptop without your Allow for that exact assistant.

---

Owners and developers: see [DEVELOPERS.md](DEVELOPERS.md). License: MIT.
