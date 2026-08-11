import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sms_sync/core/file_transfer_service.dart';
import 'package:sms_sync/core/models/sync_message.dart';

void main() {
  late FileTransferService service;
  late Directory tempDir;

  setUp(() async {
    service = FileTransferService();
    tempDir = await Directory.systemTemp.createTemp('file_transfer_test_');
  });

  tearDown(() async {
    service.dispose();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('sendFile error paths', () {
    test('sendFile with non-existent file throws or marks failed', () async {
      final nonExistentFile = File('${tempDir.path}/does_not_exist.txt');
      final sentMessages = <SyncMessage>[];

      // file.length() throws PathNotFoundException before any transfer item
      // is created, so the method itself throws (no transfer to mark failed).
      try {
        await service.sendFile(
          file: nonExistentFile,
          sender: 'Test',
          sendMessage: (msg) async {
            sentMessages.add(msg);
          },
        );
      } on PathNotFoundException {
        // Expected: file doesn't exist, so length() throws
      }

      // No messages should have been sent
      expect(sentMessages, isEmpty);
    });

    test('sendFile marks item as failed when sendMessage throws mid-transfer', () async {
      // Create a file with content larger than one chunk boundary
      final testFile = File('${tempDir.path}/test_data.txt');
      await testFile.writeAsString('A' * 1024); // 1KB file

      int sendCount = 0;
      await service.sendFile(
        file: testFile,
        sender: 'Test',
        sendMessage: (msg) async {
          sendCount++;
          if (sendCount > 1) {
            throw Exception('Network error during chunk send');
          }
        },
      );

      final transfers = service.activeTransfers;
      expect(transfers, isNotEmpty);
      expect(transfers.first.isFailed, isTrue);
    });
  });

  group('sendFile zero-byte handling', () {
    test('zero-byte file completes immediately after header', () async {
      final emptyFile = File('${tempDir.path}/empty.txt');
      await emptyFile.writeAsString('');

      final sentMessages = <SyncMessage>[];
      await service.sendFile(
        file: emptyFile,
        sender: 'Test',
        sendMessage: (msg) async {
          sentMessages.add(msg);
        },
      );

      // Should only send a header, no chunks
      expect(sentMessages.length, 1);
      expect(sentMessages.first.type, SyncMessageType.fileHeader);
      expect(sentMessages.first.payload['fileSize'], 0);

      // Transfer should be marked completed
      final transfers = service.activeTransfers;
      expect(transfers, isNotEmpty);
      expect(transfers.first.isCompleted, isTrue);
      expect(transfers.first.isFailed, isFalse);
    });
  });

  group('handleFileHeader filename validation (pre-directory)', () {
    // These tests only exercise the filename validation logic,
    // which runs BEFORE _getDownloadDirectory() is called.
    // This avoids path_provider platform issues in test environments.

    test('rejects dot-only filename ".."', () async {
      await service.handleFileHeader({
        'fileId': 'test-dot',
        'fileName': '..',
        'fileSize': 100,
        'sender': 'Evil Device',
      });

      // '..' should be rejected before any file I/O
      final item = service.activeTransfers.where((t) => t.fileId == 'test-dot');
      expect(item, isEmpty);
    });

    test('rejects single dot filename "."', () async {
      await service.handleFileHeader({
        'fileId': 'test-single-dot',
        'fileName': '.',
        'fileSize': 100,
        'sender': 'Evil Device',
      });

      final item = service.activeTransfers.where((t) => t.fileId == 'test-single-dot');
      expect(item, isEmpty);
    });

    test('rejects empty filename', () async {
      await service.handleFileHeader({
        'fileId': 'test-empty',
        'fileName': '',
        'fileSize': 100,
        'sender': 'Evil Device',
      });

      final item = service.activeTransfers.where((t) => t.fileId == 'test-empty');
      expect(item, isEmpty);
    });
  });

  group('FileTransferItem', () {
    test('progress is 0.0 when fileSize is 0', () {
      final item = FileTransferItem(
        fileId: 'test',
        fileName: 'empty.txt',
        fileSize: 0,
        sender: 'Test',
        isOutgoing: false,
      );
      expect(item.progress, 0.0);
    });

    test('progress is clamped to 1.0 when bytesTransferred exceeds fileSize', () {
      final item = FileTransferItem(
        fileId: 'test',
        fileName: 'file.txt',
        fileSize: 100,
        sender: 'Test',
        isOutgoing: false,
        bytesTransferred: 200,
      );
      expect(item.progress, 1.0);
    });

    test('progress calculates correctly at 50%', () {
      final item = FileTransferItem(
        fileId: 'test',
        fileName: 'file.txt',
        fileSize: 100,
        sender: 'Test',
        isOutgoing: false,
        bytesTransferred: 50,
      );
      expect(item.progress, 0.5);
    });

    test('progress is 0.0 when no bytes transferred', () {
      final item = FileTransferItem(
        fileId: 'test',
        fileName: 'file.txt',
        fileSize: 1024,
        sender: 'Test',
        isOutgoing: true,
      );
      expect(item.progress, 0.0);
    });

    test('default values are correct', () {
      final item = FileTransferItem(
        fileId: 'id-1',
        fileName: 'test.pdf',
        fileSize: 512,
        sender: 'Device A',
        isOutgoing: true,
      );
      expect(item.bytesTransferred, 0);
      expect(item.localPath, isNull);
      expect(item.isCompleted, isFalse);
      expect(item.isFailed, isFalse);
    });
  });
}
