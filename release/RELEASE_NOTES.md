# Tether (Windows)

**Download `Tether-windows.zip`** below, unzip it anywhere, and run `Tether.exe`. No Flutter, no Git. If Windows says a DLL is missing, install the Microsoft Visual C++ Redistributable (x64). Windows SmartScreen may warn because the app is not code-signed: More info > Run anyway.

1. Open the app, read the notice, tap "I understand".
2. Sign up inside the app with the email the owner invited. Open the verification email, click the link, then come back to the app and sign in. (The link opens a page saying "Email confirmed". Close it.)
3. Give your own assistant `assistant-kit.zip` (or `lk.py` and `ASSISTANT.md`). It signs in with your email and password (give them to it only through a private vault link, never in chat), runs `lk.py pair` and tells you a code like AB12-CD34. The app turns red with the same code. If the code matches, tap **Allow**. If not, tap **Deny**.
4. The green bar means your assistant is connected. STOP button or Ctrl+Alt+Shift+S ends it.

What your assistant can do: see your screen, move the mouse, click, type and press keys, open links and apps, only while the app is open and green, and only after you tapped Allow. It never types your passwords. Nobody can control the laptop without your Allow on that exact device. The app owner runs the Supabase service (screenshots pass through it for about a minute and are deleted). The full activity log stays on your laptop only.

Stop or revoke: STOP button; Advanced > Approved devices > Remove; sign out; close the app or delete the folder.

Only your public Supabase project URL and its publishable key are inside the app. No passwords or private keys.

---

# Tether (ويندوز)

نزّل `Tether-windows.zip`، فُكّه، وشغّل `Tether.exe`. من غير Flutter ولا Git. لو ظهرت رسالة DLL ناقص نزّل Visual C++ Redistributable (x64). ويندوز ممكن يحذّر لأن التطبيق مش موقّع: More info ثم Run anyway.

1. افتح التطبيق، اقرأ التنبيه، واضغط "فاهم".
2. سجّل حساب جوه التطبيق بالإيميل اللي صاحب التطبيق ضافه. افتح إيميل التأكيد، اضغط اللينك، وارجع للتطبيق وسجّل دخول.
3. اديّ مساعدك الخاص ملف `assistant-kit.zip`. هو بيدخل بنفس الإيميل والباسورد (اديهم له بلينك الخزنة بس، مش في الشات)، ويشغّل `lk.py pair` ويقولك كود زي AB12-CD34. التطبيق هيبقى أحمر بنفس الكود. لو الكود مطابق اضغط **Allow**، لو لأ اضغط **Deny**.
4. الشريط الأخضر معناه إن مساعدك متصل. زرار STOP أو Ctrl+Alt+Shift+S بيوقفه.

المساعد بيشوف الشاشة ويستخدم الماوس والكيبورد وهو متصل بس وبعد Allow منك. مبيكتبش الباسوردات. اللقطات بتعدي على Supabase بتاع صاحب التطبيق حوالي دقيقة وبتتمسح. السجل الكامل على اللابتوب بتاعك بس. للإلغاء: STOP، أو Advanced > Approved devices > Remove، أو سجّل خروج، أو امسح الفولدر.
