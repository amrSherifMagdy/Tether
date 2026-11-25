import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';
import 'pairing.dart';

/// Web side of session mode: shows the latest laptop screenshot (with a coordinate grid)
/// and sends one JSON action at a time. Actions only run while the laptop's own session is active.
class SessionPanel extends StatefulWidget {
  const SessionPanel({super.key});
  @override
  State<SessionPanel> createState() => _SessionPanelState();
}

class _SessionPanelState extends State<SessionPanel> {
  final _json = TextEditingController();
  String? _err;
  Timer? _t;
  Map<String, dynamic>? _session;
  List<Map<String, dynamic>> _actions = [];
  Map<String, dynamic>? _frameRow;
  String _lastB64 = '';
  Uint8List? _bytes;
  RealtimeChannel? _ch;
  String? _chSid;

  @override
  void initState() {
    super.initState();
    _poll();
    _t = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
  }

  @override
  void dispose() {
    _t?.cancel();
    _ch?.unsubscribe();
    super.dispose();
  }

  Future<void> _poll() async {
    try {
      final rows = await sb
          .from('sessions')
          .select()
          .eq('status', 'active')
          .order('created_at', ascending: false)
          .limit(1);
      final s = rows.isEmpty ? null : rows.first;
      List<Map<String, dynamic>> acts = [];
      Map<String, dynamic>? fr = _frameRow;
      if (s != null) {
        acts = List<Map<String, dynamic>>.from(
          await sb
              .from('actions')
              .select('type,status,result,created_at')
              .eq('session_id', s['id'])
              .order('created_at', ascending: false)
              .limit(6),
        );
        _listen('${s['id']}');
        if (fr == null || '${fr['session_id']}' != '${s['id']}') {
          fr = await sb
              .from('frames')
              .select()
              .eq('session_id', s['id'])
              .maybeSingle();
        }
      }
      if (mounted) {
        setState(() {
          _session = s;
          _actions = acts;
          if (s == null) {
            _frameRow = null;
          } else if (fr != null) {
            _frameRow = fr;
          }
          _err = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    }
  }

  /// Live frames: each new screenshot is pushed over realtime.
  void _listen(String sid) {
    if (_chSid == sid) return;
    _ch?.unsubscribe();
    _chSid = sid;
    _ch = sb
        .channel('frames-$sid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'frames',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'session_id',
            value: sid,
          ),
          callback: (p) {
            if (mounted && p.newRecord.isNotEmpty)
              setState(() => _frameRow = p.newRecord);
          },
        )
        .subscribe();
  }

  ControllerIdentity? _ident;
  String? _cid;

  Future<void> _send(String sid) async {
    try {
      final m = jsonDecode(_json.text) as Map<String, dynamic>;
      final type = m.remove('type');
      if (type is! String) throw 'missing "type"';
      _ident ??= await ControllerIdentity.load();
      final cid = _cid ??= await _ident!.register('Web console');
      final id = newUuid();
      final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final payload = jsonEncode({'type': type, 'params': m});
      final sig = await _ident!.sign(signedMessage(id, sid, ts, payload));
      await sb.from('actions').insert({
        'id': id,
        'session_id': sid,
        'type': type,
        'params': m,
        'controller_id': cid,
        'payload': payload,
        'sig': sig,
        'sig_ts': ts,
      });
      setState(() {
        _err = null;
        _json.clear();
      });
      _poll();
    } catch (e) {
      setState(() => _err = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _session;
    if (s == null) {
      return Center(
        child: Text(
          _err == null
              ? 'No active session. Open the laptop app (it starts a session by itself).'
              : 'Error: $_err',
        ),
      );
    }
    final exp = DateTime.tryParse('${s['expires_at']}');
    final left = exp?.difference(DateTime.now());
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            left == null
                ? 'Session ${s['id']}  |  live, no time limit'
                : 'Session ${s['id']}  |  ${left.inMinutes}m ${left.inSeconds.remainder(60)}s left',
            style: const TextStyle(fontSize: 12),
          ),
          _frame(),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _json,
                  decoration: const InputDecoration(
                    labelText:
                        'Action JSON, e.g. {"type":"click","x":100,"y":200}',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => _send('${s['id']}'),
                child: const Text('Send'),
              ),
            ],
          ),
          if (_err != null)
            Text(
              _err!,
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
          Expanded(
            child: ListView(
              children: [
                for (final d in _actions)
                  Text(
                    '${d['type']}  ${d['status']}  ${d['result'] ?? ''}',
                    style: const TextStyle(fontSize: 12),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _frame() {
    final d = _frameRow;
    if (d == null)
      return const SizedBox(
        height: 200,
        child: Center(child: Text('Waiting for first screenshot...')),
      );
    final b64 = d['image_b64'] as String;
    if (b64 != _lastB64) {
      _lastB64 = b64;
      _bytes = base64Decode(b64);
    }
    final w = (d['width'] as num).toDouble(),
        h = (d['height'] as num).toDouble();
    return SizedBox(
      width: w,
      height: h,
      child: Stack(
        children: [
          Image.memory(_bytes!, width: w, height: h, gaplessPlayback: true),
          CustomPaint(size: Size(w, h), painter: _GridPainter()),
        ],
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = const Color(0x44FF00FF)
      ..strokeWidth = 1;
    for (double x = 100; x < size.width; x += 100) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
      _label(canvas, '${x.toInt()}', Offset(x + 2, 2));
    }
    for (double y = 100; y < size.height; y += 100) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
      _label(canvas, '${y.toInt()}', Offset(2, y + 2));
    }
  }

  void _label(Canvas c, String t, Offset o) {
    final tp = TextPainter(
      text: TextSpan(
        text: t,
        style: const TextStyle(color: Color(0xFFFF00FF), fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, o);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
