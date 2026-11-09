import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/plant_name_config.dart';
import '../models/plant.dart';
import '../models/plant_avatar_id.dart';
import '../models/plant_commit.dart';
import '../models/plant_device_draft.dart';
import '../models/plant_form_draft.dart';
import '../models/plant_form_input.dart';
import '../models/plant_profile.dart';
import '../models/sensor_reading.dart';
import '../services/plant_preview.dart';
import '../services/plant_repository.dart';
import '../state/plant_store.dart';
import '../theme/app_theme.dart';
import '../widgets/plant_form_shell.dart';
import '../widgets/plant_form_sections.dart';
import '../widgets/companion_device_section.dart';

/// One persistent draft owns both Add and Edit. Store notifications never reset it.
class PlantFormScreen extends StatefulWidget {
  const PlantFormScreen({
    super.key,
    this.plantId,
    this.expandDevice = false,
    this.saveReturnsHome = false,
  });
  final String? plantId;
  final bool expandDevice, saveReturnsHome;
  @override
  State<PlantFormScreen> createState() => _PlantFormScreenState();
}

class _PlantFormScreenState extends State<PlantFormScreen> {
  final _scroll = ScrollController(),
      _form = GlobalKey<FormState>(),
      _deviceAnchor = GlobalKey();
  final _nickname = TextEditingController(),
      _fullName = TextEditingController(),
      _species = TextEditingController();
  final _bounds = {
    for (final m in formMetrics)
      m: [TextEditingController(), TextEditingController()],
  };
  final _focus = <String, FocusNode>{}, _anchors = <String, GlobalKey>{};
  final _previewId = 'draft:${newPlantOperationId()}';
  String _saveOperation = newPlantOperationId(),
      _deleteOperation = newPlantOperationId();
  PlantAvatarId _avatar = PlantAvatarId.pothos;
  PlantEditToken? _editToken;
  TargetRange? _originalTemperature;
  List<String>? _originalTemperatureText;
  PlantDeviceDraft? _devices;
  PreviewMood? _mood;
  PreviewConnection _connection = PreviewConnection.connected;
  bool _loaded = false,
      _loading = false,
      _submitted = false,
      _busy = false,
      _uncertain = false,
      _deleting = false,
      _conflict = false,
      _initialMissing = false;
  int _focusVersion = 0;
  Timer? _revealTimer;
  String? _operationError;
  PlantFormDraft? _pendingDraft;
  PlantCommitResult? _completed;

  Iterable<String> get _fieldOrder sync* {
    yield* ['nickname-field', 'full-name-field', 'species-field'];
    for (final m in formMetrics) {
      yield rangeFieldKey(m, 0);
      yield rangeFieldKey(m, 1);
    }
  }

  bool get _locked => _busy || _uncertain || _completed != null;
  PlantFormInput get _input => PlantFormInput(
    nickname: _nickname.text,
    fullName: _fullName.text,
    species: _species.text,
    bounds: {
      for (final m in formMetrics) m: [for (final c in _bounds[m]!) c.text],
    },
  );

  @override
  void initState() {
    super.initState();
    for (final key in _fieldOrder) {
      final node = _focus[key] = FocusNode(debugLabel: key);
      _anchors[key] = GlobalKey();
      node.addListener(() {
        if (node.hasFocus) _reveal(key);
      });
    }
    for (final c in [
      _nickname,
      _fullName,
      _species,
      ..._bounds.values.expand((v) => v),
    ]) {
      c.addListener(_changed);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    final store = context.read<PlantStore>();
    final plant = widget.plantId == null
        ? null
        : store.findPlant(widget.plantId!);
    _initialMissing = widget.plantId != null && plant == null;
    _load(plant);
    if (widget.expandDevice && !_initialMissing) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await _devices!.scan();
        if (mounted) await _showDevice();
      });
    }
  }

  void _load(Plant? plant) {
    _loading = true;
    _nickname.text = plant?.nickname ?? '';
    _fullName.text = plant?.fullName ?? '';
    _species.text = plant?.speciesName ?? '';
    _avatar = plant?.avatar ?? PlantAvatarId.pothos;
    for (final m in formMetrics) {
      final r = plant?.profile.ranges[m];
      final temperatureText = m == SensorMetric.temperature && r != null
          ? temperatureRangeInputNumbers(r)
          : null;
      for (var b = 0; b < 2; b++) {
        final value = r == null
            ? null
            : b == 0
            ? r.minimum
            : r.maximum;
        _bounds[m]![b].text = value == null
            ? ''
            : m == SensorMetric.temperature
            ? temperatureText![b]
            : inputNumber(value);
      }
    }
    _originalTemperature = plant?.profile.ranges[SensorMetric.temperature];
    _originalTemperatureText = [
      for (final c in _bounds[SensorMetric.temperature]!) c.text.trim(),
    ];
    final store = context.read<PlantStore>(),
        device = plant == null ? null : store.deviceFor(plant);
    _editToken = plant == null
        ? null
        : PlantEditToken(
            profileRevision: plant.profileRevision,
            deviceId: plant.deviceId,
            deviceRevision: device?.revision,
          );
    _devices?.dispose();
    _devices = PlantDeviceDraft(
      store,
      plantId: widget.plantId,
      deviceId: plant?.deviceId,
      expanded: widget.expandDevice,
    )..addListener(_deviceChanged);
    _mood = plant == null && widget.plantId == null
        ? PreviewMood.healthy
        : null;
    _connection = plant == null
        ? PreviewConnection.connected
        : plant.deviceId == null
        ? PreviewConnection.noDevice
        : device?.isConnected == true
        ? PreviewConnection.connected
        : PreviewConnection.disconnected;
    _submitted =
        plant != null &&
        [0, 1].any(
          (b) => _input.errors.containsKey(
            rangeFieldKey(SensorMetric.temperature, b),
          ),
        );
    if (_submitted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _form.currentState?.validate();
      });
    }
    _operationError = null;
    _conflict = false;
    _uncertain = false;
    _pendingDraft = null;
    _saveOperation = newPlantOperationId();
    _deleteOperation = newPlantOperationId();
    _loading = false;
  }

  void _changed() {
    if (mounted && !_loading) {
      setState(() {});
      if (_submitted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _form.currentState?.validate();
        });
      }
    }
  }

  void _deviceChanged() {
    if (mounted && !_loading) setState(() {});
  }

  void _reveal(String key) {
    final version = ++_focusVersion;
    _revealTimer?.cancel();
    _revealTimer = Timer(const Duration(milliseconds: 220), () {
      if (!mounted ||
          version != _focusVersion ||
          !(_focus[key]?.hasFocus ?? false)) {
        return;
      }
      final target = _anchors[key]?.currentContext;
      if (target != null && target.mounted) {
        unawaited(
          Scrollable.ensureVisible(
            target,
            alignment: .2,
            duration: const Duration(milliseconds: 160),
          ),
        );
      }
    });
  }

  Future<void> _showDevice() async {
    final target = _deviceAnchor.currentContext;
    if (target != null) {
      await Scrollable.ensureVisible(
        target,
        alignment: .05,
        duration: const Duration(milliseconds: 180),
      );
    }
  }

  void _focusInvalid(Map<String, String> errors) {
    final key = _fieldOrder.firstWhere(errors.containsKey);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focus[key]!.requestFocus();
      _reveal(key);
    });
  }

  PlantFormDraft _draft() => PlantFormDraft(
    nickname: _nickname.text,
    speciesName: _species.text,
    avatar: _avatar,
    fullName: _fullName.text.trim().isEmpty ? null : _fullName.text,
    ranges: _input.canonicalRanges(
      originalTemperature: _originalTemperature,
      originalTemperatureText: _originalTemperatureText,
    ),
    deviceId: _devices!.selectedDeviceId,
    createDevice: _devices!.createsDevice,
    connectDevice: _devices!.connectionRequested,
    editToken: _editToken,
  );

  Future<void> _save() async {
    if (_busy || _completed != null) return;
    if (!_uncertain) {
      final errors = _input.errors;
      if (errors.isNotEmpty) {
        setState(() {
          _submitted = true;
          _operationError = null;
        });
        _form.currentState!.validate();
        _focusInvalid(errors);
        return;
      }
      _pendingDraft = _draft();
      _devices!.cancelOperations();
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _operationError = null;
      _deleting = false;
    });
    final result = await context.read<PlantStore>().saveForm(
      _pendingDraft!,
      plantId: widget.plantId,
      operationId: _saveOperation,
    );
    if (!mounted) return;
    _handle(result);
  }

  Future<void> _delete() async {
    if (_busy || _completed != null || widget.plantId == null) return;
    _devices!.cancelOperations();
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _operationError = null;
      _deleting = true;
    });
    final result = await context.read<PlantStore>().deleteForm(
      widget.plantId!,
      expected: _editToken,
      operationId: _deleteOperation,
    );
    if (!mounted) return;
    _handle(result);
  }

  void _handle(PlantCommitResult result) {
    setState(() {
      _busy = false;
      if (result.committed) {
        _completed = result;
        _uncertain = false;
      } else {
        _uncertain = result.status == PlantCommitStatus.uncertain;
        _conflict = result.status == PlantCommitStatus.conflict;
        _operationError = switch (result.status) {
          PlantCommitStatus.uncertain =>
            'The result is not yet confirmed. Check the result before making changes.',
          PlantCommitStatus.conflict =>
            result.error is DeviceAssignmentConflict
                ? 'This device is now assigned to another plant. Choose an available device or reload current data.'
                : 'This plant or device changed. Your entries were kept. Reload current data before saving.',
          _ =>
            _deleting
                ? 'Could not delete. Your plant and entries were kept. Try again.'
                : result.error is PlantPersistenceFailure
                ? 'Could not save to local storage. Your entries were kept. Try again.'
                : 'Unexpected error while saving. Your entries were kept. Try again.',
        };
      }
    });
    if (result.committed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _finish();
      });
    }
  }

  void _finish() {
    final completed = _completed;
    if (completed == null) return;
    try {
      final navigator = Navigator.of(context);
      if (completed.deletion || widget.saveReturnsHome) {
        navigator.popUntil((route) => route.isFirst);
      } else {
        navigator.pop();
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _operationError = completed.deletion
              ? 'Plant deleted. Could not return to Home. Continue to leave this screen.'
              : 'Plant saved. Could not return to the previous screen. Continue to leave this screen.',
        );
      }
    }
  }

  Future<void> _reloadCurrent() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final store = context.read<PlantStore>();
      await store.reload();
      if (!mounted) return;
      final current = widget.plantId == null
          ? null
          : store.findPlant(widget.plantId!);
      if (widget.plantId != null && current == null) {
        Navigator.of(context).popUntil((r) => r.isFirst);
        return;
      }
      setState(() {
        _load(current);
        _busy = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _operationError =
              'Could not reload current data. Your entries were kept.';
        });
      }
    }
  }

  Widget _textField(
    String label,
    String key,
    TextEditingController controller,
    String hint, {
    bool last = false,
  }) => Padding(
    padding: const EdgeInsets.only(top: 14, left: 1, right: 1),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.heading.copyWith(fontSize: 14)),
        const SizedBox(height: 10),
        KeyedSubtree(
          key: _anchors[key],
          child: Semantics(
            label: label,
            child: TextFormField(
              key: Key(key),
              controller: controller,
              focusNode: _focus[key],
              enabled: !_locked,
              style: AppTextStyles.body.copyWith(
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
              scrollPadding: const EdgeInsets.only(top: 20, bottom: 120),
              decoration: plantFormDecoration(hint: hint),
              autovalidateMode: _submitted
                  ? AutovalidateMode.onUserInteraction
                  : AutovalidateMode.disabled,
              validator: (_) => _submitted ? _input.errors[key] : null,
              onFieldSubmitted: (_) =>
                  _focus[last
                          ? rangeFieldKey(formMetrics.first, 0)
                          : key == 'nickname-field'
                          ? 'full-name-field'
                          : 'species-field']!
                      .requestFocus(),
            ),
          ),
        ),
        if (key == 'nickname-field' &&
            PlantNameConfig.warnsForNickname(controller.text.trim()))
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Long names may be shortened on plant cards.',
              key: const Key('nickname-warning'),
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
  Widget _bound(SensorMetric metric, int bound) {
    final key = rangeFieldKey(metric, bound),
        hint = displayHint(_avatar, metric);
    final value = bound == 0 ? hint.minimum : hint.maximum;
    return KeyedSubtree(
      key: _anchors[key],
      child: Semantics(
        label:
            '${metric.label} ${bound == 0 ? 'minimum' : 'maximum'} ${metric == SensorMetric.temperature
                ? 'degrees Fahrenheit'
                : metric == SensorMetric.light
                ? 'lux'
                : 'percent'}',
        child: TextFormField(
          key: Key(key),
          controller: _bounds[metric]![bound],
          focusNode: _focus[key],
          enabled: !_locked,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 14,
            fontWeight: FontWeight.w500,
            height: 1.2,
          ),
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          textInputAction: key == rangeFieldKey(formMetrics.last, 1)
              ? TextInputAction.done
              : TextInputAction.next,
          scrollPadding: const EdgeInsets.only(top: 20, bottom: 120),
          decoration: plantFormDecoration(
            compact: true,
            prefix: bound == 0 ? 'MIN  ' : 'MAX  ',
            suffix: metric == SensorMetric.temperature
                ? '°F'
                : metric == SensorMetric.light
                ? 'lux'
                : '%',
            hint: metric == SensorMetric.temperature
                ? temperatureInputNumber(value)
                : inputNumber(value),
          ),
          autovalidateMode: _submitted
              ? AutovalidateMode.onUserInteraction
              : AutovalidateMode.disabled,
          validator: (_) => _submitted ? _input.errors[key] : null,
          onFieldSubmitted: (_) {
            final order = _fieldOrder.toList(), index = order.indexOf(key);
            if (index + 1 < order.length) {
              _focus[order[index + 1]]!.requestFocus();
            } else {
              FocusScope.of(context).unfocus();
            }
          },
        ),
      ),
    );
  }

  Widget _button(
    String text,
    VoidCallback? action, {
    required Key key,
    Color color = AppColors.forest,
  }) => TextButton(
    key: key,
    onPressed: action,
    style: TextButton.styleFrom(
      backgroundColor: color,
      disabledBackgroundColor: color,
      foregroundColor: Colors.white,
      disabledForegroundColor: Colors.white70,
      minimumSize: const Size(48, 61),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
    ),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: AppTextStyles.heading.copyWith(fontSize: 25, color: Colors.white),
    ),
  );
  Widget _actions() {
    if (_completed != null) {
      return SizedBox(
        width: double.infinity,
        child: _button(
          'Continue',
          _finish,
          key: const Key('finish-committed-operation'),
        ),
      );
    }
    if (_uncertain) {
      return SizedBox(
        width: double.infinity,
        child: _button(
          _deleting ? 'Check Delete Result' : 'Check Save Result',
          _busy
              ? null
              : _deleting
              ? _delete
              : _save,
          key: const Key('check-commit-result'),
        ),
      );
    }
    if (widget.plantId == null) {
      return SizedBox(
        width: double.infinity,
        child: _button(
          _busy ? 'Saving…' : 'Save Plant  ✓',
          _busy ? null : _save,
          key: const Key('save-plant-button'),
        ),
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _button(
              _busy && _deleting ? 'Deleting…' : 'Delete ×',
              _busy ? null : _delete,
              key: const Key('delete-plant-button'),
              color: AppColors.delete,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _button(
              _busy && !_deleting ? 'Saving…' : 'Save ✓',
              _busy ? null : _save,
              key: const Key('save-changes-button'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<PlantStore>();
    if (_initialMissing) {
      return PlantFormShell(
        title: 'Edit Plant',
        controller: _scroll,
        child: const Text(
          'This plant no longer exists.',
          style: TextStyle(color: AppColors.terracotta),
        ),
      );
    }
    final actual = widget.plantId == null
        ? null
        : store.findPlant(widget.plantId!);
    final ranges = _input.previewRanges(
      _avatar,
      originalTemperature: _originalTemperature,
      originalTemperatureText: _originalTemperatureText,
    );
    final preview = PlantPreviewData(
      id: widget.plantId ?? _previewId,
      nickname: _nickname.text,
      species: _species.text,
      avatar: _avatar,
      ranges: ranges,
      connection: _connection,
      override: _mood,
      actual: actual,
    );
    final errors = _input.errors;
    final summary = _submitted && errors.isNotEmpty
        ? _input.missing
              ? 'Please fill in all required fields.'
              : 'Please correct the highlighted fields.'
        : null;
    return PlantFormShell(
      title: widget.plantId == null ? 'Add a Plant' : 'Edit Plant',
      controller: _scroll,
      locked: _busy || _uncertain,
      onUserScroll: () {
        _focusVersion++;
        _revealTimer?.cancel();
      },
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 1),
              child: Text(
                'Meet your new companion',
                style: AppTextStyles.heading,
              ),
            ),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 1),
              child: Text(
                'Choose a plant and give it a name.',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  color: AppColors.muted,
                ),
              ),
            ),
            const SizedBox(height: 13),
            _textField('Nickname', 'nickname-field', _nickname, 'My Pothos'),
            _textField(
              'Full Name (optional)',
              'full-name-field',
              _fullName,
              '',
            ),
            _textField(
              'Scientific Name',
              'species-field',
              _species,
              scientificHint(_avatar),
              last: true,
            ),
            const SizedBox(height: 16),
            Text(
              'Choose an avatar',
              style: AppTextStyles.heading.copyWith(fontSize: 15),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: PlantAvatarSelector(
                value: _avatar,
                onChanged: _locked ? null : (a) => setState(() => _avatar = a),
              ),
            ),
            const SizedBox(height: 26),
            const Text('Preview your companion', style: AppTextStyles.heading),
            const SizedBox(height: 14),
            LargeMoodPreview(
              data: preview,
              avatar: _avatar,
              nickname: _nickname.text,
              species: _species.text,
              onChanged: _locked
                  ? null
                  : (m) {
                      if (m != null) setState(() => _mood = m);
                    },
            ),
            const SizedBox(height: 20),
            HomepagePlantPreview(
              data: preview,
              connection: _connection,
              onChanged: _locked
                  ? null
                  : (c) {
                      if (c != null) setState(() => _connection = c);
                    },
            ),
            const SizedBox(height: 34),
            const Text('Ideal care ranges', style: AppTextStyles.heading),
            const SizedBox(height: 8),
            const Text(
              'Set minimum and maximum readings for your plant.',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 12,
                color: Color(0xFF667A6A),
              ),
            ),
            const SizedBox(height: 26),
            for (final m in formMetrics) ...[
              PlantCareRangeCard(
                metric: m,
                minimum: _bound(m, 0),
                maximum: _bound(m, 1),
              ),
              if (m != formMetrics.last) const SizedBox(height: 12),
            ],
            const SizedBox(height: 36),
            const Text('Finish connecting', style: AppTextStyles.heading),
            const SizedBox(height: 8),
            const Text(
              'Connect a companion device now, or set it up later.',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 12,
                color: Color(0xFF667B6C),
              ),
            ),
            const SizedBox(height: 20),
            KeyedSubtree(
              key: _deviceAnchor,
              child: CompanionDeviceSection(draft: _devices!, locked: _locked),
            ),
            const SizedBox(height: 20),
            if (_operationError != null) ...[
              Semantics(
                liveRegion: true,
                child: Text(
                  _operationError!,
                  key: const Key('form-operation-error'),
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    color: AppColors.terracotta,
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (_conflict) ...[
              TextButton(
                key: const Key('reload-current-data'),
                onPressed: _busy ? null : _reloadCurrent,
                child: const Text('Reload Current Data'),
              ),
              const SizedBox(height: 8),
            ],
            if (summary != null) ...[
              Semantics(
                liveRegion: true,
                child: Text(
                  summary,
                  key: const Key('form-validation-summary'),
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    color: AppColors.terracotta,
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            _actions(),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _focusVersion++;
    _revealTimer?.cancel();
    _devices?.dispose();
    _scroll.dispose();
    for (final c in [
      _nickname,
      _fullName,
      _species,
      ..._bounds.values.expand((v) => v),
    ]) {
      c.dispose();
    }
    for (final node in _focus.values) {
      node.dispose();
    }
    super.dispose();
  }
}
