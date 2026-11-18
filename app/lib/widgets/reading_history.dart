import 'package:flutter/material.dart';
import '../models/sensor_reading.dart';
import '../theme/app_theme.dart';
import '../utils/sensor_units.dart';

/// Loaded only when expanded; the normal plant reload still fetches one packet.
class ReadingHistory extends StatefulWidget {
  const ReadingHistory({
    super.key,
    required this.plantId,
    required this.packetId,
    required this.load,
  });
  final String plantId;
  final String? packetId;
  final Future<List<SensorReading>> Function(String) load;
  @override
  State<ReadingHistory> createState() => _ReadingHistoryState();
}

class _ReadingHistoryState extends State<ReadingHistory> {
  Future<List<SensorReading>>? _history;
  @override
  void didUpdateWidget(ReadingHistory old) {
    super.didUpdateWidget(old);
    if (_history != null &&
        (old.packetId != widget.packetId || old.plantId != widget.plantId)) {
      _history = widget.load(widget.plantId);
    }
  }

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.card,
    borderRadius: BorderRadius.circular(17),
    clipBehavior: Clip.antiAlias,
    child: ExpansionTile(
      title: const Text(
        'Reading history',
        style: TextStyle(fontFamily: 'Inter', fontSize: 16),
      ),
      onExpansionChanged: (open) {
        if (open) setState(() => _history = widget.load(widget.plantId));
      },
      children: [
        FutureBuilder<List<SensorReading>>(
          future: _history,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Could not load history. Close and reopen to retry.',
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.all(12),
                child: Text('Loading saved readings…'),
              );
            }
            final rows = snapshot.data!;
            return Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${rows.length} saved readings · Showing latest ${rows.length.clamp(0, 20)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  for (final r in rows.take(20))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        '${r.origin.startsWith('ble_') ? 'Physical BLE #${r.sequence} · ${r.origin.substring(4)}' : 'Simulated · ${r.origin}'}\n'
                        '${r.measuredAt?.toLocal().toString() ?? 'Measurement time unknown'}${r.timeQuality == 'phone_anchored' ? ' (phone anchored)' : ''}\n'
                        'Soil ${r.soilMoisture?.toStringAsFixed(0) ?? '—'}% · ${r.temperature == null ? '—' : celsiusToFahrenheit(r.temperature!).toStringAsFixed(1)}°F · '
                        '${r.humidity?.toStringAsFixed(0) ?? '—'}% RH · ${r.light?.toStringAsFixed(0) ?? '—'} lux',
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          color: AppColors.muted,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ],
    ),
  );
}
