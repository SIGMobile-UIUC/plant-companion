import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/device.dart';
import '../models/plant.dart';
import '../models/plant_profile.dart';
import '../services/fake_sensor_repository.dart';

class PlantStore extends ChangeNotifier {
  PlantStore({FakeSensorRepository? repository, bool seedDemo = true})
    : repository = repository ?? FakeSensorRepository() {
    if (seedDemo) {
      final now = DateTime.now();
      final profile = PlantProfile.samples.first;
      _devices[FakeSensorRepository.demoDevice.id] =
          FakeSensorRepository.demoDevice;
      _plants.add(
        Plant(
          id: 'plant-1',
          nickname: 'Moss',
          profile: profile,
          deviceId: FakeSensorRepository.demoDevice.id,
          readings: List.generate(
            3,
            (index) => this.repository.makeReading(
              profile,
              DemoScenario.comfortable,
              now.subtract(Duration(minutes: index * 15)),
            ),
          ),
        ),
      );
    }
    // Freshness changes with elapsed time even when no new reading arrives.
    _freshnessTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => notifyListeners(),
    );
  }

  final FakeSensorRepository repository;
  final List<Plant> _plants = [];
  final Map<String, Device> _devices = {};
  final Set<String> _refreshing = {};
  late final Timer _freshnessTimer;
  int _nextId = 2;
  bool _disposed = false;

  static const staleAfter = Duration(minutes: 30);
  List<Plant> get plants => List.unmodifiable(_plants);
  Plant plantById(String id) => _plants.firstWhere((plant) => plant.id == id);
  Device? deviceFor(Plant plant) => _devices[plant.deviceId];
  bool isRefreshing(String id) => _refreshing.contains(id);
  bool isStale(Plant plant) =>
      plant.latestReading != null &&
      DateTime.now().difference(plant.latestReading!.recordedAt) >= staleAfter;

  Plant? ownerOfDevice(String deviceId) {
    for (final plant in _plants) {
      if (plant.deviceId == deviceId) return plant;
    }
    return null;
  }

  void addPlant({
    required String nickname,
    required PlantProfile profile,
    Device? device,
  }) {
    if (nickname.trim().isEmpty) {
      throw ArgumentError('Give your plant a nickname.');
    }
    if (device != null && ownerOfDevice(device.id) != null) {
      throw StateError('This device is already linked. Save without a device.');
    }
    if (device != null) _devices[device.id] = device;
    _plants.add(
      Plant(
        id: 'plant-${_nextId++}',
        nickname: nickname.trim(),
        profile: profile,
        deviceId: device?.id,
      ),
    );
    notifyListeners();
  }

  Future<String> refresh(String id) async {
    final plant = plantById(id);
    final device = deviceFor(plant);
    if (device == null) return 'No device linked. Readings are unavailable.';
    if (!device.isConnected) {
      return 'Device disconnected. Your last reading is still saved.';
    }
    if (!_refreshing.add(id)) return 'A refresh is already in progress.';
    notifyListeners();
    try {
      final reading = await repository.read(plant.profile, plant.demoScenario);
      if (_disposed) return 'Demo closed.';
      final current = plantById(id);
      // The stale scenario freezes the old timestamp; refresh cannot make it fresh.
      if (current.demoScenario == DemoScenario.staleData) {
        return 'Stale-data demo: the original timestamp is preserved. Choose Comfortable to resume.';
      }
      if (deviceFor(current)?.isConnected != true) {
        return 'Device disconnected. Last reading preserved.';
      }
      _replace(
        current.withReadings([reading, ...current.readings].take(8).toList()),
      );
      return 'Simulated readings updated.';
    } catch (_) {
      return 'Could not refresh the demo. Please try again.';
    } finally {
      _refreshing.remove(id);
      if (!_disposed) notifyListeners();
    }
  }

  void setDemoScenario(String id, DemoScenario scenario) {
    final plant = plantById(id);
    final device = deviceFor(plant);
    if (device == null || isRefreshing(id)) return;
    _devices[device.id] = device.withConnection(
      scenario != DemoScenario.disconnected,
    );
    if (scenario == DemoScenario.disconnected) {
      // Connection and reading age are independent. Keep the complete saved history.
      _replace(plant.withReadings(plant.readings, scenario: scenario));
    } else if (scenario == DemoScenario.staleData) {
      // Seed an old packet once, then leave its actual timestamp untouched.
      final timestamp = DateTime.now().subtract(const Duration(hours: 2));
      if (plant.demoScenario != DemoScenario.staleData) {
        final oldReading = repository.makeReading(
          plant.profile,
          DemoScenario.comfortable,
          timestamp,
        );
        _replace(plant.withReadings([oldReading], scenario: scenario));
      }
    } else {
      final reading = repository.makeReading(
        plant.profile,
        scenario,
        DateTime.now(),
      );
      _replace(
        plant.withReadings(
          [reading, ...plant.readings].take(8).toList(),
          scenario: scenario,
        ),
      );
    }
    notifyListeners();
  }

  void _replace(Plant plant) {
    _plants[_plants.indexWhere((item) => item.id == plant.id)] = plant;
  }

  void unlinkDevice(String id) {
    final plant = plantById(id);
    if (isRefreshing(id)) return;
    _replace(plant.withoutDevice());
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _freshnessTimer.cancel();
    super.dispose();
  }
}
