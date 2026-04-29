import 'package:flutter/material.dart';
import 'package:local_drop/l10n/app_localizations.dart';

import '../models/transfer_diagnostics_snapshot.dart';
import '../models/transfer_models.dart';

Future<void> showTransferDiagnosticsDialog(
  BuildContext context, {
  required String title,
  TransferDiagnosticsSnapshot? diagnostics,
  TransferTerminalReason? terminalReason,
  String? errorMessage,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) {
      final l10n = AppLocalizations.of(context)!;
      return AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (diagnostics != null) ...<Widget>[
                  _DetailLine(
                    label: l10n.transferDiagnosticsStageLabel,
                    value: _stageLabel(l10n, diagnostics.stage),
                  ),
                  _DetailLine(
                    label: l10n.transferDiagnosticsEndpointLabel,
                    value: _endpointLabel(l10n, diagnostics),
                  ),
                  _DetailLine(
                    label: l10n.transferDiagnosticsAddressFamilyLabel,
                    value:
                        diagnostics.addressFamily ?? l10n.transferUnknownValue,
                  ),
                  _DetailLine(
                    label: l10n.transferDiagnosticsSecurityLabel,
                    value: diagnostics.tlsFingerprintVerified == null
                        ? l10n.transferDiagnosticsSecurityNotUsed
                        : diagnostics.tlsFingerprintVerified!
                        ? l10n.transferDiagnosticsSecurityVerified
                        : l10n.transferDiagnosticsSecurityFailed,
                  ),
                  _DetailLine(
                    label: l10n.transferDiagnosticsHttpRouteLabel,
                    value:
                        diagnostics.lastHttpRoute ??
                        l10n.transferNotAvailableValue,
                  ),
                  _DetailLine(
                    label: l10n.transferDiagnosticsHttpStatusLabel,
                    value:
                        diagnostics.lastHttpStatusCode?.toString() ??
                        l10n.transferNotAvailableValue,
                  ),
                  _DetailLine(
                    label: l10n.transferDiagnosticsOfferStatusLabel,
                    value:
                        diagnostics.offerStatus ??
                        l10n.transferNotAvailableValue,
                  ),
                  _DetailLine(
                    label: l10n.transferDiagnosticsDecisionLabel,
                    value:
                        diagnostics.decisionStatus?.name ??
                        l10n.transferNotAvailableValue,
                  ),
                  _DetailLine(
                    label: l10n.transferDiagnosticsUploadLabel,
                    value:
                        diagnostics.uploadStatus ??
                        l10n.transferNotAvailableValue,
                  ),
                ],
                _DetailLine(
                  label: l10n.transferDiagnosticsTerminalReasonLabel,
                  value: _terminalReasonLabel(
                    l10n,
                    diagnostics?.terminalReason ?? terminalReason,
                  ),
                ),
                _DetailLine(
                  label: l10n.transferDiagnosticsMessageLabel,
                  value:
                      diagnostics?.errorMessage ??
                      errorMessage ??
                      l10n.transferDiagnosticsNoExtraDetails,
                ),
                if ((diagnostics?.logFilePath ?? '').trim().isNotEmpty)
                  _SelectableDetailLine(
                    label: l10n.transferDiagnosticsLogLabel,
                    value: diagnostics!.logFilePath!,
                  ),
              ],
            ),
          ),
        ),
        actions: <Widget>[
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.closeButtonLabel),
          ),
        ],
      );
    },
  );
}

String _endpointLabel(
  AppLocalizations l10n,
  TransferDiagnosticsSnapshot diagnostics,
) {
  final address = diagnostics.selectedAddress;
  final port = diagnostics.selectedPort;
  if (address == null || port == null) {
    return l10n.transferNotAvailableValue;
  }
  return '$address:$port';
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
  TransferTerminalReason? reason,
) {
  return switch (reason) {
    TransferTerminalReason.discoveryVisibleButUnreachable =>
      l10n.transferReasonConnectionIssue,
    TransferTerminalReason.tlsVerificationFailed =>
      l10n.transferReasonSecurityIssue,
    TransferTerminalReason.pinVerificationFailed => 'PIN verification failed',
    TransferTerminalReason.approvalExpired =>
      l10n.transferReasonApprovalExpired,
    TransferTerminalReason.declined => l10n.transferReasonDeclined,
    TransferTerminalReason.uploadFailed => l10n.transferReasonTransferFailed,
    TransferTerminalReason.integrityCheckFailed =>
      l10n.transferReasonVerificationFailed,
    TransferTerminalReason.incompatibleProtocol =>
      l10n.transferReasonUpdateRequired,
    TransferTerminalReason.canceled => l10n.statusCanceled,
    TransferTerminalReason.unknown || null => l10n.transferNotAvailableValue,
  };
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 2),
          Text(value),
        ],
      ),
    );
  }
}

class _SelectableDetailLine extends StatelessWidget {
  const _SelectableDetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 2),
          SelectableText(value),
        ],
      ),
    );
  }
}
