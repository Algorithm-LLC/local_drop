import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_drop/l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_links.dart';
import '../../core/security/fingerprint_codes.dart';
import '../../models/app_preferences.dart';
import '../../models/peer_presence_models.dart';
import '../../models/picker_failure.dart';
import '../../models/transfer_diagnostics_snapshot.dart';
import '../../services/transfer_pin_service.dart';
import '../../state/app_controller.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _nicknameController;
  late final TextEditingController _pinController;
  late final TextEditingController _confirmPinController;
  late String _lastSyncedNickname;
  bool _savingNickname = false;
  bool _savingPin = false;
  String? _pinErrorText;

  @override
  void initState() {
    super.initState();
    _lastSyncedNickname = widget.controller.preferences.nickname;
    _nicknameController = TextEditingController(text: _lastSyncedNickname);
    _pinController = TextEditingController();
    _confirmPinController = TextEditingController();
  }

  @override
  void didUpdateWidget(covariant SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final savedNickname = widget.controller.preferences.nickname;
    if (savedNickname != _lastSyncedNickname) {
      _lastSyncedNickname = savedNickname;
      _nicknameController.value = TextEditingValue(
        text: savedNickname,
        selection: TextSelection.collapsed(offset: savedNickname.length),
      );
    }
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _pinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final identity = widget.controller.identity;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  l10n.nicknameLabel,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        controller: _nicknameController,
                        maxLength: 24,
                        decoration: InputDecoration(
                          labelText: l10n.nicknameLabel,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton(
                      onPressed: _savingNickname ? null : _saveNickname,
                      child: _savingNickname
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(l10n.saveButton),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  'Transfer PIN',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _pinController,
                  maxLength: TransferPinService.maxPinLength,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  decoration: InputDecoration(
                    labelText: 'New PIN',
                    helperText: TransferPinService.pinRequirementsLabel,
                    errorText: _pinErrorText,
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _confirmPinController,
                  maxLength: TransferPinService.maxPinLength,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  decoration: const InputDecoration(labelText: 'Confirm PIN'),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: _savingPin ? null : _saveTransferPin,
                    child: _savingPin
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save PIN'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        Icons.devices_other_rounded,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            l10n.websiteLinkLabel,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            l10n.websiteLinkDescription,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  child: Text(
                    AppLinks.website,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final actionButtons = Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      alignment: WrapAlignment.end,
                      children: <Widget>[
                        FilledButton.icon(
                          onPressed: _openWebsite,
                          icon: const Icon(Icons.open_in_new),
                          label: Text(l10n.openWebsiteButton),
                        ),
                        OutlinedButton.icon(
                          onPressed: _copyWebsiteLink,
                          icon: const Icon(Icons.copy),
                          label: Text(l10n.copyLinkButton),
                        ),
                      ],
                    );
                    if (constraints.maxWidth < 560) {
                      return Align(
                        alignment: Alignment.centerRight,
                        child: actionButtons,
                      );
                    }
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: <Widget>[Expanded(child: actionButtons)],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  l10n.themeSection,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                SegmentedButton<AppThemePreference>(
                  selected: <AppThemePreference>{
                    widget.controller.preferences.themePreference,
                  },
                  onSelectionChanged: (selected) {
                    final preference = selected.first;
                    widget.controller.setThemePreference(preference);
                  },
                  segments: <ButtonSegment<AppThemePreference>>[
                    ButtonSegment<AppThemePreference>(
                      value: AppThemePreference.system,
                      label: Text(l10n.themeSystem),
                    ),
                    ButtonSegment<AppThemePreference>(
                      value: AppThemePreference.light,
                      label: Text(l10n.themeLight),
                    ),
                    ButtonSegment<AppThemePreference>(
                      value: AppThemePreference.dark,
                      label: Text(l10n.themeDark),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.saveDirectoryLabel,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final actionButtons = Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.end,
                      children: <Widget>[
                        TextButton.icon(
                          onPressed: widget.controller.useDefaultSaveDirectory,
                          icon: const Icon(Icons.download_for_offline_outlined),
                          label: Text(l10n.useDefaultDirectoryButton),
                        ),
                        OutlinedButton.icon(
                          onPressed: _pickSaveDirectory,
                          icon: const Icon(Icons.folder_open),
                          label: Text(l10n.pickDirectoryButton),
                        ),
                      ],
                    );
                    if (constraints.maxWidth < 640) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            widget.controller.preferences.saveDirectory ?? '-',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerRight,
                            child: actionButtons,
                          ),
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              widget.controller.preferences.saveDirectory ??
                                  '-',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Flexible(child: actionButtons),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  l10n.identitySection,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                _CopyLine(
                  label: l10n.deviceIdLabel,
                  value: identity?.deviceId ?? '-',
                ),
                const SizedBox(height: 8),
                _CopyLine(
                  label: l10n.fingerprintLabel,
                  value: identity?.fingerprint ?? '-',
                ),
                const SizedBox(height: 12),
                _LocalSecurityCodeCard(code: widget.controller.localSecurityCode),
                const SizedBox(height: 16),
                Text(
                  l10n.securityModelTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(l10n.securityModelDescription),
                const SizedBox(height: 18),
                Text(
                  'Trusted devices',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (widget.controller.trustedPeers.isEmpty)
                  Text(
                    'Devices appear here after you confirm the security code and complete an encrypted transfer.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  )
                else
                  ...widget.controller.trustedPeers.map(
                    (peer) => _TrustedPeerTile(
                      peer: peer,
                      onForget: () => _forgetTrustedPeer(peer),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _SupportDiagnosticsCard(controller: widget.controller),
      ],
    );
  }

  Future<void> _saveNickname() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _savingNickname = true;
    });
    await widget.controller.saveNickname(_nicknameController.text);
    if (!mounted) {
      return;
    }
    _lastSyncedNickname = widget.controller.preferences.nickname;
    setState(() {
      _savingNickname = false;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.nicknameSaved)));
  }

  Future<void> _saveTransferPin() async {
    final pin = _pinController.text.trim();
    final confirmPin = _confirmPinController.text.trim();
    if (!TransferPinService.isValidPin(pin) || pin != confirmPin) {
      setState(() {
        _pinErrorText = pin == confirmPin
            ? 'Enter ${TransferPinService.pinRequirementsLabel}.'
            : 'PINs do not match.';
      });
      return;
    }
    setState(() {
      _savingPin = true;
      _pinErrorText = null;
    });
    final saved = await widget.controller.saveTransferPin(pin);
    if (!mounted) {
      return;
    }
    _pinController.clear();
    _confirmPinController.clear();
    setState(() {
      _savingPin = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(saved ? 'Transfer PIN saved' : 'Invalid PIN')),
    );
  }

  Future<void> _forgetTrustedPeer(TrustedPeerRecord peer) async {
    await widget.controller.forgetTrustedPeer(peer.deviceId);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('${peer.nickname} forgotten.')));
  }

  Future<void> _openWebsite() async {
    final l10n = AppLocalizations.of(context)!;
    final opened = await launchUrl(
      Uri.parse(AppLinks.website),
      mode: LaunchMode.externalApplication,
    );
    if (!mounted || opened) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.websiteOpenFailed)));
  }

  void _copyWebsiteLink() {
    final l10n = AppLocalizations.of(context)!;
    Clipboard.setData(const ClipboardData(text: AppLinks.website));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.copied)));
  }

  Future<void> _pickSaveDirectory() async {
    final l10n = AppLocalizations.of(context)!;
    try {
      await widget.controller.pickSaveDirectory();
    } on PickerFailure catch (error) {
      if (!mounted) {
        return;
      }
      final message = error.isMacOSAvailabilityIssue
          ? l10n.macosDirectoryPickerUnavailable
          : l10n.directoryPickerOpenFailed;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }
}

class _SupportDiagnosticsCard extends StatelessWidget {
  const _SupportDiagnosticsCard({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final latestDiagnostics = controller.recentDiagnostics.isEmpty
        ? null
        : controller.recentDiagnostics.first;
    final leases = controller.transportVerifiedPeerLeases.values.toList()
      ..sort(
        (a, b) =>
            b.lastSuccessfulActivityAt.compareTo(a.lastSuccessfulActivityAt),
      );
    final latestLease = leases.isEmpty ? null : leases.first;
    TransferDiagnosticsSnapshot? latestFailure;
    for (final diagnostics in controller.recentDiagnostics) {
      if ((diagnostics.errorMessage ?? '').trim().isNotEmpty ||
          diagnostics.terminalReason != null) {
        latestFailure = diagnostics;
        break;
      }
    }
    final hasDiscoveryRoute = controller.nearbyDevices.any(
      (device) => device.discoverySources.isNotEmpty,
    );
    final routeSource = latestLease == null
        ? (hasDiscoveryRoute ? 'Discovery' : '-')
        : (hasDiscoveryRoute
              ? 'Discovery + recent verified lease'
              : 'Recent verified lease');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Support and diagnostics',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            _CopyLine(
              label: 'Transport log',
              value: controller.diagnosticsLogPath ?? '-',
            ),
            const SizedBox(height: 8),
            _CopyLine(
              label: 'Active transfer port',
              value: '${controller.activePort}',
            ),
            const SizedBox(height: 8),
            _CopyLine(label: 'Route source', value: routeSource),
            const SizedBox(height: 8),
            _CopyLine(
              label: 'Last successful route',
              value: latestLease == null ? '-' : _formatLeaseRoute(latestLease),
            ),
            const SizedBox(height: 8),
            _CopyLine(
              label: 'Last failed route',
              value: latestFailure == null
                  ? '-'
                  : _formatFailureRoute(latestFailure),
            ),
            if (latestDiagnostics != null) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                'Latest transfer diagnostic',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(latestDiagnostics.peerNickname),
              const SizedBox(height: 4),
              Text('Stage: ${latestDiagnostics.stage.name}'),
              if ((latestDiagnostics.errorMessage ?? '')
                  .trim()
                  .isNotEmpty) ...<Widget>[
                const SizedBox(height: 4),
                Text(
                  latestDiagnostics.errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ] else
              const Text('No transfer diagnostics have been captured yet.'),
          ],
        ),
      ),
    );
  }

  String _formatLeaseRoute(TransportVerifiedPeerLease lease) {
    final nickname = lease.profile.nickname.trim().isNotEmpty
        ? lease.profile.nickname.trim()
        : lease.deviceId;
    final address =
        lease.selectedAddress?.trim().isNotEmpty == true
        ? lease.selectedAddress!.trim()
        : lease.profile.ipAddress.trim();
    final port =
        lease.selectedPort ?? lease.profile.securePort ?? lease.profile.activePort;
    final route = address.isEmpty || port <= 0 ? 'unknown route' : '$address:$port';
    return '$nickname @ $route (${_formatAge(lease.lastSuccessfulActivityAt)} ago)';
  }

  String _formatFailureRoute(TransferDiagnosticsSnapshot diagnostics) {
    final nickname = diagnostics.peerNickname.trim().isNotEmpty
        ? diagnostics.peerNickname.trim()
        : diagnostics.peerDeviceId;
    final address = diagnostics.selectedAddress?.trim() ?? '';
    final port = diagnostics.selectedPort;
    final route = address.isEmpty || port == null || port <= 0
        ? 'unknown route'
        : '$address:$port';
    final reason =
        (diagnostics.errorMessage ?? '').trim().isNotEmpty
        ? diagnostics.errorMessage!.trim()
        : diagnostics.terminalReason?.name ?? diagnostics.stage.name;
    return '$nickname @ $route - $reason';
  }

  String _formatAge(DateTime timestamp) {
    final elapsed = DateTime.now().difference(timestamp);
    if (elapsed.inSeconds < 60) {
      return '${elapsed.inSeconds}s';
    }
    if (elapsed.inMinutes < 60) {
      return '${elapsed.inMinutes}m';
    }
    if (elapsed.inHours < 24) {
      return '${elapsed.inHours}h';
    }
    return '${elapsed.inDays}d';
  }
}

class _LocalSecurityCodeCard extends StatelessWidget {
  const _LocalSecurityCodeCard({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hasCode = code.trim().isNotEmpty && code != '-';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.28),
        ),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.verified_user_outlined, color: colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'This device security code',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Compare this with the code shown for this device on another LocalDrop screen.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  hasCode ? code : '-',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: hasCode
                ? () {
                    final l10n = AppLocalizations.of(context)!;
                    Clipboard.setData(ClipboardData(text: code));
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(l10n.copied)));
                  }
                : null,
            icon: const Icon(Icons.copy),
          ),
        ],
      ),
    );
  }
}

class _CopyLine extends StatelessWidget {
  const _CopyLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(label, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 2),
              Text(value, maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        IconButton(
          onPressed: value == '-'
              ? null
              : () {
                  final l10n = AppLocalizations.of(context)!;
                  Clipboard.setData(ClipboardData(text: value));
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(l10n.copied)));
                },
          icon: const Icon(Icons.copy),
        ),
      ],
    );
  }
}

class _TrustedPeerTile extends StatelessWidget {
  const _TrustedPeerTile({required this.peer, required this.onForget});

  final TrustedPeerRecord peer;
  final VoidCallback onForget;

  @override
  Widget build(BuildContext context) {
    final verifiedAt = MaterialLocalizations.of(
      context,
    ).formatShortDate(peer.lastVerifiedAt.toLocal());
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.verified_user_outlined),
        title: Text(peer.nickname.isEmpty ? peer.deviceId : peer.nickname),
        subtitle: Text(
          'Code ${shortSecurityCodeForFingerprint(peer.certFingerprint)} - verified $verifiedAt',
        ),
        trailing: TextButton(onPressed: onForget, child: const Text('Forget')),
      ),
    );
  }
}
