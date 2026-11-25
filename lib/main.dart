import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:window_manager/window_manager.dart';

import 'src/auth_gate.dart';
import 'src/config.dart';
import 'src/consent.dart';
import 'src/lang.dart';
import 'src/console_page.dart';
import 'src/desktop_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb && Platform.isWindows) {
    await windowManager.ensureInitialized();
    // The Windows runner template names the window after the package; show the product name instead.
    await windowManager.setTitle('Tether');
  }
  await loadLang();
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  runApp(const TetherApp());
}

class TetherApp extends StatelessWidget {
  const TetherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tether',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      // Web build = command console. Desktop build = agent that executes (with approval).
      home: AuthGate(
        child: kIsWeb
            ? const ConsolePage()
            : const ConsentGate(child: DesktopPage()),
      ),
    );
  }
}
