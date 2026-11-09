import 'package:flutter/material.dart';
import '../models/device.dart';
import '../theme/app_theme.dart';

class DetailsDeviceCard extends StatelessWidget {
  const DetailsDeviceCard({super.key, required this.device, this.onChange});
  final Device? device;
  final VoidCallback? onChange;
  @override
  Widget build(BuildContext context) {
    final connected = device?.isConnected == true;
    final status = connected ? 'Connected' : 'Disconnected';
    final label = device == null
        ? 'No device assigned · Change Device'
        : '${device!.name} · Change Device';
    final color = connected ? const Color(0xFF29A64D) : AppColors.terracotta;
    Widget dot() => Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
    final heading = Text(
      'Companion Device',
      style: AppTextStyles.heading.copyWith(fontSize: 21),
    );
    final state = Text(
      status,
      style: const TextStyle(
        fontFamily: 'Inter',
        fontSize: 14,
        color: AppColors.muted,
      ),
    );
    Widget action() => Semantics(
      button: true,
      enabled: onChange != null,
      label: label,
      child: ExcludeSemantics(
        child: TextButton(
          onPressed: onChange,
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size(48, 48),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Container(
            constraints: const BoxConstraints(minHeight: 30),
            decoration: BoxDecoration(
              color: const Color(0xFFD9E8D5),
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.fromLTRB(24, 4, 12, 4),
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w500,
                fontSize: 13,
                color: AppColors.ink,
              ),
            ),
          ),
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final normal =
            constraints.maxWidth >= 354 &&
            MediaQuery.textScalerOf(context).scale(1) <= 1.05;
        return Container(
          key: const Key('details-device'),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(17),
          ),
          child: normal
              ? SizedBox(
                  height: 111,
                  child: Stack(
                    children: [
                      Positioned(left: 18, right: 18, top: 11, child: heading),
                      Positioned(left: 19, top: 49, child: dot()),
                      Positioned(left: 39, right: 18, top: 45, child: state),
                      Positioned(
                        left: 17,
                        right: 22,
                        top: 63,
                        height: 48,
                        child: action(),
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
                          dot(),
                          const SizedBox(width: 10),
                          Expanded(child: state),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(width: double.infinity, child: action()),
                    ],
                  ),
                ),
        );
      },
    );
  }
}
