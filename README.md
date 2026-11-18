# SIGMobile Plant Companion

Plant Companion is a Flutter application developed for SIGMobile to help people manage houseplants and understand their growing conditions. The MVP combines pixel-art plant companions, configurable care ranges and persistent sensor data. Phase G adds production XIAO ESP32-C3 firmware and Android/iOS foreground BLE alongside the simulator. Software verification is recorded in the [Phase G audit](docs/phase-g-audit.md); physical ESP32/iPhone acceptance remains pending.

## Features

- Add, edit and delete plants, including nicknames, scientific names, optional full names and three plant portraits.
- Configure ideal soil moisture, light, temperature and humidity ranges for each plant.
- See current readings, ideal-range rails, connection status and the last genuine sync time on Home and individual plant Details.
- Recognize nine conditions: Happy; moisture too low/high; light too low/high; temperature too low/high; humidity too low/high.
- Discover, create, connect, change and unassign multiple simulated devices through the inline Companion Device controls.
- Discover and assign a production physical BLE device in the same controls; reconnect to its saved identity and import retained readings.
- Refresh readings manually and receive scheduled readings while the app is active.
- Save plants, care settings, device assignments and historical readings in SQLite across application and browser restarts.

Home card actions open the corresponding plant's Details. The drawer's **Edit Plants** action opens plant selection. Add and Edit share validated forms, original artwork and isolated condition previews. Device changes are staged until Save; cancelling discards them. Delete is immediate. Validation and operation errors appear inline.

## Readings and simulation

The four measurements are soil moisture and humidity on a 0–100 scale, light in lux and temperature displayed in Fahrenheit. Temperature is stored internally in Celsius. Ideal care ranges are user-configured targets.

For simulated devices, manual Refresh selects a feasible condition, then generates all four measurements consistently with it. When all nine conditions are possible, Happy has a 20% probability and each low/high problem has a 10% probability. Impossible conditions are excluded and the remaining weights are normalized. Repeated conditions are expected; Refresh does not cycle through a fixed list.

Simulated initial connection and automatic acquisitions use a separate gradual environmental simulation. Automatic readings follow each simulated device's creation time at 20-minute intervals. Manual Refresh preserves that schedule. This scheduler operates in the foreground and performs one overdue catch-up when the app resumes; it is not a background service.

For physical BLE devices, the ESP32 takes a startup reading and records every 20 minutes while powered, including while the phone is away. Refresh requests and saves a matching new device measurement without resetting that deadline. On launch/resume the mobile app reconnects and imports latest/offline records transactionally before acknowledgment. Calibration is performed once through USB Serial Monitor and saved on the board; uncalibrated soil stays unavailable. Physical and simulated source IDs/storage remain separate. Physical Details includes an inline history list; samples without a defensible clock anchor retain unknown time. Follow the [production flash/calibration/iPhone runbook](docs/phase-g-hardware-runbook.md) and [wire protocol](docs/ble-protocol.md).

Connection, sensor availability and plant health are separate. Disconnected devices retain their genuine last-known readings and time. Missing measurements do not count as healthy. A plant without a device displays demonstration midpoint values with a sleeping portrait and no need bubble or fabricated sync time. Form previews never become acquired readings.

The nine condition indicators use the original faces and sensor artwork. Excess moisture, light and humidity add the red slash. Cold uses the blue thermometer in its need bubble; standard temperature-row icons always remain red. Happy has no Home bubble and retains the heart in Details.

SQLite retains seven days of history relative to each plant's latest stored packet. Home and Details load the latest reading relevant to the assigned device; history is retrieved separately by the repository. Editing care ranges does not rewrite earlier packets. History charts are not part of the current UI.

## Requirements and setup

- A compatible Flutter SDK on `PATH`, including Dart satisfying `>=3.8.0 <4.0.0` in [pubspec.yaml](app/pubspec.yaml).
- Chrome for web development, or an Android SDK with a running emulator/connected Android device.
- The project has been validated with Flutter 3.47.6 and Dart 3.13.5.

From the repository root:

```sh
cd app
flutter pub get
flutter devices
```

Run in Chrome:

```sh
flutter run -d chrome
```

For Android, start an emulator or connect a device, then run with its ID from `flutter devices`. For example, the first Android emulator commonly uses:

```sh
flutter run -d emulator-5554
```

Web SQLite requires [sqlite3.wasm](app/web/sqlite3.wasm) and [drift_worker.js](app/web/drift_worker.js) at the served application root. Flutter copies these checked-in resources into the web build. Serve over localhost or HTTPS. The app rejects an unavailable persistent backend rather than silently treating an in-memory database as durable storage. Browser data remains specific to its origin and browser profile.

## Tests and builds

Run from `app/`:

```sh
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze
flutter test
flutter build web --release
flutter build apk --debug
flutter build apk --release
```

Tests protect plant management, validation/navigation, all nine condition mappings, sensor scales, SQLite persistence/migrations, device ownership, deterministic simulation, timer-triggered acquisitions, history/restarts, concurrency/failure recovery and responsive/accessibility behavior.

An optional real-browser persistence smoke test checks creation, editing, page reload and a complete browser process restart using a disposable profile. It requires Node 22+ and Chrome. Set `CHROME_EXECUTABLE` if Chrome is not at the Windows default installation path.

```sh
flutter build web --release -t tool/browser_persistence_smoke.dart --output build/browser-persistence-smoke
node tool/run_browser_persistence_smoke.mjs build/browser-persistence-smoke
```

## Project structure

| Path | Purpose |
|---|---|
| `app/lib/models/` | Plants, care ranges, readings, device state and form drafts |
| `app/lib/persistence/` | SQLite schema, migrations, atomic mutations and reading history |
| `app/lib/services/` | Sensor/device interfaces, simulation, condition calculation and scheduling |
| `app/lib/ble/` | Native transport, versioned wire codec and foreground durable synchronization |
| `app/lib/state/` | Shared application state and durable operation coordination |
| `app/lib/screens/`, `app/lib/navigation/` | Home, Details, plant selection and shared Add/Edit workflows |
| `app/lib/widgets/` | Portrait composition, sensor rails, device controls and accessible form components |
| `app/test/`, `app/test/fixtures/` | Automated regressions and shared test fixtures |
| `app/tool/` | Launcher icon generation and the optional browser persistence smoke test |
| `app/assets/` | Original plant artwork, indicators, branding, fonts and font licenses |
| `app/android/`, `app/ios/`, `app/web/` | Platform configuration, launcher resources and web SQLite runtime |
| `artwork/` | Original AppLogo and generated platform-icon manifest |
| `firmware/` | Production XIAO ESP32-C3 sketch, unchanged diagnostic rollback and portable core tests |
| `protocol/`, `docs/` | Shared wire fixtures, BLE reference, physical runbook and evidence-backed Phase G audit |

See [asset documentation](README_ASSETS.md), the [asset manifest](asset_manifest.json) and [launcher generation instructions](artwork/README.md). The original horizontal wordmark remains in the application; platform launcher icons use AppLogo on `#163F2E`. Project licensing is in [LICENSE](LICENSE); font licenses are included with the fonts.

## Limitations and future work

Physical ESP32/BLE integration and serial soil calibration are implemented but have not been verified on a real board/phone in this session. Automatic watering, cloud synchronization and user accounts are not implemented. Notifications, Settings and About are presentational drawer entries. There is no new phone background acquisition service or history-chart UI. Physical BLE requires the Android/iOS app; web/desktop retain simulator support.

Phase G checks cover Android/web builds, Flutter tests and Chrome SQLite persistence. Physical BLE on Android/iPhone has not been observed. Building/running iOS requires macOS and Xcode; iOS compile/sign/install and Safari runtime validation remain outstanding. Android release configuration currently uses debug signing and must be configured for production distribution. Fully validated Android App Bundles also require the Android SDK command-line tools, including `apkanalyzer`.

The next acceptance work is the documented board serial/calibration preflight and Mac build/install, followed by the fast Florence demo, offline catch-up and reboot checks on the physical ESP32/iPhone. See the audit for exact completed checks and remaining blockers.
