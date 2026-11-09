import 'dart:async';
import '../persistence/sqlite_plant_repository.dart';
import '../models/device.dart';
import '../models/sensor_reading.dart';
import 'clock.dart';
import 'plant_repository.dart';
import 'sensor_gateway.dart';
import 'plant_simulation.dart';
import 'condition_driven_simulation.dart';

enum RefreshResult {
  updated,
  updatedPublicationFailed,
  updatedSchedulerFailed,
  busy,
  noDevice,
  connectionFailed,
  acquisitionFailed,
  simulationUnavailable,
  assignmentChanged,
}

enum _Acquisition { rejected, committed, publicationFailed }

/// Foreground only. Operations serialize per immutable device; independent
/// devices acquire concurrently. Only SQLite commit advances a generation/slot.
class ReadingScheduler {
  ReadingScheduler(
    this.repository,
    this.gateway, {
    this.clock = const SystemClock(),
    this.createTimer = Timer.new,
    this.onChanged,
    this.onError,
  });
  final PlantRepository repository;
  final SensorGateway gateway;
  final Clock clock;
  final Timer Function(Duration delay, void Function() callback) createTimer;
  final Future<void> Function()? onChanged;
  final void Function(Object error)? onError;
  final Map<String, Future<void>> _queues = {};
  Timer? _timer;
  bool _active = false, _disposed = false;
  int _armGeneration = 0;
  int get pendingDeviceCount => _queues.length;

  Future<T> _serial<T>(String id, Future<T> Function() action) {
    final result = (_queues[id] ?? Future<void>.value()).then((_) => action());
    late final Future<void> tail;
    void release() {
      if (identical(_queues[id], tail)) _queues.remove(id);
    }

    tail = result.then<void>(
      (_) => release(),
      onError: (Object _, StackTrace _) => release(),
    );
    _queues[id] = tail;
    return result;
  }

  /// Publication failure is secondary to a durable packet. Retry one transient
  /// snapshot failure; never reacquire or retry the transaction to repair UI.
  Future<bool> _publish() async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await onChanged?.call();
        return true;
      } catch (error) {
        onError?.call(error);
      }
    }
    return false;
  }

  Future<bool> refresh(
    String plantId, {
    String origin = 'manual',
    SimulationMode simulationMode = SimulationMode.manualConditionDriven,
  }) async {
    final device = (await repository.loadAssignedDevices())[plantId];
    if (device == null) return false;
    return _serial(
      device.id,
      () async =>
          (await _acquire(
            plantId,
            device.id,
            origin: origin,
            simulationMode: simulationMode,
          )) !=
          _Acquisition.rejected,
    );
  }

  Future<RefreshResult> refreshAssigned(
    String plantId,
    DeviceGateway devices, {
    Device? expectedDevice,
    bool connectionOrigin = false,
    bool rearm = true,
    SimulationMode simulationMode = SimulationMode.manualConditionDriven,
  }) async {
    final captured =
        expectedDevice ?? (await repository.loadAssignedDevices())[plantId];
    if (captured == null) return RefreshResult.noDevice;
    RefreshResult result;
    Object? armError;
    try {
      result = await _serial(captured.id, () async {
        if (_disposed) return RefreshResult.assignmentChanged;
        var context = await repository.loadAcquisitionContext(plantId);
        var current = context?.device;
        if (current == null ||
            current.id != captured.id ||
            current.revision != captured.revision) {
          await _publish();
          return RefreshResult.assignmentChanged;
        }
        final reconnecting = !current.isConnected;
        if (reconnecting) {
          try {
            final candidate = await devices.connect(current);
            if (_disposed) return RefreshResult.assignmentChanged;
            if (candidate.id != current.id || !candidate.isConnected) {
              return RefreshResult.connectionFailed;
            }
            current = await repository.reconnectAssigned(plantId, current);
            if (current == null) {
              await _publish();
              return RefreshResult.assignmentChanged;
            }
            // Connection awaits user/hardware work. Acquire from the profile
            // committed after it completes, then retain the atomic commit guard.
            context = await repository.loadAcquisitionContext(plantId);
            if (context == null ||
                context.device.id != captured.id ||
                context.device.revision != current.revision) {
              await _publish();
              return RefreshResult.assignmentChanged;
            }
          } catch (error) {
            onError?.call(error);
            return RefreshResult.connectionFailed;
          }
        }
        try {
          if (reconnecting) await _publish();
          final acquired = await _acquire(
            plantId,
            captured.id,
            origin: reconnecting || connectionOrigin ? 'connection' : 'manual',
            expectedRevision: current.revision,
            context: context!.withDevice(current),
            simulationMode: simulationMode,
          );
          if (acquired == _Acquisition.committed) return RefreshResult.updated;
          if (acquired == _Acquisition.publicationFailed) {
            return RefreshResult.updatedPublicationFailed;
          }
          final latest = await repository.loadAcquisitionContext(plantId);
          await _publish();
          return latest?.device.id == captured.id &&
                  latest?.device.revision == current.revision
              ? RefreshResult.acquisitionFailed
              : RefreshResult.assignmentChanged;
        } catch (error) {
          onError?.call(error);
          await _publish();
          return error is NoFeasibleManualCondition
              ? RefreshResult.simulationUnavailable
              : RefreshResult.acquisitionFailed;
        }
      });
    } finally {
      if (rearm) armError = await assignmentsChanged();
    }
    if (armError != null && result == RefreshResult.updated) {
      return RefreshResult.updatedSchedulerFailed;
    }
    return result;
  }

  Future<Device> prepareConnection(Device candidate, DeviceGateway devices) =>
      _serial(candidate.id, () async {
        final result = await devices.connect(candidate);
        if (result.id != candidate.id || !result.isConnected) {
          throw StateError('Connection failed.');
        }
        return result;
      });
  Future<_Acquisition> _acquire(
    String plantId,
    String deviceId, {
    required String origin,
    int? slot,
    int? expectedRevision,
    DeviceReadingContext? context,
    SimulationMode simulationMode = SimulationMode.environment,
  }) async {
    if (_disposed) return _Acquisition.rejected;
    final snapshot =
        context ?? await repository.loadAcquisitionContext(plantId);
    final device = snapshot?.device;
    if (device == null ||
        device.id != deviceId ||
        !device.isConnected ||
        (expectedRevision != null && device.revision != expectedRevision)) {
      return _Acquisition.rejected;
    }
    if (slot != null && slot <= device.lastAutoSlot) {
      return _Acquisition.rejected;
    }
    final local = gateway is PlantSimulationGateway;
    final reading = local
        ? await (gateway as PlantSimulationGateway).acquire(
            device,
            clock.now().toUtc(),
            previousReading: snapshot!.previousReading,
            simulationMode: simulationMode,
            plantContext: PlantSimulationContext(
              plantId: snapshot.plantId,
              lightRange: snapshot.lightRange,
              idealRanges: snapshot.idealRanges,
            ),
          )
        : await gateway.acquire(
            device,
            clock.now().toUtc(),
            previousReading: snapshot!.previousReading,
            simulationMode: simulationMode,
          );
    if (_disposed) return _Acquisition.rejected;
    bool committed;
    try {
      committed = await repository.commitReading(
        plantId,
        device,
        reading,
        origin: origin,
        autoSlot: slot,
        expectedProfileRevision: local ? snapshot.profileRevision : null,
      );
    } catch (error) {
      // A worker/transport can lose the acknowledgement after commit. Confirm
      // that exact packet at the next durable generation, never retry its write.
      onError?.call(error);
      final persisted = await repository.loadAcquisitionContext(plantId);
      final packet = persisted?.previousReading;
      committed =
          persisted?.device.id == device.id &&
          persisted?.device.revision == device.revision &&
          persisted?.device.generationSequence ==
              device.generationSequence + 1 &&
          (origin != 'automatic' || persisted?.device.lastAutoSlot == slot) &&
          packet != null &&
          packet.origin == origin &&
          packet.recordedAt.millisecondsSinceEpoch ==
              reading.recordedAt.millisecondsSinceEpoch &&
          SensorMetric.values.every(
            (m) => packet.valueFor(m) == reading.valueFor(m),
          );
      if (!committed) rethrow;
    }
    if (!committed) return _Acquisition.rejected;
    return await _publish()
        ? _Acquisition.committed
        : _Acquisition.publicationFailed;
  }

  Future<void> processDue() async {
    final assignments = await repository.loadAssignedDevices();
    await Future.wait(
      assignments.entries.map((entry) async {
        final device = entry.value;
        if (!device.isConnected || device.createdAt == null) return;
        final slot = SqlitePlantRepository.slotAt(device, clock.now());
        if (slot <= device.lastAutoSlot) return;
        try {
          await _serial(
            device.id,
            () =>
                _acquire(entry.key, device.id, origin: 'automatic', slot: slot),
          );
        } catch (error) {
          onError?.call(error);
        }
      }),
    );
  }

  Future<void> resume() async {
    if (_disposed) return;
    _active = true;
    _timer?.cancel();
    try {
      await processDue();
    } catch (error) {
      onError?.call(error);
    }
    await _arm();
  }

  Future<Object?> assignmentsChanged() async {
    if (!_active || _disposed) return null;
    return _arm();
  }

  Future<Object?> _arm() async {
    if (!_active || _disposed) return null;
    final generation = ++_armGeneration;
    _timer?.cancel();
    try {
      final devices = (await repository.loadAssignedDevices()).values;
      DateTime? next;
      for (final d in devices) {
        if (!d.isConnected || d.createdAt == null) continue;
        final slot = SqlitePlantRepository.slotAt(d, clock.now());
        final deadline = d.createdAt!.add(
          Duration(
            milliseconds:
                (slot < d.lastAutoSlot ? d.lastAutoSlot + 1 : slot + 1) *
                SqlitePlantRepository.interval.inMilliseconds,
          ),
        );
        final candidate = slot > d.lastAutoSlot
            ? clock.now().add(const Duration(seconds: 30))
            : deadline;
        if (next == null || candidate.isBefore(next)) next = candidate;
      }
      if (!_active ||
          _disposed ||
          generation != _armGeneration ||
          next == null) {
        return null;
      }
      var delay = next.difference(clock.now());
      if (delay.isNegative) delay = Duration.zero;
      _timer = createTimer(delay, () {
        if (_active && !_disposed && generation == _armGeneration) {
          unawaited(resume());
        }
      });
      return null;
    } catch (error) {
      onError?.call(error);
      if (_active && !_disposed && generation == _armGeneration) {
        try {
          _timer = createTimer(const Duration(seconds: 30), () {
            if (_active && !_disposed && generation == _armGeneration) {
              unawaited(resume());
            }
          });
        } catch (timerError) {
          onError?.call(timerError);
        }
      }
      return error;
    }
  }

  void pause() {
    _active = false;
    _armGeneration++;
    _timer?.cancel();
  }

  void dispose() {
    _disposed = true;
    pause();
  }
}
