import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'models/sync_message.dart';

class FileTransferItem {
  final String fileId;
  final String fileName;
  final int fileSize;
  final String sender; // 'Mobile' or 'Desktop'
  final bool isOutgoing;
  int bytesTransferred;
  String? localPath;
  bool isCompleted;
  bool isFailed;

  FileTransferItem({
    required this.fileId,
    required this.fileName,
    required this.fileSize,
    required this.sender,
    required this.isOutgoing,
    this.bytesTransferred = 0,
    this.localPath,
    this.isCompleted = false,
    this.isFailed = false,
  });

  double get progress => fileSize == 0 ? 0.0 : (bytesTransferred / fileSize).clamp(0.0, 1.0);
}

class FileTransferService {
  static const int chunkSize = 64 * 1024; // 64 KB chunks

  final Map<String, FileTransferItem> _transfers = {};
  final Map<String, IOSink> _incomingFileSinks = {};

  final _transfersController = StreamController<List<FileTransferItem>>.broadcast();
  Stream<List<FileTransferItem>> get transfersStream => _transfersController.stream;

  List<FileTransferItem> get activeTransfers => _transfers.values.toList();

  void _notifyListeners() {
    _transfersController.add(_transfers.values.toList());
  }

  /// Resolve destination directory for received files.
  ///
  /// On Android: uses app-specific external storage (compatible with scoped
  /// storage on Android 10+) without requiring MANAGE_EXTERNAL_STORAGE.
  /// TODO: Consider MediaStore API for user-visible Downloads folder.
  Future<Directory> _getDownloadDirectory() async {
    Directory? dir;
    if (Platform.isAndroid) {
      // App-specific external storage works under scoped storage restrictions
      final extDir = await getExternalStorageDirectory();
      if (extDir != null) {
        dir = Directory(p.join(extDir.path, 'SMS_Sync'));
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
      }
    } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final downloadsDir = await getDownloadsDirectory();
      dir = Directory(p.join(downloadsDir?.path ?? Directory.current.path, 'SMS_Sync'));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    }
    dir ??= await getApplicationDocumentsDirectory();
    return dir;
  }

  /// Start sending a file over WebSocket transport
  Future<void> sendFile({
    required File file,
    required String sender,
    required Future<void> Function(SyncMessage msg) sendMessage,
  }) async {
    final fileName = p.basename(file.path);
    final fileSize = await file.length();
    final fileId = const Uuid().v4();
    final totalChunks = (fileSize / chunkSize).ceil();

    final item = FileTransferItem(
      fileId: fileId,
      fileName: fileName,
      fileSize: fileSize,
      sender: sender,
      isOutgoing: true,
      localPath: file.path,
    );

    _transfers[fileId] = item;
    _notifyListeners();

    try {
      // 1. Send Header
      await sendMessage(SyncMessage(
        type: SyncMessageType.fileHeader,
        payload: {
          'fileId': fileId,
          'fileName': fileName,
          'fileSize': fileSize,
          'totalChunks': totalChunks,
          'sender': sender,
        },
      ));

      // 2. Handle zero-byte files: no chunks to send
      if (fileSize == 0) {
        item.isCompleted = true;
        _notifyListeners();
        return;
      }

      // 3. Stream Chunks
      final stream = file.openRead();
      int chunkIndex = 0;
      List<int> buffer = [];

      await for (var data in stream) {
        buffer.addAll(data);
        while (buffer.length >= chunkSize) {
          final chunkData = buffer.sublist(0, chunkSize);
          buffer = buffer.sublist(chunkSize);

          final base64String = base64Encode(chunkData);
          await sendMessage(SyncMessage(
            type: SyncMessageType.fileChunk,
            payload: {
              'fileId': fileId,
              'chunkIndex': chunkIndex,
              'base64Data': base64String,
            },
          ));

          chunkIndex++;
          item.bytesTransferred += chunkData.length;
          _notifyListeners();
        }
      }

      // Send remaining buffer
      if (buffer.isNotEmpty) {
        final base64String = base64Encode(buffer);
        await sendMessage(SyncMessage(
          type: SyncMessageType.fileChunk,
          payload: {
            'fileId': fileId,
            'chunkIndex': chunkIndex,
            'base64Data': base64String,
          },
        ));
        item.bytesTransferred += buffer.length;
      }

      item.isCompleted = true;
      _notifyListeners();
    } catch (e) {
      debugPrint("File sending failed: $e");
      item.isFailed = true;
      _notifyListeners();
    }
  }

  /// Handle incoming file header
  Future<void> handleFileHeader(Map<String, dynamic> payload) async {
    final fileId = payload['fileId'] as String;
    final rawFileName = payload['fileName'] as String;

    // Sanitize: strip any directory components from the remote-supplied name
    final fileName = p.basename(rawFileName);

    // Validate: reject names that could cause problems
    if (fileName.isEmpty || fileName == '.' || fileName == '..' ||
        fileName.contains('/') || fileName.contains('\\')) {
      debugPrint('Rejected invalid file name after sanitization: "$rawFileName" -> "$fileName"');
      return;
    }

    final fileSize = payload['fileSize'] as int;
    final sender = payload['sender'] as String? ?? 'Remote Device';

    final saveDir = await _getDownloadDirectory();
    final targetPath = p.join(saveDir.path, fileName);

    // Defense-in-depth: verify the resolved path is still inside the save dir
    final canonicalTarget = p.canonicalize(targetPath);
    final canonicalSaveDir = p.canonicalize(saveDir.path);
    if (!canonicalTarget.startsWith(canonicalSaveDir)) {
      debugPrint('Path traversal blocked: "$targetPath" escapes "$canonicalSaveDir"');
      return;
    }

    final targetFile = File(targetPath);

    if (await targetFile.exists()) {
      await targetFile.delete();
    }

    final sink = targetFile.openWrite();
    _incomingFileSinks[fileId] = sink;

    final item = FileTransferItem(
      fileId: fileId,
      fileName: fileName,
      fileSize: fileSize,
      sender: sender,
      isOutgoing: false,
      localPath: targetPath,
    );

    _transfers[fileId] = item;

    // Handle zero-byte files immediately (Item 11)
    if (fileSize == 0) {
      await sink.flush();
      await sink.close();
      _incomingFileSinks.remove(fileId);
      item.isCompleted = true;
    }

    _notifyListeners();
  }

  /// Handle incoming file chunk
  Future<void> handleFileChunk(Map<String, dynamic> payload) async {
    final fileId = payload['fileId'] as String;
    final base64Data = payload['base64Data'] as String;
    final bytes = base64Decode(base64Data);

    final sink = _incomingFileSinks[fileId];
    final item = _transfers[fileId];

    if (sink != null && item != null) {
      sink.add(bytes);
      item.bytesTransferred += bytes.length;

      if (item.bytesTransferred >= item.fileSize) {
        await sink.flush();
        await sink.close();
        _incomingFileSinks.remove(fileId);
        item.isCompleted = true;
      }
      _notifyListeners();
    }
  }

  void dispose() {
    for (var sink in _incomingFileSinks.values) {
      sink.close();
    }
    _incomingFileSinks.clear();
    _transfersController.close();
  }
}
