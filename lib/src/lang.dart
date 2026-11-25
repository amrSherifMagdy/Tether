import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One language at a time. true = Arabic. Remembered across runs.
final ValueNotifier<bool> isArabic = ValueNotifier<bool>(false);

Future<void> loadLang() async {
  final p = await SharedPreferences.getInstance();
  final v = p.getString('lk_lang');
  if (v != null) {
    isArabic.value = v == 'ar';
  }
}

Future<void> setLang(bool ar) async {
  isArabic.value = ar;
  final p = await SharedPreferences.getInstance();
  await p.setString('lk_lang', ar ? 'ar' : 'en');
}

/// Picks one side of "English  |  Arabic".
String pick(String both) {
  final i = both.indexOf('  |  ');
  if (i < 0) return both;
  return isArabic.value ? both.substring(i + 5) : both.substring(0, i);
}

/// Rebuilds [builder] when the language changes and sets text direction.
class LangBuilder extends StatelessWidget {
  const LangBuilder({super.key, required this.builder});
  final Widget Function(BuildContext) builder;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: isArabic,
    builder: (ctx, ar, _) => Directionality(
      textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
      child: Builder(builder: builder),
    ),
  );
}

/// Header switch: EN / عربي.
class LangButton extends StatelessWidget {
  const LangButton({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: isArabic,
    builder: (_, ar, __) => TextButton(
      onPressed: () => setLang(!ar),
      child: Text(ar ? 'English' : 'عربي'),
    ),
  );
}

/// App bar title: knot logo + name.
class TetherTitle extends StatelessWidget {
  const TetherTitle({super.key});
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Image.asset(
        'assets/logo_knot.png',
        height: 28,
        filterQuality: FilterQuality.medium,
      ),
      const SizedBox(width: 10),
      const Text('Tether'),
    ],
  );
}
