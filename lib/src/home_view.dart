import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'account_menu.dart';
import 'allowlist.dart';
import 'approval.dart';
import 'extras.dart';
import 'lang.dart';
import 'session_controller.dart';
import 'tray.dart';
import 'version.dart';

/// Label in the chosen language (English or Arabic, never both).
class Bi extends StatelessWidget {
  const Bi(
    this.en,
    this.ar, {
    super.key,
    this.big = false,
    this.bold = false,
    this.color,
  });
  final String en, ar;
  final bool big, bold;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.onSurface;
    return ValueListenableBuilder<bool>(
      valueListenable: isArabic,
      builder: (_, a, __) => Text(
        a ? ar : en,
        style: TextStyle(
          fontSize: big ? (a ? 19 : 20) : 14,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          color: c,
        ),
      ),
    );
  }
}

/// Main window while no session is running (when the session is live you only see the green bar).
class HomeView extends StatefulWidget {
  const HomeView({
    super.key,
    required this.session,
    required this.tray,
    required this.logPath,
    required this.allow,
  });
  final SessionController session;
  final AppTray tray;
  final String? logPath;
  final Allowlist? allow;

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  Map<String, String> _devices = {};

  @override
  void initState() {
    super.initState();
    _loadDevices();
    widget.session.addListener(_loadDevices);
  }

  @override
  void dispose() {
    widget.session.removeListener(_loadDevices);
    super.dispose();
  }

  Future<void> _loadDevices() async {
    final d = await widget.session.trust.approvedList();
    if (mounted) setState(() => _devices = d);
  }

  @override
  Widget build(BuildContext context) => LangBuilder(builder: _body);

  Widget _body(BuildContext context) {
    final s = widget.session;
    final waiting = s.pairName != null;
    final failed = s.error != null;
    final (Color color, IconData icon, String en, String ar) = waiting
        ? (
            Colors.red.shade800,
            Icons.hourglass_top,
            'Waiting for your approval',
            'في انتظار موافقتك',
          )
        : failed
        ? (
            Colors.blueGrey.shade700,
            Icons.error_outline,
            'Not connected',
            'غير متصل',
          )
        : (Colors.grey.shade700, Icons.pause_circle_outline, 'Paused', 'متوقف');

    return Scaffold(
      appBar: AppBar(
        title: const TetherTitle(),
        actions: const [LangButton(), AccountMenu()],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(icon, color: color, size: 34),
                    const SizedBox(width: 10),
                    Bi(en, ar, big: true, bold: true, color: color),
                  ],
                ),
                const SizedBox(height: 16),
                if (waiting)
                  _pairCard(context, s)
                else
                  _connectCard(context, s),
                if (failed && !waiting)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      s.error!,
                      style: TextStyle(
                        color: Colors.blueGrey.shade700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                const UpdateBanner(),
                _modeCard(context, s),
                const SizedBox(height: 16),
                ValueListenableBuilder<bool>(
                  valueListenable: widget.tray.autostart,
                  builder: (_, on, __) => Card(
                    child: SwitchListTile(
                      title: const Bi('Start with Windows', 'تشغيل مع ويندوز'),
                      subtitle: Text(
                        pick(
                          'Opens by itself when you sign in to Windows and connects the assistant (a green bar shows).  |  بيفتح لوحده مع ويندوز ويوصّل المساعد (الشريط الأخضر بيظهر).',
                        ),
                        style: const TextStyle(fontSize: 12),
                      ),
                      value: on,
                      onChanged: (v) => widget.tray.setAutostart(v),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  pick(
                    'When the assistant asks permission, the orange bar shows Allow and Deny. You can also answer with the keyboard: Ctrl+Alt+Y = Allow, Ctrl+Alt+N = Deny. No answer in 60 seconds = Deny.  |  لما المساعد يطلب إذن، الشريط البرتقالي بيظهر Allow و Deny. وتقدر ترد من الكيبورد: Ctrl+Alt+Y = موافقة، Ctrl+Alt+N = رفض. من غير رد خلال 60 ثانية = رفض.',
                  ),
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                ),
                const SizedBox(height: 8),
                Text(
                  pick(
                    'Your assistant can see your screen and use the mouse and keyboard only while connected. It never types your passwords. Stop it any time: the STOP button on the green bar, or Ctrl+Alt+Shift+S.  |  المساعد بيشوف شاشتك ويستخدم الماوس والكيبورد وهو متصل بس، ومبيكتبش الباسوردات أبداً. توقفه في أي وقت بزرار STOP في الشريط الأخضر أو Ctrl+Alt+Shift+S.',
                  ),
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                ),
                const SizedBox(height: 16),
                _advanced(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _modeCard(BuildContext context, SessionController s) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Bi('Control mode', 'وضع التحكم', bold: true),
            Text('v$kVersion  build $kBuild', style: const TextStyle(fontSize: 11, color: Colors.grey)),
            if (!s.modeChosen)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  pick('Choose a mode to start. Nothing connects until you do.  |  اختار وضع عشان يبدأ. مفيش اتصال قبل ما تختار.'),
                  style: const TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold),
                ),
              ),
            const SizedBox(height: 4),
            for (final m in ControlMode.values)
              RadioListTile<ControlMode>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: m,
                groupValue: s.modeChosen ? s.mode : null,
                onChanged: (v) => s.setMode(v!),
                title: Text(isArabic.value ? m.titleAr : m.title),
              ),
            Text(
              pick(
                'Questions appear on this laptop only, with Allow / Deny. No answer in 60 seconds counts as Deny. Ask mode asks before every click, typing, key press and opening a link or app (screenshots, scrolling and moving the mouse never ask). Smart mode asks for deleting or closing keys, sign-in or payment windows, sensitive typing, installers and system tools, downloads and bank or payment links.  |  الأسئلة بتظهر على اللابتوب ده بس، بزرار سماح أو رفض. لو متردّش في 60 ثانية يتحسب رفض. وضع "اسألني قبل كل خطوة" بيسأل قبل أي كليك أو كتابة أو زرار أو فتح لينك أو برنامج (اللقطات والسكرول وتحريك الماوس مبتسألش). الوضع الذكي بيسأل عن الحذف وقفل النوافذ ونوافذ الدخول والدفع والكتابة الحساسة والتثبيت وأدوات النظام والتحميل ولينكات البنوك والدفع.',
              ),
              style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _connectCard(BuildContext context, SessionController s) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Bi(
              'The assistant is not connected to this laptop.',
              'المساعد مش متصل باللابتوب ده دلوقتي.',
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: s.modeChosen ? () => s.start(null) : null,
              icon: const Icon(Icons.power_settings_new),
              label: Text(pick('Connect the assistant  |  وصّل المساعد')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pairCard(BuildContext context, SessionController s) {
    return Card(
      color: Colors.red.shade50,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Colors.red.shade700, width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Bi(
              'Allow "${s.pairName}" to control this laptop?',
              'تسمح لـ "${s.pairName}" يتحكم في اللابتوب ده؟',
              bold: true,
            ),
            const SizedBox(height: 10),
            Center(
              child: Text(
                s.pairFp ?? '',
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 3,
                ),
              ),
            ),
            const SizedBox(height: 6),
            const Bi(
              'Tap Allow only if this code is the same one your assistant shows you.',
              'اضغط Allow بس لو الكود ده نفس الكود اللي المساعد قالهولك.',
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => s.answerPairing(false),
                    child: Text(pick('Deny  |  رفض')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => s.answerPairing(true),
                    child: Text(pick('Allow  |  سماح')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _advanced(BuildContext context) {
    return ExpansionTile(
      title: Text(pick('Advanced  |  متقدم')),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pick('Approved devices  |  الأجهزة المسموحة'),
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                if (_devices.isEmpty) Text(pick('None yet  |  لسه مفيش')),
                for (final e in _devices.entries)
                  Row(
                    children: [
                      Expanded(child: Text(e.value)),
                      TextButton(
                        onPressed: () async {
                          await widget.session.trust.forget(e.key);
                          _loadDevices();
                        },
                        child: Text(pick('Remove  |  إزالة')),
                      ),
                    ],
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.history, size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        pick('Tether activity log (stays on this laptop)  |  سجل نشاط Tether (بيفضل على اللابتوب ده)'),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    TextButton(
                      onPressed: widget.logPath == null
                          ? null
                          : () => Process.start('notepad.exe', [widget.logPath!]),
                      child: Text(pick('Open  |  فتح')),
                    ),
                    TextButton(
                      onPressed: widget.logPath == null
                          ? null
                          : () => Clipboard.setData(ClipboardData(text: widget.logPath!)),
                      child: Text(pick('Copy path  |  نسخ المسار')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
