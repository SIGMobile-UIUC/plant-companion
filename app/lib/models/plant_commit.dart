import 'dart:math';
import 'device.dart';

/// This token changes for profile/assignment edits, never for sensor packets.
class PlantEditToken {
  const PlantEditToken({
    required this.profileRevision,
    this.deviceId,
    this.deviceRevision,
  });
  final int profileRevision;
  final String? deviceId;
  final int? deviceRevision;
  Map<String, Object?> toJson() => {
    'profileRevision': profileRevision,
    'deviceId': deviceId,
    'deviceRevision': deviceRevision,
  };
}

/// Transaction receipt, not a pre-Save UI snapshot or proof of a new connection.
class PlantSaveReceipt {
  const PlantSaveReceipt({
    required this.operationId,
    required this.plantId,
    required this.previousDevice,
    required this.assignedDevice,
    required this.deviceCreated,
    required this.connectionRequested,
  });
  final String operationId, plantId;
  final Device? previousDevice, assignedDevice;
  final bool deviceCreated, connectionRequested;
  bool get assignmentChanged => previousDevice?.id != assignedDevice?.id;
  bool get needsConnectionPacket =>
      assignedDevice != null &&
      (deviceCreated ||
          assignmentChanged ||
          (connectionRequested && !assignedDevice!.isConnected));

  Map<String, Object?> toJson() => {
    'operationId': operationId,
    'plantId': plantId,
    'previousDevice': _deviceJson(previousDevice),
    'assignedDevice': _deviceJson(assignedDevice),
    'deviceCreated': deviceCreated,
    'connectionRequested': connectionRequested,
  };
  factory PlantSaveReceipt.fromJson(Map<String, dynamic> j) => PlantSaveReceipt(
    operationId: j['operationId'] as String,
    plantId: j['plantId'] as String,
    previousDevice: _device(j['previousDevice']),
    assignedDevice: _device(j['assignedDevice']),
    deviceCreated: j['deviceCreated'] as bool,
    connectionRequested: j['connectionRequested'] as bool,
  );
  static Map<String, Object?>? _deviceJson(Device? d) => d == null
      ? null
      : {
          'id': d.id,
          'name': d.name,
          'connected': d.isConnected,
          'ordinal': d.displayOrdinal,
          'createdAt': d.createdAt?.toIso8601String(),
          'revision': d.revision,
          'slot': d.lastAutoSlot,
          'sequence': d.generationSequence,
        };
  static Device? _device(dynamic j) => j == null
      ? null
      : Device(
          id: j['id'] as String,
          name: j['name'] as String,
          isConnected: j['connected'] as bool,
          displayOrdinal: j['ordinal'] as int,
          createdAt: j['createdAt'] == null
              ? null
              : DateTime.parse(j['createdAt'] as String),
          revision: j['revision'] as int,
          lastAutoSlot: j['slot'] as int,
          generationSequence: j['sequence'] as int,
        );
}

enum PlantCommitStatus {
  notCommitted,
  committed,
  committedWithWarning,
  conflict,
  uncertain,
}

enum PlantPostCommitIssue {
  reload,
  connection,
  acquisition,
  assignmentChanged,
  scheduler,
}

/// A committed result can never be presented as a rolled-back operation.
class PlantCommitResult {
  const PlantCommitResult(
    this.status, {
    this.plantId,
    this.receipt,
    this.issue,
    this.error,
    this.deletion = false,
  });
  final PlantCommitStatus status;
  final String? plantId;
  final PlantSaveReceipt? receipt;
  final PlantPostCommitIssue? issue;
  final Object? error;
  final bool deletion;
  bool get committed =>
      status == PlantCommitStatus.committed ||
      status == PlantCommitStatus.committedWithWarning;
}

/// Local command identity only: does not reserve a plant/device database ID.
String newPlantOperationId() =>
    '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(0x100000000)}-${Random.secure().nextInt(0x100000000)}';
