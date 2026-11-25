import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

import 'approval.dart';
import 'version.dart';
import 'local_log.dart';
import 'models.dart';
import 'native_win.dart' show foregroundWindowTitle, Native;
import 'pairing.dart';
import 'session_worker.dart';

/// Time-boxed "session mode". Started ONLY by a button on the laptop.
/// The desktop honours only the session it created itself (id kept in memory),
/// and stops on: Stop button, Ctrl+Alt+Shift+S, or expiry (local timer).
class SessionController extends ChangeNotifier {
  SessionController(this.uid, this.log);
  final String uid;
  final LocalLog log;

  static const hotkeyLabel = 'Ctrl+Alt+Shift+S';
  static const _maxW = 800;

  String? sessionId;
  DateTime? expiresAt;
  String lastAction = '';
  String? error;

  SessionWorker? _worker;
  Timer? _expiry, _ui, _hot;
  RealtimeChannel? _ch;
  Timer? _poll;
  bool _frameExists = false;
  final _queue = <Map<String, dynamic>>[];
  final _seen = <String>{};
  bool _busy = false, _polling = false, _stopping = false;
  double _scale = 1;
  int _sw = 1, _sh = 1;

  bool get active => sessionId != null;
  Duration get remaining {
    final e = expiresAt;
    if (e == null) return Duration.zero;
    final d = e.difference(DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }

  /// [d] == null means no time limit: the session lives until STOP, the hotkey, or the app closes.
  Future<void> start(Duration? d) async {
    if (active) return;
    if (!modeChosen) return; // first run: a control mode must be picked in the window first
    error = null;
    paused = false;
    final w = SessionWorker();
    try {
      await w.start();
      final info = await w.call({'op': 'info'});
      _sw = (info['w'] as num).toInt();
      _sh = (info['h'] as num).toInt();
      _scale = _sw > _maxW ? _maxW / _sw : 1.0;
      // Close leftovers from a crash or a force-quit so only one session is ever active.
      try {
        await sb
            .from('sessions')
            .update({'status': 'ended'})
            .eq('status', 'active');
      } catch (e) {
        await log.add('could not close old sessions: $e');
      }
      final exp = d == null ? null : DateTime.now().add(d);
      final created = await sb
          .from('sessions')
          .insert({
            'status': 'active',
            if (exp != null) 'expires_at': exp.toUtc().toIso8601String(),
            if (d != null) 'duration_minutes': d.inMinutes,
          })
          .select('id')
          .single();
      final newId = '${created['id']}';
      _worker = w;
      sessionId = newId;
      _frameExists = false;
      expiresAt = exp;
      _stopping = false;
      _seen.clear();
      _queue.clear();
      await log.add(
        'SESSION START build=$kBuild id=$newId ${d == null ? 'no time limit' : 'minutes=${d.inMinutes}'}',
      );
      if (!startedBefore) {
        startedBefore = true;
        final sp = await SharedPreferences.getInstance();
        await sp.setBool('lk_started_once', true);
      }
      if (d != null) _expiry = Timer(d, () => stop('expired'));
      _ui = Timer.periodic(
        const Duration(seconds: 1),
        (_) => notifyListeners(),
      );
      _hot = Timer.periodic(
        const Duration(milliseconds: 200),
        (_) => _checkHotkey(),
      );
      // New actions arrive over realtime; a light poll is the safety net if a message is missed.
      void take(Map<String, dynamic> row) {
        if (row['status'] != Status.pending) return;
        if (_seen.add('${row['id']}')) _queue.add(row);
      }

      Future<void> fetchPending() async {
        try {
          final rows = await sb
              .from('actions')
              .select()
              .eq('session_id', newId)
              .eq('status', Status.pending)
              .order('created_at')
              .limit(30);
          for (final r in rows) {
            take(Map<String, dynamic>.from(r));
          }
          _drain();
        } catch (e) {
          log.add('session poll error: $e');
        }
      }

      _ch = sb
          .channel('actions-$newId')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'actions',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'session_id',
              value: newId,
            ),
            callback: (p) {
              take(Map<String, dynamic>.from(p.newRecord));
              _drain();
            },
          )
          .subscribe();
      _poll = Timer.periodic(const Duration(seconds: 3), (_) => fetchPending());
      unawaited(fetchPending());
      notifyListeners();
      await _enterBar();
      unawaited(
        _shot().catchError(
          (Object e) => log.add('first screenshot failed: $e'),
        ),
      );
    } catch (e) {
      w.dispose();
      error = 'Could not start session: $e';
      await log.add('SESSION START FAILED: $e');
      notifyListeners();
    }
  }

  Future<void> stop(String reason) async {
    if (!active || _stopping) return;
    _stopping = true;
    paused = false;
    answerApproval(false);
    final id = sessionId!;
    _expiry?.cancel();
    _ui?.cancel();
    _hot?.cancel();
    _poll?.cancel();
    try {
      if (_ch != null) await sb.removeChannel(_ch!);
    } catch (_) {}
    _ch = null;
    _worker?.dispose();
    _worker = null;
    _frameTtl?.cancel();
    try {
      await sb.from('frames').delete().eq('session_id', id);
    } catch (_) {}
    sessionId = null;
    expiresAt = null;
    _queue.clear();
    try {
      await sb
          .from('sessions')
          .update({'status': reason == 'expired' ? 'expired' : 'stopped'})
          .eq('id', id);
    } catch (e) {
      await log.add('could not mark session ended: $e');
    }
    await log.add('SESSION END id=$id reason=$reason');
    await _exitBar();
    notifyListeners();
  }

  Future<void> _checkHotkey() async {
    final w = _worker;
    if (w == null || _polling) return;
    _polling = true;
    try {
      final r = await w.call({
        'op': 'hotkey',
      }, timeout: const Duration(seconds: 5));
      if (r['down'] == true) await stop('hotkey');
    } catch (_) {
    } finally {
      _polling = false;
    }
  }

  static const _barSize = Size(580, 80);
  _BarGuard? _barGuard;

  /// The bar has one fixed size: no maximize, no resize (mouse, keyboard, Win+Up, title double-click),
  /// no full screen. Locked by the window style AND by a listener that snaps it back.
  Future<void> _enterBar() async {
    try {
      await windowManager.setFullScreen(false);
      if (await windowManager.isMaximized()) await windowManager.unmaximize();
      await windowManager.setResizable(true);
      await windowManager.setMinimumSize(_barSize);
      await windowManager.setMaximumSize(_barSize);
      await windowManager.setSize(_barSize);
      await windowManager.setAlignment(Alignment.topCenter);
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setMaximizable(false);
      await windowManager.setResizable(false);
      _barGuard ??= _BarGuard(_barSize);
      windowManager.addListener(_barGuard!);
    } catch (e) {
      await log.add('window bar mode failed: $e');
    }
  }

  Future<void> _exitBar() async {
    try {
      if (_barGuard != null) windowManager.removeListener(_barGuard!);
      await windowManager.setAlwaysOnTop(false);
      await windowManager.setResizable(true);
      await windowManager.setMaximizable(true);
      await windowManager.setMinimumSize(const Size(400, 300));
      await windowManager.setMaximumSize(const Size(100000, 100000));
      await windowManager.setSize(const Size(900, 640));
      await windowManager.center();
    } catch (_) {}
  }

  Future<void> _drain() async {
    if (_busy) return;
    _busy = true;
    try {
      while (_queue.isNotEmpty && active) {
        await _run(_queue.removeAt(0));
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _finish(String id, String status, String result) async {
    try {
      await sb
          .from('actions')
          .update({
            'status': status,
            'result': result.length > 2000 ? result.substring(0, 2000) : result,
          })
          .eq('id', id);
      await log.add(
        'action $id -> $status: ${result.length > 300 ? result.substring(0, 300) : result}',
      );
    } catch (e) {
      await log.add('could not write result for $id: $e');
    }
  }

  Future<void> _run(Map<String, dynamic> d) async {
    final aid = '${d['id']}';
    final exp = expiresAt;
    if (!active || (exp != null && DateTime.now().isAfter(exp))) return;
    // Only actions signed by a controller approved on THIS laptop may run.
    final authErr = await _authorize(d);
    if (authErr != null) {
      lastAction = 'BLOCKED: $authErr';
      await log.add('BLOCKED ACTION $aid: $authErr');
      await _finish(aid, Status.rejected, authErr);
      return;
    }
    late final String type;
    late final Map<String, dynamic> params;
    try {
      final pl = jsonDecode(d['payload'] as String) as Map<String, dynamic>;
      type = pl['type'] as String;
      params = Map<String, dynamic>.from(pl['params'] as Map);
    } catch (_) {
      await log.add('BLOCKED ACTION $aid: unreadable payload');
      await _finish(aid, Status.rejected, 'unreadable payload');
      return;
    }
    if (paused) {
      lastAction = 'paused (action refused)';
      await log.add('ACTION $aid $type refused: paused');
      await _finish(
        aid,
        Status.rejected,
        'paused: the person at the laptop paused control. Ask them to press Resume.',
      );
      return;
    }
    // Optional "shot": false skips the screenshot after this action (and its "then" steps). Default is true.
    // Use it for obvious steps (click a known search box and type) so no frame is captured or uploaded.
    final wantShot = params.remove('shot') != false;
    var err = _validate(type, params);
    // Optional "then": a short list of follow-up actions run in order, with ONE result frame at the end.
    // Every step goes through the same validation as a single action.
    final steps = <Map<String, dynamic>>[];
    final then = params.remove('then');
    if (err == null && then != null) {
      if (then is! List || then.length > 15) {
        err = '"then" must be a list of at most 15 actions';
      } else {
        for (var i = 0; i < then.length && err == null; i++) {
          final it = then[i];
          if (it is! Map || it['type'] is! String) {
            err = 'then[$i] needs a type';
            break;
          }
          final sp = Map<String, dynamic>.from(it);
          final st = sp.remove('type') as String;
          if (sp.containsKey('then')) {
            err = 'then[$i] cannot contain "then"';
            break;
          }
          final e2 = _validate(st, sp);
          if (e2 != null) {
            err = 'then[$i]: $e2';
          } else {
            steps.add({'type': st, 'params': sp});
          }
        }
      }
    }
    if (err != null) {
      await log.add('ACTION $aid $type REJECTED: $err');
      await _finish(aid, Status.rejected, err);
      return;
    }
    // Claim once. Rules only allow pending -> running, so a second claim fails.
    try {
      final claimed = await sb
          .from('actions')
          .update({'status': Status.running})
          .eq('id', aid)
          .eq('status', Status.pending)
          .select('id');
      if (claimed.isEmpty) {
        await log.add('ACTION $aid claim refused: already taken');
        return;
      }
    } catch (e) {
      await log.add('ACTION $aid claim refused: $e');
      return;
    }
    lastAction = type;
    notifyListeners();
    await log.add('ACTION $aid $type $params');
    try {
      await _gate(type, params);
      var result = await _exec(type, params);
      for (var i = 0; i < steps.length; i++) {
        final e = expiresAt;
        if (!active || (e != null && DateTime.now().isAfter(e))) {
          throw StateError(
            'session ended before step ${i + 2}. Done so far: $result',
          );
        }
        await Future.delayed(const Duration(milliseconds: 120));
        final st = steps[i]['type'] as String;
        final sp = steps[i]['params'] as Map<String, dynamic>;
        await log.add('ACTION $aid step ${i + 2} $st $sp');
        try {
          await _gate(st, sp);
          result = '$result; ${await _exec(st, sp)}';
        } catch (e) {
          throw StateError(
            'step ${i + 2} ($st) failed: $e. Done so far: $result',
          );
        }
      }
      if (!wantShot && type != 'screenshot') {
        await _finish(aid, Status.done, '$result (no screenshot, shot=false)');
        return;
      }
      if (type != 'screenshot') {
        await Future.delayed(const Duration(milliseconds: 150));
      }
      // Capture here, then upload the frame and write the result at the same time (one round trip saved).
      final row = await _capture(actionId: aid);
      String note = '';
      await Future.wait([
        _uploadFrame(row).catchError((Object e) {
          note = ' (screenshot upload failed: $e)';
        }),
        _finish(aid, Status.done, result),
      ]);
      if (note.isNotEmpty) await log.add('ACTION $aid$note');
    } on _Denied catch (e) {
      await log.add('ACTION $aid $type DENIED: ${e.msg}');
      // The database only allows running -> done|failed, so a denied step is written as failed with a "denied:" text.
      await _finish(aid, Status.failed, e.msg);
    } catch (e) {
      await log.add('ACTION $aid $type FAILED: $e');
      await _finish(aid, Status.failed, '$e');
    }
  }

  // ---- validation ----

  static const _types = {
    'screenshot',
    'move',
    'click',
    'scroll',
    'type',
    'key',
    'open_url',
    'open_app',
    'wait',
  };

  num? _n(dynamic v) => v is num ? v : null;

  String? _validate(String type, Map<String, dynamic> p) {
    if (!_types.contains(type)) return 'Unknown action type';
    switch (type) {
      case 'screenshot':
        return null;
      case 'move':
      case 'click':
      case 'scroll':
        final x = _n(p['x']), y = _n(p['y']);
        if (x == null || y == null || x < 0 || y < 0 || x > 20000 || y > 20000)
          return 'x and y must be numbers (screenshot pixels)';
        if (type == 'click') {
          final b = p['button'] ?? 'left';
          if (b != 'left' && b != 'right')
            return 'button must be left or right';
          final c = p['count'] ?? 1;
          if (c is! num || c < 1 || c > 2) return 'count must be 1 or 2';
        }
        if (type == 'scroll') {
          final dy = _n(p['dy']);
          if (dy == null || dy.abs() > 50)
            return 'dy must be a number between -50 and 50';
        }
        return null;
      case 'type':
        final t = p['text'];
        if (t is! String || t.isEmpty || t.length > 500)
          return 'text must be 1-500 characters';
        return null;
      case 'key':
        final c = p['combo'];
        if (c is! String || _parseCombo(c) == null)
          return 'Invalid or blocked key combo';
        return null;
      case 'open_url':
        final u = p['url'];
        if (u is! String || u.length > 2000) return 'url required';
        final uri = Uri.tryParse(u);
        if (uri == null ||
            !(uri.scheme == 'https' || uri.scheme == 'http') ||
            uri.host.isEmpty) {
          return 'Only http(s) URLs are allowed';
        }
        return null;
      case 'open_app':
        final n = p['name'];
        if (n is! String ||
            !RegExp(r'^[\p{L}\p{N} ._+-]{1,40}$', unicode: true).hasMatch(n)) {
          return 'App name must be 1-40 letters, digits, spaces or . _ + -';
        }
        return null;
      case 'wait':
        final ms = _n(p['ms']);
        if (ms == null || ms < 0 || ms > 5000) return 'ms must be 0-5000';
        return null;
    }
    return 'Unsupported';
  }

  static const _vk = <String, List<int>>{
    'ctrl': [0x11, 0],
    'shift': [0x10, 0],
    'alt': [0x12, 0],
    'win': [0x5B, 1],
    'enter': [0x0D, 0],
    'tab': [0x09, 0],
    'esc': [0x1B, 0],
    'space': [0x20, 0],
    'backspace': [0x08, 0],
    'delete': [0x2E, 1],
    'up': [0x26, 1],
    'down': [0x28, 1],
    'left': [0x25, 1],
    'right': [0x27, 1],
    'home': [0x24, 1],
    'end': [0x23, 1],
    'pageup': [0x21, 1],
    'pagedown': [0x22, 1],
  };
  static const _alias = {
    'control': 'ctrl',
    'escape': 'esc',
    'return': 'enter',
    'del': 'delete',
    'pgup': 'pageup',
    'pgdn': 'pagedown',
    'windows': 'win',
    'meta': 'win',
    'cmd': 'win',
  };

  List<Map<String, int>>? _parseCombo(String s) {
    final parts = s
        .toLowerCase()
        .split('+')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.isEmpty || parts.length > 4) return null;
    final names = parts.map((e) => _alias[e] ?? e).toList();
    // The stop hotkey can never be sent remotely.
    if (names.contains('ctrl') &&
        names.contains('alt') &&
        names.contains('shift') &&
        names.contains('s')) {
      return null;
    }
    // The approval keys (Ctrl+Alt+Y = Allow, Ctrl+Alt+N = Deny) can never be sent remotely.
    if (names.contains('ctrl') && (names.contains('y') || names.contains('n'))) {
      return null;
    }
    final out = <Map<String, int>>[];
    for (final n in names) {
      if (_vk.containsKey(n)) {
        out.add({'vk': _vk[n]![0], 'ext': _vk[n]![1]});
      } else if (RegExp(r'^[a-z0-9]$').hasMatch(n)) {
        out.add({
          'vk': n.codeUnitAt(0) - (n.codeUnitAt(0) >= 97 ? 32 : 0),
          'ext': 0,
        });
      } else if (RegExp(r'^f([1-9]|1[0-2])$').hasMatch(n)) {
        out.add({'vk': 0x70 + int.parse(n.substring(1)) - 1, 'ext': 0});
      } else {
        return null;
      }
    }
    return out;
  }

  // ---- execution ----

  int _sx(num x) => (x / _scale).round().clamp(0, _sw - 1);
  int _sy(num y) => (y / _scale).round().clamp(0, _sh - 1);

  Future<String> _exec(String type, Map<String, dynamic> p) async {
    final w = _worker!;
    switch (type) {
      case 'screenshot':
        return 'ok';
      case 'move':
        await w.call({'op': 'move', 'x': _sx(p['x']), 'y': _sy(p['y'])});
        return 'moved';
      case 'click':
        await w.call({
          'op': 'click',
          'x': _sx(p['x']),
          'y': _sy(p['y']),
          'button': p['button'] ?? 'left',
          'count': (p['count'] ?? 1) as num,
        });
        return 'clicked';
      case 'scroll':
        await w.call({
          'op': 'scroll',
          'x': _sx(p['x']),
          'y': _sy(p['y']),
          'dy': (p['dy'] as num).round(),
        });
        return 'scrolled';
      case 'type':
        await w.call({
          'op': 'type',
          'text': p['text'],
        }, timeout: const Duration(seconds: 60));
        return 'typed ${(p['text'] as String).length} chars';
      case 'key':
        await w.call({'op': 'key', 'keys': _parseCombo(p['combo'] as String)});
        return 'pressed ${p['combo']}';
      case 'open_url':
        final ok = await launchUrl(
          Uri.parse(p['url'] as String),
          mode: LaunchMode.externalApplication,
        );
        if (!ok) throw StateError('Could not open URL');
        return 'opened';
      case 'open_app':
        // Same as a person: Win key, type the name, Enter. No command string is built.
        await w.call({
          'op': 'key',
          'keys': [
            {'vk': 0x5B, 'ext': 1},
          ],
        });
        await Future.delayed(const Duration(milliseconds: 800));
        await w.call({'op': 'type', 'text': p['name']});
        await Future.delayed(const Duration(milliseconds: 1000));
        await w.call({
          'op': 'key',
          'keys': [
            {'vk': 0x0D, 'ext': 0},
          ],
        });
        return 'asked Windows to open ${p['name']}';
      case 'wait':
        await Future.delayed(Duration(milliseconds: (p['ms'] as num).toInt()));
        return 'waited';
    }
    throw StateError('unsupported');
  }

  Future<void> _shot({String? actionId}) async {
    final row = await _capture(actionId: actionId);
    if (row != null) await _uploadFrame(row);
  }

  Future<Map<String, dynamic>?> _capture({String? actionId}) async {
    final w = _worker, id = sessionId;
    if (w == null || id == null) return null;
    var r = await w.shot(_maxW, 50);
    if ((r['b64'] as String).length > 850000) {
      r = await w.shot(math.min(_maxW, 640), 35);
    }
    _scale = (r['scale'] as num).toDouble();
    _sw = (r['screenW'] as num).toInt();
    _sh = (r['screenH'] as num).toInt();
    final row = {
      'image_b64': r['b64'],
      'width': (r['width'] as num).toInt(),
      'height': (r['height'] as num).toInt(),
      'action_id': actionId ?? '',
    };
    return row;
  }

  Future<void> _uploadFrame(Map<String, dynamic>? row) async {
    final id = sessionId;
    if (row == null || id == null) return;
    _frameTtl?.cancel();
    _frameTtl = Timer(const Duration(seconds: 60), _dropFrame);
    // The assistant deletes the frame after fetching it, so update first and insert when no row is left.
    if (_frameExists) {
      final upd = await sb
          .from('frames')
          .update(row)
          .eq('session_id', id)
          .select('session_id');
      if (upd.isNotEmpty) return;
    }
    try {
      await sb.from('frames').insert({'session_id': id, ...row});
    } catch (_) {
      await sb
          .from('frames')
          .update(row)
          .eq('session_id', id); // another upload won the race
    }
    _frameExists = true;
  }

  /// Local soft pause: the session and the pairing stay, but no action runs until Resume.
  /// Only the person at the laptop can change it (bar button or tray menu), never a remote action.
  bool paused = false;

  // ---- control mode and local approvals ----
  ControlMode mode = ControlMode.smart;
  /// False until the person at the laptop picks a mode for the first time. No session starts before that.
  bool modeChosen = false;
  bool modeLoaded = false;
  bool startedBefore = false;
  String? approvalText, approvalReason;
  DateTime? approvalEnds;
  Completer<bool>? _approval;
  static const _approvalWait = Duration(seconds: 60);

  Future<void> loadMode() async {
    final p = await SharedPreferences.getInstance();
    final saved = p.getString('lk_mode');
    modeChosen = saved != null && ControlMode.values.any((m) => m.name == saved);
    mode = ControlModeText.parse(saved);
    modeLoaded = true;
    notifyListeners();
    startedBefore = p.getBool('lk_started_once') ?? false;
    notifyListeners();
    // First ever run: the person presses Connect themselves. Afterwards it opens live.
    if (modeChosen && startedBefore) await start(null);
  }

  /// Only the person at the laptop can change the mode (bar, window or tray). Never a remote action.
  Future<void> setMode(ControlMode m) async {
    if (mode == m && modeChosen) return;
    mode = m;
    modeChosen = true;
    final p = await SharedPreferences.getInstance();
    await p.setString('lk_mode', m.name);
    await log.add('MODE ${m.name}');
    notifyListeners();
  }

  bool get approving => _approval != null && !_approval!.isCompleted;

  void answerApproval(bool ok) {
    final c = _approval;
    if (c != null && !c.isCompleted) c.complete(ok);
  }

  /// Shows the question on the laptop and waits. No answer within 25 s means no.
  Future<bool> _askLocal(String reason, String text) async {
    final c = Completer<bool>();
    _approval = c;
    approvalReason = reason;
    approvalText = text;
    approvalEnds = DateTime.now().add(_approvalWait);
    await log.add('APPROVAL ASKED ($reason): $text [build $kBuild]');
    notifyListeners();
    // Nothing else runs while a question is open: the queue is serial and this step is waiting here.
    try {
      await windowManager.setAlwaysOnTop(true);
      await windowManager.show();
      await windowManager.focus();
    } catch (_) {}
    final n = Native.i;
    n.beep();
    var ticks = 0;
    var armed = false; // wait until the keys are released once, so a held key never answers by accident
    var lastSeen = '';
    void answerByKey(bool ok, String how) {
      if (c.isCompleted) return;
      log.add('APPROVAL KEY ${ok ? 'Ctrl+Alt+Y (Allow)' : 'Ctrl+Alt+N (Deny)'} seen via $how');
      c.complete(ok);
    }

    // Path 1: physical key state, polled fast (works whichever window is in front).
    final keys = Timer.periodic(const Duration(milliseconds: 40), (_) {
      if (c.isCompleted) return;
      ticks++;
      if (ticks % 200 == 0) n.beep(); // about every 8 s
      final ctrl = n.keyDown(0x11) && n.keyDown(0x12), yDown = n.keyDown(0x59), nDown = n.keyDown(0x4E);
      final y = ctrl && yDown, no = ctrl && nDown;
      final now = 'ctrl+alt=$ctrl y=$yDown n=$nDown';
      if ((ctrl || yDown || nDown) && now != lastSeen) {
        lastSeen = now;
        log.add('APPROVAL key state: $now (armed=$armed)');
      }
      if (!armed) {
        armed = !y && !no;
        return;
      }
      if (y) {
        answerByKey(true, 'key state');
      } else if (no) {
        answerByKey(false, 'key state');
      }
    });
    // Path 2: the app's own key events (when the bar has focus).
    bool onKey(KeyEvent e) {
      if (e is! KeyDownEvent || !armed) return false;
      final ctrl = HardwareKeyboard.instance.isControlPressed && HardwareKeyboard.instance.isAltPressed;
      if (ctrl && e.logicalKey == LogicalKeyboardKey.keyY) {
        answerByKey(true, 'window key event');
        return true;
      }
      if (ctrl && e.logicalKey == LogicalKeyboardKey.keyN) {
        answerByKey(false, 'window key event');
        return true;
      }
      return false;
    }

    HardwareKeyboard.instance.addHandler(onKey);
    final t = Timer(_approvalWait, () {
      if (!c.isCompleted) c.complete(false);
    });
    final ok = await c.future;
    HardwareKeyboard.instance.removeHandler(onKey);
    keys.cancel();
    t.cancel();
    _approval = null;
    approvalText = approvalReason = null;
    approvalEnds = null;
    await log.add('APPROVAL ${ok ? 'GIVEN' : 'DENIED (or timed out)'}');
    notifyListeners();
    return ok;
  }

  /// Runs before every step. Throws when the person at the laptop says no (or does not answer).
  Future<void> _gate(String type, Map<String, dynamic> p) async {
    if (mode == ControlMode.auto) return;
    String title = '';
    try {
      title = foregroundWindowTitle();
    } catch (_) {}
    final why = mode == ControlMode.ask
        ? askModeReason(type)
        : importantReason(type, p, title);
    if (why == null) return;
    final ok = await _askLocal(why, describeAction(type, p, title));
    if (!ok) {
      throw _Denied(
        'denied: the person at the laptop did not approve "${describeAction(type, p, title)}" (mode ${mode.label}). Nothing was done for this step. Do not retry unless they ask you to.',
      );
    }
  }

  Future<void> setPaused(bool v) async {
    if (!active || paused == v) return;
    paused = v;
    await log.add(v ? 'PAUSED by user' : 'RESUMED by user');
    notifyListeners();
  }

  final _keyCache = <String, String>{};
  final trust = Trust();
  String? pairName;
  String? pairFp;
  String? _pairPub;
  Timer? _pairPoll;

  Future<String?> _authorize(Map<String, dynamic> d) async {
    final cid = d['controller_id'];
    final payload = d['payload'];
    final sig = d['sig'];
    final ts = d['sig_ts'];
    if (cid == null || payload == null || sig == null || ts == null) {
      return 'unsigned action blocked (controller not paired)';
    }
    final age = DateTime.now().millisecondsSinceEpoch / 1000 - (ts as num);
    if (age.abs() > 120) return 'signature time out of range (check clocks)';
    // A controller's public key never changes (frozen by the database rules), so ask the cloud once.
    var pub = _keyCache['$cid'];
    if (pub == null) {
      final rows = await sb
          .from('controllers')
          .select('public_key')
          .eq('id', cid);
      if (rows.isEmpty) return 'unknown controller';
      pub = '${rows.first['public_key']}';
      _keyCache['$cid'] = pub;
    }
    if (!await trust.isApproved(pub)) {
      return 'controller not approved on the laptop yet';
    }
    final ok = await verifySignature(
      pub,
      signedMessage('${d['id']}', '${d['session_id']}', ts.toInt(), '$payload'),
      '$sig',
    );
    return ok ? null : 'bad signature';
  }

  /// Looks for a controller waiting for approval and shows Allow/Deny in the bar (red).
  Future<void> _checkPairing() async {
    if (_pairPub != null) return;
    try {
      final rows = await sb
          .from('controllers')
          .select('name,public_key')
          .order('created_at');
      for (final r in rows) {
        final pub = '${r['public_key']}';
        if (await trust.isApproved(pub) || await trust.isDenied(pub)) continue;
        _pairPub = pub;
        pairName = '${r['name']}';
        pairFp = await fingerprint(pub);
        await log.add('NEW CONTROLLER asks to pair: "$pairName" code $pairFp');
        try {
          await windowManager.focus();
        } catch (_) {}
        notifyListeners();
        return;
      }
    } catch (e) {
      await log.add('pairing check error: $e');
    }
  }

  /// Watches for controllers asking to pair, whether or not a session is live.
  void watchPairing() {
    _pairPoll ??= Timer.periodic(
      const Duration(seconds: 3),
      (_) => _checkPairing(),
    );
    _checkPairing();
  }

  void stopWatchingPairing() {
    _pairPoll?.cancel();
    _pairPoll = null;
  }

  Future<void> answerPairing(bool allow) async {
    final pub = _pairPub;
    if (pub == null) return;
    final name = pairName ?? '';
    if (allow) {
      await trust.approve(pub, name);
      await log.add('CONTROLLER APPROVED: "$name" code $pairFp');
    } else {
      await trust.deny(pub);
      await log.add('CONTROLLER DENIED: "$name" code $pairFp');
      try {
        await sb.from('controllers').delete().eq('public_key', pub);
      } catch (_) {}
    }
    _pairPub = null;
    pairName = null;
    pairFp = null;
    notifyListeners();
    _checkPairing();
  }

  Timer? _frameTtl;

  /// Screenshots are transient: no cloud copy stays longer than 60s after the last upload.
  Future<void> _dropFrame() async {
    final id = sessionId;
    if (id == null) return;
    try {
      await sb.from('frames').delete().eq('session_id', id);
      _frameExists = false;
    } catch (_) {}
  }

  @override
  void dispose() {
    _pairPoll?.cancel();
    _frameTtl?.cancel();
    stop('app closed');
    super.dispose();
  }
}

class _Denied implements Exception {
  _Denied(this.msg);
  final String msg;
  @override
  String toString() => msg;
}

/// Snaps the green bar back to its fixed size if anything tries to maximize, enlarge or full-screen it.
class _BarGuard with WindowListener {
  _BarGuard(this.size);
  final Size size;
  bool _fixing = false;

  Future<void> _fix() async {
    if (_fixing) return;
    _fixing = true;
    try {
      if (await windowManager.isFullScreen()) await windowManager.setFullScreen(false);
      if (await windowManager.isMaximized()) await windowManager.unmaximize();
      final cur = await windowManager.getSize();
      if ((cur.width - size.width).abs() > 2 || (cur.height - size.height).abs() > 2) {
        await windowManager.setSize(size);
      }
    } catch (_) {}
    _fixing = false;
  }

  @override
  void onWindowMaximize() => _fix();
  @override
  void onWindowResize() => _fix();
  @override
  void onWindowResized() => _fix();
  @override
  void onWindowEnterFullScreen() => _fix();
}
