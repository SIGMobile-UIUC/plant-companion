import 'package:drift_flutter/drift_flutter.dart';
import 'app_database.dart';

AppDatabase openAppDatabase() => AppDatabase(
  driftDatabase(
    name: 'plant_companion',
    web: DriftWebOptions(
      sqlite3Wasm: Uri.parse('sqlite3.wasm'),
      driftWorker: Uri.parse('drift_worker.js'),
      onResult: (result) {
        if (result.chosenImplementation == WasmStorageImplementation.inMemory) {
          throw StateError('Persistent browser storage is unavailable.');
        }
      },
    ),
  ),
);
