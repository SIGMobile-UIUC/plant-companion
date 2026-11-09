import 'package:flutter/foundation.dart';
import '../state/plant_store.dart';
import 'device.dart';
import 'plant_commit.dart';

class PendingPlantDevice {
  PendingPlantDevice(this.label) : token = newPlantOperationId();
  final String token, label;
  Device get candidate =>
      Device(id: 'draft:$token', name: label, isConnected: false);
}

/// Form-local selection/preparation. No command here persists assignments.
class PlantDeviceDraft extends ChangeNotifier {
  PlantDeviceDraft(
    this.store, {
    this.plantId,
    String? deviceId,
    this.expanded = false,
  }) : selectedDeviceId = deviceId,
       inventory = store.devices;
  final PlantStore store;
  final String? plantId;
  List<Device> inventory;
  final List<PendingPlantDevice> candidates = [];
  String? selectedDeviceId, selectedCandidateToken, connectingKey, error;
  bool expanded, searching = false, connectionRequested = false;
  String? preparedKey;
  int _scanVersion = 0, _connectionVersion = 0;
  bool _disposed = false;
  bool get createsDevice => selectedCandidateToken != null;
  String? ownerName(String id) {
    final owner = store.ownerOfDevice(id);
    return owner?.id == plantId ? null : owner?.nickname;
  }

  bool eligible(String id) => ownerName(id) == null;
  String? get selectionKey => selectedCandidateToken == null
      ? selectedDeviceId
      : 'draft:$selectedCandidateToken';
  Device? get selectedDevice {
    final selected = inventory.where((d) => d.id == selectedDeviceId);
    return selected.isEmpty ? null : selected.first;
  }

  String get selectedLabel {
    if (selectedCandidateToken != null) {
      return candidates
          .firstWhere((c) => c.token == selectedCandidateToken)
          .label;
    }
    return selectedDevice?.name ?? 'No device assigned';
  }

  Future<void> scan() async {
    expanded = true;
    searching = true;
    error = null;
    final version = ++_scanVersion;
    notifyListeners();
    try {
      final result = await store.discoverDevices();
      if (_disposed || version != _scanVersion) return;
      inventory = List.unmodifiable(result);
    } catch (_) {
      if (!_disposed && version == _scanVersion) {
        error = 'Could not scan. Try again.';
      }
    } finally {
      if (!_disposed && version == _scanVersion) {
        searching = false;
        notifyListeners();
      }
    }
  }

  PendingPlantDevice createCandidate() {
    final candidate = PendingPlantDevice('New device ${candidates.length + 1}');
    candidates.add(candidate);
    expanded = true;
    notifyListeners();
    return candidate;
  }

  Future<void> connectExisting(Device device) async {
    if (!eligible(device.id)) return;
    _select(deviceId: device.id);
    await _prepare(device);
  }

  Future<void> connectCandidate(PendingPlantDevice candidate) async {
    if (!candidates.contains(candidate)) return;
    _select(candidateToken: candidate.token);
    await _prepare(candidate.candidate);
  }

  void _select({String? deviceId, String? candidateToken}) {
    _connectionVersion++;
    connectingKey = null;
    selectedDeviceId = deviceId;
    selectedCandidateToken = candidateToken;
    preparedKey = null;
    connectionRequested = true;
    error = null;
    notifyListeners();
  }

  void unassign() {
    _select();
    connectionRequested = false;
  }

  Future<void> _prepare(Device device) async {
    final version = ++_connectionVersion, key = selectionKey;
    connectingKey = key;
    notifyListeners();
    try {
      await store.prepareDevice(device);
      if (_disposed || version != _connectionVersion || selectionKey != key) {
        return;
      }
      if (selectedDeviceId != null && !eligible(selectedDeviceId!)) {
        error =
            'This device is now assigned to another plant. Choose another device.';
        return;
      }
      preparedKey = key;
    } catch (_) {
      if (!_disposed && version == _connectionVersion) {
        error = 'Could not connect. Save disconnected or try again.';
      }
    } finally {
      if (!_disposed && version == _connectionVersion) {
        connectingKey = null;
        notifyListeners();
      }
    }
  }

  void cancelOperations() {
    _scanVersion++;
    _connectionVersion++;
    searching = false;
    connectingKey = null;
  }

  @override
  void dispose() {
    _disposed = true;
    cancelOperations();
    super.dispose();
  }
}
