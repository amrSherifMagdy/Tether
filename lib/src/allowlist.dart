import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

class AllowedCommand {
  AllowedCommand(this.key, Map<String, dynamic> j)
    : description = j['description'] as String? ?? key,
      openUrl = j['type'] == 'openUrl' ? Uri.parse(j['url'] as String) : null,
      executable = (j['executable'] as String?) ?? '',
      fixedArgs = List<String>.from(j['fixedArgs'] ?? const []),
      allowExtraArgs = j['allowExtraArgs'] == true,
      extraArgPattern = j['extraArgPattern'] != null
          ? RegExp(j['extraArgPattern'] as String)
          : null,
      maxExtraArgs = (j['maxExtraArgs'] ?? 0) as int;

  final String key;
  final String description;
  final String executable;

  /// Fixed URL for type=openUrl commands. Opened with the OS URL API, never a shell, never remote-supplied.
  final Uri? openUrl;
  final List<String> fixedArgs;
  final bool allowExtraArgs;
  final RegExp? extraArgPattern;
  final int maxExtraArgs;

  /// Returns an error message, or null if the extra args are acceptable.
  String? validateArgs(List<String> args) {
    if (args.isEmpty) return null;
    if (!allowExtraArgs) return 'This command does not accept arguments';
    if (args.length > maxExtraArgs) return 'Too many arguments';
    final p = extraArgPattern;
    if (p != null && !args.every(p.hasMatch))
      return 'Argument rejected by pattern';
    return null;
  }
}

class Allowlist {
  Allowlist(this.commands);
  final Map<String, AllowedCommand> commands;

  static Future<Allowlist> load() async {
    final raw = jsonDecode(
      await rootBundle.loadString('assets/allowlist.json'),
    ) as Map<String, dynamic>;
    final cmds = (raw['commands'] as Map<String, dynamic>).map(
      (k, v) => MapEntry(k, AllowedCommand(k, v as Map<String, dynamic>)),
    );
    return Allowlist(cmds);
  }

  AllowedCommand? lookup(String key) => commands[key];
}
