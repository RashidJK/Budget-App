import 'dart:convert';
import 'dart:io';

import 'package:postgres/postgres.dart';

/// All Postgres access lives here. Records are stored verbatim as JSONB; the
/// updatedAt / deletedAt they already carry drive last-write-wins and
/// tombstones, and a global `seq` lets a client pull just what changed.
class Db {
  Db(this._pool);

  final Pool _pool;

  static Future<Db> open(String url) async {
    final uri = Uri.parse(url); // postgres://user:pass@host:port/dbname
    final creds = uri.userInfo.split(':');
    final endpoint = Endpoint(
      host: uri.host.isEmpty ? 'localhost' : uri.host,
      port: uri.hasPort ? uri.port : 5432,
      database:
          uri.pathSegments.isNotEmpty ? uri.pathSegments.first : 'postgres',
      username:
          creds.isNotEmpty && creds.first.isNotEmpty ? creds.first : 'postgres',
      password: creds.length > 1 ? creds.sublist(1).join(':') : null,
    );
    final pool = Pool.withEndpoints(
      [endpoint],
      settings: const PoolSettings(
        maxConnectionCount: 8,
        sslMode: SslMode.disable, // DB is on the same host / docker network
      ),
    );
    final db = Db(pool);
    await db._migrate();
    return db;
  }

  Future<void> _migrate() async {
    final ddl = await File('schema.sql').readAsString();
    // schema.sql has several statements; the default (extended/prepared)
    // protocol rejects that with 42601, so run it as a simple query.
    await _pool.execute(ddl, queryMode: QueryMode.simple);
  }

  /// Find or create the user behind a verified Google identity; returns the id.
  Future<String> upsertUser({
    required String googleSub,
    String? email,
    String? name,
  }) async {
    final result = await _pool.execute(
      Sql.named('''
        insert into users (google_sub, email, name)
        values (@sub, @email, @name)
        on conflict (google_sub) do update
          set email = excluded.email, name = excluded.name
        returning id
      '''),
      parameters: {'sub': googleSub, 'email': email, 'name': name},
    );
    return result.first.first.toString();
  }

  /// Upsert one record into a collection, keeping whichever copy is newer.
  Future<void> applyChange(
    String userId,
    String collection,
    Map<String, dynamic> record,
  ) async {
    final id = record['id']?.toString();
    if (id == null || id.isEmpty) return;
    final updatedAt = record['updatedAt']?.toString() ??
        DateTime.now().toUtc().toIso8601String();
    final deletedAt = record['deletedAt']?.toString();

    await _pool.execute(
      Sql.named('''
        insert into documents (user_id, collection, doc_id, updated_at, deleted_at, body, seq)
        values (@uid::uuid, @col, @id, @upd::timestamptz, @del::timestamptz, @body::jsonb, nextval('documents_seq'))
        on conflict (user_id, collection, doc_id) do update
          set updated_at = excluded.updated_at,
              deleted_at = excluded.deleted_at,
              body = excluded.body,
              seq = nextval('documents_seq')
          -- strictly newer only: re-pushing an unchanged record must not bump
          -- its seq, or every device would re-pull everything each sync.
          where excluded.updated_at > documents.updated_at
      '''),
      parameters: {
        'uid': userId,
        'col': collection,
        'id': id,
        'upd': updatedAt,
        'del': deletedAt,
        'body': jsonEncode(record),
      },
    );
  }

  /// Every record for [userId] written after [since] (null = everything),
  /// oldest change first, grouped by collection, plus the new cursor.
  Future<({int cursor, Map<String, List<Map<String, dynamic>>> changes})>
      changesSince(String userId, int since) async {
    final result = await _pool.execute(
      Sql.named('''
        select collection, body, seq from documents
        where user_id = @uid::uuid and seq > @since
        order by seq asc
        limit 5000
      '''),
      parameters: {'uid': userId, 'since': since},
    );

    final changes = <String, List<Map<String, dynamic>>>{};
    var cursor = since;
    for (final row in result) {
      final map = row.toColumnMap();
      final collection = map['collection'] as String;
      final seq = (map['seq'] as int?) ?? cursor;
      if (seq > cursor) cursor = seq;
      final body = map['body'];
      final record = body is String
          ? jsonDecode(body) as Map<String, dynamic>
          : Map<String, dynamic>.from(body as Map);
      (changes[collection] ??= []).add(record);
    }
    return (cursor: cursor, changes: changes);
  }

  /// Permanently remove tombstones (soft-deleted rows) older than [olderThan],
  /// so the table doesn't keep every deletion forever. Returns how many rows
  /// were removed.
  ///
  /// The window must be comfortably longer than any device stays offline: once
  /// a tombstone is gone, a device that still holds the record and syncs would
  /// re-push it and resurrect it. 90 days is the default — long enough that
  /// this is a non-issue in practice.
  Future<int> pruneTombstones(Duration olderThan) async {
    final result = await _pool.execute(
      Sql.named('''
        delete from documents
        where deleted_at is not null
          and deleted_at < now() - make_interval(secs => @secs)
      '''),
      parameters: {'secs': olderThan.inSeconds},
    );
    return result.affectedRows;
  }
}
