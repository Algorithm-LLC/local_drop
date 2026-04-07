import 'dart:io';

import 'package:flutter/material.dart';
import 'package:local_drop/l10n/app_localizations.dart';

import '../models/device_profile.dart';
import '../models/discovery_health.dart';
import '../models/peer_presence_models.dart';
import '../models/transfer_diagnostics_snapshot.dart';

Future<void> showDiscoveryTroubleshootingDialog(
  BuildContext context, {
  required DiscoveryHealth health,
  Future<void> Function()? onRepairFirewall,
  List<DeviceProfile> devices = const <DeviceProfile>[],
  Map<String, PeerAvailabilitySnapshot> availabilityByDeviceId =
      const <String, PeerAvailabilitySnapshot>{},
  Map<String, TransportVerifiedPeerLease> transportLeasesByDeviceId =
      const <String, TransportVerifiedPeerLease>{},
}) {
  return showDialog<void>(
    context: context,
    builder: (context) {
      final now = DateTime.now();
      final l10n = AppLocalizations.of(context)!;
      final materialLocalizations = MaterialLocalizations.of(context);
      final activeBackends = health.backendState.activeBackends;
      final healthyBackends = health.backendState.healthyBackends;
      final degradedBackends = health.backendState.degradedBackends;
      final backendLabels = activeBackends
          .map(_backendLabel)
          .toList(growable: false);
      final healthyBackendLabels = healthyBackends
          .map(_backendLabel)
          .toList(growable: false);
      final degradedBackendLabels = degradedBackends
          .map(_backendLabel)
          .toList(growable: false);
      final peerCounts = activeBackends
          .map((kind) {
            final count =
                health.backendState.peerCountsByBackend[kind.name] ?? 0;
            return '${_backendLabel(kind)}: $count';
          })
          .toList(growable: false);
      final backendMessages = activeBackends
          .map((kind) {
            final message = health.backendState.lastLogsByBackend[kind.name];
            if (message == null || message.trim().isEmpty) {
              return null;
            }
            return '${_backendLabel(kind)}: $message';
          })
          .whereType<String>()
          .toList(growable: false);
      final backendErrors = activeBackends
          .map((kind) {
            final message = health.backendState.lastErrorsByBackend[kind.name];
            if (message == null || message.trim().isEmpty) {
              return null;
            }
            return '${_backendLabel(kind)}: $message';
          })
          .whereType<String>()
          .toList(growable: false);
      final peerDetails = devices
          .map((device) {
            final availability = availabilityByDeviceId[device.deviceId];
            final transportLease = transportLeasesByDeviceId[device.deviceId];
            final sourceLabels = device.discoverySources.isEmpty
                ? const <String>[]
                : device.discoverySources
                      .map((item) => _backendLabel(item.backendKind))
                      .toList(growable: false);
            final sourceAges = device.discoverySources
                .map(
                  (item) =>
                      '${_backendLabel(item.backendKind)} ${_relativeAge(now.difference(item.lastSeen))}',
                )
                .toList(growable: false);
            final endpointAddress =
                availability?.selectedAddress ??
                transportLease?.selectedAddress;
            final endpointPort =
                availability?.selectedPort ??
                transportLease?.selectedPort ??
                device.activePort;
            final endpoint = endpointAddress == null
                ? null
                : '$endpointAddress:$endpointPort';
            final availabilityStatus = availability == null
                ? 'not probed'
                : availability.status.name;
            final failure = availability?.errorMessage?.trim();
            final lines = <String>[
              '${device.nickname} (${device.platform})',
              'Backends: ${sourceLabels.isEmpty ? 'unknown' : sourceLabels.join(', ')}',
              'Addresses: ${device.ipAddresses.join(', ')}',
              'Chosen family: ${device.preferredAddressFamily}',
              if (sourceAges.isNotEmpty)
                'Discovery ages: ${sourceAges.join(', ')}',
              if (endpoint != null)
                'Last verified: $endpoint [$availabilityStatus]',
              if (endpoint == null) 'Availability: $availabilityStatus',
              if (transportLease != null)
                'Transport lease: ${_relativeAge(now.difference(transportLease.lastSuccessfulActivityAt))}',
              if (failure != null && failure.isNotEmpty)
                'Last failure: $failure',
            ];
            return lines.join('\n');
          })
          .toList(growable: false);

      final lastScanText = health.lastScanAt == null
          ? l10n.discoveryStatusNoScanYet
          : l10n.discoveryStatusLastScan(
              materialLocalizations.formatTimeOfDay(
                TimeOfDay.fromDateTime(health.lastScanAt!.toLocal()),
              ),
            );

      final firewallText = switch (health.firewallSetupResult.status) {
        FirewallSetupStatus.notRequired => l10n.discoveryFirewallNotRequired,
        FirewallSetupStatus.alreadyConfigured => l10n.discoveryFirewallReady,
        FirewallSetupStatus.configuredNow =>
          l10n.discoveryFirewallConfiguredNow,
        FirewallSetupStatus.denied => l10n.discoveryFirewallDenied,
        FirewallSetupStatus.failed => l10n.discoveryFirewallFailed(
          health.firewallSetupResult.message ?? l10n.sendErrorUnknown,
        ),
      };

      return AlertDialog(
        title: Text(l10n.nearbyTroubleshootTitle),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _DetailLine(
                  label: l10n.nearbyTechnicalStatusLabel,
                  value: _statusText(l10n, health),
                ),
                _DetailLine(
                  label: l10n.nearbyTechnicalDevicesLabel,
                  value: l10n.nearbyTechnicalDevicesValue(
                    health.discoveredDeviceCount,
                    health.verifiedSendReadyPeerCount,
                  ),
                ),
                _DetailLine(
                  label: l10n.nearbyTechnicalListeningPortLabel,
                  value: health.boundPort == null
                      ? l10n.discoveryStatusPortPending
                      : l10n.discoveryStatusListeningPort(health.boundPort!),
                ),
                _DetailLine(
                  label: l10n.nearbyTechnicalInterfacesLabel,
                  value: l10n.discoveryStatusInterfaces(
                    health.interfaceCount,
                    health.lastScanTargetCount,
                  ),
                ),
                _DetailLine(
                  label: l10n.nearbyTechnicalPacketsLabel,
                  value: l10n.discoveryStatusPackets(
                    health.packetsSent,
                    health.packetsReceived,
                  ),
                ),
                _DetailLine(
                  label: l10n.nearbyTechnicalBackendsLabel,
                  value: backendLabels.isEmpty
                      ? health.backend
                      : backendLabels.join(', '),
                ),
                if (healthyBackendLabels.isNotEmpty)
                  _DetailLine(
                    label: 'Healthy backends',
                    value: healthyBackendLabels.join(', '),
                  ),
                if (degradedBackendLabels.isNotEmpty)
                  _DetailLine(
                    label: 'Degraded backends',
                    value: degradedBackendLabels.join(', '),
                  ),
                if (peerCounts.isNotEmpty)
                  _DetailLine(
                    label: l10n.nearbyTechnicalPerBackendLabel,
                    value: peerCounts.join(' • '),
                  ),
                _DetailLine(
                  label: l10n.nearbyTechnicalLastScanLabel,
                  value: lastScanText,
                ),
                if (Platform.isWindows)
                  _DetailLine(
                    label: l10n.nearbyTechnicalFirewallLabel,
                    value: firewallText,
                  ),
                if (health.lastPermissionIssue != null &&
                    health.lastPermissionIssue!.trim().isNotEmpty)
                  _DetailLine(
                    label: l10n.nearbyTechnicalPermissionLabel,
                    value: health.lastPermissionIssue!,
                  ),
                if (health.lastError != null &&
                    health.lastError!.trim().isNotEmpty)
                  _DetailLine(
                    label: l10n.nearbyTechnicalIssueLabel,
                    value: health.lastError!,
                  ),
                if (backendErrors.isNotEmpty)
                  _DetailLine(
                    label: l10n.nearbyTechnicalBackendIssuesLabel,
                    value: backendErrors.join('\n'),
                  ),
                if (backendMessages.isNotEmpty)
                  _DetailLine(
                    label: l10n.nearbyTechnicalRecentMessagesLabel,
                    value: backendMessages.join('\n'),
                  ),
                if (peerDetails.isNotEmpty)
                  _DetailLine(
                    label: 'Visible peers',
                    value: peerDetails.join('\n\n'),
                  ),
              ],
            ),
          ),
        ),
        actions: <Widget>[
          if (Platform.isWindows &&
              health.firewallSetupResult.isFailure &&
              onRepairFirewall != null)
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                onRepairFirewall();
              },
              child: Text(l10n.repairFirewallButton),
            ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.closeButtonLabel),
          ),
        ],
      );
    },
  );
}

String _statusText(AppLocalizations l10n, DiscoveryHealth health) {
  if (health.isPaused &&
      health.pauseReason == DiscoveryPauseReason.backgrounded) {
    return l10n.nearbyStatusPaused;
  }
  if (health.verifiedSendReadyPeerCount > 0) {
    return l10n.nearbyStatusReady;
  }
  if (health.hasBlockingIssue) {
    return l10n.nearbyStatusNeedsAttention;
  }
  if (health.isStarting || health.isScanning || health.lastScanAt == null) {
    return l10n.nearbyStatusScanning;
  }
  if (health.hasHealthyBackend && health.discoveredDeviceCount == 0) {
    return l10n.nearbyStatusNoDevices;
  }
  if (health.hasHealthyBackend || health.isRunning) {
    return l10n.nearbyStatusScanning;
  }
  return l10n.nearbyStatusNeedsAttention;
}

String _backendLabel(DiscoveryBackendKind kind) {
  return switch (kind) {
    DiscoveryBackendKind.androidNsd => 'Android NSD',
    DiscoveryBackendKind.appleBonjour => 'Apple Bonjour',
    DiscoveryBackendKind.udpLan => 'UDP LAN',
  };
}

String _relativeAge(Duration age) {
  if (age.inSeconds <= 1) {
    return 'just now';
  }
  if (age.inSeconds < 60) {
    return '${age.inSeconds}s ago';
  }
  if (age.inMinutes < 60) {
    return '${age.inMinutes}m ago';
  }
  return '${age.inHours}h ago';
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          SelectableText(value),
        ],
      ),
    );
  }
}
