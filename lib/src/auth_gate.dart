import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'lang.dart';
import 'models.dart';

/// Email + password sign-in, sign-up (invite-only, email verification) and password reset.
/// Use the SAME account on the web console and the desktop app.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.child});
  final Widget child;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _pass2 = TextEditingController();
  bool _signUpMode = false;
  String? _error, _info;
  bool _recovery = false;

  @override
  void initState() {
    super.initState();
    sb.auth.onAuthStateChange.listen((s) {
      if (s.event == AuthChangeEvent.passwordRecovery && mounted)
        setState(() => _recovery = true);
    });
  }

  Future<void> _run(Future<void> Function() f) async {
    setState(() {
      _error = null;
      _info = null;
    });
    try {
      await f();
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  Future<void> _signIn() => _run(() async {
    await sb.auth.signInWithPassword(
      email: _email.text.trim(),
      password: _pass.text,
    );
  });

  Future<void> _signUp() => _run(() async {
    if (_pass.text.length < 8) {
      throw AuthException(
        pick(
          'Password must be at least 8 characters.  |  الباسورد لازم يكون 8 حروف على الأقل.',
        ),
      );
    }
    if (_pass.text != _pass2.text) {
      throw AuthException(
        pick('The two passwords do not match.  |  الباسوردين مش زي بعض.'),
      );
    }
    try {
      await sb.auth.signUp(
        email: _email.text.trim(),
        password: _pass.text,
        emailRedirectTo: siteUrl,
      );
      setState(() {
        _info = pick(
          'Check your email and click the verification link, then come back here and sign in.  |  افتح إيميلك واضغط لينك التأكيد، وبعدين ارجع هنا وسجّل دخول.',
        );
        _signUpMode = false;
        _pass.clear();
        _pass2.clear();
      });
    } on AuthException catch (e) {
      // The invite gate rejects emails that are not on the list with a generic database error.
      if (e.message.toLowerCase().contains('database error')) {
        throw AuthException(
          pick(
            'This email is not invited yet. Ask the owner to add it.  |  الإيميل ده لسه متدعاش. اطلب من صاحب التطبيق يضيفه.',
          ),
        );
      }
      rethrow;
    }
  });

  Future<void> _reset() => _run(() async {
    final e = _email.text.trim();
    if (e.isEmpty)
      throw AuthException(
        pick('Type your email first.  |  اكتب إيميلك الأول.'),
      );
    await sb.auth.resetPasswordForEmail(e, redirectTo: siteUrl);
    setState(
      () => _info = pick(
        'If that email has an account, a reset link is on its way.  |  لو الإيميل ده له حساب، لينك تغيير الباسورد في الطريق.',
      ),
    );
  });

  Future<void> _setNew() => _run(() async {
    await sb.auth.updateUser(UserAttributes(password: _pass.text));
    setState(() => _recovery = false);
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: sb.auth.onAuthStateChange,
      builder: (context, snap) {
        final signedIn = sb.auth.currentSession != null;
        if (signedIn && !_recovery) return widget.child;
        return LangBuilder(builder: (_) => _screen());
      },
    );
  }

  Widget _screen() {
    return Scaffold(
      appBar: AppBar(actions: const [LangButton()]),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.asset('assets/logo_lockup.jpg', width: 180),
              ),
              const SizedBox(height: 12),
              if (!_recovery)
                TextField(
                  controller: _email,
                  decoration: InputDecoration(
                    labelText: pick('Email  |  الإيميل'),
                  ),
                ),
              TextField(
                controller: _pass,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: pick(
                    _recovery
                        ? 'New password  |  الباسورد الجديد'
                        : 'Password  |  الباسورد',
                  ),
                ),
              ),
              if (_signUpMode && !_recovery)
                TextField(
                  controller: _pass2,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: pick('Password again  |  الباسورد تاني'),
                  ),
                ),
              const SizedBox(height: 12),
              if (_recovery)
                FilledButton(
                  onPressed: _setNew,
                  child: Text(pick('Set new password  |  حفظ الباسورد الجديد')),
                )
              else ...[
                FilledButton(
                  onPressed: _signUpMode ? _signUp : _signIn,
                  child: Text(
                    pick(
                      _signUpMode
                          ? 'Create account  |  إنشاء حساب'
                          : 'Sign in  |  دخول',
                    ),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: () => setState(() {
                        _signUpMode = !_signUpMode;
                        _error = null;
                        _info = null;
                      }),
                      child: Text(
                        pick(
                          _signUpMode
                              ? 'I have an account  |  عندي حساب'
                              : 'Sign up  |  حساب جديد',
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _reset,
                      child: Text(pick('Forgot password  |  نسيت الباسورد')),
                    ),
                  ],
                ),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              if (_info != null)
                Padding(padding: const EdgeInsets.all(8), child: Text(_info!)),
            ],
          ),
        ),
      ),
    );
  }
}
