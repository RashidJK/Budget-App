import 'dart:convert';

import 'package:shelf/shelf.dart';

import 'db.dart';

/// Push + pull in one round-trip. The client sends the records it has changed
/// and the cursor it last saw; the server upserts them (last-write-wins) and
/// returns everything changed since that cursor, plus the new cursor.
///
/// Request body:  `{ "since": int, "changes": { "<collection>": [ {record} ] } }`
/// Response body: `{ "cursor": int, "changes": { "<collection>": [ {record} ] } }`
Future<Response> handleSync(Db db, String userId, Request request) async {
  final raw = await request.readAsString();
  Map<String, dynamic> body;
  try {
    body = raw.isEmpty ? {} : jsonDecode(raw) as Map<String, dynamic>;
  } catch (_) {
    return Response(400, body: 'Invalid JSON.');
  }

  final since = int.tryParse(body['since']?.toString() ?? '0') ?? 0;

  final changes = body['changes'];
  if (changes is Map) {
    for (final entry in changes.entries) {
      final collection = entry.key.toString();
      final records = entry.value;
      if (records is! List) continue;
      for (final record in records) {
        if (record is Map) {
          await db.applyChange(
            userId,
            collection,
            Map<String, dynamic>.from(record),
          );
        }
      }
    }
  }

  final pulled = await db.changesSince(userId, since);
  return Response.ok(
    jsonEncode({'cursor': pulled.cursor, 'changes': pulled.changes}),
    headers: {'content-type': 'application/json'},
  );
}
