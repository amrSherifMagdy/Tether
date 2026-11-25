import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'lang.dart';

/// App version, compared with the newest GitHub release tag.
const String kVersion = '1.0.1';

const String _releasesPage =
    'https://github.com/amrSherifMagdy/Tether/releases/latest';
const String _latestApi =
    'https://api.github.com/repos/amrSherifMagdy/Tether/releases/latest';

// ---------------------------------------------------------------------------
// 1. Single instance guard
// ---------------------------------------------------------------------------

const String _mutexName = 'Local\\TetherSingleInstance';
// Kept open for the life of the process so the mutex exists until the app exits.
int _mutexHandle = 0;

/// Returns false when another Tether is already running. In that case it also
/// tries to bring the running window to the front. Never throws.
bool acquireSingleInstance() {
  if (!Platform.isWindows) return true;
  try {
    final k = DynamicLibrary.open('kernel32.dll');
    final openMutex = k.lookupFunction<
      IntPtr Function(Uint32, Int32, Pointer<Utf16>),
      int Function(int, int, Pointer<Utf16>)
    >('OpenMutexW');
    final createMutex = k.lookupFunction<
      IntPtr Function(Pointer<Void>, Int32, Pointer<Utf16>),
      int Function(Pointer<Void>, int, Pointer<Utf16>)
    >('CreateMutexW');
    final name = _mutexName.toNativeUtf16();
    try {
      // SYNCHRONIZE = 0x00100000. A non-zero handle means another instance owns it.
      final existing = openMutex(0x00100000, 0, name);
      if (existing != 0) {
        _focusRunningWindow();
        return false;
      }
      _mutexHandle = createMutex(nullptr, 0, name);
    } finally {
      calloc.free(name);
    }
  } catch (_) {
    // If the check itself fails, do not block the app from starting.
  }
  return true;
}

void _focusRunningWindow() {
  try {
    final u = DynamicLibrary.open('user32.dll');
    final findWindow = u.lookupFunction<
      IntPtr Function(Pointer<Utf16>, Pointer<Utf16>),
      int Function(Pointer<Utf16>, Pointer<Utf16>)
    >('FindWindowW');
    final showWindow = u.lookupFunction<
      Int32 Function(IntPtr, Int32),
      int Function(int, int)
    >('ShowWindow');
    final setFg = u.lookupFunction<Int32 Function(IntPtr), int Function(int)>(
      'SetForegroundWindow',
    );
    final title = 'Tether'.toNativeUtf16();
    try {
      final h = findWindow(nullptr, title);
      if (h != 0) {
        showWindow(h, 9); // SW_RESTORE
        setFg(h);
      }
    } finally {
      calloc.free(title);
    }
  } catch (_) {}
}

// ---------------------------------------------------------------------------
// 2. Daily update check (read-only, no auto install)
// ---------------------------------------------------------------------------

/// Newer release tag (like "1.0.2") when one exists, else null.
final ValueNotifier<String?> updateAvailable = ValueNotifier<String?>(null);

List<int>? _parse(String v) {
  final m = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)$').firstMatch(v.trim());
  if (m == null) return null;
  return [for (var i = 1; i <= 3; i++) int.parse(m.group(i)!)];
}

bool _isNewer(String a, String b) {
  final x = _parse(a), y = _parse(b);
  if (x == null || y == null) return false;
  for (var i = 0; i < 3; i++) {
    if (x[i] != y[i]) return x[i] > y[i];
  }
  return false;
}

/// Asks GitHub at most once every 24 hours. Only the tag name is read from the
/// reply, and it must look like a version number. Never throws.
Future<void> checkForUpdate() async {
  try {
    final p = await SharedPreferences.getInstance();
    final cached = p.getString('lk_update_tag');
    if (cached != null && _isNewer(cached, kVersion)) {
      updateAvailable.value = cached;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - (p.getInt('lk_update_checked') ?? 0) < 24 * 3600 * 1000) return;
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await c.getUrl(Uri.parse(_latestApi));
      req.headers.set('Accept', 'application/vnd.github+json');
      req.headers.set('User-Agent', 'Tether/$kVersion');
      final res = await req.close().timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) {
        await res.drain<void>();
        return;
      }
      final body = await res
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 10));
      final tag = (jsonDecode(body) as Map)['tag_name'];
      await p.setInt('lk_update_checked', now);
      if (tag is String && _parse(tag) != null) {
        await p.setString('lk_update_tag', tag);
        updateAvailable.value = _isNewer(tag, kVersion) ? tag : null;
      }
    } finally {
      c.close(force: true);
    }
  } catch (_) {}
}

/// Banner shown on the home screen when a newer release exists.
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String?>(
    valueListenable: updateAvailable,
    builder: (_, tag, __) {
      if (tag == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Card(
          color: Colors.amber.shade100,
          child: ListTile(
            leading: const Icon(Icons.system_update_alt),
            title: Text(
              pick('Update available: $tag  |  فيه تحديث جديد: $tag'),
            ),
            subtitle: Text(
              pick(
                'Download the new zip, close Tether, and replace the folder. Your sign-in and approved devices stay.  |  نزّل الـ zip الجديد، اقفل Tether، واستبدل الفولدر. الدخول والأجهزة المعتمدة بتفضل زي ما هي.',
              ),
              style: const TextStyle(fontSize: 12),
            ),
            trailing: FilledButton(
              onPressed: () => launchUrl(
                Uri.parse(_releasesPage),
                mode: LaunchMode.externalApplication,
              ),
              child: Text(pick('Download  |  تحميل')),
            ),
          ),
        ),
      );
    },
  );
}

// ---------------------------------------------------------------------------
// 3. First run: offer a desktop shortcut
// ---------------------------------------------------------------------------

/// Asks once, on the first run, whether to put a Tether shortcut on the Desktop.
/// The shortcut points at the folder the app runs from, so the folder must stay.
Future<void> offerShortcutOnce(BuildContext context) async {
  if (!Platform.isWindows) return;
  try {
    final p = await SharedPreferences.getInstance();
    if (p.getBool('lk_shortcut_asked') == true) return;
    await p.setBool('lk_shortcut_asked', true);
    if (!context.mounted) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(pick('Add a Desktop shortcut?  |  تضيف اختصار على سطح المكتب؟')),
        content: Text(
          pick(
            'This makes a Tether shortcut on your Desktop so it is easy to open. Keep the Tether folder where it is.  |  ده بيعمل اختصار لـ Tether على سطح المكتب عشان تفتحه بسهولة. سيب فولدر Tether مكانه.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(pick('Not now  |  مش دلوقتي')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(pick('Yes  |  أيوه')),
          ),
        ],
      ),
    );
    if (yes != true) return;
    // Fixed script. The exe path is passed as an environment variable, never inside the script text.
    const script =
        r"$s=(New-Object -ComObject WScript.Shell).CreateShortcut("
        r"[IO.Path]::Combine([Environment]::GetFolderPath('Desktop'),'Tether.lnk'));"
        r"$s.TargetPath=$env:TETHER_EXE;"
        r"$s.WorkingDirectory=[IO.Path]::GetDirectoryName($env:TETHER_EXE);"
        r"$s.Save()";
    await Process.run(
      'powershell',
      ['-NoProfile', '-NonInteractive', '-Command', script],
      environment: {'TETHER_EXE': Platform.resolvedExecutable},
    );
  } catch (_) {}
}
