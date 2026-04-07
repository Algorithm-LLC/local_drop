import 'package:flutter/material.dart';
import 'package:local_drop/l10n/app_localizations.dart';

import '../../state/app_controller.dart';
import '../history/history_page.dart';
import '../nearby/nearby_page.dart';
import '../settings/settings_page.dart';
import '../transfers/transfers_page.dart';

enum _HomeTab { nearby, history, settings }

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.controller});

  final AppController controller;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  _HomeTab _selectedTab = _HomeTab.nearby;
  final Set<String> _seenIncomingTransferIds = <String>{};
  bool _isTransfersModalOpen = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        _maybePresentIncomingTransfersModal();

        final l10n = AppLocalizations.of(context)!;
        final destinations = <_ShellDestination>[
          _ShellDestination(
            tab: _HomeTab.nearby,
            page: NearbyPage(
              controller: widget.controller,
              onOpenTransfers: _showTransfersModal,
            ),
            icon: const Icon(Icons.radar),
            label: l10n.nearbyTab,
          ),
          _ShellDestination(
            tab: _HomeTab.history,
            page: HistoryPage(controller: widget.controller),
            icon: const Icon(Icons.history),
            label: l10n.historyTab,
          ),
          _ShellDestination(
            tab: _HomeTab.settings,
            page: SettingsPage(controller: widget.controller),
            icon: const Icon(Icons.settings),
            label: l10n.settingsTab,
          ),
        ];

        final selectedIndex = destinations.indexWhere(
          (destination) => destination.tab == _selectedTab,
        );
        final pages = destinations
            .map((item) => item.page)
            .toList(growable: false);
        final navigationDestinations = destinations
            .map(
              (destination) => NavigationDestination(
                icon: destination.icon,
                label: destination.label,
              ),
            )
            .toList(growable: false);
        final railDestinations = destinations
            .map(
              (destination) => NavigationRailDestination(
                icon: destination.icon,
                label: Text(destination.label),
              ),
            )
            .toList(growable: false);

        void onDestinationSelected(int value) {
          setState(() {
            _selectedTab = destinations[value].tab;
          });
          widget.controller.triggerDiscoveryScan();
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 1000;
            final transferChip = _buildTransferChip(context, wide: wide);
            if (!wide) {
              return Scaffold(
                appBar: AppBar(title: Text(l10n.appTitle)),
                body: IndexedStack(index: selectedIndex, children: pages),
                bottomNavigationBar: NavigationBar(
                  selectedIndex: selectedIndex,
                  destinations: navigationDestinations,
                  onDestinationSelected: onDestinationSelected,
                ),
                floatingActionButton: transferChip,
                floatingActionButtonLocation:
                    FloatingActionButtonLocation.centerFloat,
              );
            }

            return Scaffold(
              floatingActionButton: transferChip,
              floatingActionButtonLocation:
                  FloatingActionButtonLocation.endFloat,
              body: Row(
                children: <Widget>[
                  SafeArea(
                    child: NavigationRail(
                      selectedIndex: selectedIndex,
                      labelType: NavigationRailLabelType.selected,
                      onDestinationSelected: onDestinationSelected,
                      destinations: railDestinations,
                    ),
                  ),
                  Expanded(
                    child: IndexedStack(index: selectedIndex, children: pages),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _maybePresentIncomingTransfersModal() {
    final incomingIds = widget.controller.activeTransfers
        .where((item) => item.isIncoming)
        .map((item) => item.transferId)
        .toSet();
    final unseenIncomingIds = incomingIds.difference(_seenIncomingTransferIds);
    if (unseenIncomingIds.isNotEmpty) {
      _seenIncomingTransferIds.addAll(unseenIncomingIds);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showTransfersModal();
        }
      });
    }
  }

  Widget? _buildTransferChip(BuildContext context, {required bool wide}) {
    final activeTransfers = widget.controller.activeTransfers;
    if (activeTransfers.isEmpty) {
      return null;
    }

    final l10n = AppLocalizations.of(context)!;
    final primaryTransfer = activeTransfers.first;
    final label = activeTransfers.length == 1
        ? '${l10n.currentTransferTitle}: ${primaryTransfer.peerNickname}'
        : '${activeTransfers.length} ${l10n.transfersTab}';

    return SafeArea(
      minimum: EdgeInsets.only(bottom: wide ? 0 : 18),
      child: FilledButton.icon(
        onPressed: _showTransfersModal,
        icon: const Icon(Icons.swap_horizontal_circle),
        label: Text(label, overflow: TextOverflow.ellipsis),
      ),
    );
  }

  Future<void> _showTransfersModal() async {
    if (_isTransfersModalOpen) {
      return;
    }
    setState(() {
      _isTransfersModalOpen = true;
    });
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _TransfersModalPage(controller: widget.controller),
      ),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _isTransfersModalOpen = false;
    });
  }
}

class _ShellDestination {
  const _ShellDestination({
    required this.tab,
    required this.page,
    required this.icon,
    required this.label,
  });

  final _HomeTab tab;
  final Widget page;
  final Widget icon;
  final String label;
}

class _TransfersModalPage extends StatelessWidget {
  const _TransfersModalPage({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.transfersTab)),
      body: AnimatedBuilder(
        animation: controller,
        builder: (context, _) => TransfersPage(controller: controller),
      ),
    );
  }
}
