import '../models/device.dart';
import '../models/plant.dart';
import '../models/plant_form_draft.dart';
import '../models/sensor_reading.dart';
import '../models/plant_commit.dart';

class PlantEditConflict extends StateError {
  PlantEditConflict()
    : super('This plant or device changed. Reload current data before saving.');
}

class PlantOperationConflict extends StateError {
  PlantOperationConflict()
    : super('Operation identity already used for different input.');
}

class PlantCommitUncertain extends StateError {
  PlantCommitUncertain(this.operationId)
    : super('The operation outcome must be reconciled before retrying.');
  final String operationId;
}

class DeviceAssignmentConflict extends StateError {
  DeviceAssignmentConflict() : super('This device is already assigned.');
}

class PlantPersistenceFailure implements Exception {
  PlantPersistenceFailure(this.cause);
  final Object cause;
  @override
  String toString() => 'PlantPersistenceFailure: $cause';
}

abstract interface class PlantRepository {
  Future<void> initialize();
  Future<List<Plant>> loadPlants();

  /// Explicit history access; list snapshots contain at most the latest packet.
  Future<List<SensorReading>> loadHistory(String plantId);
  Future<List<Device>> loadDevices();

  /// Plant ID to assigned device, without loading ranges or sensor history.
  Future<Map<String, Device>> loadAssignedDevices();

  /// Targeted, consistent snapshot for a serialized sensor operation.
  Future<DeviceReadingContext?> loadAcquisitionContext(String plantId);
  Future<String> save(PlantFormDraft draft, {String? plantId});
  Future<PlantSaveReceipt> saveWithReceipt(
    PlantFormDraft draft, {
    String? plantId,
    required String operationId,
  });
  Future<PlantSaveReceipt?> findSaveReceipt(String operationId);
  Future<void> deletePlant(
    String plantId, {
    PlantEditToken? expected,
    String? operationId,
  });
  Future<bool> deletionCommitted(String operationId);
  Future<void> setConnection(String deviceId, bool connected);

  /// Persist a successful reconnect only for the captured owner/revision.
  /// Returns the updated snapshot, or null when the asynchronous result is stale.
  Future<Device?> reconnectAssigned(String plantId, Device captured);
  Future<bool> commitReading(
    String plantId,
    Device captured,
    SensorReading reading, {
    String origin = 'manual',
    int? autoSlot,
    int? expectedProfileRevision,
  });
  Future<void> pruneHistory();
  Future<void> close();
}
