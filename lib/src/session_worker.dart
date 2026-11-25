import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import 'native_win.dart';

/// Runs each input action in its own short-lived PowerShell process (fixed scripts in assets/).
/// Remote data reaches the scripts only as numbers, validated key codes, or a temp text file.
/// Every call has a timeout, and failures return the exit code and error text.
class SessionWorker {
  String? _op, _hot, _shotScript;
  String? _dir;
  Future<void> _chain = Future.value();

  Future<void> start() async {
    final dir = await getApplicationSupportDirectory();
    _dir = dir.path;
    Future<String> put(String asset, String name) async {
      final f = File('${dir.path}${Platform.pathSeparator}$name');
      await f.writeAsString(await rootBundle.loadString(asset));
      return f.path;
    }

    _op = await put('assets/op.ps1', 'laptop_link_op.ps1');
    _hot = await put('assets/hot.ps1', 'laptop_link_hot.ps1');
    _shotScript = await put('assets/shot.ps1', 'laptop_link_shot.ps1');
  }

  Future<String> _run(List<String> args, Duration timeout) async {
    final p = await Process.start('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      ...args,
    ], runInShell: false);
    final so = StringBuffer(), se = StringBuffer();
    final f1 = p.stdout.transform(utf8.decoder).forEach(so.write);
    final f2 = p.stderr.transform(utf8.decoder).forEach(se.write);
    try {
      await p.stdin.close();
    } catch (_) {}
    var timedOut = false;
    final code = await p.exitCode.timeout(
      timeout,
      onTimeout: () {
        timedOut = true;
        p.kill();
        return -1;
      },
    );
    await Future.wait([f1, f2])
        .timeout(const Duration(seconds: 2), onTimeout: () => []);
    if (timedOut)
      throw StateError(
        'timed out after ${timeout.inSeconds}s. ${se.toString().trim()}',
      );
    if (code != 0)
      throw StateError(
        'failed (exit $code): ${se.toString().trim()} ${so.toString().trim()}',
      );
    return so.toString().trim();
  }

  /// Calls are serialized so only one input runs at a time.
  Future<Map<String, dynamic>> _callPs(
    Map<String, dynamic> req, {
    Duration timeout = const Duration(seconds: 20),
  }) {
    final out = Completer<Map<String, dynamic>>();
    _chain = _chain.then((_) async {
      final op = '${req['op']}';
      try {
        if (op == 'hotkey') {
          final o = await _run([_hot!], timeout);
          out.complete(jsonDecode(o.split('\n').last) as Map<String, dynamic>);
          return;
        }
        final args = <String>[_op!, '-Op', op];
        File? tmp;
        if (req['x'] != null)
          args.addAll([
            '-X',
            '${(req['x'] as num).round()}',
            '-Y',
            '${(req['y'] as num).round()}',
          ]);
        if (op == 'click') {
          args.addAll([
            '-Button',
            req['button'] == 'right' ? 'right' : 'left',
            '-Count',
            '${(req['count'] as num).round()}',
          ]);
        }
        if (op == 'scroll')
          args.addAll(['-Dy', '${(req['dy'] as num).round()}']);
        if (op == 'key') {
          final keys = (req['keys'] as List)
              .map(
                (k) =>
                    '${(k['vk'] as num).toInt()}:${(k['ext'] ?? 0) == 1 ? 1 : 0}',
              )
              .join(',');
          args.addAll(['-Keys', keys]);
        }
        if (op == 'type') {
          tmp = File('$_dir${Platform.pathSeparator}laptop_link_text.tmp');
          await tmp.writeAsString(req['text'] as String);
          args.addAll(['-TextFile', tmp.path]);
        }
        try {
          final o = await _run(args, timeout);
          out.complete(
            o.isEmpty
                ? {'ok': true}
                : jsonDecode(o.split('\n').last) as Map<String, dynamic>,
          );
        } finally {
          try {
            if (tmp != null && await tmp.exists()) await tmp.delete();
          } catch (_) {}
        }
      } catch (e) {
        if (!out.isCompleted)
          out.completeError(
            StateError('$op failed: $e'.replaceFirst('Bad state: ', '')),
          );
      }
    });
    return out.future;
  }

  /// Screenshot in its own short-lived PowerShell process (fixed script, numeric args only).
  /// Errors and exit code come back in the exception text, so failures are visible.
  Future<Map<String, dynamic>> _shotPs(int maxW, int q) async {
    final dir = await getTemporaryDirectory();
    final out = File(
      '${dir.path}${Platform.pathSeparator}laptop_link_shot.jpg',
    );
    if (await out.exists()) await out.delete();
    final p = await Process.start('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      _shotScript!,
      out.path,
      '$maxW',
      '$q',
    ], runInShell: false);
    final so = StringBuffer(), se = StringBuffer();
    p.stdout.transform(utf8.decoder).listen(so.write);
    p.stderr.transform(utf8.decoder).listen(se.write);
    try {
      await p.stdin.close();
    } catch (_) {}
    final code = await p.exitCode.timeout(
      const Duration(seconds: 60),
      onTimeout: () {
        p.kill();
        return -1;
      },
    );
    if (code != 0 || !await out.exists()) {
      throw StateError(
        'capture failed (exit $code): ${se.toString().trim()} ${so.toString().trim()}',
      );
    }
    final line = so.toString().trim().split('\n').last.trim();
    final meta = jsonDecode(line) as Map<String, dynamic>;
    final bytes = await out.readAsBytes();
    return {...meta, 'b64': base64Encode(bytes)};
  }

  /// Fast path: direct Win32 calls. If one ever fails, fall back to the PowerShell one-shot path.
  bool _nativeOk = true;

  Future<Map<String, dynamic>> call(
    Map<String, dynamic> req, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    if (_nativeOk) {
      try {
        final n = Native.i;
        switch ('${req['op']}') {
          case 'info':
            return {'ok': true, 'w': n.screenW, 'h': n.screenH};
          case 'hotkey':
            return {'ok': true, 'down': n.hotkeyDown()};
          case 'move':
            n.moveTo((req['x'] as num).round(), (req['y'] as num).round());
            return {'ok': true};
          case 'click':
            await n.click(
              (req['x'] as num).round(),
              (req['y'] as num).round(),
              req['button'] == 'right',
              (req['count'] as num).round(),
            );
            return {'ok': true};
          case 'scroll':
            await n.scroll(
              (req['x'] as num).round(),
              (req['y'] as num).round(),
              (req['dy'] as num).round(),
            );
            return {'ok': true};
          case 'type':
            await n.typeText(req['text'] as String);
            return {'ok': true};
          case 'key':
            await n.keys(
              (req['keys'] as List)
                  .map<List<int>>(
                    (k) => [
                      (k['vk'] as num).toInt(),
                      (k['ext'] ?? 0) == 1 ? 1 : 0,
                    ],
                  )
                  .toList(),
            );
            return {'ok': true};
        }
      } catch (e) {
        _nativeOk = false;
        stderr.writeln('native input failed, using PowerShell: $e');
      }
    }
    return _callPs(req, timeout: timeout);
  }

  Future<Map<String, dynamic>> shot(int maxW, int q) async {
    if (_nativeOk) {
      try {
        return await captureNative(
          maxW,
          q,
        ).timeout(const Duration(seconds: 15));
      } catch (e) {
        _nativeOk = false;
        stderr.writeln('native capture failed, using PowerShell: $e');
      }
    }
    return _shotPs(maxW, q);
  }

  void dispose() {}
}
