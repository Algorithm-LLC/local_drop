import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_drop/l10n/app_localizations.dart';

import '../../models/app_preferences.dart';
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
                          onPressed: widget.controller.pickSaveDirectory,
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
