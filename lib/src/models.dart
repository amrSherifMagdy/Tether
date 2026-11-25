import 'package:supabase_flutter/supabase_flutter.dart';

SupabaseClient get sb => Supabase.instance.client;
String get myUid => sb.auth.currentUser!.id;

/// Status flow: pending -> running -> done | failed, or pending -> rejected | denied.
class Status {
  static const pending = 'pending';
  static const running = 'running';
  static const done = 'done';
  static const failed = 'failed';
  static const rejected = 'rejected'; // you tapped Reject
  static const denied = 'denied'; // not in the allowlist
}

class CommandDoc {
  CommandDoc(this.id, this.data);
  final String id;
  final Map<String, dynamic> data;

  String get commandKey => (data['command_key'] ?? '') as String;
  List<String> get args =>
      List<String>.from(((data['args'] ?? const []) as List).map((e) => '$e'));
  String get status => (data['status'] ?? '') as String;
  String get result => (data['result'] ?? '') as String;
  DateTime? get createdAt => DateTime.tryParse('${data['created_at']}');

  factory CommandDoc.fromRow(Map<String, dynamic> r) =>
      CommandDoc('${r['id']}', r);
}
