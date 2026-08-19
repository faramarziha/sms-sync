import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'sync_data.db');

    return await openDatabase(
      path,
      version: 4,
      onCreate: (db, version) async {
        await _createTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS raw_texts (
              id TEXT PRIMARY KEY,
              text TEXT,
              sender TEXT,
              created_at INTEGER
            )
          ''');
        }
        if (oldVersion < 3) {
          // Add each column independently. A partially-applied migration should
          // still be able to finish the remaining columns on the next upgrade.
          await _addColumnIfMissing(db, 'sim_subscriptions', 'device_id', 'TEXT');
          await _addColumnIfMissing(db, 'sim_subscriptions', 'device_name', 'TEXT');
          await _addColumnIfMissing(db, 'sms_messages', 'device_id', 'TEXT');
          await _addColumnIfMissing(db, 'sms_messages', 'device_name', 'TEXT');
          await _addColumnIfMissing(db, 'raw_texts', 'device_id', 'TEXT');
          await _addColumnIfMissing(db, 'raw_texts', 'device_name', 'TEXT');
        }
        if (oldVersion < 4) {
          await _addColumnIfMissing(db, 'sms_messages', 'is_starred', 'INTEGER DEFAULT 0');
        }
      },
    );
  }

  Future<void> _addColumnIfMissing(
    Database db,
    String table,
    String column,
    String definition,
  ) async {
    try {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
    } catch (_) {
      // The column already exists, or the database is being opened by another
      // isolate. Existing data remains usable in either case.
    }
  }

  Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sim_subscriptions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        subscription_id INTEGER,
        phone_number TEXT,
        carrier_name TEXT,
        sim_slot INTEGER,
        device_id TEXT,
        device_name TEXT,
        last_synced_at INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sms_messages (
        id TEXT PRIMARY KEY,
        android_sms_id INTEGER,
        address TEXT,
        body TEXT,
        date INTEGER,
        type INTEGER,
        dedup_hash TEXT UNIQUE,
        device_id TEXT,
        device_name TEXT,
        is_starred INTEGER DEFAULT 0,
        created_at INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS raw_texts (
        id TEXT PRIMARY KEY,
        text TEXT,
        sender TEXT,
        device_id TEXT,
        device_name TEXT,
        created_at INTEGER
      )
    ''');
  }

  String _calculateHash(Map<String, dynamic> sms) {
    final sb = StringBuffer()
      ..write(sms['device_id'] ?? '')
      ..write(sms['address'] ?? '')
      ..write(sms['date'] ?? '')
      ..write(sms['body'] ?? '');
    return sha256.convert(utf8.encode(sb.toString())).toString();
  }

  String _uniqueSmsId(Map<String, dynamic> sms, String hash) {
    final devId = sms['device_id']?.toString() ?? '';
    final rawId = sms['id']?.toString();
    if (rawId != null && rawId.isNotEmpty && devId.isNotEmpty) {
      return '${devId}_$rawId';
    }
    return rawId ?? hash;
  }

  Future<void> insertOrUpdateSms(Map<String, dynamic> sms) async {
    final db = await database;
    final hash = _calculateHash(sms);
    final id = _uniqueSmsId(sms, hash);
    
    await db.insert(
      'sms_messages',
      {
        'id': id,
        'android_sms_id': sms['id'],
        'address': sms['address'],
        'body': sms['body'],
        'date': sms['date'],
        'type': sms['type'],
        'dedup_hash': hash,
        'device_id': sms['device_id'],
        'device_name': sms['device_name'],
        'created_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> insertOrUpdateSim(Map<String, dynamic> sim) async {
    final db = await database;
    final slot = sim['sim_slot'] ?? 0;
    final subId = sim['subscription_id'];
    final deviceId = sim['device_id'];

    await db.delete(
      'sim_subscriptions',
      where: '(sim_slot = ? AND (device_id IS NULL OR device_id = ?)) OR (subscription_id IS NOT NULL AND subscription_id = ?)',
      whereArgs: [slot, deviceId, subId],
    );

    await db.insert(
      'sim_subscriptions',
      {
        'subscription_id': subId,
        'phone_number': sim['phone_number'],
        'carrier_name': sim['carrier_name'],
        'sim_slot': slot,
        'device_id': sim['device_id'],
        'device_name': sim['device_name'],
        'last_synced_at': DateTime.now().millisecondsSinceEpoch,
      },
    );
  }

  Future<void> insertRawText(Map<String, dynamic> data) async {
    final db = await database;
    await db.insert(
      'raw_texts',
      {
        'id': data['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
        'text': data['text'],
        'sender': data['sender'] ?? 'Remote',
        'device_id': data['device_id'],
        'device_name': data['device_name'],
        'created_at': data['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getAllSms({String? deviceId}) async {
    final db = await database;
    if (deviceId != null && deviceId.isNotEmpty) {
      return await db.query('sms_messages', where: 'device_id = ?', whereArgs: [deviceId], orderBy: 'date DESC');
    }
    return await db.query('sms_messages', orderBy: 'date DESC');
  }

  Future<List<Map<String, dynamic>>> getAllSims({String? deviceId}) async {
    final db = await database;
    if (deviceId != null && deviceId.isNotEmpty) {
      return await db.query('sim_subscriptions', where: 'device_id = ?', whereArgs: [deviceId], orderBy: 'sim_slot ASC');
    }
    return await db.query('sim_subscriptions', orderBy: 'sim_slot ASC');
  }

  Future<List<Map<String, dynamic>>> getAllRawTexts({String? deviceId}) async {
    final db = await database;
    if (deviceId != null && deviceId.isNotEmpty) {
      return await db.query('raw_texts', where: 'device_id = ?', whereArgs: [deviceId], orderBy: 'created_at DESC');
    }
    return await db.query('raw_texts', orderBy: 'created_at DESC');
  }

  /// Search SMS by text or phone number.
  Future<List<Map<String, dynamic>>> searchSms(String query, {String? deviceId}) async {
    final db = await database;
    final like = '%$query%';
    if (deviceId != null && deviceId.isNotEmpty) {
      return await db.query(
        'sms_messages',
        where: 'device_id = ? AND (body LIKE ? OR address LIKE ?)',
        whereArgs: [deviceId, like, like],
        orderBy: 'date DESC',
      );
    }
    return await db.query(
      'sms_messages',
      where: 'body LIKE ? OR address LIKE ?',
      whereArgs: [like, like],
      orderBy: 'date DESC',
    );
  }

  /// Return one thread for a single phone number.
  Future<List<Map<String, dynamic>>> getSmsForAddress(String address, {String? deviceId}) async {
    final db = await database;
    if (deviceId != null && deviceId.isNotEmpty) {
      return await db.query(
        'sms_messages',
        where: 'device_id = ? AND address = ?',
        whereArgs: [deviceId, address],
        orderBy: 'date DESC',
      );
    }
    return await db.query(
      'sms_messages',
      where: 'address = ?',
      whereArgs: [address],
      orderBy: 'date DESC',
    );
  }

  /// Group messages by phone number for a conversation-style view.
  Future<List<Map<String, dynamic>>> getConversations({String? deviceId}) async {
    final db = await database;
    if (deviceId != null && deviceId.isNotEmpty) {
      return await db.rawQuery('''
        SELECT address, COUNT(*) AS count, MAX(date) AS last_date,
          (SELECT body FROM sms_messages m2
            WHERE m2.address = m1.address AND m2.device_id = ?
            ORDER BY date DESC LIMIT 1) AS last_body
        FROM sms_messages m1
        WHERE m1.device_id = ?
        GROUP BY address
        ORDER BY last_date DESC
      ''', [deviceId, deviceId]);
    }
    return await db.rawQuery('''
      SELECT address, COUNT(*) AS count, MAX(date) AS last_date,
        (SELECT body FROM sms_messages m2
          WHERE m2.address = m1.address
          ORDER BY date DESC LIMIT 1) AS last_body
      FROM sms_messages m1
      GROUP BY address
      ORDER BY last_date DESC
    ''');
  }

  /// Aggregated message statistics for the dashboard.
  Future<Map<String, dynamic>> getStats({String? deviceId}) async {
    final db = await database;
    final hasDevice = deviceId != null && deviceId.isNotEmpty;
    final where = hasDevice ? 'WHERE device_id = ?' : '';
    final args = hasDevice ? [deviceId] : <Object>[];
    final rows = await db.rawQuery('''
      SELECT COUNT(*) AS total,
        SUM(CASE WHEN type = 1 THEN 1 ELSE 0 END) AS received,
        SUM(CASE WHEN type = 2 THEN 1 ELSE 0 END) AS sent,
        SUM(CASE WHEN is_starred = 1 THEN 1 ELSE 0 END) AS starred,
        COUNT(DISTINCT address) AS contacts
      FROM sms_messages
      $where
    ''', args);
    return rows.isNotEmpty ? rows.first : {};
  }

  /// Toggle the starred flag for a message. Returns the new starred state.
  Future<bool> toggleSmsStarred(String id) async {
    final db = await database;
    final rows = await db.query('sms_messages', columns: ['is_starred'], where: 'id = ?', whereArgs: [id]);
    final current = rows.isNotEmpty ? ((rows.first['is_starred'] as int?) ?? 0) : 0;
    final next = current == 1 ? 0 : 1;
    await db.update('sms_messages', {'is_starred': next}, where: 'id = ?', whereArgs: [id]);
    return next == 1;
  }

  /// Delete a single message.
  Future<void> deleteSms(String id) async {
    final db = await database;
    await db.delete('sms_messages', where: 'id = ?', whereArgs: [id]);
  }

  /// Delete an entire conversation (all messages from a phone number).
  Future<void> deleteSmsByAddress(String address, {String? deviceId}) async {
    final db = await database;
    if (deviceId != null && deviceId.isNotEmpty) {
      await db.delete('sms_messages', where: 'device_id = ? AND address = ?', whereArgs: [deviceId, address]);
    } else {
      await db.delete('sms_messages', where: 'address = ?', whereArgs: [address]);
    }
  }

  /// Restore a full SMS backup, preserving starred state and original IDs.
  Future<void> restoreSmsBatch(List<Map<String, dynamic>> smsList) async {
    if (smsList.isEmpty) return;
    final db = await database;
    await db.transaction((txn) async {
      for (final sms in smsList) {
        final id = sms['id']?.toString();
        if (id == null || id.isEmpty) continue;
        await txn.insert(
          'sms_messages',
          {
            'id': id,
            'android_sms_id': sms['android_sms_id'],
            'address': sms['address'],
            'body': sms['body'],
            'date': sms['date'],
            'type': sms['type'],
            'dedup_hash': sms['dedup_hash'] ?? _calculateHash(sms),
            'device_id': sms['device_id'],
            'device_name': sms['device_name'],
            'is_starred': sms['is_starred'] == 1 ? 1 : 0,
            'created_at': sms['created_at'] ?? DateTime.now().millisecondsSinceEpoch,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  /// Wipe temporary synced data for a specific device when it disconnects
  Future<void> deleteDataForDevice(String deviceId) async {
    final db = await database;
    await db.delete('sms_messages', where: 'device_id = ?', whereArgs: [deviceId]);
    await db.delete('sim_subscriptions', where: 'device_id = ?', whereArgs: [deviceId]);
    await db.delete('raw_texts', where: 'device_id = ?', whereArgs: [deviceId]);
  }

  /// Batch-delete data for multiple devices in a single transaction (Items 5/6)
  Future<void> deleteDataForDevices(List<String> deviceIds) async {
    if (deviceIds.isEmpty) return;
    final db = await database;
    final placeholders = List.filled(deviceIds.length, '?').join(', ');
    final whereClause = 'device_id IN ($placeholders)';
    await db.transaction((txn) async {
      await txn.delete('sms_messages', where: whereClause, whereArgs: deviceIds);
      await txn.delete('sim_subscriptions', where: whereClause, whereArgs: deviceIds);
      await txn.delete('raw_texts', where: whereClause, whereArgs: deviceIds);
    });
  }

  /// Batch-insert SMS messages in a single transaction (Item 7)
  Future<void> insertSmsBatch(List<Map<String, dynamic>> smsList) async {
    if (smsList.isEmpty) return;
    final db = await database;
    await db.transaction((txn) async {
      for (final sms in smsList) {
        final hash = _calculateHash(sms);
        final id = _uniqueSmsId(sms, hash);
        await txn.insert(
          'sms_messages',
          {
            'id': id,
            'android_sms_id': sms['id'],
            'address': sms['address'],
            'body': sms['body'],
            'date': sms['date'],
            'type': sms['type'],
            'dedup_hash': hash,
            'device_id': sms['device_id'],
            'device_name': sms['device_name'],
            'created_at': DateTime.now().millisecondsSinceEpoch,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    });
  }

  /// Batch-insert SIM subscription records in a single transaction (Item 8)
  Future<void> insertSimBatch(List<Map<String, dynamic>> sims) async {
    if (sims.isEmpty) return;
    final db = await database;
    await db.transaction((txn) async {
      for (final sim in sims) {
        final slot = sim['sim_slot'] ?? 0;
        final subId = sim['subscription_id'];
        final deviceId = sim['device_id'];
        await txn.delete(
          'sim_subscriptions',
          where: '(sim_slot = ? AND (device_id IS NULL OR device_id = ?)) OR (subscription_id IS NOT NULL AND subscription_id = ?)',
          whereArgs: [slot, deviceId, subId],
        );
        await txn.insert(
          'sim_subscriptions',
          {
            'subscription_id': subId,
            'phone_number': sim['phone_number'],
            'carrier_name': sim['carrier_name'],
            'sim_slot': slot,
            'device_id': sim['device_id'],
            'device_name': sim['device_name'],
            'last_synced_at': DateTime.now().millisecondsSinceEpoch,
          },
        );
      }
    });
  }

  Future<void> clearAllData() async {
    final db = await database;
    await db.delete('sms_messages');
    await db.delete('sim_subscriptions');
    await db.delete('raw_texts');
  }
}
