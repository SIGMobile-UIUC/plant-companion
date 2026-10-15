import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/device.dart';
import '../models/plant_profile.dart';
import '../models/sensor_reading.dart';
import '../state/plant_store.dart';
import '../theme/app_theme.dart';
import '../widgets/page_body.dart';
import '../widgets/status_badge.dart';

enum _SetupPhase { idle, searching, found, connecting, connected, failed }

class AddPlantScreen extends StatefulWidget {
  const AddPlantScreen({super.key});

  @override
  State<AddPlantScreen> createState() => _AddPlantScreenState();
}

class _AddPlantScreenState extends State<AddPlantScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nickname = TextEditingController();
  final _customType = TextEditingController();
  final Map<SensorMetric, List<TextEditingController>> _rangeFields = {
    for (final metric in SensorMetric.values)
      metric: [
        TextEditingController(
          text: metric.format(
            PlantProfile.demonstrationRanges[metric]!.minimum,
          ),
        ),
        TextEditingController(
          text: metric.format(
            PlantProfile.demonstrationRanges[metric]!.maximum,
          ),
        ),
      ],
  };

  PlantProfile? _profile;
  Device? _discoveredDevice;
  Device? _selectedDevice;
  _SetupPhase _phase = _SetupPhase.idle;
  bool _failNextConnection = false;
  bool _saving = false;
  String? _saveError;

  bool get _busy =>
      _phase == _SetupPhase.searching || _phase == _SetupPhase.connecting;

  @override
  void dispose() {
    _nickname.dispose();
    _customType.dispose();
    for (final fields in _rangeFields.values) {
      for (final field in fields) {
        field.dispose();
      }
    }
    super.dispose();
  }

  Future<void> _search() async {
    final repository = context.read<PlantStore>().repository;
    setState(() {
      _phase = _SetupPhase.searching;
      _selectedDevice = null;
    });
    final devices = await repository.discoverDevices();
    if (!mounted) return;
    setState(() {
      _discoveredDevice = devices.first;
      _phase = _SetupPhase.found;
    });
  }

  Future<void> _connect() async {
    final store = context.read<PlantStore>();
    if (_discoveredDevice == null ||
        store.ownerOfDevice(_discoveredDevice!.id) != null) {
      return;
    }
    final shouldFail = _failNextConnection;
    setState(() {
      _phase = _SetupPhase.connecting;
      _failNextConnection = false;
      _selectedDevice = null;
    });
    try {
      final device = await store.repository.connect(
        _discoveredDevice!,
        simulateFailure: shouldFail,
      );
      if (!mounted) return;
      setState(() {
        _selectedDevice = device;
        _phase = _SetupPhase.connected;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _phase = _SetupPhase.failed;
      });
    }
  }

  String? _validateBound(SensorMetric metric, int bound, String? input) {
    final value = double.tryParse(input?.trim() ?? '');
    if (value == null || !value.isFinite) return 'Enter a number.';
    if ((metric == SensorMetric.soilMoisture ||
            metric == SensorMetric.humidity) &&
        (value < 0 || value > 100)) {
      return 'Use 0 to 100.';
    }
    if (metric == SensorMetric.light && value < 0) return 'Use zero or more.';
    if (metric == SensorMetric.temperature && (value < -50 || value > 100)) {
      return 'Use −50 to 100 °C.';
    }
    if (bound == 1) {
      final minimum = double.tryParse(_rangeFields[metric]!.first.text.trim());
      if (minimum != null && value <= minimum) return 'Must exceed minimum.';
    }
    return null;
  }

  void _save() {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) {
      // Bring the first required fields back into view on a long scrolling form.
      Scrollable.ensureVisible(
        _formKey.currentContext!,
        duration: const Duration(milliseconds: 250),
      );
      return;
    }
    final profile = _profile!.id == 'custom'
        ? PlantProfile(
            id: 'custom',
            plantType: _customType.text.trim(),
            ranges: {
              for (final metric in SensorMetric.values)
                metric: TargetRange(
                  double.parse(_rangeFields[metric]![0].text.trim()),
                  double.parse(_rangeFields[metric]![1].text.trim()),
                ),
            },
          )
        : _profile!;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      context.read<PlantStore>().addPlant(
        nickname: _nickname.text,
        profile: profile,
        device: _selectedDevice,
      );
      Navigator.pop(context);
    } catch (_) {
      setState(() {
        _saving = false;
        _saveError =
            'This device was just assigned to another plant. Remove the link and save without a device.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<PlantStore>();
    final owner = _discoveredDevice == null
        ? null
        : store.ownerOfDevice(_discoveredDevice!.id);
    return Scaffold(
      appBar: AppBar(title: const Text('Add Plant')),
      body: PageBody(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'MAKE ROOM FOR SOMETHING GREEN',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.muted,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Meet your new\nroommate.',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 12),
              const Text(
                'Start with a name. Add a little helper if you have one.',
                style: TextStyle(color: AppColors.muted, fontSize: 16),
              ),
              const SizedBox(height: 28),
              Text(
                '01  /  The plant',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('nickname-field'),
                controller: _nickname,
                maxLength: 40,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Plant nickname',
                  hintText: 'e.g. Fernanda',
                  helperText: 'Something you’ll love saying.',
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Give your plant a nickname.'
                    : null,
              ),
              const SizedBox(height: 18),
              DropdownButtonFormField<PlantProfile>(
                key: const Key('plant-type-field'),
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Plant type',
                  hintText: 'Choose a demo profile',
                ),
                items: [
                  for (final profile in PlantProfile.samples)
                    DropdownMenuItem(
                      value: profile,
                      child: Text(profile.plantType),
                    ),
                ],
                onChanged: (profile) => setState(() {
                  _profile = profile;
                }),
                validator: (value) =>
                    value == null ? 'Choose a plant type.' : null,
              ),
              const SizedBox(height: 12),
              const Text(
                'Profiles share sample demo ranges. They are not scientifically authoritative plant-care recommendations. Choose Custom to set your own ranges.',
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
              if (_profile?.id == 'custom') ...[
                const SizedBox(height: 18),
                TextFormField(
                  key: const Key('custom-type-field'),
                  controller: _customType,
                  maxLength: 40,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Custom plant type',
                    hintText: 'e.g. My mystery plant',
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Enter your custom plant type.'
                      : null,
                ),
                const SizedBox(height: 12),
                Text(
                  'Your demo target ranges',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                for (final metric in SensorMetric.values) ...[
                  const SizedBox(height: 16),
                  Text('${metric.label} · ${metric.unit}'),
                  const SizedBox(height: 8),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final fields = [
                        for (var bound = 0; bound < 2; bound++)
                          TextFormField(
                            key: Key('range-${metric.name}-$bound'),
                            controller: _rangeFields[metric]![bound],
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                              signed: true,
                            ),
                            decoration: InputDecoration(
                              labelText: bound == 0 ? 'Minimum' : 'Maximum',
                            ),
                            validator: (value) =>
                                _validateBound(metric, bound, value),
                          ),
                      ];
                      if (constraints.maxWidth < 300 ||
                          MediaQuery.textScalerOf(context).scale(1) > 1.3) {
                        return Column(
                          children: [
                            fields[0],
                            const SizedBox(height: 12),
                            fields[1],
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: fields[0]),
                          const SizedBox(width: 12),
                          Expanded(child: fields[1]),
                        ],
                      );
                    },
                  ),
                ],
              ],
              const SizedBox(height: 32),
              Text(
                '02  /  The little helper',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                'Optional · one simulated ESP32 is available. You can always save without a device.',
                style: TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const StatusBadge(
                        label: 'Simulated device setup',
                        icon: Icons.science_outlined,
                      ),
                      const SizedBox(height: 16),
                      if (_phase == _SetupPhase.idle) ...[
                        const Text(
                          'Find your plant’s companion',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'This search uses mock devices. Bluetooth permissions are not needed for the demo.',
                          style: TextStyle(color: AppColors.muted),
                        ),
                      ],
                      if (_busy) ...[
                        const LinearProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(
                          _phase == _SetupPhase.searching
                              ? 'Searching for a simulated ESP32…'
                              : 'Connecting to simulated ESP32…',
                          key: const Key('setup-progress'),
                        ),
                      ],
                      if (_discoveredDevice != null &&
                          _phase != _SetupPhase.searching) ...[
                        const SizedBox(height: 8),
                        Text(
                          _discoveredDevice!.name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        if (owner != null) ...[
                          const StatusBadge(
                            label: 'Already assigned',
                            icon: Icons.link,
                            attention: true,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Linked to ${owner.nickname}. Each device can belong to only one plant. Save this plant without a device, or unlink it from ${owner.nickname}’s details first.',
                          ),
                        ] else if (_phase == _SetupPhase.connected) ...[
                          const StatusBadge(
                            label: 'Connected · simulated',
                            icon: Icons.bluetooth_connected,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Ready to link when you save. Refresh in Plant Details to get the first reading.',
                          ),
                          TextButton.icon(
                            onPressed: () => setState(() {
                              _selectedDevice = null;
                              _phase = _SetupPhase.found;
                            }),
                            icon: const Icon(Icons.link_off),
                            label: const Text('Save without this device'),
                          ),
                        ] else if (_phase == _SetupPhase.failed) ...[
                          const StatusBadge(
                            label: 'Connection failed',
                            icon: Icons.error_outline,
                            attention: true,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'The simulated connection failed. Retry, or save your plant without a device.',
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            key: const Key('retry-connection'),
                            onPressed: _connect,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Retry'),
                          ),
                        ] else if (_phase == _SetupPhase.found) ...[
                          const Text(
                            'Found nearby · simulated',
                            style: TextStyle(color: AppColors.muted),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            key: const Key('connect-device'),
                            onPressed: _connect,
                            icon: const Icon(Icons.bluetooth),
                            label: const Text('Connect device'),
                          ),
                        ],
                        if (owner == null &&
                            !_busy &&
                            _phase != _SetupPhase.connected)
                          SwitchListTile.adaptive(
                            key: const Key('fail-next-connection'),
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Fail next connection'),
                            subtitle: const Text(
                              'Demo control · Retry will succeed.',
                            ),
                            value: _failNextConnection,
                            onChanged: (value) => setState(() {
                              _failNextConnection = value;
                            }),
                          ),
                      ],
                      if (!_busy &&
                          _phase != _SetupPhase.connected &&
                          _phase != _SetupPhase.failed) ...[
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          key: const Key('search-device'),
                          onPressed: _search,
                          icon: const Icon(Icons.search),
                          label: Text(
                            _phase == _SetupPhase.idle
                                ? 'Search for device'
                                : 'Search again',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              if (_saveError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    _saveError!,
                    style: const TextStyle(color: AppColors.terracotta),
                  ),
                ),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const Key('save-plant-button'),
                  onPressed: _busy || _saving ? null : _save,
                  icon: const Icon(Icons.check),
                  label: Text(
                    _selectedDevice == null
                        ? 'Save Plant · without device'
                        : 'Save Plant',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Plants and readings are kept in memory. Restarting the app resets this demo.',
                style: TextStyle(color: AppColors.muted, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
