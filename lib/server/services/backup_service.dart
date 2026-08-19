import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../db/database_service.dart';

/// Handles exporting synced data to user-friendly files (CSV/JSON) and
/// restoring from a JSON backup.
class BackupService {
  final DatabaseService db;
  BackupService(this.db);

  Future<Directory> _backupDir() async {
    Directory dir;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final downloads = await getDownloadsDirectory();
      dir = Directory(p.join(downloads?.path ?? Directory.current.path, 'SMS_Sync'));
    } else {
      dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'SMS_Sync'));
    }
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  String _csvEscape(Object? value) {
    final s = value?.toString() ?? '';
    if (s.contains(',') || s.contains('"') || s.contains('\n') || s.contains('\r')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  /// Export all SMS messages as a UTF-8 CSV (opens correctly in Excel).
  Future<File> exportCsv() async {
    final sms = await db.getAllSms();
    final dir = await _backupDir();
    final file = File(p.join(
      dir.path,
      'sms_export_${DateTime.now().millisecondsSinceEpoch}.csv',
    ));

    final buffer = StringBuffer();
    // BOM so Excel detects UTF-8.
    buffer.write('\uFEFF');
    buffer.writeln('type,address,body,date,device,starred');
    for (final m in sms) {
      final type = m['type'] == 1
          ? 'received'
          : (m['type'] == 2 ? 'sent' : 'other');
      final date = DateTime.fromMillisecondsSinceEpoch((m['date'] as int?) ?? 0).toIso8601String();
      buffer.writeln([
        type,
        m['address'],
        m['body'],
        date,
        m['device_name'],
        (m['is_starred'] == 1) ? 'yes' : 'no',
      ].map(_csvEscape).join(','));
    }
    await file.writeAsString(buffer.toString());
    return file;
  }

  /// Export a complete JSON backup (SMS + SIM cards + shared text history).
  Future<File> exportJson() async {
    final sms = await db.getAllSms();
    final sims = await db.getAllSims();
    final texts = await db.getAllRawTexts();
    final dir = await _backupDir();
    final file = File(p.join(
      dir.path,
      'sms_backup_${DateTime.now().millisecondsSinceEpoch}.json',
    ));

    final data = <String, dynamic>{
      'exported_at': DateTime.now().toIso8601String(),
      'sms': sms,
      'sims': sims,
      'texts': texts,
    };
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
    return file;
  }

  /// Restore a JSON backup produced by [exportJson]. Returns the number of
  /// SMS records restored.
  Future<int> importJson(File file) async {
    final content = await file.readAsString();
    final data = jsonDecode(content);
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Invalid backup file');
    }

    int restored = 0;

    final sms = (data['sms'] as List<dynamic>?) ?? [];
    if (sms.isNotEmpty) {
      final list = sms
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      await db.restoreSmsBatch(list);
      restored += list.length;
    }

    final sims = (data['sims'] as List<dynamic>?) ?? [];
    if (sims.isNotEmpty) {
      final list = sims
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      await db.insertSimBatch(list);
    }

    final texts = (data['texts'] as List<dynamic>?) ?? [];
    for (final t in texts) {
      final map = Map<String, dynamic>.from(t as Map);
      await db.insertRawText({
        'id': map['id'],
        'text': map['text'],
        'sender': map['sender'],
        'device_id': map['device_id'],
        'device_name': map['device_name'],
        'timestamp': map['created_at'],
      });
    }

    debugPrint('Restored $restored SMS messages from backup.');
    return restored;
  }
}
