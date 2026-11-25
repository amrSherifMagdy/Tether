import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

import 'allowlist.dart';

class RunResult {
  RunResult(this.ok, this.output);
  final bool ok;
  final String output;
}

/// Runs an allowlisted command. Never uses a shell string: executable and args are passed separately.
class CommandRunner {
  static const _timeout = Duration(seconds: 30);
  static const _maxOutput = 8000;

  // Command interpreters never get remotely supplied arguments.
  static const _interpreters = {
    'cmd.exe',
    'cmd',
    'powershell.exe',
    'powershell',
    'pwsh.exe',
    'pwsh',
    'wscript.exe',
    'cscript.exe',
    'mshta.exe',
    'sh',
    'bash',
    'zsh',
  };

  Future<RunResult> run(AllowedCommand cmd, List<String> extraArgs) async {
    final err = cmd.validateArgs(extraArgs);
    if (err != null) return RunResult(false, err);
    final url = cmd.openUrl;
    if (url != null) {
      if (extraArgs.isNotEmpty || url.scheme != 'https' || url.host.isEmpty) {
        return RunResult(false, 'Invalid openUrl command');
      }
      try {
        final ok = await launchUrl(url, mode: LaunchMode.externalApplication);
        return RunResult(ok, ok ? 'Opened $url' : 'Could not open $url');
      } catch (e) {
        return RunResult(false, 'Failed to open URL: $e');
      }
    }
    final exeName = cmd.executable.split(RegExp(r'[\\/]')).last.toLowerCase();
    if (extraArgs.isNotEmpty && _interpreters.contains(exeName)) {
      return RunResult(
        false,
        'Arguments are not allowed for command interpreters',
      );
    }
    final args = [...cmd.fixedArgs, ...extraArgs];
    try {
      final proc = await Process.start(cmd.executable, args, runInShell: false);
      final out = StringBuffer();
      proc.stdout.transform(utf8.decoder).listen(out.write);
      proc.stderr.transform(utf8.decoder).listen(out.write);
      final code = await proc.exitCode.timeout(
        _timeout,
        onTimeout: () {
          // GUI apps (notepad, calc) keep running; that is fine.
          return 0;
        },
      );
      var text = out.toString();
      if (text.length > _maxOutput)
        text = '${text.substring(0, _maxOutput)}\n...(truncated)';
      return RunResult(code == 0, text.isEmpty ? 'exit code $code' : text);
    } catch (e) {
      return RunResult(false, 'Failed to start: $e');
    }
  }
}
