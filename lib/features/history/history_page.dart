import 'package:flutter/material.dart';
import 'package:local_drop/l10n/app_localizations.dart';

import '../../models/transfer_diagnostics_snapshot.dart';
import '../../models/transfer_models.dart';
import '../../state/app_controller.dart';
import '../../widgets/transfer_diagnostics_dialog.dart';
import '../transfers/transfer_folder_page.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final filtered = widget.controller.history
        .where((record) {
          if (_query.trim().isEmpty) {
            return true;
          }
          final normalized = _query.toLowerCase();
          if (record.peerNickname.toLowerCase().contains(normalized)) {
            return true;
          }
          return record.items.any(
            (item) => item.displayName.toLowerCase().contains(normalized),
          );
        })
        .toList(growable: false);

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          child: TextField(
            onChanged: (value) {
              setState(() {
                _query = value;
              });
            },
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: l10n.historySearchHint,
            ),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(child: Text(l10n.noHistory))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final record = filtered[index];
                    return _HistoryCard(
                      controller: widget.controller,
                      record: record,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.controller, required this.record});

  final AppController controller;
  final TransferRecord record;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final diagnostics = controller.diagnosticsForTransfer(record.transferId);
    final folderPath = transferFolderPathForRecord(record);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(record.isIncoming ? Icons.download : Icons.upload),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${record.peerNickname} • ${record.isIncoming ? l10n.transferIncoming : l10n.transferOutgoing}',
                    style: Theme.of(context).textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _SmallStatus(status: record.status),
              ],
            ),
            const SizedBox(height: 8),
            Text(_formatTimestamp(record.endedAt)),
            const SizedBox(height: 8),
            Text(
              record.items.map((item) => item.displayName).join(', '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Text(
              '${_formatBytes(record.transferredBytes)} / ${_formatBytes(record.totalBytes)}',
            ),
            if (!record.isIncoming && record.stage != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(_stageLabel(l10n, record.stage!)),
            ],
            if (record.errorMessage != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                record.errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (folderPath != null ||
                record.terminalReason != null ||
                record.errorMessage != null ||
                diagnostics != null) ...<Widget>[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  if (folderPath != null)
                    TextButton.icon(
                      onPressed: () => _openFolder(context, folderPath),
                      icon: const Icon(Icons.folder_open),
                      label: Text(l10n.openFolderButton),
                    ),
                  if (record.terminalReason != null ||
                      record.errorMessage != null ||
                      diagnostics != null)
                    TextButton.icon(
                      onPressed: () => _showDiagnostics(context, diagnostics),
                      icon: const Icon(Icons.info_outline),
                      label: Text(
                        record.terminalReason == null
                            ? l10n.transferDetailsButton
                            : _terminalReasonLabel(
                                l10n,
                                record.terminalReason!,
                              ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime dateTime) {
    final local = dateTime.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
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

  String _terminalReasonLabel(
    AppLocalizations l10n,
    TransferTerminalReason reason,
  ) {
    return switch (reason) {
      TransferTerminalReason.discoveryVisibleButUnreachable =>
        l10n.transferReasonConnectionIssue,
      TransferTerminalReason.tlsVerificationFailed =>
        l10n.transferReasonSecurityIssue,
      TransferTerminalReason.approvalExpired =>
        l10n.transferReasonApprovalExpired,
      TransferTerminalReason.declined => l10n.transferReasonDeclined,
      TransferTerminalReason.uploadFailed => l10n.transferReasonTransferFailed,
      TransferTerminalReason.integrityCheckFailed =>
        l10n.transferReasonVerificationFailed,
      TransferTerminalReason.incompatibleProtocol =>
        l10n.transferReasonUpdateRequired,
      TransferTerminalReason.canceled => l10n.statusCanceled,
      TransferTerminalReason.unknown => l10n.transferDetailsButton,
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
      terminalReason: record.terminalReason,
      errorMessage: record.errorMessage,
    );
  }

  void _openFolder(BuildContext context, String folderPath) {
    final l10n = AppLocalizations.of(context)!;
    openTransferFolder(
      context,
      folderPath: folderPath,
      title: l10n.transferFolderTitle,
      sharePaths: transferSharePathsForRecord(record),
    );
  }
}

class _SmallStatus extends StatelessWidget {
  const _SmallStatus({required this.status});

  final TransferStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final label = switch (status) {
      TransferStatus.pendingApproval => l10n.statusPendingApproval,
      TransferStatus.approved => l10n.statusApproved,
      TransferStatus.declined => l10n.statusDeclined,
      TransferStatus.inProgress => l10n.statusInProgress,
      TransferStatus.completed => l10n.statusCompleted,
      TransferStatus.failed => l10n.statusFailed,
      TransferStatus.canceled => l10n.statusCanceled,
    };
    return Text(label, style: Theme.of(context).textTheme.labelMedium);
  }
}
