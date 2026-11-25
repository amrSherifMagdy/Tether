import 'dart:async';

import 'package:flutter/material.dart';

import 'account_menu.dart';
import 'models.dart';
import 'session_console.dart';

/// Web console. Tab 1: queue an allowlisted command. Tab 2: live session (screenshot + actions).
class ConsolePage extends StatelessWidget {
  const ConsolePage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Tether'),
          actions: [const AccountMenu()],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Commands'),
              Tab(text: 'Session'),
            ],
          ),
        ),
        body: const TabBarView(children: [_CommandsTab(), SessionPanel()]),
      ),
    );
  }
}

class _CommandsTab extends StatefulWidget {
  const _CommandsTab();
  @override
  State<_CommandsTab> createState() => _CommandsTabState();
}

class _CommandsTabState extends State<_CommandsTab> {
  final _key = TextEditingController();
  final _args = TextEditingController();
  List<CommandDoc> _docs = [];
  String? _err;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _load();
    _t = Timer.periodic(const Duration(seconds: 3), (_) => _load());
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final rows = await sb
          .from('commands')
          .select()
          .order('created_at', ascending: false)
          .limit(50);
      if (mounted) {
        setState(() {
          _docs = rows.map<CommandDoc>((r) => CommandDoc.fromRow(r)).toList();
          _err = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    }
  }

  Future<void> _send() async {
    final key = _key.text.trim();
    if (key.isEmpty) return;
    try {
      await sb.from('commands').insert({
        'command_key': key,
        'args': _args.text.trim().isEmpty ? [] : [_args.text.trim()],
      });
      _key.clear();
      _args.clear();
      _load();
    } catch (e) {
      setState(() => _err = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _key,
                  decoration: const InputDecoration(
                    labelText: 'Command key (e.g. open_notepad)',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _args,
                  decoration: const InputDecoration(
                    labelText: 'Optional argument',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: _send, child: const Text('Queue')),
            ],
          ),
          if (_err != null)
            Text('Error: $_err', style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              children: [
                for (final c in _docs)
                  ListTile(
                    title: Text('${c.commandKey} ${c.args.join(' ')}'),
                    subtitle: Text(
                      c.result.isEmpty ? '' : c.result,
                      maxLines: 6,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Text(c.status),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
