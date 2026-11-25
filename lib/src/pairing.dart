import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

final _ed = Ed25519();

/// What a controller signs for every action. Exactly these bytes are verified on the laptop.
String signedMessage(String id, String sessionId, int ts, String payload) =>
    '$id|$sessionId|$ts|$payload';

/// Short code shown on the laptop and printed by the controller so you can compare them: AB12-CD34.
Future<String> fingerprint(String pubB64) async {
  final h = await Sha256().hash(base64Decode(pubB64));
  final x = h.bytes
      .take(4)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join()
      .toUpperCase();
  return '${x.substring(0, 4)}-${x.substring(4)}';
}

Future<bool> verifySignature(String pubB64, String msg, String sigB64) async {
  try {
    return await _ed.verify(
      utf8.encode(msg),
      signature: Signature(
        base64Decode(sigB64),
        publicKey: SimplePublicKey(
          base64Decode(pubB64),
          type: KeyPairType.ed25519,
        ),
      ),
    );
  } catch (_) {
    return false;
  }
}

String newUuid() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

/// Laptop side: the approved list lives ONLY in a local file. The cloud cannot change it.
class Trust {
  Map<String, dynamic>? _m;
  File? _f;

  Future<File> _file() async {
    if (_f != null) return _f!;
    final dir = await getApplicationSupportDirectory();
    _f = File('${dir.path}${Platform.pathSeparator}approved_controllers.json');
    return _f!;
  }

  Future<Map<String, dynamic>> _load() async {
    if (_m != null) return _m!;
    final f = await _file();
    try {
      _m = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      _m = {'approved': <String, dynamic>{}, 'denied': <dynamic>[]};
    }
    return _m!;
  }

  Future<void> _save() async =>
      (await _file()).writeAsString(jsonEncode(_m), flush: true);

  Future<bool> isApproved(String pub) async =>
      ((await _load())['approved'] as Map).containsKey(pub);

  Future<bool> isDenied(String pub) async =>
      ((await _load())['denied'] as List).contains(pub);

  Future<void> approve(String pub, String name) async {
    final m = await _load();
    (m['approved'] as Map)[pub] = {
      'name': name,
      'at': DateTime.now().toIso8601String(),
    };
    (m['denied'] as List).remove(pub);
    await _save();
  }

  /// Approved controllers: public key -> name.
  Future<Map<String, String>> approvedList() async {
    final m = (await _load())['approved'] as Map;
    return {
      for (final e in m.entries) '${e.key}': '${(e.value as Map)['name']}',
    };
  }

  /// Revoke: removes the approval. The controller may ask again and will be prompted again.
  Future<void> forget(String pub) async {
    final m = await _load();
    (m['approved'] as Map).remove(pub);
    (m['denied'] as List).remove(pub);
    await _save();
  }

  Future<void> deny(String pub) async {
    final m = await _load();
    (m['approved'] as Map).remove(pub);
    if (!(m['denied'] as List).contains(pub)) (m['denied'] as List).add(pub);
    await _save();
  }
}

/// Browser (web console) side: a key kept in this browser's local storage.
class ControllerIdentity {
  ControllerIdentity._(this._kp, this.publicKey);
  final SimpleKeyPair _kp;
  final String publicKey;

  static Future<ControllerIdentity> load() async {
    final p = await SharedPreferences.getInstance();
    var seed = p.getString('lk_controller_seed');
    if (seed == null) {
      final r = Random.secure();
      seed = base64Encode(List<int>.generate(32, (_) => r.nextInt(256)));
      await p.setString('lk_controller_seed', seed);
    }
    final kp = await _ed.newKeyPairFromSeed(base64Decode(seed));
    final pub = await kp.extractPublicKey();
    return ControllerIdentity._(kp, base64Encode(pub.bytes));
  }

  Future<String> sign(String msg) async =>
      base64Encode((await _ed.sign(utf8.encode(msg), keyPair: _kp)).bytes);

  /// Registers this key as a pairing request (once) and returns its controller id.
  Future<String> register(String name) async {
    final rows = await sb
        .from('controllers')
        .select('id')
        .eq('public_key', publicKey);
    if (rows.isNotEmpty) return '${rows.first['id']}';
    final r = await sb
        .from('controllers')
        .insert({'name': name, 'public_key': publicKey})
        .select('id')
        .single();
    return '${r['id']}';
  }
}
