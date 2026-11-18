import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/device.dart';
import '../models/plant.dart';
import '../models/plant_avatar_id.dart';
import '../models/plant_form_draft.dart';
import '../models/plant_profile.dart';
import '../models/plant_commit.dart';
import '../services/clock.dart';
import '../services/fake_sensor_repository.dart';
import '../services/plant_repository.dart';
import '../services/reading_scheduler.dart';
import '../ble/ble_sync_service.dart';

class PlantStore extends ChangeNotifier {
  PlantStore({
    required this.persistence,
    FakeSensorRepository? repository,
    this.clock = const SystemClock(),
    this.ble,
  }) {
    ble?.onChanged = reload;
    this.repository =
        repository ?? FakeSensorRepository(inventory: persistence.loadDevices);
    scheduler = ReadingScheduler(
      persistence,
      this.repository,
      clock: clock,
      onChanged: reload,
      onError: _recordError,
    );
    initialized = _initialize();
  }

  final PlantRepository persistence;
  final Clock clock;
  final BleSyncService? ble;
  late final FakeSensorRepository repository;
  late final ReadingScheduler scheduler;
  late final Future<void> initialized;
  List<Plant> _plants = const [];
  List<Device> _deviceList = const [];
  Map<String, Device> _devices = {};
  final Set<String> _refreshing = {};
  final Map<String, Future<PlantCommitResult>> _commands = {};
  PlantCommitResult? operationNotice;
  Timer? _freshnessTimer;
  bool _disposed = false;
  Future<void>? _reloadTask;
  bool _reloadRequested = false;
  Object? lastError;

  Future<void> _initialize() async {
    await persistence.initialize();
    await reload();
    _freshnessTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!_disposed) notifyListeners();
    });
  }

  Future<void> reload() {
    if (_disposed) return Future.value();
    _reloadRequested = true;
    if (_reloadTask != null) return _reloadTask!;
    final completion = Completer<void>();
    _reloadTask = completion.future;
    unawaited(_reloadUntilCurrent(completion));
    return completion.future;
  }

  Future<void> _reloadUntilCurrent(Completer<void> completion) async {
    try {
      while (_reloadRequested && !_disposed) {
        _reloadRequested = false;
        final plants = await persistence.loadPlants();
        final devices = await persistence.loadDevices();
        // A mutation requested another reload during these reads. Skip the old
        // snapshot and let all waiting callers observe the new pass instead.
        if (_disposed) break;
        if (_reloadRequested) continue;
        _plants = List.unmodifiable(plants);
        _deviceList = List.unmodifiable(devices);
        _devices = {for (final device in devices) device.id: device};
        notifyListeners();
      }
      completion.complete();
    } catch (error, stack) {
      completion.completeError(error, stack);
    } finally {
      // Clear synchronously before completion callbacks can request a new pass.
      _reloadTask = null;
    }
  }

  void _recordError(Object error) {
    lastError = error;
    if (!_disposed) notifyListeners();
  }

  List<Plant> get plants => _plants;
  List<Device> get devices => _deviceList;
  Future<List<Device>> discoverDevices() async {
    final local = await repository.discoverDevices();
    final physical = await ble?.discover() ?? <Device>[];
    final merged = {for (final d in local) d.id: d};
    for (final d in physical) {
      final saved = merged[d.id];
      merged[d.id] = Device(
        id: d.id,
        name: d.name,
        isConnected: false,
        isPhysical: true,
        platformHint: d.platformHint,
        createdAt: saved?.createdAt,
        displayOrdinal: saved?.displayOrdinal ?? 0,
        revision: saved?.revision ?? 0,
      );
    }
    return List.unmodifiable(merged.values);
  }

  Future<Device> prepareDevice(Device device) => device.isPhysical
      ? (ble?.prepare(device) ??
            Future.error(
              StateError('Physical BLE requires the iOS or Android app.'),
            ))
      : scheduler.prepareConnection(device, repository);
  String? deviceMessage(String id) => ble?.messages[id];
  Plant? findPlant(String id) {
    final matches = _plants.where((p) => p.id == id);
    return matches.isEmpty ? null : matches.first;
  }

  Plant plantById(String id) =>
      findPlant(id) ?? (throw StateError('Plant no longer exists.'));
  Device? deviceFor(Plant plant) => _devices[plant.deviceId];
  bool isRefreshing(String id) => _refreshing.contains(id);
  Plant? ownerOfDevice(String deviceId) {
    final matches = _plants.where((p) => p.deviceId == deviceId);
    return matches.isEmpty ? null : matches.first;
  }

  Future<String> saveDraft(PlantFormDraft draft, {String? plantId}) async {
    final operationId = newPlantOperationId();
    final result = await saveForm(
      draft,
      plantId: plantId,
      operationId: operationId,
    );
    if (result.committed) return result.plantId!;
    throw result.error ?? PlantCommitUncertain(operationId);
  }

  Future<PlantCommitResult> _singleCommand(
    String id,
    Future<PlantCommitResult> Function() action,
  ) {
    final existing = _commands[id];
    if (existing != null) return existing;
    late final Future<PlantCommitResult> task;
    task = action().whenComplete(() {
      if (identical(_commands[id], task)) _commands.remove(id);
    });
    _commands[id] = task;
    return task;
  }

  /// Failed publication is secondary to a successful durable transaction.
  Future<Object?> _reloadCommitted() async {
    Object? error;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await reload();
        return null;
      } catch (e) {
        error = e;
        _recordError(e);
      }
    }
    return error;
  }

  Future<Object?> _bleAssignmentsChanged() async {
    try {
      await ble?.assignmentsChanged();
      return null;
    } catch (e) {
      _recordError(e);
      return e;
    }
  }

  Future<PlantCommitResult> saveForm(
    PlantFormDraft draft, {
    String? plantId,
    required String operationId,
  }) => _singleCommand(operationId, () async {
    operationNotice = null;
    PlantSaveReceipt? receipt;
    try {
      receipt = await persistence.saveWithReceipt(
        draft,
        plantId: plantId,
        operationId: operationId,
      );
    } catch (error) {
      if (error is PlantEditConflict ||
          error is DeviceAssignmentConflict ||
          error is PlantOperationConflict) {
        await _reloadCommitted();
        return PlantCommitResult(PlantCommitStatus.conflict, error: error);
      }
      if (error is ArgumentError) {
        return PlantCommitResult(PlantCommitStatus.notCommitted, error: error);
      }
      try {
        receipt = await persistence.findSaveReceipt(operationId);
      } catch (reconciliationError) {
        _recordError(reconciliationError);
        return PlantCommitResult(
          PlantCommitStatus.uncertain,
          error: PlantCommitUncertain(operationId),
        );
      }
      if (receipt == null) {
        return PlantCommitResult(PlantCommitStatus.notCommitted, error: error);
      }
      _recordError(error);
    }
    PlantPostCommitIssue? issue;
    Object? error = await _reloadCommitted();
    if (error != null) issue = PlantPostCommitIssue.reload;
    if (receipt.needsConnectionPacket) {
      try {
        final result = receipt.assignedDevice?.isPhysical == true
            ? await _refreshPhysical(
                receipt.plantId,
                receipt.assignedDevice!,
                refresh: false,
              )
            : await scheduler.refreshAssigned(
                receipt.plantId,
                repository,
                expectedDevice: receipt.assignedDevice,
                connectionOrigin: true,
                simulationMode: SimulationMode.environment,
                rearm: false,
              );
        issue ??= switch (result) {
          RefreshResult.updatedPublicationFailed => PlantPostCommitIssue.reload,
          RefreshResult.updatedSchedulerFailed =>
            PlantPostCommitIssue.scheduler,
          RefreshResult.connectionFailed => PlantPostCommitIssue.connection,
          RefreshResult.acquisitionFailed ||
          RefreshResult.simulationUnavailable =>
            PlantPostCommitIssue.acquisition,
          RefreshResult.assignmentChanged ||
          RefreshResult.noDevice => PlantPostCommitIssue.assignmentChanged,
          _ => null,
        };
      } catch (e) {
        error ??= e;
        issue ??= PlantPostCommitIssue.acquisition;
        _recordError(e);
      }
    }
    final timerError = await scheduler.assignmentsChanged();
    final bleError = await _bleAssignmentsChanged();
    if (bleError != null) {
      error ??= bleError;
      issue ??= PlantPostCommitIssue.connection;
    }
    if (timerError != null) {
      error ??= timerError;
      issue ??= PlantPostCommitIssue.scheduler;
    }
    final result = PlantCommitResult(
      issue == null
          ? PlantCommitStatus.committed
          : PlantCommitStatus.committedWithWarning,
      plantId: receipt.plantId,
      receipt: receipt,
      issue: issue,
      error: error,
    );
    if (issue != null) {
      operationNotice = result;
      if (!_disposed) notifyListeners();
    }
    return result;
  });

  Future<PlantCommitResult> deleteForm(
    String id, {
    PlantEditToken? expected,
    required String operationId,
  }) => _singleCommand(operationId, () async {
    operationNotice = null;
    try {
      await persistence.deletePlant(
        id,
        expected: expected,
        operationId: operationId,
      );
    } catch (error) {
      if (error is PlantEditConflict || error is PlantOperationConflict) {
        await _reloadCommitted();
        return PlantCommitResult(
          PlantCommitStatus.conflict,
          error: error,
          deletion: true,
        );
      }
      try {
        if (!await persistence.deletionCommitted(operationId)) {
          return PlantCommitResult(
            PlantCommitStatus.notCommitted,
            error: error,
            deletion: true,
          );
        }
      } catch (reconciliationError) {
        _recordError(reconciliationError);
        return PlantCommitResult(
          PlantCommitStatus.uncertain,
          error: PlantCommitUncertain(operationId),
          deletion: true,
        );
      }
      _recordError(error);
    }
    // Publish absence immediately, even if the subsequent snapshot read fails.
    // reload() invalidates older in-flight snapshots before they can publish.
    _plants = _plants.where((p) => p.id != id).toList();
    if (!_disposed) notifyListeners();
    final reloadError = await _reloadCommitted();
    final timerError = await scheduler.assignmentsChanged();
    final bleError = await _bleAssignmentsChanged();
    final issue = reloadError != null
        ? PlantPostCommitIssue.reload
        : timerError != null
        ? PlantPostCommitIssue.scheduler
        : bleError != null
        ? PlantPostCommitIssue.connection
        : null;
    final result = PlantCommitResult(
      issue == null
          ? PlantCommitStatus.committed
          : PlantCommitStatus.committedWithWarning,
      plantId: id,
      issue: issue,
      error: reloadError ?? timerError ?? bleError,
      deletion: true,
    );
    if (issue != null) {
      operationNotice = result;
      if (!_disposed) notifyListeners();
    }
    return result;
  });

  void dismissOperationNotice() {
    operationNotice = null;
    if (!_disposed) notifyListeners();
  }

  // Compatibility for original regression/review fixtures. Forms use saveForm.
  Future<void> addPlant({
    required String nickname,
    required PlantProfile profile,
    Device? device,
  }) async {
    await saveDraft(
      PlantFormDraft(
        nickname: nickname,
        speciesName: switch (profile.id) {
          'pothos' => 'Epipremnum aureum',
          'snake' => 'Dracaena trifasciata',
          'peace_lily' => 'Spathiphyllum',
          'monstera' => 'Monstera deliciosa',
          _ => profile.plantType,
        },
        avatar: switch (profile.id) {
          'snake' => PlantAvatarId.snakePlant,
          'peace_lily' => PlantAvatarId.peaceLily,
          _ => PlantAvatarId.pothos,
        },
        ranges: profile.ranges,
        deviceId: device?.id,
        connectDevice: device != null,
      ),
    );
  }

  Future<void> deletePlant(String id) async {
    final operationId = newPlantOperationId();
    final result = await deleteForm(id, operationId: operationId);
    if (!result.committed) {
      throw result.error ?? PlantCommitUncertain(operationId);
    }
  }

  Future<RefreshResult> refresh(String id) async {
    if (_disposed) return RefreshResult.assignmentChanged;
    if (!_refreshing.add(id)) return RefreshResult.busy;
    if (operationNotice?.plantId == id) operationNotice = null;
    notifyListeners();
    try {
      final plant = findPlant(id);
      final captured = plant == null ? null : deviceFor(plant);
      if (captured == null) return RefreshResult.noDevice;
      if (captured.isPhysical) return await _refreshPhysical(id, captured);
      return await scheduler.refreshAssigned(
        id,
        repository,
        expectedDevice: captured,
        simulationMode: SimulationMode.manualConditionDriven,
      );
    } catch (error) {
      lastError = error;
      return RefreshResult.acquisitionFailed;
    } finally {
      _refreshing.remove(id);
      if (!_disposed) notifyListeners();
    }
  }

  Future<RefreshResult> _refreshPhysical(
    String id,
    Device device, {
    bool refresh = true,
  }) async {
    try {
      if (ble == null) {
        throw StateError('Physical BLE requires the iOS or Android app.');
      }
      await ble!.synchronize(id, device, refresh: refresh);
      return RefreshResult.updated;
    } catch (e) {
      lastError = e;
      return RefreshResult.acquisitionFailed;
    }
  }

  Future<void> unlinkDevice(String id) async {
    final p = plantById(id);
    await saveDraft(
      PlantFormDraft(
        nickname: p.nickname,
        speciesName: p.speciesName,
        avatar: p.avatar,
        ranges: p.profile.ranges,
        fullName: p.fullName,
        editToken: PlantEditToken(
          profileRevision: p.profileRevision,
          deviceId: p.deviceId,
          deviceRevision: deviceFor(p)?.revision,
        ),
      ),
      plantId: id,
    );
  }

  Future<void> resume() async {
    await scheduler.resume();
    await reload();
    await ble?.resume();
  }

  void pause() {
    scheduler.pause();
    ble?.pause();
  }

  @override
  void dispose() {
    _disposed = true;
    _freshnessTimer?.cancel();
    scheduler.dispose();
    unawaited(() async {
      await ble?.dispose();
      await persistence.close();
    }());
    super.dispose();
  }
}
