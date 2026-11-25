import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'home_view.dart' show Bi;
import 'lang.dart';

const _consentVersion = 'v1';

/// First run: plain notice about what the assistant can do. The child (which starts the
/// assistant connection) is not built until the person taps "I understand".
class ConsentGate extends StatefulWidget {
  const ConsentGate({super.key, required this.child});
  final Widget child;
  @override
  State<ConsentGate> createState() => _ConsentGateState();
}

class _ConsentGateState extends State<ConsentGate> {
  bool? _ok;
  File? _f;

  @override
  void initState() {
    super.initState();
    () async {
      final dir = await getApplicationSupportDirectory();
      _f = File(
        '${dir.path}${Platform.pathSeparator}consent_$_consentVersion.txt',
      );
      if (mounted) setState(() => _ok = _f!.existsSync());
    }();
  }

  Future<void> _accept() async {
    await _f!.writeAsString(DateTime.now().toIso8601String());
    if (mounted) setState(() => _ok = true);
  }

  @override
  Widget build(BuildContext context) {
    return LangBuilder(builder: _view);
  }

  Widget _view(BuildContext context) {
    if (_ok == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_ok!) return widget.child;
    const items = <List<String>>[
      [
        'Your own assistant (the one you chose) can see your screen and use your mouse and keyboard on this laptop, only while the app is open and shows the green bar.',
        'مساعدك انت (اللي اخترته) بيشوف شاشتك ويستخدم الماوس والكيبورد على اللابتوب ده، وهو متصل بس، يعني والتطبيق مفتوح والشريط الأخضر ظاهر.',
      ],
      [
        'It only works after you tap Allow on a code that you compare with your assistant. Nobody else can control this laptop.',
        'مفيش حد يتحكم غير بعد ما تضغط Allow وتقارن الكود مع مساعدك. أي حد تاني مش هيقدر.',
      ],
      [
        'The assistant never types your passwords. Do not ask it to.',
        'المساعد مبيكتبش الباسوردات. متطلبش منه كده.',
      ],
      [
        'Stop it any time: the STOP button on the green bar, the hotkey Ctrl+Alt+Shift+S, or close the app. Remove an approved assistant in Advanced > Approved devices.',
        'وقّفه في أي وقت: زرار STOP، أو Ctrl+Alt+Shift+S، أو اقفل التطبيق. وتشيل أي مساعد مسموح من Advanced > Approved devices.',
      ],
      [
        'Screenshots pass briefly through the app owner\'s Supabase service (deleted within about a minute). The owner runs that service and is its administrator, but the app does not store your screen. The full activity log stays only on this laptop.',
        'اللقطات بتعدي لحظات على خدمة Supabase بتاعة صاحب التطبيق (بتتمسح في حوالي دقيقة). صاحب التطبيق هو أدمن الخدمة دي، لكن التطبيق مبيخزّنش شاشتك. سجل النشاط الكامل بيفضل على اللابتوب ده بس.',
      ],
      [
        'To revoke everything: Remove all approved devices, sign out, and close or uninstall the app (delete the folder).',
        'عشان تلغي كل حاجة: شيل كل الأجهزة المسموحة، سجّل خروج، واقفل التطبيق أو امسح الفولدر.',
      ],
    ];
    return Scaffold(
      appBar: AppBar(title: const TetherTitle(), actions: const [LangButton()]),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.asset('assets/logo_lockup.jpg', width: 200),
                  ),
                ),
                const SizedBox(height: 14),
                const Bi(
                  'Before you start',
                  'قبل ما تبدأ',
                  big: true,
                  bold: true,
                ),
                const SizedBox(height: 14),
                for (final i in items) ...[
                  Bi('\u2022 ${i[0]}', '\u2022 ${i[1]}'),
                  const SizedBox(height: 10),
                ],
                const SizedBox(height: 10),
                FilledButton(
                  onPressed: _accept,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(pick('I understand  |  فاهم')),
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => exit(0),
                  child: Text(pick('Close the app  |  اقفل التطبيق')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
