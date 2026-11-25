# Tether (للاستخدام العادي)

1. افتح صفحة **Releases** في الريبو ونزّل **Tether-windows.zip** (حوالي 20 ميجا).
2. كليك يمين على الملف > **Extract All**، وحط الفولدر في مكان ثابت (مثلاً Documents)، وبعدين شغّل **Tether.exe**.
3. لو ويندوز قال "Windows protected your PC": اضغط **More info** ثم **Run anyway**.
4. اقرأ التنبيه واضغط "فاهم"، اعمل حساب بالإيميل اللي اتضاف لك، أكّد الإيميل، وسجّل دخول.
5. اختار وضع (ابدأ بـ ASK) واضغط **Connect**. الشريط الأخضر هيظهر.
6. ابعت لمساعدك ملف `assistant-kit.zip` من نفس الصفحة وقوله إيميلك. هو هيطلب الباسورد بلينك آمن (مش في الشات) ويديك كود زي AB12-CD34. التطبيق هيبقى أحمر بنفس الكود: لو متطابق اضغط **Allow**.
7. الموافقة على الأسئلة: زرار Allow/Deny أو **Ctrl+Alt+Y** / **Ctrl+Alt+N**. من غير رد 60 ثانية = رفض. للإيقاف: **STOP** أو **Ctrl+Alt+Shift+S**.

للمطورين والمالك: [DEVELOPERS.md](DEVELOPERS.md).

---

# Tether

مشروع Flutter واحد ليه وشين، والباك إند بقى **Supabase** (بدل Firebase):

- **الويب (Console):** صفحة بتشوف فيها شاشة اللاب وبتبعت أوامر. المساعد (Instinct) بتاعك بيتحكم من خلال `scripts/lk.py`.
- **الديسكتوب (Windows):** برنامج على اللاب. أول ما يفتح بيبدأ "جلسة" لوحده (من غير مدة). الشريط الأخضر فوق، وزرار **STOP**، والهوتكي **Ctrl+Alt+Shift+S** بيوقفوها في أي لحظة. كل حاجة بتتسجل في لوج محلي.

## الأمان

1. كل صف في الداتابيز ملك صاحبه بس (Row Level Security بـ `auth.uid()`). حد تاني مش هيشوف شاشتك ولا أوامرك.
2. التسجيل مفتوح لأي حد بإيميل. وتأكيد الإيميل شغال.
3. الطلب بعد ما يتبعت مبيتعدلش، والتحويل بين الحالات محمي (pending ثم running ثم done/failed)، والـ claim بيحصل مرة واحدة.
4. البرنامج بيشتغل بس وهو مفتوح، وبيقبل بس الجلسة اللي هو فتحها بنفسه.
5. الأوامر المسموحة خارج الجلسة في `assets/allowlist.json` ومحتاجة موافقتك على اللاب.
6. التحذير المهم: أي حد معاه إيميل وباسورد حسابك يقدر يتحكم في لابك وهو مفتوح. استخدم باسورد قوي ومميز، وقفل البرنامج لما تمشي.

## للأدمن (صاحب المشروع): الإعداد مرة واحدة

1. اعمل حساب على https://supabase.com وأنشئ Project جديد (خطة Free كفاية). اختار ريجن قريب (مثلا Frankfurt).
2. من **SQL Editor** الصق محتوى `supabase/schema.sql` واضغط Run. (اختياري لو عايز تسجيل بالدعوة بس: شغّل `supabase/closed_signup.sql`).
3. من **Project Settings > API** خد الـ **Project URL** والـ **anon (publishable) key**. الاتنين عاديين وعامين (الأمان في الـ RLS). **متديش حد الـ service_role key**.
4. من **Authentication > URL Configuration** خلي الـ **Site URL** = `https://tether-link.web.app` (رابط الويب بتاعك). من **Authentication > Providers > Email** سيب **Confirm email** شغال.
5. حط القيمتين في `lib/src/config.dart` (أو مرّرهم بـ `--dart-define`).
6. أي حد يقدر يسجّل بنفسه ويأكد إيميله. لو عايز تقفل التسجيل شغّل `supabase/closed_signup.sql`.
7. ملحوظة: Supabase المجاني بيبعت عدد قليل من إيميلات التأكيد في الساعة. لو كتير هتحتاج تربط SMTP خاص (Authentication > SMTP).

## تشغيل البرنامج

```
git clone https://github.com/<حسابك>/laptop-link.git
cd laptop-link
git checkout supabase
flutter pub get
flutter run -d windows --release
```

## نسخة جاهزة للأصحاب (من غير Flutter)

على لابك (بعد ما تحط الإعدادات):

```
flutter build windows --release
```

اضغط فولدر `build\windows\x64\runner\Release` كله ZIP وابعته. الصاحب بيفك الـ ZIP ويشغّل `Tether.exe` (محتاج Microsoft Visual C++ Redistributable لو مش متثبت). بيسجّل بإيميله بنفسه.
الخصوصية: السحابة (Supabase) مجرد وسيط مؤقت للأوامر. اللقطة (جدول `frames`، صورة base64 واحدة لكل جلسة) بتتمسح فور ما المساعد يسحبها، وبعد 60 ثانية من آخر رفع، وأول ما الجلسة تخلص، وكـ backstop كل دقيقة بـ `lk_cleanup()` (pg_cron). الأوامر والإجراءات المنتهية بتتمسح بعد قراءة النتيجة أو بعد 10 دقايق، والجلسات المنتهية بعد يوم. السجل الكامل لكل إجراء موجود بس في اللوج المحلي على اللابتوب (`laptop_link.log`). لو pg_cron مش متفعّل (Database > Extensions) فالمسح من التطبيق والمساعد شغال برضه.

## المساعد (Instinct)

اقرأ `ASSISTANT.md`. الأداة `scripts/lk.py` بتبعت أوامر وتجيب آخر لقطة في 2 لـ 3 ثواني.

## اختبار العزل بين حسابين

```
export LK_SUPABASE_URL=... LK_SUPABASE_KEY=<anon key>
export A_USER_FILE=... A_PASS_FILE=... B_USER_FILE=... B_PASS_FILE=...
python3 scripts/isolation_test.py
```
بيعمل جلسة مؤقتة ويحاول يكسر القواعد بحساب B وبحساب A، وبيطبع PASS/FAIL لكل حاجة.

## حدود الخطة المجانية (للمعلومة)

قاعدة بيانات 500MB، وسعة نقل شهرية محدودة، وبيتوقف المشروع لو ما استُخدمش أسبوع (Pause). اللقطات بتتكتب فوق بعض (صف واحد لكل جلسة) فمش بتكبّر الداتابيز.

## الأمان: ربط المتحكّم (Pairing)

حتى لو حد سرق إيميلك وباسوردك، مش هيقدر يحرّك اللابتوب. التطبيق على اللابتوب بيرفض أي أمر مش موقّع بمفتاح متحكّم انت وافقت عليه **على اللابتوب نفسه**.
أول مرة متحكّم جديد (المساعد أو متصفح) يحاول، الشريط الأخضر بيتحول أحمر: "Allow controller؟" ومعاه كود زي AB12-CD34. قارنه بالكود اللي المتحكّم بيعرضه واضغط Allow (أو Deny). الموافقة بتتحفظ في ملف محلي على اللابتوب بس (`approved_controllers.json`)، مش في السحابة، فمحدش يقدر يوافق من بعيد. أي أمر مرفوض بيتسجل في اللوج المحلي كـ `BLOCKED ACTION`.
المتصفح (الكونسول) له مفتاح خاص بيتخزن في المتصفح ده ولازم يتوافق عليه برضه.
لازم تشغّل `supabase/schema.sql` تاني مرة (آمن) علشان جدول `controllers` والأعمدة الجديدة.

## التشغيل مع ويندوز والتراي

- أيقونة في الـ system tray: خضرا = تحكم المساعد شغال (LIVE)، رمادي = متوقف. القايمة: Pause، Resume، Show window، Start with Windows، Quit.
- زرار X بيخبّي التطبيق في التراي بس لما مفيش جلسة شغالة؛ أثناء الجلسة الشريط الأخضر دايماً ظاهر ومينفعش يتخبّى.
- **Start with Windows** مقفول افتراضياً. لما تفتحه (من التراي أو من نافذة التطبيق) التطبيق بيشتغل أول ما تدخل ويندوز وبتبدأ الجلسة تلقائياً. تقفله في أي وقت بنفس الطريقة.
- تسجيل الدخول بيفضل محفوظ (Supabase بيحفظ الجلسة)، فمش هتكتب الباسورد كل مرة.
- STOP وهوتكي Ctrl+Alt+Shift+S واللوج شغالين دايماً.

## نسخة جاهزة للأصحاب (من غير Flutter)

على جهازك بس: `flutter build windows --release` ثم ZIP لفولدر `build\windows\x64\runner\Release`. الصاحب بيفك الـ ZIP ويشغّل `Tether.exe` (يمكن يحتاج Visual C++ Redistributable). مش محتاج Flutter ولا Git.

## الكونسول على الويب (خفيف، من غير Flutter)

الويب دلوقتي صفحة ثابتة في فولدر `site/` (HTML + JS، من غير build). بتعمل: تسجيل دخول، إنشاء حساب، صفحة "Account verified" بعد لينك الإيميل، نسيت الباسورد، تغيير الباسورد، إرسال أوامر، وجلسة مباشرة مع ربط المتصفح كمتحكّم.
النشر (من فولدر المشروع، مفيش build):

```
firebase deploy --only hosting --project laptop-link --config firebase.hosting.json   (الموقع tether-link؛ أول مرة: firebase hosting:sites:create tether-link --project laptop-link)
```

(أول مرة بس: `firebase login`.) ما تستخدمش `flutter build web` تاني؛ التطبيق دلوقتي لويندوز بس.

## إيميلات التنبيه للأونر

- تنبيه فوري لما حد يطلب ربط جهاز جديد (pairing)، وتنبيه لأول دخول من تطبيق/متصفح جديد. بتتبعت مجاناً عن طريق Resend من قاعدة البيانات (`supabase/alerts.sql`). مفتاح Resend بيتخزن في Supabase Vault مش في الريبو.
- خطوات الإعداد: سجّل في resend.com بنفس إيميل الأونر → API Keys → Create (Sending access) → شغّل `alerts.sql` ثم السطر `select vault.create_secret('<المفتاح>', 'resend_api_key');` في الـ SQL Editor → جرّب `select public.lk_send_alert('Test','<p>hello</p>');`.
- حد Resend المجاني: 100 إيميل/يوم و3000/شهر، ومن غير دومين بيبعت لإيميلك إنت بس.
- إيميلات التفعيل والريسيت اللي Supabase بيبعتها: السيرفر الافتراضي بيبعت لأعضاء فريق المشروع بس وبحد 2 إيميل في الساعة. علشان الأصحاب يسجلوا لازم SMTP مخصص (مثلاً Gmail + App Password) من Authentication → Emails → SMTP Settings.
