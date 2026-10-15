# SIGmobile Plant Companion

A Flutter frontend for keeping an eye on houseplants, built to be readable by two students learning mobile development. The app lives in [`app/`](app/). The original repository license is preserved; no GitHub Pages files were present or changed.

This milestone uses **simulated sensor readings, Bluetooth connections, and battery voltage**. Plants and readings stay in memory. **Restarting the app (or reloading the web page) resets the demo** to Moss, a Monstera linked to the one simulated ESP32. There is no SQLite, real Bluetooth, Wi-Fi, backend, or watering implementation.

## Set up and launch

Install a [stable Flutter SDK](https://docs.flutter.dev/install/manual), put its `bin` directory on your PATH, and run:

```sh
cd app
flutter pub get
flutter doctor
flutter devices
flutter run -d chrome
```

Chrome is a convenient development target for this mock app. Android and iOS project runners are also included:

```sh
# Android: install Android Studio/SDK and start an emulator or connect a phone.
flutter run -d <android-device-id>

# iOS: on macOS with Xcode, start a simulator or connect an iPhone.
flutter run -d <ios-device-id>
```

For a browser served on a known local port:

```sh
flutter run -d web-server --web-hostname=127.0.0.1 --web-port=7357
# Open http://127.0.0.1:7357
```

A local Flutter 3.47.6 SDK was installed in the ignored `.tools/flutter` directory for verification on this machine. To use it in PowerShell without changing your global PATH, run the following from the repository root, then use the commands above:

```powershell
$env:PATH = "$PWD\.tools\flutter\bin;$env:PATH"
$env:PUB_CACHE = "$PWD\.tools\pub-cache"
```

The app uses Flutter's **Material 3 UI library**, [FlexColorScheme](https://pub.dev/packages/flex_color_scheme) for consistent component theming, and `provider` for shared state. `cupertino_icons` supplies standard iOS navigation glyphs. Plant avatars use built-in Flutter icons; no custom images are generated or downloaded.

## Try the demonstration

1. Open **My Plants**, then tap **Moss**.
2. Tap **Refresh readings**. It briefly loads, then updates values, timestamp, and history.
3. Open **Demo conditions** and choose a scene:

   | Scene | Behavior |
   | --- | --- |
   | Comfortable | Reconnects and creates a fresh reading within the selected demo ranges. |
   | Thirsty | Creates a dry-soil example and changes the avatar/status. |
   | Low light | Shows a dim-light avatar example. One low reading or nighttime darkness is not a diagnosis of insufficient light. |
   | Disconnected | Disconnects the simulated device while retaining the last reading and its original timestamp. A disconnected device can have recent data. |
   | Stale data | Loads a packet from two hours ago. Refresh preserves that packet's original timestamp. Choose Comfortable to resume fresh readings. |

4. Go back. The plant card reflects the selected condition.
5. Tap **Add Plant**, enter a nickname, choose a type, and save. The new plant appears in My Plants immediately. A device is optional; missing readings say **Unavailable**.
6. Search for the ESP32 in setup. While assigned to Moss, it explains the unique-device restriction and allows saving without linking.

To exercise all device setup states, open Moss's details and tap **Unlink simulated device**, then confirm. Saved readings stay with Moss. In Add Plant, search, turn on **Fail next connection**, and tap **Connect device**. Watch Connecting → Connection failed, then tap **Retry** to connect successfully and save the new plant. Refresh that plant's details to get its first reading. The failure toggle is consumed by one attempt; leave it off for a successful Retry.

Choose **Custom** to enter a plant type and configure the four target ranges. Nickname and plant type are required. Custom ranges validate numbers and minimum/maximum order; wetness index and humidity bounds must stay between 0 and 100. Saving without a device also works after a failed connection.

The empty state is implemented and tested with `PlantStore(seedDemo: false)`. To demonstrate it manually, temporarily pass `seedDemo: false` to the `PlantStore` constructor in `main.dart` and restart.

## Reading semantics

- Soil moisture is a **relative wetness index from 0–100**, not an actual soil-water percentage. Future hardware needs calibration before interpreting this index.
- Temperature uses °C, humidity uses % RH, and light uses lux.
- Sample species share deliberately identical teaching ranges. These are **demonstration thresholds, not scientifically authoritative ideal ranges**. Custom lets you configure your own.
- Each card compares its available value with its selected target range. Saved stale values keep their numeric range status and carry an additional stale label.
- Data becomes stale after 30 minutes. A minute timer updates freshness labels even without a new reading. Connection state and freshness are tracked separately.
- Null means unavailable. Unlinking a device preserves any saved readings, and no synthetic zeros replace missing values.
- History holds at most eight packets, newest first. Entering the stale demo replaces history with its one old demonstration packet to keep the recent-readings list chronological.
- Battery is shown as simulated voltage, without inventing a charge percentage.
- Dry and dim scenes adapt to custom target ranges. If a custom soil range starts at zero, the thirsty avatar is explicitly labeled as a demo while the numeric reading stays correctly marked in range.

## How the code fits together

| File or folder | Responsibility |
| --- | --- |
| [`app/lib/main.dart`](app/lib/main.dart) | App entry, Material app, and the single provider above navigation. |
| [`app/lib/models/`](app/lib/models/) | Shared `Plant`, `PlantProfile`, `Device`, `SensorReading`, and target-range types. |
| [`app/lib/state/plant_store.dart`](app/lib/state/plant_store.dart) | In-memory plants, device assignments, reading history, refresh/loading, demo conditions, and freshness. |
| [`app/lib/services/fake_sensor_repository.dart`](app/lib/services/fake_sensor_repository.dart) | Delays, mock discovery/connection/failure, and deterministic changing sensor values. |
| [`app/lib/screens/my_plants_screen.dart`](app/lib/screens/my_plants_screen.dart) | Plant list, empty state, and navigation. |
| [`app/lib/screens/plant_details_screen.dart`](app/lib/screens/plant_details_screen.dart) | Avatar/condition, readings, demo menu, device information, and recent history. |
| [`app/lib/screens/add_plant_screen.dart`](app/lib/screens/add_plant_screen.dart) | Validated form, optional setup state machine, and custom target ranges. |
| [`app/lib/widgets/`](app/lib/widgets/) | Reusable avatar, reading card, status badge, condition presentation, and scrolling page layout. |
| [`app/lib/theme/app_theme.dart`](app/lib/theme/app_theme.dart) | Off-white, forest, sage, and terracotta palette; Material 3 typography and component theme. |
| [`app/lib/utils/reading_time.dart`](app/lib/utils/reading_time.dart) | Local readable timestamps and elapsed time. |
| [`app/test/`](app/test/) | Focused widget flows, accessibility/layout checks, and state semantics. |

**Shared state:** `ChangeNotifierProvider` creates one `PlantStore` above the navigator. Both list and details call `context.watch<PlantStore>()`. Saving, refreshing, changing a demo condition, and unlinking update the store and call `notifyListeners()`, so both screens rebuild from the same data. Details routes hold a plant ID and look that ID up in the store, avoiding stale snapshots or opening the wrong plant. Temporary form/search state stays local to Add Plant.

**Later Bluetooth:** discovery, connection, and read behavior belongs at the service boundary in `fake_sensor_repository.dart`. Add a real Bluetooth service returning the same `Device` and `SensorReading` models, inject it into the store, and isolate/remove demo controls. Decode ESP32 packets, preserve device timestamps, and represent actual connection changes in shared state. The UI should continue consuming the same models.

**Later SQLite:** introduce a persistence repository for loading and saving plants, profiles, device assignments, and reading history. Connect it to store initialization and mutations (`addPlant`, refresh, unlink) while keeping SQL out of screens. Enforce device uniqueness in both state and storage. No persistence dependency is included in this milestone.

**Later pixel art:** replace the icon composition inside [`PlantAvatar`](app/lib/widgets/plant_avatar.dart) with your assets; screens already pass its condition and size.

## Checks

From `app/`:

```sh
dart format lib test
flutter analyze
flutter test
flutter build web
```

The tests cover required fields, adding without a device, navigation to the correct plant, refresh and shared status updates, occupied device behavior, searching/connecting/failure/Retry, custom ranges, the empty state, and 320-pixel layouts with doubled text and keyboard insets. State tests verify disconnected/recent data, preserved stale timestamps, unique device assignments, and unavailable data.

Verification on this Windows machine used Flutter 3.47.6 / Dart 3.13.5. Formatting, analysis, and the production web build pass; all 15 tests pass. The app starts successfully in Chrome. Phone-sized widget previews were rendered with local fonts and inspected; the main flow and narrow/enlarged-text layouts are covered by widget tests. Live browser automation is unavailable, so an interactive browser walkthrough could not be verified. Android execution cannot be verified because the Android SDK is absent. iOS execution cannot be verified on this Windows host; macOS and Xcode are required.
