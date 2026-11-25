/// Control modes and the rules that decide when the person at the laptop is asked.
/// Everything here is local. Approvals are shown and answered on the laptop only.
enum ControlMode { ask, auto, smart }

extension ControlModeText on ControlMode {
  String get label => switch (this) {
    ControlMode.ask => 'ASK',
    ControlMode.auto => 'AUTO',
    ControlMode.smart => 'SMART',
  };
  String get title => switch (this) {
    ControlMode.ask => 'Ask before every step',
    ControlMode.auto => 'Do it directly (never ask)',
    ControlMode.smart => 'Ask only for important actions',
  };
  String get titleAr => switch (this) {
    ControlMode.ask => 'اسألني قبل كل خطوة',
    ControlMode.auto => 'نفّذ على طول (من غير ما تسأل)',
    ControlMode.smart => 'اسألني في المهم بس',
  };
  static ControlMode parse(String? s) => ControlMode.values.firstWhere(
    (m) => m.name == s,
    orElse: () => ControlMode.smart,
  );
}

/// Action types that only look or wait. They never ask in ask mode.
const _passive = {'screenshot', 'wait', 'move', 'scroll'};

bool _has(String s, List<String> words) {
  final l = s.toLowerCase();
  return words.any(l.contains);
}

const _titleWords = [
  'delete',
  'remove',
  'uninstall',
  'install',
  'setup',
  'purchase',
  'buy',
  'payment',
  'checkout',
  'pay now',
  'place order',
  'confirm',
  'send',
  'transfer',
  'unsaved',
  'save changes',
  'do you want to save',
  'administrator',
  'user account control',
  'password',
  'format',
  'erase',
  'reset',
  'wipe',
  'permanently',
  'bank',
  'wallet',
  'cvv',
];

const _typeWords = [
  'password',
  'passcode',
  'passwd',
  'pin ',
  'otp',
  'cvv',
  'card number',
  'seed phrase',
  'secret',
  'iban',
  'ssn',
  'rm -rf',
  'del /',
  'rmdir',
  'format ',
  'shutdown',
  'reg delete',
  'powershell',
  'invoke-expression',
  'iex ',
  'curl ',
  'wget ',
];

const _appWords = [
  'powershell',
  'cmd',
  'command prompt',
  'terminal',
  'regedit',
  'registry',
  'install',
  'setup',
  'uninstall',
  'diskpart',
  'disk management',
  'services',
  'task scheduler',
  'group policy',
];

const _urlWords = [
  'bank',
  'pay',
  'checkout',
  'wallet',
  'billing',
  'invoice',
  'purchase',
  'login',
  'signin',
  'account',
  'password',
];

const _downloadExt = [
  '.exe',
  '.msi',
  '.bat',
  '.cmd',
  '.ps1',
  '.scr',
  '.zip',
  '.iso',
  '.vbs',
  '.jar',
];

const _dangerKeys = {
  'alt+f4',
  'ctrl+w',
  'ctrl+q',
  'delete',
  'shift+delete',
  'ctrl+shift+delete',
  'ctrl+shift+esc',
  'ctrl+alt+delete',
  'win+r',
};

final _cardLike = RegExp(r'(?:\d[ -]?){13,19}');

/// Why an action counts as important (smart mode), or null when it does not.
/// [title] is the title of the window in front right now.
String? importantReason(String type, Map<String, dynamic> p, String title) {
  switch (type) {
    case 'type':
      final t = '${p['text']}';
      if (_has(t, _typeWords)) return 'typing something that looks sensitive';
      if (_cardLike.hasMatch(t))
        return 'typing what looks like a card or ID number';
      if (_has(title, [
        'password',
        'sign in',
        'log in',
        'user account control',
      ])) {
        return 'typing in a sign-in or admin window';
      }
      return null;
    case 'key':
      final c = '${p['combo']}'.toLowerCase().replaceAll(' ', '');
      if (_dangerKeys.contains(c))
        return 'a key that closes, deletes or opens system tools ($c)';
      if ((c == 'enter' || c == 'space') && _has(title, _titleWords)) {
        return 'confirming in a window titled "$title"';
      }
      return null;
    case 'click':
      if (_has(title, _titleWords))
        return 'clicking in a window titled "$title"';
      return null;
    case 'open_url':
      final u = '${p['url']}'.toLowerCase();
      if (u.startsWith('http://')) return 'opening an unencrypted link';
      final path = u.split('?').first;
      if (_downloadExt.any(path.endsWith))
        return 'opening a file download link';
      if (_has(u, _urlWords)) return 'opening a bank, payment or account page';
      return null;
    case 'open_app':
      if (_has('${p['name']}', _appWords))
        return 'opening a system or installer tool';
      return null;
  }
  return null;
}

/// Ask mode asks for everything that acts. Screenshots, waits, moves and scrolls never ask.
String? askModeReason(String type) =>
    _passive.contains(type) ? null : 'ask-before-every-step mode';

String describeAction(String type, Map<String, dynamic> p, String title) {
  String cut(String s, int n) => s.length > n ? '${s.substring(0, n)}...' : s;
  final where = title.isEmpty ? '' : ' in "${cut(title, 28)}"';
  switch (type) {
    case 'click':
      return '${p['button'] == 'right' ? 'right-click' : 'click'}${(p['count'] ?? 1) == 2 ? ' x2' : ''} at (${p['x']}, ${p['y']})$where';
    case 'type':
      return 'type "${cut('${p['text']}'.replaceAll('\n', ' '), 50)}"$where';
    case 'key':
      return 'press ${p['combo']}$where';
    case 'open_url':
      return 'open ${cut('${p['url']}', 60)}';
    case 'open_app':
      return 'open app "${cut('${p['name']}', 30)}"';
  }
  return type;
}
