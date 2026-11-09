import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/plant_commit.dart';
import '../state/plant_store.dart';
import '../theme/app_theme.dart';

/// Failure-only feedback after durable operations; never offers destructive retry.
class PlantOperationNotice extends StatelessWidget {
  const PlantOperationNotice({super.key, this.plantId});
  final String? plantId;
  @override
  Widget build(BuildContext context) {
    final store = context.watch<PlantStore>(), notice = store.operationNotice;
    if (notice == null || (plantId != null && notice.plantId != plantId)) {
      return const SizedBox.shrink();
    }
    final prefix = notice.deletion ? 'Plant deleted.' : 'Plant saved.';
    final detail = switch (notice.issue) {
      PlantPostCommitIssue.connection =>
        'Could not connect the sensor. Use Refresh in Details to retry.',
      PlantPostCommitIssue.acquisition =>
        'Could not acquire readings. Use Refresh in Details to retry.',
      PlantPostCommitIssue.assignmentChanged =>
        'The device assignment changed during connection.',
      PlantPostCommitIssue.scheduler =>
        'Could not synchronize automatic readings. Reopen the app to resume.',
      _ =>
        'Could not refresh the local view. Reopen the app if the list appears outdated.',
    };
    return Padding(
      padding: const EdgeInsets.only(left: 18, right: 6),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Text(
                '$prefix $detail',
                key: const Key('post-commit-notice'),
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  color: AppColors.terracotta,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Dismiss message',
            onPressed: store.dismissOperationNotice,
            icon: const Text(
              '×',
              style: TextStyle(fontSize: 22, color: AppColors.terracotta),
            ),
          ),
        ],
      ),
    );
  }
}
