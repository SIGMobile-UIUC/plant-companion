import 'fixtures/simulation_context.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plant_companion/models/device.dart';
import 'package:plant_companion/models/sensor_reading.dart';
import 'package:plant_companion/services/fake_sensor_repository.dart';
import 'package:plant_companion/services/simulated_environment.dart';
import 'package:plant_companion/services/simulation_config.dart';

List<double?> values(SensorReading r) =>
    SensorMetric.values.map(r.valueFor).toList();
Device device(String id, int sequence, {String name = 'ESP32-Sim01'}) =>
    Device(id: id, name: name, isConnected: true, generationSequence: sequence);

void main() {
  final at = DateTime.utc(2026, 11, 7);
  test('stable process ignores labels, clock and foreign source readings', () {
    final a = SimulatedEnvironment.sample(
      device('immutable-a', 19),
      at,
      plantContext: simulationContext,
    );
    final b = SimulatedEnvironment.sample(
      device('immutable-a', 19, name: 'ESP32-Sim99'),
      at.add(const Duration(days: 20)),
      previousReading: SensorReading(
        recordedAt: at,
        sourceDeviceId: 'other',
        soilMoisture: 100,
        temperature: -50,
        light: 200000,
        humidity: 0,
      ),
      plantContext: simulationContext,
    );
    expect(values(a), values(b));
    expect(b.recordedAt, at.add(const Duration(days: 20)));
    expect(
      values(a),
      isNot(
        values(
          SimulatedEnvironment.sample(
            device('immutable-b', 19),
            at,
            plantContext: simulationContext,
          ),
        ),
      ),
    );
    expect(
      values(a),
      isNot(
        values(
          SimulatedEnvironment.sample(
            device('immutable-a', 20),
            at,
            plantContext: simulationContext,
          ),
        ),
      ),
    );
  });
  test(
    'partial and invalid prior packets fall back independently per metric',
    () {
      final d = device('partial', 7);
      final baseline = SimulatedEnvironment.sample(
        d,
        at,
        plantContext: simulationContext,
      );
      final prior = SensorReading(
        recordedAt: at,
        sourceDeviceId: d.id,
        soilMoisture: 99,
        temperature: double.nan,
        light: -10,
      );
      final next = SimulatedEnvironment.sample(
        d,
        at,
        previousReading: prior,
        plantContext: simulationContext,
      );
      expect(next.soilMoisture, inInclusiveRange(96.5, 100));
      expect(next.temperature, baseline.temperature);
      expect(
        next.light,
        inInclusiveRange(0, 220),
      ); // Project the old off-envelope value into the local envelope.
      expect(next.humidity, baseline.humidity);
    },
  );
  test('1000 samples per device remain bounded, gradual and non-periodic', () {
    final streams = <List<List<double?>>>[];
    var roundedEquals = 0;
    for (final id in ['alpha', 'beta', 'gamma']) {
      SensorReading? prior;
      final packets = <List<double?>>[];
      final directions = <String>{};
      for (var i = 0; i < 1000; i++) {
        final next = SimulatedEnvironment.sample(
          device(id, i),
          at,
          previousReading: prior,
          plantContext: simulationContext,
        );
        packets.add(values(next));
        for (final m in SensorMetric.values) {
          final c = SimulationConfig.metrics[m]!;
          expect(next.valueFor(m), inInclusiveRange(c.minimum, c.maximum));
          if (prior != null) {
            expect(
              (next.valueFor(m)! - prior.valueFor(m)!).abs(),
              lessThanOrEqualTo(c.maximumChange + 1 / c.scale),
            );
            if (next.valueFor(m)!.round() == prior.valueFor(m)!.round()) {
              roundedEquals++;
            }
          }
        }
        if (prior != null) {
          directions.add(
            SensorMetric.values
                .map(
                  (m) => (next.valueFor(m)! - prior!.valueFor(m)!).sign.toInt(),
                )
                .join(','),
          );
        }
        prior = next;
      }
      for (var period = 1; period <= 32; period++) {
        expect(
          List.generate(
            1000 - period,
            (i) => valuesEqual(packets[i], packets[i + period]),
          ).every((x) => x),
          isFalse,
        );
      }
      expect(directions.length, greaterThan(8));
      streams.add(packets);
    }
    expect(streams[0], isNot(streams[1]));
    expect(streams[1], isNot(streams[2]));
    expect(
      roundedEquals,
      greaterThan(0),
    ); // No forced uniqueness after display rounding.
  });
  testWidgets('separate configurable gateway delays use controllable time', (
    tester,
  ) async {
    final g = FakeSensorRepository(
      discoveryDelay: const Duration(milliseconds: 60),
      connectionDelay: const Duration(milliseconds: 35),
      acquisitionDelay: const Duration(minutes: 5),
    );
    var done = false;
    final discovery = g.discoverDevices().then((_) => done = true);
    await tester.pump(const Duration(milliseconds: 59));
    expect(done, isFalse);
    await tester.pump(const Duration(milliseconds: 1));
    await discovery;
    done = false;
    final connection = g.connect(device('d', 0)).then((_) => done = true);
    await tester.pump(const Duration(milliseconds: 34));
    expect(done, isFalse);
    await tester.pump(const Duration(milliseconds: 1));
    await connection;
    done = false;
    final read = g
        .acquire(device('d', 0), at, plantContext: simulationContext)
        .then((_) => done = true);
    await tester.pump(const Duration(minutes: 4, seconds: 59));
    expect(done, isFalse);
    await tester.pump(const Duration(seconds: 1));
    await read;
    expect(done, isTrue);
  });
  test(
    'defaults are small, shorthand remains injectable, negative delays fail',
    () {
      final g = FakeSensorRepository();
      expect(
        [g.discoveryDelay, g.connectionDelay, g.acquisitionDelay].every(
          (d) => d >= Duration.zero && d <= const Duration(milliseconds: 100),
        ),
        isTrue,
      );
      final legacy = FakeSensorRepository(
        delay: const Duration(seconds: 9),
        connectionDelay: Duration.zero,
      );
      expect(legacy.discoveryDelay, const Duration(seconds: 9));
      expect(legacy.connectionDelay, Duration.zero);
      expect(legacy.acquisitionDelay, const Duration(seconds: 9));
      expect(
        () => FakeSensorRepository(
          acquisitionDelay: const Duration(microseconds: -1),
        ),
        throwsArgumentError,
      );
    },
  );
}

bool valuesEqual(List<double?> a, List<double?> b) =>
    List.generate(a.length, (i) => a[i] == b[i]).every((x) => x);
