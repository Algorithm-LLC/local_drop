import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_drop/l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_links.dart';
import '../../models/app_preferences.dart';
import '../../models/picker_failure.dart';
import '../../state/app_controller.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _nicknameController;
  late String _lastSyncedNickname;
  bool _savingNickname = false;

  @override
  void initState() {
    super.initState();
    _lastSyncedNickname = widget.controller.preferences.nickname;
    _nicknameController = TextEditingController(
      text: _lastSyncedNickname,
    );
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
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.55,
                    ),
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
        const SizedBox(height: 12),
        Card(
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
                  value: widget.controller.diagnosticsLogPath ?? '-',
                ),
                const SizedBox(height: 8),
                _CopyLine(
                  label: 'Active transfer port',
                  value: '${widget.controller.activePort}',
                ),
                if (widget.controller.recentDiagnostics.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    'Latest transfer diagnostic',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(widget.controller.recentDiagnostics.first.peerNickname),
                  const SizedBox(height: 4),
                  Text(
                    'Stage: ${widget.controller.recentDiagnostics.first.stage.name}',
                  ),
                  if ((widget.controller.recentDiagnostics.first.errorMessage ??
                          '')
                      .trim()
                      .isNotEmpty) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(
                      widget.controller.recentDiagnostics.first.errorMessage!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ] else
                  const Text('No transfer diagnostics have been captured yet.'),
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
                const SizedBox(height: 16),
                Text(
                  l10n.securityModelTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(l10n.securityModelDescription),
              ],
            ),
          ),
        ),
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
