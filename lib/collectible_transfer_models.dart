import 'package:cloud_firestore/cloud_firestore.dart';
import 'collectible_models.dart';

enum CollectibleTransferStatus {
  pending,
  accepted,
  rejected,
  cancelled;

  static CollectibleTransferStatus fromValue(Object? value) {
    return CollectibleTransferStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => throw FormatException(
        'Estado de transferencia no reconocido: $value',
      ),
    );
  }
}

class CollectibleTransfer {
  const CollectibleTransfer({
    required this.id,
    required this.collectibleCode,
    required this.fromUid,
    required this.toUid,
    required this.status,
    required this.requestedAt,
    required this.lastHistoryId,
    this.respondedAt,
  });

  final String id;
  final String collectibleCode;
  final String fromUid;
  final String toUid;
  final CollectibleTransferStatus status;
  final DateTime requestedAt;
  final String lastHistoryId;
  final DateTime? respondedAt;

  Map<String, Object?> toMap() {
    final data = {
      'collectibleCode': collectibleCode,
      'fromUid': fromUid,
      'toUid': toUid,
      'status': status.name,
      'requestedAt': Timestamp.fromDate(requestedAt.toUtc()),
      'lastHistoryId': lastHistoryId,
      'respondedAt':
          respondedAt == null ? null : Timestamp.fromDate(respondedAt!.toUtc()),
    };
    _validateTransferMap(data);
    return data;
  }

  factory CollectibleTransfer.fromMap(
    String id,
    Map<String, dynamic> data,
  ) {
    final transfer = CollectibleTransfer(
      id: id,
      collectibleCode: _requiredString(data, 'collectibleCode'),
      fromUid: _requiredString(data, 'fromUid'),
      toUid: _requiredString(data, 'toUid'),
      status: CollectibleTransferStatus.fromValue(data['status']),
      requestedAt: _requiredDateTime(data, 'requestedAt'),
      lastHistoryId: _requiredString(data, 'lastHistoryId'),
      respondedAt: _optionalDateTime(data, 'respondedAt'),
    );
    _validateTransferMap(transfer.toMap());
    return transfer;
  }
}

enum CollectibleTransferAction {
  requested,
  accepted,
  rejected,
  cancelled;
}

class CollectibleTransferHistoryEntry {
  const CollectibleTransferHistoryEntry({
    required this.id,
    required this.transferId,
    required this.collectibleCode,
    required this.action,
    required this.actorUid,
    required this.fromUid,
    required this.toUid,
    required this.createdAt,
  });

  final String id;
  final String transferId;
  final String collectibleCode;
  final CollectibleTransferAction action;
  final String actorUid;
  final String fromUid;
  final String toUid;
  final DateTime createdAt;

  Map<String, Object?> toMap() {
    final data = {
      'transferId': transferId,
      'collectibleCode': collectibleCode,
      'action': action.name,
      'actorUid': actorUid,
      'fromUid': fromUid,
      'toUid': toUid,
      'createdAt': Timestamp.fromDate(createdAt.toUtc()),
    };
    _validateHistoryMap(data);
    return data;
  }

  factory CollectibleTransferHistoryEntry.fromMap(
    String id,
    Map<String, dynamic> data,
  ) {
    final entry = CollectibleTransferHistoryEntry(
      id: id,
      transferId: _requiredString(data, 'transferId'),
      collectibleCode: _requiredString(data, 'collectibleCode'),
      action: CollectibleTransferAction.values.firstWhere(
        (action) => action.name == data['action'],
        orElse: () => throw FormatException(
          'Acción de transferencia no reconocida: ${data['action']}',
        ),
      ),
      actorUid: _requiredString(data, 'actorUid'),
      fromUid: _requiredString(data, 'fromUid'),
      toUid: _requiredString(data, 'toUid'),
      createdAt: _requiredDateTime(data, 'createdAt'),
    );
    _validateHistoryMap(entry.toMap());
    return entry;
  }
}

void _validateTransferMap(Map<String, Object?> data) {
  final code = data['collectibleCode'];
  final fromUid = data['fromUid'];
  final toUid = data['toUid'];
  final status = CollectibleTransferStatus.fromValue(data['status']);
  final requestedAt = data['requestedAt'];
  final respondedAt = data['respondedAt'];
  if (code is! String ||
      !isValidCollectibleModelUnit(code) ||
      fromUid is! String ||
      fromUid.trim().isEmpty ||
      toUid is! String ||
      toUid.trim().isEmpty ||
      fromUid == toUid ||
      requestedAt is! Timestamp ||
      data['lastHistoryId'] is! String ||
      (data['lastHistoryId'] as String).trim().isEmpty ||
      (respondedAt != null && respondedAt is! Timestamp) ||
      (status == CollectibleTransferStatus.pending && respondedAt != null) ||
      (status != CollectibleTransferStatus.pending && respondedAt == null)) {
    throw const FormatException('Los datos de transferencia no son válidos.');
  }
}

void _validateHistoryMap(Map<String, Object?> data) {
  final code = data['collectibleCode'];
  final transferId = data['transferId'];
  final actorUid = data['actorUid'];
  final fromUid = data['fromUid'];
  final toUid = data['toUid'];
  final action = CollectibleTransferAction.values.firstWhere(
    (value) => value.name == data['action'],
    orElse: () => throw FormatException(
      'Acción de transferencia no reconocida: ${data['action']}',
    ),
  );
  if (code is! String ||
      !isValidCollectibleModelUnit(code) ||
      transferId is! String ||
      transferId.trim().isEmpty ||
      actorUid is! String ||
      actorUid.trim().isEmpty ||
      fromUid is! String ||
      fromUid.trim().isEmpty ||
      toUid is! String ||
      toUid.trim().isEmpty ||
      fromUid == toUid ||
      data['createdAt'] is! Timestamp ||
      ((action == CollectibleTransferAction.requested ||
              action == CollectibleTransferAction.cancelled) &&
          actorUid != fromUid) ||
      ((action == CollectibleTransferAction.accepted ||
              action == CollectibleTransferAction.rejected) &&
          actorUid != toUid)) {
    throw const FormatException(
      'Los datos del historial de transferencia no son válidos.',
    );
  }
}

String _requiredString(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('El campo "$key" debe ser texto no vacío.');
  }
  return value;
}

DateTime _requiredDateTime(Map<String, dynamic> data, String key) {
  final dateTime = _optionalDateTime(data, key);
  if (dateTime == null) {
    throw FormatException('El campo "$key" debe contener una fecha.');
  }
  return dateTime;
}

DateTime? _optionalDateTime(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value == null) return null;
  if (value is Timestamp) return value.toDate().toUtc();
  if (value is DateTime) return value.toUtc();
  throw FormatException('El campo "$key" debe contener una fecha.');
}
