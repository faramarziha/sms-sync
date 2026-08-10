import 'dart:convert';
import 'package:uuid/uuid.dart';

enum SyncMessageType {
  pairRequest,
  pairVerify,
  contactInfo,
  sms,
  rawText,
  fileHeader,
  fileChunk,
  ack,
}

enum SyncScope {
  textFiles, // 1. فایل و متن
  smsSim,    // 2. پیامک و شماره تلفن
  both,      // 3. هردو
}

class SyncMessage {
  final String id;
  final SyncMessageType type;
  final int timestamp;
  final Map<String, dynamic> payload;

  SyncMessage({
    String? id,
    required this.type,
    int? timestamp,
    required this.payload,
  })  : id = id ?? const Uuid().v4(),
        timestamp = timestamp ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'timestamp': timestamp,
      'payload': payload,
    };
  }

  factory SyncMessage.fromJson(Map<String, dynamic> json) {
    return SyncMessage(
      id: json['id'],
      type: SyncMessageType.values.byName(json['type']),
      timestamp: json['timestamp'],
      payload: json['payload'],
    );
  }

  String encode() => jsonEncode(toJson());

  factory SyncMessage.decode(String raw) =>
      SyncMessage.fromJson(jsonDecode(raw));
}
