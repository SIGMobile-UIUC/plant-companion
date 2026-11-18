# Phase G — flash, calibrate and run once

Production sketch: **`firmware/PlantCompanion/PlantCompanion.ino`**, with adjacent `pc_core.h`. Rollback baseline: **`firmware/diagnostic/PlantCompanion_Test (1).ino`**, copied unchanged; SHA256 `ad088e1ecf33e20c847580c507d07e21183818b8318c20afadc7f3324ef1bc4b`.

No ESP32 has been flashed in this session. No sensor/calibration values below are claimed to be observed hardware results. Finish the preparation below before starting the single ordered phone checklist.

## Prepare the board on the laptop

Wiring stays as supplied: XIAO ESP32-C3, SDA D4/GPIO6, SCL D5/GPIO7, SHT40 at 0x44, VEML7700 at 0x10, SEN0308 signal at D1/GPIO3 through the existing **two 10 kΩ soil-signal divider**. Confirm actual wiring against the working diagnostic before changing anything. The logged 2× voltage is only a probe-output estimate; calibration uses measured ADC-side mV. No battery divider, battery telemetry, sleep mode, sync button or firmware-controlled power switch is added.

Use Arduino IDE's board manager **esp32 by Espressif Systems 3.3.12**, board **XIAO_ESP32C3**, USB CDC On Boot **Enabled**, Partition Scheme **Huge APP (3 MB No OTA / 1 MB SPIFFS)**, Erase All Flash **Disabled**. LittleFS uses that data partition. Install these exact library versions with Library Manager: Adafruit SHT4x 1.0.5, Adafruit VEML7700 2.1.6, Adafruit BusIO 1.17.4 and Adafruit Unified Sensor 1.1.15. Wire, SPI, BLE, FS, LittleFS and Preferences come from the selected core. BLE uses that core's NimBLE-backed built-in API and subscription callback; do not add an unrelated BLE library.

Open the production sketch, compile, select the board's USB port, then Upload. CLI equivalent from the repository root in PowerShell (replace `COM7` with the actual board port):

```powershell
$arduino = "$env:LOCALAPPDATA\Programs\Arduino IDE\resources\app\lib\backend\resources\arduino-cli.exe"
$board = 'esp32:esp32:XIAO_ESP32C3:CDCOnBoot=default,PartitionScheme=huge_app,EraseFlash=none'
& $arduino board list
& $arduino compile --fqbn $board --warnings all firmware/PlantCompanion
& $arduino upload --port COM7 --fqbn $board firmware/PlantCompanion
& $arduino monitor --port COM7 --config baudrate=115200
```

Arduino Serial Monitor: **115200 baud**, **Newline** line ending. These are the implemented commands, one per line:

```text
help
status
live on
adc
cal show
```

Observe SHT40 temperature/humidity, VEML7700 lux and ADC mV. Change lighting and verify lux changes; check the soil signal is not near a rail. `live on` is a two-second diagnostic stream and does not fill the history ring. In final wiring, put the probe in representative dry soil, allow it to stabilize, then send:

```text
cal dry
```

Water the reference soil, let the reading stabilize, then send:

```text
cal wet
cal show
cal save
cal show
live off
sample
status
```

Explicit entry is also supported: `cal dry 1500` and `cal wet 700` are **syntax examples, not approved endpoints**. Substitute your measured ADC-side mV, never doubled probe-output mV. Endpoints must each be 20–2400 mV with at least 50 mV separation. Either slope works; values clamp to 0–100%. Sustained rail readings reject capture/save and require checking wiring. Before calibration soil is unavailable; other working sensors remain usable. `cal save` must report success. Power-cycle and verify `cal show` still reports saved endpoints before borrowing the phone. Serial `sample` creates a stored manual sample without changing the automatic deadline.

Illustrative output shape (numbers vary; **not a captured board log**):

```text
PC BLE advertising PlantComp-... production service=d1a10000-7c2f-4a9d-a6b4-36b51743c301
PC DEVICE ... protocol=1 storage=ready oldest=1 newest=1 ...
PC SAMPLE source=startup seq=1 boot=1 uptime=... utc=0 valid=0x0E BLE=advertising
SHT40 temperature=23.50C humidity=45.00% | VEML7700 lux=120.000
SOIL ADC=1100 mV estimated_probe_output=2200 mV (2x divider estimate ONLY), moisture=UNAVAILABLE ... calibration=not calibrated
PC CAL SAVED (survives power cycle)
PC SAMPLE source=manual ... valid=0x0F ...
PC SCHEDULE next_ms=... remaining_ms=... interval_ms=1200000
PC ACK cursor=... (advisory; records retained)
```

Check a USB-disconnected startup on the board's existing physical power. USB serial waiting is bounded at 2.5 seconds; BLE and sampling do not require a Serial Monitor. Do not change existing power wiring for this software task.

## Prepare and install on the borrowed Mac/iPhone

This Windows session cannot compile/sign iOS. Use a Mac with Xcode and the iPhone's supported iOS SDK; deployment target is iOS 15.0. Copy the **whole current working tree**, including untracked `app/lib/ble/`, tests, docs, firmware and protocol fixtures, plus original assets/fonts. Exclude `.tools`, `.dart_tool`, `build`, `.git`, local databases and credentials. The Windows `.tools/flutter` SDK is not a Mac SDK. Install matching **Flutter 3.47.6 / Dart 3.13.5 for the Mac's CPU** from the [Flutter SDK archive](https://docs.flutter.dev/install/archive).

On the Mac:

```sh
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
xcodebuild -downloadPlatform iOS
flutter doctor -v
cd /path/to/plant-companion/app
flutter pub get
flutter analyze
flutter test
flutter build ios --release --no-codesign
open ios/Runner.xcworkspace
```

Resolve any Xcode license/platform-download or CocoaPods requirement reported by `flutter doctor` before continuing; Flutter supports Swift Package Manager but may use CocoaPods for plugins without SPM support. If CocoaPods is required, install it following the [Flutter iOS setup guide](https://docs.flutter.dev/platform-integration/ios/setup), rerun `flutter pub get` and the iOS build, and open **Runner.xcworkspace**, not only the project file. Keep the locked dependencies; do not run `pub upgrade` during the borrowed session.

Connect/unlock the iPhone by USB, Trust the Mac, and let Xcode pair/register it. In Xcode Settings → Apple Accounts, sign in with the account authorized for development on the borrowed setup. Select Runner target → Signing & Capabilities → Automatically manage signing → that account's development Team. The checked-in bundle ID is `org.sigmobile.plantCompanion`. If unavailable to that team, use a unique development-only suffix on the borrowed copy and its test target; do not commit signing/account changes. No development team or credential is stored in this repository.

On the iPhone, enable Settings → Privacy & Security → Developer Mode, restart if requested, then confirm. If the menu is absent, first pair/run from Xcode. Accept a development-profile trust prompt in Settings → General → VPN & Device Management if shown. Select the **physical iPhone** as destination. Use Product → Scheme → Edit Scheme → Run → Build Configuration **Release**, then Product → Run to build/sign/install. This permits launch from the home screen without an attached debug session. Alternatively, after signing is configured:

```sh
flutter devices
flutter run --release -d <physical-iPhone-device-id>
```

Allow the app's Bluetooth permission. The app requests no location permission on iOS, has `NSBluetoothAlwaysUsageDescription`, and uses foreground BLE with resume catch-up. Record the actual iPhone/iOS/Xcode versions and build/signing outcome. A simulator is not a physical BLE acceptance run. See [Apple's device signing/run instructions](https://developer.apple.com/documentation/xcode/building-and-running-an-app) and [Developer Mode instructions](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device).

## One ordered borrowed-device checklist

1. **Fast demo first:** with USB disconnected, power on the calibrated ESP32 using its existing power setup. Open Plant Companion on the physical iPhone → Florence. On first setup use Florence's Edit → Companion Device → Scan for nearby devices → `PlantComp-…` physical BLE row → Connect → Save. Later launches should use the saved association automatically. Confirm the device card says Physical BLE and all four normal Florence readings appear promptly (°F, % RH, lux, soil %), then change the lighting and press the existing Refresh icon. Wait for the refreshed measurement to save; expand **Reading history**, verify a `Physical BLE #… · manual` row and the changed light value. Capture a screenshot/sequence and elapsed time. This is the first acceptance check, before the 20-minute wait.
2. Record the current latest sequence and history count. Close and reopen the app from the home screen. Verify Florence retains the same physical device, reconnects without reassignment and displays saved/new readings. If the board is unreachable, saved readings/age remain visible with disconnected status, rather than simulator updates.
3. **Offline scheduled sample:** keep the ESP32 powered and turn the phone's Bluetooth off in **Settings**, or take the phone out of range. Leave the app/phone away for at least 20 minutes (slightly over 20 minutes guarantees crossing the next deadline). The production interval is 1,200,000 ms and Refresh does not restart it. Bring the phone back, enable Bluetooth and foreground the app. Verify at least one new `scheduled` sequence imports. Reopen/reconnect/refresh the history panel and verify that same sequence appears **once**. Check the saved count/sequence, not only the latest card value. USB serial `PC SCHEDULE`/`PC SAMPLE source=scheduled` can corroborate the deadline in a separate powered-laptop check.
4. **Reboot:** power-cycle the ESP32 with USB disconnected. Reopen Florence and verify its unchanged saved device identity reconnects; a new startup sample (new boot ID) or Refresh saves. Soil must still be available with the saved calibration. A boot recorded before any phone clock anchor may say Measurement time unknown; do not reinterpret reconnect time as its measurement time.
5. If time permits, create an unsynced scheduled sample while the phone is away, power-cycle before reconnecting, then reconnect. Verify retained pre-reboot and new startup sequences import once. If the previous boot was never phone-anchored, its time must stay unknown. Briefly disable Bluetooth during catch-up, then retry to check recovery without duplicates.
6. Save evidence: app screenshots, hardware ID/stream, sample sequences/kinds/counts, actual elapsed time, serial logs when available, firmware versions, iPhone/iOS/Xcode version, build/install command and result. Mark the physical audit rows PASS only after observing them. Reserve a second device session for a specific diagnosed fix.

## Fast isolation / rollback

| Symptom | Check |
| --- | --- |
| Soil unavailable / ADC near rail | `adc`, `live on`, `cal show`; inspect existing probe supply, ground, D1 and two-resistor soil divider. Do not enter doubled voltage. Confirm `cal save` succeeded. |
| Temperature/humidity unavailable | SHT40 address 0x44, D4/D5/ground/power; serial marks unavailable. Other sensors/BLE should continue. |
| Light unavailable | VEML7700 address 0x10, bus/power, saturation message; 0 lux is valid darkness. |
| No production scan result | Power, `PC BLE advertising`, production UUID, Bluetooth Settings permission. `PlantComp-Test` is intentionally excluded. Stop other BLE clients holding the board. |
| Denied / Bluetooth off | Enable the app's Bluetooth access in Settings; turn Bluetooth on and retry or foreground the app. Android ≤11 additionally needs Location Services/permission for scanning. |
| Incompatible / malformed packet | Confirm the exact production sketch/core and protocol v1 on both sides; keep the 20-byte framing. Capture the error and firmware identity. |
| Storage error / failed fresh write | Keep old app readings; retry safely. Capture app error and `PC STORAGE`/ACK logs. Do not clear SQLite/NVS or erase flash to hide the fault. |
| iPhone build/sign/install fails | Capture Xcode error, account Team, bundle ID, Developer Mode, supported iOS SDK and `flutter doctor -v`. This is not a sensor/protocol pass. |
| Repeated history gap | Ring overrun/torn slots cannot be recovered; preserve the warning and retained data. Very frequent manual samples/reboots reduce the 1024-slot horizon. |

Rollback only if needed: open the unchanged diagnostic sketch in Arduino IDE (copy into a matching Arduino sketch folder if requested), compile/upload to XIAO_ESP32C3 with the same pin/library baseline and **Erase All Flash Disabled**. Its `PlantComp-Test` ASCII service is for diagnosis; the production app intentionally will not treat it as a production peripheral. Do not erase calibration/history during diagnosis.
