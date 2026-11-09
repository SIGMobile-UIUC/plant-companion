import 'package:flutter/material.dart';
import '../models/device.dart';
import '../models/plant_device_draft.dart';
import '../theme/app_theme.dart';

/// The measured collapsed card expands in normal flow; all selection is staged.
class CompanionDeviceSection extends StatelessWidget {
  const CompanionDeviceSection({
    super.key,
    required this.draft,
    this.locked = false,
  });
  final PlantDeviceDraft draft;
  final bool locked;
  Widget _action(String label, VoidCallback? action, {Key? key}) => TextButton(
    key: key,
    onPressed: locked ? null : action,
    style: TextButton.styleFrom(
      padding: EdgeInsets.zero,
      minimumSize: const Size(48, 48),
      foregroundColor: AppColors.ink,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    child: Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 30),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFD9E8D5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: AppColors.ink,
        ),
      ),
    ),
  );

  Widget _row({
    required String name,
    required String secondary,
    required String keyId,
    required bool selected,
    required bool eligible,
    VoidCallback? connect,
    bool mayReconnect = false,
  }) => Container(
    key: Key('device-row-$keyId'),
    constraints: const BoxConstraints(minHeight: 56),
    decoration: BoxDecoration(
      color: AppColors.card,
      border: Border.all(
        color: selected ? const Color(0xFF326C43) : const Color(0xFFD4DECE),
        width: selected ? 2 : 1,
      ),
      borderRadius: BorderRadius.circular(11),
    ),
    padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
    child: LayoutBuilder(
      builder: (context, c) {
        final info = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              secondary,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 12,
                color: AppColors.muted,
              ),
            ),
          ],
        );
        final busy = draft.connectingKey == keyId;
        final controls = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!selected || mayReconnect)
              _action(
                busy
                    ? 'Connecting…'
                    : draft.error != null && selected
                    ? 'Retry'
                    : 'Connect',
                busy ? null : connect,
                key: Key('connect-$keyId'),
              ),
            if (selected)
              _action('Unassign', draft.unassign, key: Key('unassign-$keyId')),
          ],
        );
        return Semantics(
          enabled: eligible,
          selected: selected,
          child: !eligible
              ? info
              : c.maxWidth < 270 ||
                    MediaQuery.textScalerOf(context).scale(1) > 1.15
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [info, const SizedBox(height: 6), controls],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: info),
                    const SizedBox(width: 8),
                    SizedBox(width: 96, child: controls),
                  ],
                ),
        );
      },
    ),
  );
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: draft,
    builder: (context, _) {
      final plant = draft.plantId == null
          ? null
          : draft.store.findPlant(draft.plantId!);
      final saved = plant == null ? null : draft.store.deviceFor(plant);
      final same =
          draft.selectedCandidateToken == null &&
          draft.selectedDeviceId != null &&
          draft.selectedDeviceId == plant?.deviceId;
      final connected = same && saved?.isConnected == true;
      final selected = draft.selectionKey != null;
      final state = selected
          ? draft.connectionRequested
                ? 'Selected for save'
                : connected
                ? 'Connected'
                : 'Disconnected'
          : 'Not connected';
      final label = draft.searching
          ? 'Searching…'
          : selected
          ? '${draft.selectedLabel} · Change Device'
          : 'Scan for nearby devices';
      final heading = Text(
        'Companion Device',
        style: AppTextStyles.heading.copyWith(fontSize: 21),
      );
      final dot = Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: connected ? const Color(0xFF29A64D) : AppColors.terracotta,
        ),
      );
      final status = Text(
        state,
        style: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 14,
          color: AppColors.muted,
        ),
      );
      Widget scan() => _action(
        label,
        draft.searching ? null : draft.scan,
        key: const Key('scan-devices-button'),
      );
      return Container(
        key: const Key('companion-device-section'),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(17),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, c) =>
                  c.maxWidth >= 354 &&
                      MediaQuery.textScalerOf(context).scale(1) <= 1.05
                  ? SizedBox(
                      height: 111,
                      child: Stack(
                        children: [
                          Positioned(
                            left: 18,
                            right: 18,
                            top: 11,
                            child: heading,
                          ),
                          Positioned(left: 19, top: 49, child: dot),
                          Positioned(
                            left: 39,
                            right: 18,
                            top: 45,
                            child: status,
                          ),
                          Positioned(
                            left: 17,
                            right: 22,
                            top: 63,
                            height: 48,
                            child: scan(),
                          ),
                        ],
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(18, 11, 18, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          heading,
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              dot,
                              const SizedBox(width: 10),
                              Expanded(child: status),
                            ],
                          ),
                          const SizedBox(height: 8),
                          scan(),
                        ],
                      ),
                    ),
            ),
            if (draft.expanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(17, 17, 22, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (draft.inventory.isEmpty && !draft.searching) ...[
                      const Text(
                        'No saved devices found.',
                        style: TextStyle(fontSize: 12, color: AppColors.muted),
                      ),
                      const SizedBox(height: 8),
                    ],
                    for (final d in draft.inventory) ...[
                      _existingRow(d),
                      const SizedBox(height: 8),
                    ],
                    for (final candidate in draft.candidates) ...[
                      _row(
                        name: candidate.label,
                        secondary:
                            draft.selectedCandidateToken == candidate.token
                            ? 'Selected for save · Not saved'
                            : 'Temporary · Not saved',
                        keyId: candidate.candidate.id,
                        selected:
                            draft.selectedCandidateToken == candidate.token,
                        eligible: true,
                        mayReconnect:
                            draft.selectedCandidateToken == candidate.token &&
                            draft.preparedKey != candidate.candidate.id,
                        connect: () => draft.connectCandidate(candidate),
                      ),
                      const SizedBox(height: 8),
                    ],
                    _action(
                      'Create simulated device',
                      draft.createCandidate,
                      key: const Key('create-device-button'),
                    ),
                    if (draft.error != null) ...[
                      const SizedBox(height: 8),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          draft.error!,
                          key: const Key('device-draft-error'),
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            color: AppColors.terracotta,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      );
    },
  );
  Widget _existingRow(Device d) {
    final owner = draft.ownerName(d.id),
        selected = draft.selectedDeviceId == d.id;
    final current = draft.store.devices.where((item) => item.id == d.id);
    final connected = current.isEmpty
        ? d.isConnected
        : current.first.isConnected;
    final secondary = owner != null
        ? 'Assigned to $owner'
        : selected
        ? draft.connectionRequested
              ? 'Selected for save'
              : 'Current device · ${connected ? 'Connected' : 'Disconnected'}'
        : 'Available · ${connected ? 'Connected' : 'Disconnected'}';
    return _row(
      name: d.name,
      secondary: secondary,
      keyId: d.id,
      selected: selected,
      eligible: owner == null,
      mayReconnect:
          selected &&
          (!connected || draft.connectionRequested) &&
          draft.preparedKey != d.id,
      connect: () => draft.connectExisting(d),
    );
  }
}
