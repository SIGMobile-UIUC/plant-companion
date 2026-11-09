import 'package:flutter/material.dart';
import '../models/plant_avatar_id.dart';
import '../models/plant_form_input.dart';
import '../models/sensor_reading.dart';
import '../services/plant_preview.dart';
import '../theme/app_theme.dart';
import 'companion_header.dart';
import 'plant_portrait.dart';
import 'plant_card.dart';

InputDecoration plantFormDecoration({
  String? hint,
  String? prefix,
  String? suffix,
  bool compact = false,
}) {
  OutlineInputBorder border(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(compact ? 11 : 12),
    borderSide: BorderSide(color: color),
  );
  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: Color(0xFF7D8578)),
    prefixIcon: prefix == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(left: 12, right: 5),
            child: Text(
              prefix.trim(),
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
    prefixIconConstraints: const BoxConstraints(minWidth: 48, minHeight: 0),
    suffixIcon: suffix == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(right: 12, left: 4),
            child: Text(
              suffix,
              style: const TextStyle(fontFamily: 'Inter', fontSize: 13),
            ),
          ),
    suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
    isDense: true,
    filled: true,
    fillColor: Colors.white,
    contentPadding: EdgeInsets.symmetric(
      horizontal: compact ? 12 : 14,
      vertical: compact ? 10 : 13,
    ),
    constraints: BoxConstraints(minHeight: compact ? 39 : 48),
    border: border(AppColors.border),
    enabledBorder: border(compact ? const Color(0xFFD4DECE) : AppColors.border),
    focusedBorder: border(const Color(0xFF326C43)),
    disabledBorder: border(AppColors.border),
    errorBorder: border(AppColors.terracotta),
    focusedErrorBorder: border(AppColors.terracotta),
    errorMaxLines: 3,
    errorStyle: const TextStyle(
      fontFamily: 'Inter',
      fontSize: 12,
      color: AppColors.terracotta,
    ),
  );
}

class PlantAvatarSelector extends StatelessWidget {
  const PlantAvatarSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final PlantAvatarId value;
  final ValueChanged<PlantAvatarId>? onChanged;
  @override
  Widget build(BuildContext context) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, avatar) in PlantAvatarId.values.indexed) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(
            child: Semantics(
              selected: value == avatar,
              button: true,
              label: avatarLabel(avatar),
              child: TextButton(
                key: Key('avatar-${avatar.name}'),
                onPressed: onChanged == null ? null : () => onChanged!(avatar),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(48, 111),
                  backgroundColor: value == avatar
                      ? const Color(0xFFE1EBCF)
                      : const Color(0xFFF9F7ED),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(17),
                    side: BorderSide(
                      color: value == avatar
                          ? const Color(0xFF326C43)
                          : const Color(0xFFD0D7C5),
                      width: value == avatar ? 2 : 1,
                    ),
                  ),
                ),
                child: ExcludeSemantics(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 2),
                      Image.asset(
                        avatar.assetPath,
                        width: 79,
                        height: 81,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.none,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 3,
                          vertical: 6,
                        ),
                        child: Text(
                          avatarLabel(avatar),
                          textAlign: TextAlign.center,
                          style: AppTextStyles.heading.copyWith(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

class LargeMoodPreview extends StatelessWidget {
  const LargeMoodPreview({
    super.key,
    required this.data,
    required this.avatar,
    required this.nickname,
    required this.species,
    required this.onChanged,
  });
  final PlantPreviewData data;
  final PlantAvatarId avatar;
  final String nickname, species;
  final ValueChanged<PreviewMood?>? onChanged;
  Widget _selector() => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(11),
      border: Border.all(color: const Color(0xFFD5DED0)),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 9),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<PreviewMood>(
        key: const Key('mood-selector'),
        value: data.mood,
        isDense: true,
        isExpanded: true,
        focusColor: Colors.transparent,
        hint: Text(
          'Choose a preview',
          style: AppTextStyles.heading.copyWith(fontSize: 13),
        ),
        icon: Text('⌄', style: AppTextStyles.heading.copyWith(fontSize: 21)),
        itemHeight: null,
        selectedItemBuilder: (context) => [
          for (final m in PreviewMood.values)
            Align(
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  Image.asset(
                    '$companionAssets${m == PreviewMood.healthy
                        ? 'faces/happy.png'
                        : m == PreviewMood.sleeping || m == PreviewMood.lightBelow
                        ? 'faces/sleeping.png'
                        : 'faces/sad.png'}',
                    width: 40,
                    height: 16,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.none,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      m.label,
                      maxLines: 2,
                      style: AppTextStyles.heading.copyWith(
                        fontSize:
                            m == PreviewMood.healthy ||
                                m == PreviewMood.sleeping
                            ? 18
                            : 12,
                        color: const Color(0xFF1F6943),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
        items: [
          for (final m in PreviewMood.values)
            DropdownMenuItem(
              value: m,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  m.label,
                  style: AppTextStyles.heading.copyWith(fontSize: 15),
                ),
              ),
            ),
        ],
        onChanged: onChanged,
      ),
    ),
  );
  Widget _portrait() => PlantPortrait(
    key: const Key('large-form-portrait'),
    avatar: avatar,
    appearance: data.largeAppearance,
  );
  Widget _name() => Text(
    nickname.trim().isEmpty ? 'This plant' : nickname.trim(),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    textAlign: TextAlign.center,
    style: AppTextStyles.heading.copyWith(
      fontSize: 15,
      color: const Color(0xFF194632),
    ),
  );
  Widget _species() => Text(
    species.trim(),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    textAlign: TextAlign.center,
    style: const TextStyle(
      fontFamily: 'Inter',
      fontSize: 10,
      color: Color(0xFF708271),
    ),
  );
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      const copy = TextStyle(
        fontFamily: 'Inter',
        fontSize: 13,
        color: Color(0xFF657B69),
      );
      final text = TextPainter(
        text: TextSpan(text: data.explanation, style: copy),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(maxWidth: 165);
      final normal =
          c.maxWidth >= 354 &&
          MediaQuery.textScalerOf(context).scale(1) <= 1.05 &&
          text.height <= 69;
      text.dispose();
      return Container(
        key: const Key('large-mood-preview'),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFD8E4D1)),
        ),
        child: normal
            ? SizedBox(
                height: 273,
                child: Stack(
                  children: [
                    Positioned(
                      left: 15,
                      top: 19,
                      width: 177,
                      child: Text(
                        'Companion mood',
                        style: AppTextStyles.heading.copyWith(
                          fontSize: 18,
                          color: const Color(0xFF1E4936),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 15,
                      top: 56,
                      width: 175,
                      height: 48,
                      child: _selector(),
                    ),
                    Positioned(
                      left: 17,
                      top: 130,
                      width: 165,
                      child: Text(
                        data.explanation,
                        key: const Key('mood-explanation'),
                        style: copy,
                      ),
                    ),
                    const Positioned(
                      left: 17,
                      top: 200,
                      width: 164,
                      height: 1,
                      child: ColoredBox(color: Color(0xFFDCE5D4)),
                    ),
                    // The old annotation's 211px slot deliberately remains blank.
                    Positioned(right: 23, top: 15, child: _portrait()),
                    Positioned(right: 12, top: 230, width: 171, child: _name()),
                    Positioned(
                      right: 12,
                      top: 252,
                      width: 171,
                      child: _species(),
                    ),
                  ],
                ),
              )
            : Padding(
                padding: const EdgeInsets.all(15),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Companion mood',
                      style: AppTextStyles.heading.copyWith(fontSize: 18),
                    ),
                    const SizedBox(height: 14),
                    ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 48),
                      child: _selector(),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      data.explanation,
                      key: const Key('mood-explanation'),
                      style: copy,
                    ),
                    const SizedBox(height: 20),
                    const Divider(height: 1, color: Color(0xFFDCE5D4)),
                    const SizedBox(height: 24),
                    Center(child: _portrait()),
                    const SizedBox(height: 10),
                    Center(child: _name()),
                    const SizedBox(height: 4),
                    Center(child: _species()),
                  ],
                ),
              ),
      );
    },
  );
}

class HomepagePlantPreview extends StatelessWidget {
  const HomepagePlantPreview({
    super.key,
    required this.data,
    required this.connection,
    required this.onChanged,
  });
  final PlantPreviewData data;
  final PreviewConnection connection;
  final ValueChanged<PreviewConnection?>? onChanged;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Homepage card preview',
        style: AppTextStyles.heading.copyWith(fontSize: 18),
      ),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFD9E8D5),
          borderRadius: BorderRadius.circular(11),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<PreviewConnection>(
            key: const Key('preview-connection'),
            value: connection,
            isExpanded: true,
            focusColor: Colors.transparent,
            itemHeight: null,
            items: [
              for (final value in PreviewConnection.values)
                DropdownMenuItem(
                  value: value,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(switch (value) {
                      PreviewConnection.connected => 'Connected preview',
                      PreviewConnection.disconnected => 'Disconnected preview',
                      PreviewConnection.noDevice => 'No Device preview',
                    }, style: AppTextStyles.body.copyWith(fontSize: 13)),
                  ),
                ),
            ],
            onChanged: onChanged,
          ),
        ),
      ),
      const SizedBox(height: 12),
      Semantics(
        container: true,
        label: 'Homepage card preview. Demonstration only.',
        child: PlantCard(
          key: const Key('homepage-card-preview'),
          plant: data.cardPlant,
          device: data.cardDevice,
          now: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          onAction: null,
          preview: true,
          appearanceOverride: data.cardAppearance,
        ),
      ),
    ],
  );
}

class PlantCareRangeCard extends StatelessWidget {
  const PlantCareRangeCard({
    super.key,
    required this.metric,
    required this.minimum,
    required this.maximum,
  });
  final SensorMetric metric;
  final Widget minimum, maximum;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final stacked =
          c.maxWidth < 330 || MediaQuery.textScalerOf(context).scale(1) > 1.15;
      return Container(
        key: Key('care-${metric.name}'),
        constraints: const BoxConstraints(minHeight: 128),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(18),
        ),
        padding: const EdgeInsets.fromLTRB(13, 15, 17, 13),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Image.asset(
                  '$companionAssets${sensorAsset(metric)}',
                  width: 42,
                  height: 42,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.none,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        metric == SensorMetric.soilMoisture
                            ? 'Soil Moisture'
                            : metric.label,
                        style: AppTextStyles.heading.copyWith(fontSize: 20),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Measured in ${metric == SensorMetric.temperature
                            ? '°F'
                            : metric == SensorMetric.light
                            ? 'lux'
                            : '%'}',
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 19),
            Padding(
              padding: const EdgeInsets.only(left: 1),
              child: stacked
                  ? Column(
                      children: [minimum, const SizedBox(height: 12), maximum],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: minimum),
                        const SizedBox(width: 23),
                        Expanded(child: maximum),
                      ],
                    ),
            ),
          ],
        ),
      );
    },
  );
}
