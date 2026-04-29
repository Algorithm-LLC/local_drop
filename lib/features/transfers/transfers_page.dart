import 'package:flutter/material.dart';
import 'package:local_drop/l10n/app_localizations.dart';

import '../../models/device_profile.dart';
import '../../models/send_draft.dart';
import '../../models/transfer_diagnostics_snapshot.dart';
import '../../models/transfer_models.dart';
import '../../state/app_controller.dart';
import '../../widgets/receiver_pin_dialog.dart';
import '../../widgets/transfer_diagnostics_dialog.dart';
import 'transfer_folder_page.dart';

class TransfersPage extends StatelessWidget {
  const TransfersPage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final transfers = controller.activeTransfers;
    if (transfers.isEmpty) {
      return Center(child: Text(l10n.noActiveTransfers));
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: transfers.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final progress = transfers[index];
        final record = controller.history.cast<TransferRecord?>().firstWhere(
          (item) => item?.transferId == progress.transferId,
          orElse: () => null,
        );
        return _TransferCard(
          controller: controller,
          progress: progress,
          record: record,
          onCancel: () => controller.cancelTransfer(progress),
          onRetry: () async {
            if (record != null) {
              await _retryTransfer(context, record);
            }
          },
        );
      },
    );
  }

  Future<void> _retryTransfer(
    BuildContext context,
    TransferRecord? record,
  ) async {
    if (record == null) {
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    final peer = controller.knownProfileForDeviceId(record.peerDeviceId);
    final receiverPin = await _requestReceiverPin(
      context,
      record.peerNickname,
      peer: peer,
    );
    if (!context.mounted || receiverPin == null) {
      return;
    }
    final result = await controller.retryTransfer(
      record,
      receiverPin: receiverPin.pin,
      trustConfirmed: receiverPin.trustConfirmed,
    );
    if (!context.mounted || result.success) {
      return;
    }
    final details = result.details?.trim();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          details != null && details.isNotEmpty
              ? details
              : _messageForFailure(l10n, result.failureReason),
        ),
      ),
    );
  }

  Future<ReceiverPinResult?> _requestReceiverPin(
    BuildContext context,
    String peerNickname, {
    DeviceProfile? peer,
  }) async {
    return showReceiverPinDialog(
      context,
      peerNickname: peerNickname,
      requiresSecurityConfirmation:
          peer != null && controller.requiresFirstTransferConfirmation(peer),
      peerSecurityCode: peer == null
          ? null
          : controller.securityCodeForDevice(peer),
      localSecurityCode: controller.localSecurityCode,
    );
  }

  String _messageForFailure(AppLocalizations l10n, SendFailureReason? reason) {
    return switch (reason) {
      SendFailureReason.noContent => l10n.selectContentFirst,
      SendFailureReason.recipientOffline => l10n.sendErrorRecipientOffline,
      SendFailureReason.transferUnreachable =>
        l10n.sendErrorTransferUnreachable,
      SendFailureReason.missingLocalFile => l10n.sendErrorMissingFile,
      SendFailureReason.timeout => l10n.sendErrorTimeout,
      SendFailureReason.approvalExpired => l10n.sendErrorApprovalExpired,
      SendFailureReason.invalidPin => 'Incorrect receiver PIN',
      SendFailureReason.certificateMismatch => l10n.sendErrorCertificate,
      SendFailureReason.integrityCheckFailed => l10n.sendErrorIntegrity,
      SendFailureReason.rejected => l10n.sendErrorRejected,
      SendFailureReason.incompatibleVersion =>
        l10n.sendErrorIncompatibleVersion,
      SendFailureReason.canceled => l10n.statusCanceled,
      SendFailureReason.busy => l10n.sendErrorBusy,
      SendFailureReason.unknown || null => l10n.sendErrorUnknown,
    };
  }
}

class _TransferCard extends StatelessWidget {
  const _TransferCard({
    required this.controller,
    required this.progress,
    required this.record,
    required this.onCancel,
    required this.onRetry,
  });

  final AppController controller;
  final TransferProgress progress;
  final TransferRecord? record;
  final VoidCallback onCancel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final diagnostics = controller.diagnosticsForTransfer(progress.transferId);
    final folderPath = record == null
        ? null
        : transferFolderPathForRecord(record!);
    final terminal =
        progress.status == TransferStatus.failed ||
        progress.status == TransferStatus.completed ||
        progress.status == TransferStatus.canceled ||
        progress.status == TransferStatus.declined;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(progress.isIncoming ? Icons.south_west : Icons.north_east),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${progress.peerNickname} • ${progress.isIncoming ? l10n.transferIncoming : l10n.transferOutgoing}',
                    style: Theme.of(context).textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _StatusChip(status: progress.status),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: progress.completion.clamp(0, 1),
              minHeight: 7,
            ),
            const SizedBox(height: 10),
            Text(
              '${_formatBytes(progress.transferredBytes)} / ${_formatBytes(progress.totalBytes)}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (!progress.isIncoming && progress.stage != null) ...<Widget>[
              const SizedBox(height: 6),
              Text(_stageLabel(l10n, progress.stage!)),
            ],
            const SizedBox(height: 6),
            Text(
              '${l10n.speedLabel}: ${_formatBytes(progress.bytesPerSecond.round())}/s'
              '${progress.eta != null ? ' • ${l10n.etaLabel}: ${_formatDuration(progress.eta!)}' : ''}',
            ),
            if (progress.errorMessage != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                progress.errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                if (!terminal)
                  OutlinedButton.icon(
                    onPressed: onCancel,
                    icon: const Icon(Icons.close),
                    label: Text(l10n.cancelButton),
                  ),
                if (progress.status == TransferStatus.failed ||
                    progress.status == TransferStatus.canceled)
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: Text(l10n.retryButton),
                  ),
                if (folderPath != null)
                  TextButton.icon(
                    onPressed: () => _openFolder(context, folderPath),
                    icon: const Icon(Icons.folder_open),
                    label: Text(l10n.openFolderButton),
                  ),
                if (diagnostics != null || progress.errorMessage != null)
                  TextButton.icon(
                    onPressed: () => _showDiagnostics(context, diagnostics),
                    icon: const Icon(Icons.info_outline),
                    label: Text(l10n.transferDetailsButton),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds.clamp(0, 24 * 60 * 60);
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String _stageLabel(AppLocalizations l10n, TransferStage stage) {
    return switch (stage) {
      TransferStage.connecting => l10n.transferStageConnecting,
      TransferStage.offerQueued => l10n.transferStageOfferQueued,
      TransferStage.awaitingApproval => l10n.transferStageAwaitingApproval,
      TransferStage.uploading => l10n.transferStageUploading,
      TransferStage.completing => l10n.transferStageCompleting,
      TransferStage.failed => l10n.statusFailed,
    };
  }

  void _showDiagnostics(
    BuildContext context,
    TransferDiagnosticsSnapshot? diagnostics,
  ) {
    final l10n = AppLocalizations.of(context)!;
    showTransferDiagnosticsDialog(
      context,
      title: l10n.transferDiagnosticsTitle,
      diagnostics: diagnostics,
      terminalReason: progress.terminalReason,
      errorMessage: progress.errorMessage,
    );
  }

  void _openFolder(BuildContext context, String folderPath) {
    final l10n = AppLocalizations.of(context)!;
    final sharePaths = record == null
        ? const <String>[]
        : transferSharePathsForRecord(record!);
    openTransferFolder(
      context,
      folderPath: folderPath,
      title: l10n.transferFolderTitle,
      sharePaths: sharePaths,
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final TransferStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final label = switch (status) {
      TransferStatus.pendingApproval => l10n.statusPendingApproval,
      TransferStatus.approved => l10n.statusApproved,
      TransferStatus.declined => l10n.statusDeclined,
      TransferStatus.inProgress => l10n.statusInProgress,
      TransferStatus.completed => l10n.statusCompleted,
      TransferStatus.failed => l10n.statusFailed,
      TransferStatus.canceled => l10n.statusCanceled,
    };
    final Color background = switch (status) {
      TransferStatus.completed => Colors.green.withValues(alpha: 0.15),
      TransferStatus.failed => colorScheme.error.withValues(alpha: 0.18),
      TransferStatus.canceled => colorScheme.error.withValues(alpha: 0.12),
      TransferStatus.inProgress => colorScheme.secondary.withValues(
        alpha: 0.18,
      ),
      TransferStatus.approved => colorScheme.primary.withValues(alpha: 0.18),
      TransferStatus.pendingApproval => colorScheme.primary.withValues(
        alpha: 0.14,
      ),
      TransferStatus.declined => colorScheme.error.withValues(alpha: 0.12),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: background,
      ),
      child: Text(label, style: theme.textTheme.labelLarge),
    );
  }
}
