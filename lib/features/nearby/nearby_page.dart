import 'dart:io';
import 'dart:ui';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:local_drop/l10n/app_localizations.dart';

import '../../models/device_profile.dart';
import '../../models/discovery_health.dart';
import '../../models/picker_failure.dart';
import '../../models/send_draft.dart';
import '../../models/transfer_diagnostics_snapshot.dart';
import '../../models/transfer_models.dart';
import '../../state/app_controller.dart';
import '../../widgets/discovery_troubleshooting_dialog.dart';
import '../../widgets/transfer_diagnostics_dialog.dart';

class NearbyPage extends StatefulWidget {
  const NearbyPage({super.key, required this.controller, this.onOpenTransfers});

  final AppController controller;
  final VoidCallback? onOpenTransfers;

  @override
  State<NearbyPage> createState() => _NearbyPageState();
}

class _NearbyPageState extends State<NearbyPage> {
  final TextEditingController _textController = TextEditingController();
  bool _desktopDropHover = false;
  bool _isPreparingItems = false;
  String? _sendingDeviceId;

  bool get _supportsDesktopDrop =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux);

  bool get _supportsFolderSelection =>
      !kIsWeb && !Platform.isAndroid && !Platform.isIOS;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final draft = widget.controller.sendDraft;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
            Theme.of(context).colorScheme.secondary.withValues(alpha: 0.08),
            Theme.of(context).scaffoldBackgroundColor,
          ],
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: <Widget>[
          _DeviceHeader(
            nickname: widget.controller.localNickname,
            step: draft.step,
          ),
          const SizedBox(height: 14),
          if (draft.step == SendStep.selectContent)
            _buildSelectContentStep(context, draft, l10n),
          if (draft.step == SendStep.chooseDevice)
            _buildChooseDeviceStep(context, draft, l10n),
        ],
      ),
    );
  }

  Widget _buildSelectContentStep(
    BuildContext context,
    SendDraft draft,
    AppLocalizations l10n,
  ) {
    final canOpenRecipientStep = widget.controller.isNetworkReady;
    final discoveryHealth = widget.controller.discoveryHealth;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _NearbyStatusCard(
          health: discoveryHealth,
          visibleDeviceCount: widget.controller.nearbyDevices.length,
          networkStartupState: widget.controller.networkStartupState,
          actionEnabled: !widget.controller.isNetworkWarmupInProgress,
          onRefresh: _refreshNearbyDevices,
          onTroubleshoot: () {
            showDiscoveryTroubleshootingDialog(
              context,
              health: discoveryHealth,
              onRepairFirewall: widget.controller.repairWindowsFirewall,
              devices: widget.controller.nearbyDevices,
              availabilityByDeviceId: <String, PeerAvailabilitySnapshot>{
                for (final device in widget.controller.nearbyDevices)
                  device.deviceId: widget.controller.availabilityForDevice(
                    device.deviceId,
                  ),
              },
              transportLeasesByDeviceId:
                  widget.controller.transportVerifiedPeerLeases,
            );
          },
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  l10n.selectContentTitle,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _isPreparingItems || draft.isSending
                        ? null
                        : () => _pickByType(TransferPayloadType.file),
                    icon: _isPreparingItems
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.attach_file),
                    label: Text(l10n.selectFilesButton),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: <Widget>[
                    OutlinedButton.icon(
                      onPressed: _isPreparingItems || draft.isSending
                          ? null
                          : () => _pickByType(TransferPayloadType.photo),
                      icon: const Icon(Icons.photo),
                      label: Text(l10n.contentPhoto),
                    ),
                    OutlinedButton.icon(
                      onPressed: _isPreparingItems || draft.isSending
                          ? null
                          : () => _pickByType(TransferPayloadType.video),
                      icon: const Icon(Icons.videocam),
                      label: Text(l10n.contentVideo),
                    ),
                    if (_supportsFolderSelection)
                      OutlinedButton.icon(
                        onPressed: _isPreparingItems || draft.isSending
                            ? null
                            : () => _pickByType(TransferPayloadType.folder),
                        icon: const Icon(Icons.folder),
                        label: Text(l10n.contentFolder),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(l10n.moreContentOptions),
                  childrenPadding: const EdgeInsets.only(bottom: 8),
                  children: <Widget>[
                    TextField(
                      controller: _textController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: l10n.textPayloadHint,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: <Widget>[
                        OutlinedButton.icon(
                          onPressed: _isPreparingItems || draft.isSending
                              ? null
                              : _addTextPayload,
                          icon: const Icon(Icons.short_text),
                          label: Text(l10n.addTextButton),
                        ),
                        OutlinedButton.icon(
                          onPressed: _isPreparingItems || draft.isSending
                              ? null
                              : _addClipboardPayload,
                          icon: const Icon(Icons.content_paste),
                          label: Text(l10n.contentClipboard),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (_supportsDesktopDrop) ...<Widget>[
          const SizedBox(height: 12),
          DropTarget(
            onDragDone: _onDesktopDrop,
            onDragEntered: (_) {
              setState(() {
                _desktopDropHover = true;
              });
            },
            onDragExited: (_) {
              setState(() {
                _desktopDropHover = false;
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _desktopDropHover
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.outlineVariant,
                  width: _desktopDropHover ? 2 : 1,
                ),
                color: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    _desktopDropHover
                        ? Icons.file_download_done
                        : Icons.file_upload_outlined,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _desktopDropHover
                          ? l10n.dropFilesNowHint
                          : l10n.dragDropHint,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (_isPreparingItems) ...<Widget>[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(l10n.preparingSelectedContent),
                  const SizedBox(height: 10),
                  const LinearProgressIndicator(minHeight: 6),
                ],
              ),
            ),
          ),
        ],
        if (widget.controller.activeTransfers.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          _OutgoingStatusCard(
            progress: widget.controller.currentOutgoingSendProgress,
            diagnostics: widget.controller.currentOutgoingTransferDiagnostics,
            onOpenTransfers: widget.onOpenTransfers,
          ),
        ],
        const SizedBox(height: 12),
        _SelectionTray(
          draft: draft,
          onRemoveItem: widget.controller.removeDraftItem,
          onClear: widget.controller.clearSendDraft,
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed:
                draft.hasItems && !_isPreparingItems && canOpenRecipientStep
                ? _openRecipientStep
                : null,
            icon: const Icon(Icons.arrow_forward),
            label: Text(l10n.chooseDeviceButton),
          ),
        ),
      ],
    );

    return content;
  }

  Widget _buildChooseDeviceStep(
    BuildContext context,
    SendDraft draft,
    AppLocalizations l10n,
  ) {
    final devices = widget.controller.nearbyDevices;
    final discoveryHealth = widget.controller.discoveryHealth;
    final diagnostics = widget.controller.currentOutgoingTransferDiagnostics;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    OutlinedButton.icon(
                      onPressed: draft.isSending
                          ? null
                          : widget.controller.backToContentStep,
                      icon: const Icon(Icons.arrow_back),
                      label: Text(l10n.backToContent),
                    ),
                    const SizedBox(width: 10),
                    TextButton(
                      onPressed: draft.isSending
                          ? null
                          : widget.controller.clearSendDraft,
                      child: Text(l10n.clearSelectionButton),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.selectedItemsWithTotal(
                    draft.items.length,
                    _formatBytes(draft.totalBytes),
                  ),
                ),
                if (draft.isSending) ...<Widget>[
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              l10n.sendingInProgress,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (widget
                                    .controller
                                    .currentOutgoingTransferStage !=
                                null) ...<Widget>[
                              const SizedBox(height: 4),
                              Text(
                                _stageLabel(
                                  l10n,
                                  widget
                                      .controller
                                      .currentOutgoingTransferStage!,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          l10n.chooseDeviceTitle,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 10),
        _NearbyStatusCard(
          health: discoveryHealth,
          visibleDeviceCount: devices.length,
          networkStartupState: widget.controller.networkStartupState,
          actionEnabled:
              !draft.isSending && !widget.controller.isNetworkWarmupInProgress,
          onRefresh: _refreshNearbyDevices,
          onTroubleshoot: () {
            showDiscoveryTroubleshootingDialog(
              context,
              health: discoveryHealth,
              onRepairFirewall: widget.controller.repairWindowsFirewall,
              devices: devices,
              availabilityByDeviceId: <String, PeerAvailabilitySnapshot>{
                for (final device in devices)
                  device.deviceId: widget.controller.availabilityForDevice(
                    device.deviceId,
                  ),
              },
              transportLeasesByDeviceId:
                  widget.controller.transportVerifiedPeerLeases,
            );
          },
        ),
        if (draft.isSending || diagnostics != null) ...<Widget>[
          const SizedBox(height: 10),
          _OutgoingStatusCard(
            progress: widget.controller.currentOutgoingSendProgress,
            diagnostics: diagnostics,
            onOpenTransfers: widget.onOpenTransfers,
          ),
        ],
        const SizedBox(height: 10),
        if (devices.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _emptyStateMessage(
                  l10n,
                  discoveryHealth,
                  widget.controller.networkStartupState,
                ),
              ),
            ),
          )
        else
          ...devices.map((device) {
            final availability = widget.controller.availabilityForDevice(
              device.deviceId,
            );
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _RecipientCard(
                displayName: widget.controller.displayNameForDevice(device),
                device: device,
                availability: availability,
                sending: draft.isSending && _sendingDeviceId == device.deviceId,
                onPrimaryAction: () => _handleRecipientAction(
                  device: device,
                  availability: availability,
                ),
              ),
            );
          }),
      ],
    );
  }

  Future<void> _pickByType(TransferPayloadType type) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final count = await _runPreparingItems(
        () => widget.controller.addDraftItemsFromType(type),
      );
      if (!mounted || count == null || count > 0) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.noItemsSelected)));
    } on PickerFailure catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_pickerFailureMessage(l10n, error))),
      );
    }
  }

  Future<void> _addTextPayload() async {
    final l10n = AppLocalizations.of(context)!;
    final success = await widget.controller.addDraftTextItem(
      _textController.text,
    );
    if (!mounted) {
      return;
    }
    if (!success) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.textPayloadEmpty)));
      return;
    }
    _textController.clear();
  }

  Future<void> _addClipboardPayload() async {
    final l10n = AppLocalizations.of(context)!;
    final success = await widget.controller.addDraftClipboardItem();
    if (!mounted || success) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.clipboardEmpty)));
  }

  void _openRecipientStep() {
    final l10n = AppLocalizations.of(context)!;
    final opened = widget.controller.openRecipientStep();
    if (opened) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          widget.controller.sendDraft.hasItems
              ? l10n.networkWarmupStarting
              : l10n.selectContentFirst,
        ),
      ),
    );
  }

  Future<void> _onDesktopDrop(DropDoneDetails details) async {
    if (_isPreparingItems) {
      return;
    }
    final paths = details.files
        .map((file) => file.path)
        .where((path) => path.trim().isNotEmpty)
        .toList(growable: false);
    if (paths.isEmpty) {
      return;
    }
    final count = await _runPreparingItems(
      () => widget.controller.addDraftItemsFromPaths(paths),
    );
    if (!mounted || count == null || count > 0) {
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.noItemsSelected)));
  }

  Future<void> _sendToDevice(DeviceProfile device) async {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _sendingDeviceId = device.deviceId;
    });
    final result = await widget.controller.sendDraftToDevice(device.deviceId);
    if (!mounted) {
      return;
    }
    setState(() {
      _sendingDeviceId = null;
    });
    if (result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.sentToDevice(widget.controller.displayNameForDevice(device)),
          ),
        ),
      );
      return;
    }

    final reason = result.failureReason ?? SendFailureReason.unknown;
    final details = result.details?.trim();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          details != null && details.isNotEmpty
              ? details
              : _messageForFailure(l10n, reason),
        ),
      ),
    );
  }

  Future<void> _handleRecipientAction({
    required DeviceProfile device,
    required PeerAvailabilitySnapshot availability,
  }) async {
    if (availability.status == PeerAvailabilityStatus.ready) {
      await _sendToDevice(device);
      return;
    }
    if (availability.status == PeerAvailabilityStatus.incompatible) {
      return;
    }
    await widget.controller.refreshPeerAvailability(device.deviceId);
  }

  Future<void> _refreshNearbyDevices() async {
    await widget.controller.refreshNearbyDevices();
  }

  String _messageForFailure(AppLocalizations l10n, SendFailureReason reason) {
    return switch (reason) {
      SendFailureReason.noContent => l10n.selectContentFirst,
      SendFailureReason.recipientOffline => l10n.sendErrorRecipientOffline,
      SendFailureReason.transferUnreachable =>
        l10n.sendErrorTransferUnreachable,
      SendFailureReason.missingLocalFile => l10n.sendErrorMissingFile,
      SendFailureReason.timeout => l10n.sendErrorTimeout,
      SendFailureReason.approvalExpired => l10n.sendErrorApprovalExpired,
      SendFailureReason.certificateMismatch => l10n.sendErrorCertificate,
      SendFailureReason.integrityCheckFailed => l10n.sendErrorIntegrity,
      SendFailureReason.rejected => l10n.sendErrorRejected,
      SendFailureReason.incompatibleVersion =>
        l10n.sendErrorIncompatibleVersion,
      SendFailureReason.canceled => l10n.statusCanceled,
      SendFailureReason.busy => l10n.sendErrorBusy,
      SendFailureReason.unknown => l10n.sendErrorUnknown,
    };
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

  Future<T?> _runPreparingItems<T>(Future<T> Function() action) async {
    if (_isPreparingItems) {
      return null;
    }
    setState(() {
      _isPreparingItems = true;
    });
    try {
      return await action();
    } finally {
      if (mounted) {
        setState(() {
          _isPreparingItems = false;
        });
      }
    }
  }

  String _pickerFailureMessage(
    AppLocalizations l10n,
    PickerFailure failure,
  ) {
    if (failure.isMacOSAvailabilityIssue) {
      return l10n.macosContentPickerUnavailable;
    }
    return l10n.contentPickerOpenFailed;
  }

  String _emptyStateMessage(
    AppLocalizations l10n,
    DiscoveryHealth health,
    NetworkStartupState networkStartupState,
  ) {
    if (networkStartupState == NetworkStartupState.warmingUp ||
        networkStartupState == NetworkStartupState.idle) {
      return l10n.networkWarmupStarting;
    }
    if (health.isPaused &&
        health.pauseReason == DiscoveryPauseReason.backgrounded) {
      return l10n.nearbyEmptyPaused;
    }
    if (health.hasBlockingIssue) {
      return l10n.nearbyEmptyIssue;
    }
    if (health.isStarting || health.isScanning || health.lastScanAt == null) {
      return l10n.waitingForDevices;
    }
    if (health.discoveredDeviceCount > 0 &&
        health.verifiedSendReadyPeerCount == 0) {
      return l10n.nearbyEmptyChecking;
    }
    if (health.hasHealthyBackend || health.isRunning) {
      return l10n.noDevicesFound;
    }
    return l10n.nearbyEmptyIssue;
  }
}

class _DeviceHeader extends StatelessWidget {
  const _DeviceHeader({required this.nickname, required this.step});

  final String nickname;
  final SendStep step;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              l10n.yourDeviceLabel,
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 4),
            Text(nickname, style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                _StepChip(
                  label: l10n.selectContentTitle,
                  selected: step == SendStep.selectContent,
                ),
                _StepChip(
                  label: l10n.chooseDeviceTitle,
                  selected: step == SendStep.chooseDevice,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StepChip extends StatelessWidget {
  const _StepChip({required this.label, required this.selected});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: selected
            ? theme.colorScheme.primary.withValues(alpha: 0.18)
            : theme.colorScheme.surfaceContainerHighest,
      ),
      child: Text(label, style: theme.textTheme.labelLarge),
    );
  }
}

class _SelectionTray extends StatelessWidget {
  const _SelectionTray({
    required this.draft,
    required this.onRemoveItem,
    required this.onClear,
  });

  final SendDraft draft;
  final void Function(String itemId) onRemoveItem;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (!draft.hasItems) {
      return SizedBox(
        width: double.infinity,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(l10n.noItemsSelected),
          ),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          l10n.selectionTrayTitle,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      TextButton(
                        onPressed: onClear,
                        child: Text(l10n.clearSelectionButton),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(l10n.selectedItemsCount(draft.items.length)),
                  const SizedBox(height: 8),
                  ...draft.items.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: <Widget>[
                          Icon(_iconForItem(item.type), size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              item.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            onPressed: () => onRemoveItem(item.id),
                            icon: const Icon(Icons.close),
                            tooltip: l10n.removeButton,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  IconData _iconForItem(TransferPayloadType type) {
    return switch (type) {
      TransferPayloadType.file => Icons.insert_drive_file,
      TransferPayloadType.photo => Icons.photo,
      TransferPayloadType.video => Icons.videocam,
      TransferPayloadType.folder => Icons.folder,
      TransferPayloadType.text => Icons.short_text,
      TransferPayloadType.clipboard => Icons.content_paste,
    };
  }
}

class _RecipientCard extends StatelessWidget {
  const _RecipientCard({
    required this.displayName,
    required this.device,
    required this.availability,
    required this.sending,
    required this.onPrimaryAction,
  });

  final String displayName;
  final DeviceProfile device;
  final PeerAvailabilitySnapshot availability;
  final bool sending;
  final VoidCallback onPrimaryAction;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final subtitle = _subtitle(l10n);
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          child: Text(displayName.substring(0, 1).toUpperCase()),
        ),
        title: Text(displayName),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(subtitle),
            const SizedBox(height: 4),
            Text(
              _availabilityMessage(l10n),
              style: TextStyle(
                color: _availabilityColor(context),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        trailing: FilledButton.icon(
          onPressed: _buttonEnabled ? onPrimaryAction : null,
          icon: sending
              ? const SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(_buttonIcon),
          label: Text(_buttonLabel(l10n)),
        ),
      ),
    );
  }

  bool get _buttonEnabled {
    if (sending) {
      return false;
    }
    return availability.status != PeerAvailabilityStatus.incompatible &&
        availability.status != PeerAvailabilityStatus.checking;
  }

  IconData get _buttonIcon {
    return switch (availability.status) {
      PeerAvailabilityStatus.ready => Icons.send,
      PeerAvailabilityStatus.checking => Icons.sync,
      PeerAvailabilityStatus.incompatible => Icons.system_update,
      PeerAvailabilityStatus.securityFailure => Icons.verified_user_outlined,
      PeerAvailabilityStatus.unreachable => Icons.refresh,
      PeerAvailabilityStatus.unknown => Icons.radar,
    };
  }

  String _buttonLabel(AppLocalizations l10n) {
    return switch (availability.status) {
      PeerAvailabilityStatus.ready => l10n.sendNowButton,
      PeerAvailabilityStatus.checking => l10n.recipientCheckingButton,
      PeerAvailabilityStatus.incompatible => l10n.updateRequiredLabel,
      PeerAvailabilityStatus.securityFailure => l10n.recipientCheckAgainButton,
      PeerAvailabilityStatus.unreachable => l10n.recipientCheckAgainButton,
      PeerAvailabilityStatus.unknown => l10n.recipientCheckAgainButton,
    };
  }

  String _subtitle(AppLocalizations l10n) {
    return _platformLabel(l10n, device.platform);
  }

  String _availabilityMessage(AppLocalizations l10n) {
    return switch (availability.status) {
      PeerAvailabilityStatus.ready => l10n.recipientReadyMessage,
      PeerAvailabilityStatus.checking => l10n.recipientCheckingMessage,
      PeerAvailabilityStatus.incompatible => l10n.recipientNeedsUpdateMessage,
      PeerAvailabilityStatus.securityFailure => l10n.recipientSecurityMessage,
      PeerAvailabilityStatus.unreachable => l10n.recipientUnavailableMessage,
      PeerAvailabilityStatus.unknown => l10n.recipientPendingMessage,
    };
  }

  String _platformLabel(AppLocalizations l10n, String platform) {
    return switch (platform.trim().toLowerCase()) {
      'android' => 'Android',
      'ios' => 'iPhone or iPad',
      'ipados' => 'iPad',
      'macos' => 'macOS',
      'windows' => 'Windows',
      'linux' => 'Linux',
      '' => l10n.nearbyGenericDeviceLabel,
      final value => value[0].toUpperCase() + value.substring(1),
    };
  }

  Color _availabilityColor(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return switch (availability.status) {
      PeerAvailabilityStatus.ready => Colors.green.shade700,
      PeerAvailabilityStatus.incompatible ||
      PeerAvailabilityStatus.securityFailure ||
      PeerAvailabilityStatus.unreachable => colorScheme.error,
      PeerAvailabilityStatus.checking ||
      PeerAvailabilityStatus.unknown => colorScheme.primary,
    };
  }
}

class _OutgoingStatusCard extends StatelessWidget {
  const _OutgoingStatusCard({
    required this.progress,
    required this.diagnostics,
    this.onOpenTransfers,
  });

  final TransferProgress? progress;
  final TransferDiagnosticsSnapshot? diagnostics;
  final VoidCallback? onOpenTransfers;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final errorColor = Theme.of(context).colorScheme.error;
    return SizedBox(
      width: double.infinity,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                l10n.currentTransferTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (progress != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  '${progress!.peerNickname} • ${progress!.stage != null ? _stageLabel(l10n, progress!.stage!) : _statusLabel(l10n, progress!.status)}',
                ),
              ] else if (onOpenTransfers != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(l10n.transfersTab),
              ],
              if ((progress?.errorMessage ?? diagnostics?.errorMessage) !=
                  null) ...<Widget>[
                const SizedBox(height: 6),
                Text(
                  progress?.errorMessage ?? diagnostics?.errorMessage ?? '',
                  style: TextStyle(color: errorColor),
                ),
              ],
              if (diagnostics != null || onOpenTransfers != null) ...<Widget>[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    if (onOpenTransfers != null)
                      TextButton.icon(
                        onPressed: onOpenTransfers,
                        icon: const Icon(Icons.swap_horizontal_circle),
                        label: Text(l10n.transfersTab),
                      ),
                    TextButton.icon(
                      onPressed: () {
                        showTransferDiagnosticsDialog(
                          context,
                          title: l10n.transferDiagnosticsTitle,
                          diagnostics: diagnostics,
                          terminalReason: progress?.terminalReason,
                          errorMessage: progress?.errorMessage,
                        );
                      },
                      icon: const Icon(Icons.info_outline),
                      label: Text(l10n.transferDetailsButton),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _statusLabel(AppLocalizations l10n, TransferStatus status) {
    return switch (status) {
      TransferStatus.pendingApproval => l10n.statusPendingApproval,
      TransferStatus.approved => l10n.statusApproved,
      TransferStatus.declined => l10n.statusDeclined,
      TransferStatus.inProgress => l10n.statusInProgress,
      TransferStatus.completed => l10n.statusCompleted,
      TransferStatus.failed => l10n.statusFailed,
      TransferStatus.canceled => l10n.statusCanceled,
    };
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
}

class _NearbyStatusCard extends StatelessWidget {
  const _NearbyStatusCard({
    required this.health,
    required this.visibleDeviceCount,
    required this.networkStartupState,
    required this.actionEnabled,
    required this.onRefresh,
    required this.onTroubleshoot,
  });

  final DiscoveryHealth health;
  final int visibleDeviceCount;
  final NetworkStartupState networkStartupState;
  final bool actionEnabled;
  final Future<void> Function() onRefresh;
  final VoidCallback onTroubleshoot;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final statusText = _statusText(l10n);
    final summaryText = _summaryText(l10n);
    final hintText =
        networkStartupState == NetworkStartupState.warmingUp ||
            networkStartupState == NetworkStartupState.idle
        ? l10n.networkWarmupHint
        : health.isPaused
        ? l10n.nearbyPausedHint
        : health.verifiedSendReadyPeerCount > 0
        ? l10n.refreshHint
        : health.hasBlockingIssue
        ? l10n.nearbyIssueHint
        : l10n.refreshHint;
    final statusColor = _statusColor(theme.colorScheme);

    return SizedBox(
      width: double.infinity,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(l10n.nearbyStatusTitle, style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                statusText,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: statusColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (summaryText.isNotEmpty) ...<Widget>[
                const SizedBox(height: 6),
                Text(summaryText),
              ],
              const SizedBox(height: 8),
              Text(hintText),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: <Widget>[
                  OutlinedButton.icon(
                    onPressed: actionEnabled ? onRefresh : null,
                    icon: const Icon(Icons.refresh),
                    label: Text(l10n.refreshDevicesButton),
                  ),
                  TextButton.icon(
                    onPressed: onTroubleshoot,
                    icon: const Icon(Icons.tune),
                    label: Text(l10n.nearbyTroubleshootButton),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _statusText(AppLocalizations l10n) {
    if (networkStartupState == NetworkStartupState.warmingUp ||
        networkStartupState == NetworkStartupState.idle) {
      return l10n.networkWarmupStarting;
    }
    if (health.isPaused &&
        health.pauseReason == DiscoveryPauseReason.backgrounded) {
      return l10n.nearbyStatusPaused;
    }
    if (health.verifiedSendReadyPeerCount > 0 || visibleDeviceCount > 0) {
      return l10n.nearbyStatusReady;
    }
    if (health.hasBlockingIssue) {
      return l10n.nearbyStatusNeedsAttention;
    }
    if (health.isStarting || health.isScanning || health.lastScanAt == null) {
      return l10n.nearbyStatusScanning;
    }
    if (health.hasHealthyBackend && health.discoveredDeviceCount == 0) {
      return l10n.nearbyStatusScanning;
    }
    if (health.hasHealthyBackend || health.isRunning) {
      return l10n.nearbyStatusScanning;
    }
    return l10n.nearbyStatusNeedsAttention;
  }

  String _summaryText(AppLocalizations l10n) {
    if (networkStartupState == NetworkStartupState.warmingUp ||
        networkStartupState == NetworkStartupState.idle) {
      return l10n.networkWarmupHint;
    }
    if (visibleDeviceCount > 0) {
      return l10n.nearbyReadyCount(visibleDeviceCount);
    }
    if (health.verifiedSendReadyPeerCount > 0) {
      return l10n.nearbyReadyCount(health.verifiedSendReadyPeerCount);
    }
    if (health.discoveredDeviceCount > 0) {
      return l10n.nearbyFoundCount(health.discoveredDeviceCount);
    }
    return '';
  }

  Color _statusColor(ColorScheme colorScheme) {
    if (networkStartupState == NetworkStartupState.warmingUp ||
        networkStartupState == NetworkStartupState.idle) {
      return colorScheme.primary;
    }
    if (health.isPaused &&
        health.pauseReason == DiscoveryPauseReason.backgrounded) {
      return colorScheme.primary;
    }
    if (health.verifiedSendReadyPeerCount > 0 || visibleDeviceCount > 0) {
      return Colors.green.shade700;
    }
    if (health.hasBlockingIssue) {
      return colorScheme.error;
    }
    return colorScheme.primary;
  }
}
