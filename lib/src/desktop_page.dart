import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'allowlist.dart';
import 'extras.dart';
import 'command_runner.dart';
import 'local_log.dart';
import 'account_menu.dart';
import 'models.dart';
import 'session_bar.dart';
import 'session_controller.dart';
import 'home_view.dart';
import 'tray.dart';

/// Desktop agent. Listens for pending commands and NEVER runs one without your tap.
class DesktopPage extends StatefulWidget {
  const DesktopPage({super.key});
  @override
  State<DesktopPage> createState() => _DesktopPageState();
}

class _DesktopPageState extends State<DesktopPage> {
  final _log = LocalLog();
  final _runner = CommandRunner();
  final _askedIds = <String>{};
  Allowlist? _allow;
  bool _dialogOpen = false;
  final _queue = <CommandDoc>[];
  String? _logPath;
  late final SessionController _session;
  late final AppTray _tray;

  String get _uid => myUid;
  RealtimeChannel? _cmdCh;
  Timer? _cmdPoll;

  @override
  void initState() {
    super.initState();
    _session = SessionController(_uid, _log);
    _tray = AppTray(_session, _log);
    _session.loadMode();
    checkForUpdate();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) offerShortcutOnce(context);
    });
    _session.watchPairing();
    _tray.init().catchError((e) => _log.add('tray init failed: $e'));
    // Live as soon as the app opens, but only once a control mode has been chosen (loadMode starts it).
    // It ends on STOP, the hotkey, or when the app closes.
    _session.addListener(() {
      if (!_session.active) _next();
    });
    Allowlist.load().then((a) => setState(() => _allow = a));
    _log.path().then((p) => setState(() => _logPath = p));
    // New commands arrive over realtime; a light poll is the safety net.
    void take(Map<String, dynamic> row) {
      if (row['status'] != Status.pending) return;
      if (_askedIds.add('${row['id']}'))
        _queue.add(CommandDoc.fromRow(Map<String, dynamic>.from(row)));
    }

    Future<void> fetch() async {
      try {
        final rows = await sb
            .from('commands')
            .select()
            .eq('status', Status.pending)
            .order('created_at')
            .limit(20);
        for (final r in rows) {
          take(Map<String, dynamic>.from(r));
        }
        _next();
      } catch (e) {
        _log.add('command poll error: $e');
      }
    }

    _cmdCh = sb
        .channel('commands-$_uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'commands',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: _uid,
          ),
          callback: (p) {
            take(Map<String, dynamic>.from(p.newRecord));
            _next();
          },
        )
        .subscribe();
    _cmdPoll = Timer.periodic(const Duration(seconds: 5), (_) => fetch());
    fetch();
  }

  /// Moves a command from [from] to [to] with a plain update. No client transaction:
  /// A client transaction is not needed: the update is conditional on the current status.
  /// Atomicity comes from firestore.rules instead: an update is accepted only while the
  /// stored status is still [from], and commandKey/args/ownerId are frozen after create.
  /// So a second claim, or a claim of a changed request, is rejected by the server.
  Future<bool> _transition(
    CommandDoc c,
    String from,
    String to, {
    String? result,
  }) async {
    try {
      // Only moves the row if it is still in the expected state: the claim happens exactly once.
      final rows = await sb
          .from('commands')
          .update({'status': to, if (result != null) 'result': result})
          .eq('id', c.id)
          .eq('status', from)
          .select('id');
      return rows.isNotEmpty;
    } catch (e) {
      await _log.add('${c.id} transition $from -> $to refused or failed: $e');
      return false;
    }
  }

  Future<void> _finish(
    CommandDoc c,
    String from,
    String status,
    String result,
  ) async {
    final ok = await _transition(c, from, status, result: result);
    await _log.add(
      '${c.id} ${c.commandKey} $from -> $status${ok ? '' : ' (REFUSED: request changed)'}',
    );
  }

  Future<void> _next() async {
    if (_session.active ||
        _dialogOpen ||
        _queue.isEmpty ||
        _allow == null ||
        !mounted)
      return;
    final c = _queue.removeAt(0);
    final allowed = _allow!.lookup(c.commandKey);
    if (allowed == null) {
      await _finish(
        c,
        Status.pending,
        Status.denied,
        'Command "${c.commandKey}" is not in the allowlist',
      );
      return _next();
    }
    final argErr = allowed.validateArgs(c.args);
    if (argErr != null) {
      await _finish(c, Status.pending, Status.denied, argErr);
      return _next();
    }
    _dialogOpen = true;
    await _log.add('${c.id} requested: ${c.commandKey} ${c.args}');
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Approve command?'),
        content: Text(
          '${allowed.description}\n\n'
          'Runs: ${allowed.openUrl != null ? 'open ${allowed.openUrl}' : '${allowed.executable} ${[...allowed.fixedArgs, ...c.args].join(' ')}'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Reject'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
    _dialogOpen = false;
    if (ok == true) {
      // Claim exactly this request once. If it changed or was already claimed, do not run.
      final claimed = await _transition(c, Status.pending, Status.running);
      if (!claimed) {
        await _log.add('${c.id} ${c.commandKey} claim refused, not executed');
      } else {
        await _log.add('${c.id} ${c.commandKey} approved and claimed');
        final r = await _runner.run(allowed, c.args);
        await _finish(
          c,
          Status.running,
          r.ok ? Status.done : Status.failed,
          r.output,
        );
      }
    } else {
      await _finish(
        c,
        Status.pending,
        Status.rejected,
        'Rejected by user on the laptop',
      );
    }
    _next();
  }

  @override
  void dispose() {
    _cmdPoll?.cancel();
    if (_cmdCh != null) sb.removeChannel(_cmdCh!);
    _tray.dispose();
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _session,
      builder: (context, _) {
        if (_session.active) return SessionBar(controller: _session);
        return HomeView(
          session: _session,
          tray: _tray,
          logPath: _logPath,
          allow: _allow,
        );
      },
    );
  }
}
