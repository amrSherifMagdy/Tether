import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Append-only local log of every command seen and what you decided.
class LocalLog {
  File? _file;

  Future<File> _f() async {
    if (_file != null) return _file!;
    final dir = await getApplicationSupportDirectory();
    _file = File('${dir.path}${Platform.pathSeparator}laptop_link.log');
    return _file!;
  }

  Future<String> path() async => (await _f()).path;

  Future<void> add(String line) async {
    final f = await _f();
    await f.writeAsString(
      '${DateTime.now().toIso8601String()}  $line\n',
      mode: FileMode.append,
    );
  }
}
