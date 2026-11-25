import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'lang.dart';
import 'models.dart';

/// Account menu for the signed-in app bar: shows the email, Change password, Sign out.
class AccountMenu extends StatelessWidget {
  const AccountMenu({super.key});

  @override
  Widget build(BuildContext context) {
    final email = sb.auth.currentUser?.email ?? '';
    return PopupMenuButton<String>(
      tooltip: pick('Account  |  الحساب'),
      icon: const Icon(Icons.account_circle),
      onSelected: (v) {
        if (v == 'pw') {
          showDialog<void>(
            context: context,
            builder: (_) =>
                LangBuilder(builder: (_) => const _ChangePasswordDialog()),
          );
        } else if (v == 'out') {
          sb.auth.signOut();
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem<String>(enabled: false, child: Text(email)),
        PopupMenuItem<String>(
          value: 'pw',
          child: Text(pick('Change password  |  تغيير الباسورد')),
        ),
        PopupMenuItem<String>(
          value: 'out',
          child: Text(pick('Sign out  |  تسجيل خروج')),
        ),
      ],
    );
  }
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _cur = TextEditingController();
  final _new = TextEditingController();
  final _again = TextEditingController();
  String? _error;
  bool _busy = false, _done = false;

  Future<void> _save() async {
    if (_new.text.length < 8) {
      setState(
        () => _error = pick(
          'New password must be at least 8 characters.  |  الباسورد الجديد لازم 8 حروف على الأقل.',
        ),
      );
      return;
    }
    if (_new.text != _again.text) {
      setState(
        () => _error = pick(
          'The two new passwords do not match.  |  الباسوردين الجدد مش زي بعض.',
        ),
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Re-check the current password first, so a stolen open window cannot change it silently.
      await sb.auth.signInWithPassword(
        email: sb.auth.currentUser!.email!,
        password: _cur.text,
      );
      await sb.auth.updateUser(UserAttributes(password: _new.text));
      setState(() => _done = true);
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(pick('Change password  |  تغيير الباسورد')),
      content: SizedBox(
        width: 320,
        child: _done
            ? Text(pick('Password changed.  |  تم تغيير الباسورد.'))
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _cur,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: pick('Current password  |  الباسورد الحالي'),
                    ),
                  ),
                  TextField(
                    controller: _new,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: pick(
                        'New password (8+ characters)  |  الباسورد الجديد (8+ حروف)',
                      ),
                    ),
                  ),
                  TextField(
                    controller: _again,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: pick(
                        'New password again  |  الباسورد الجديد تاني',
                      ),
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(pick(_done ? 'Close  |  إغلاق' : 'Cancel  |  إلغاء')),
        ),
        if (!_done)
          FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(pick('Save  |  حفظ')),
          ),
      ],
    );
  }
}
