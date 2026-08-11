import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sms_sync/core/models/sync_message.dart';

void main() {
  group('SyncMessage toJson/fromJson round-trip', () {
    test('round-trips for each SyncMessageType', () {
      for (final type in SyncMessageType.values) {
        final original = SyncMessage(
          id: 'test-id-${type.name}',
          type: type,
          timestamp: 1700000000000,
          payload: {'key': 'value', 'number': 42},
        );

        final json = original.toJson();
        final restored = SyncMessage.fromJson(json);

        expect(restored.id, original.id);
        expect(restored.type, original.type);
        expect(restored.timestamp, original.timestamp);
        expect(restored.payload['key'], 'value');
        expect(restored.payload['number'], 42);
      }
    });

    test('preserves nested payload data', () {
      final msg = SyncMessage(
        type: SyncMessageType.smsBatch,
        payload: {
          'device_id': 'dev1',
          'records': [
            {'address': '+1234', 'body': 'hello'},
            {'address': '+5678', 'body': 'world'},
          ],
        },
      );

      final json = msg.toJson();
      final restored = SyncMessage.fromJson(json);

      final records = restored.payload['records'] as List;
      expect(records.length, 2);
      expect(records[0]['address'], '+1234');
      expect(records[1]['body'], 'world');
    });
  });

  group('SyncMessage encode/decode round-trip', () {
    test('encode produces valid JSON string', () {
      final msg = SyncMessage(
        type: SyncMessageType.sms,
        payload: {'address': '+1234567890', 'body': 'Test SMS'},
      );

      final encoded = msg.encode();
      expect(() => jsonDecode(encoded), returnsNormally);
    });

    test('decode restores message from encoded string', () {
      final original = SyncMessage(
        id: 'round-trip-test',
        type: SyncMessageType.contactInfo,
        timestamp: 1700000000000,
        payload: {'phone_number': '+1234', 'carrier_name': 'Test'},
      );

      final encoded = original.encode();
      final decoded = SyncMessage.decode(encoded);

      expect(decoded.id, original.id);
      expect(decoded.type, original.type);
      expect(decoded.timestamp, original.timestamp);
      expect(decoded.payload['phone_number'], '+1234');
    });

    test('encode/decode round-trip with all message types', () {
      for (final type in SyncMessageType.values) {
        final msg = SyncMessage(
          type: type,
          payload: {'test': true},
        );

        final decoded = SyncMessage.decode(msg.encode());
        expect(decoded.type, type);
        expect(decoded.payload['test'], true);
      }
    });
  });

  group('edge cases', () {
    test('unknown message type falls back to ack', () {
      final json = {
        'id': 'test',
        'type': 'nonExistentType',
        'timestamp': 1700000000000,
        'payload': {},
      };

      final msg = SyncMessage.fromJson(json);
      expect(msg.type, SyncMessageType.ack);
    });

    test('null payload in JSON defaults to empty map', () {
      final json = {
        'id': 'test',
        'type': 'sms',
        'timestamp': 1700000000000,
        'payload': null,
      };

      final msg = SyncMessage.fromJson(json);
      expect(msg.payload, isEmpty);
    });

    test('empty payload round-trips correctly', () {
      final msg = SyncMessage(
        type: SyncMessageType.ack,
        payload: {},
      );

      final decoded = SyncMessage.decode(msg.encode());
      expect(decoded.payload, isEmpty);
    });

    test('auto-generates id when not provided', () {
      final msg = SyncMessage(
        type: SyncMessageType.pairRequest,
        payload: {},
      );

      expect(msg.id, isNotEmpty);
      expect(msg.id.length, greaterThan(0));
    });

    test('auto-generates timestamp when not provided', () {
      final before = DateTime.now().millisecondsSinceEpoch;
      final msg = SyncMessage(
        type: SyncMessageType.pairRequest,
        payload: {},
      );
      final after = DateTime.now().millisecondsSinceEpoch;

      expect(msg.timestamp, greaterThanOrEqualTo(before));
      expect(msg.timestamp, lessThanOrEqualTo(after));
    });

    test('batch message types exist and round-trip', () {
      final smsBatch = SyncMessage(
        type: SyncMessageType.smsBatch,
        payload: {'records': []},
      );
      final contactBatch = SyncMessage(
        type: SyncMessageType.contactInfoBatch,
        payload: {'records': []},
      );

      expect(SyncMessage.decode(smsBatch.encode()).type, SyncMessageType.smsBatch);
      expect(SyncMessage.decode(contactBatch.encode()).type, SyncMessageType.contactInfoBatch);
    });

    test('special characters in payload survive round-trip', () {
      final msg = SyncMessage(
        type: SyncMessageType.rawText,
        payload: {
          'text': 'Hello "world" with\nnewlines & <special> chars: éàü 🎉',
        },
      );

      final decoded = SyncMessage.decode(msg.encode());
      expect(decoded.payload['text'], msg.payload['text']);
    });
  });

  group('SyncScope enum', () {
    test('all expected values exist', () {
      expect(SyncScope.values, containsAll([
        SyncScope.textFiles,
        SyncScope.smsSim,
        SyncScope.both,
      ]));
    });

    test('byName round-trips', () {
      for (final scope in SyncScope.values) {
        expect(SyncScope.values.byName(scope.name), scope);
      }
    });
  });
}
