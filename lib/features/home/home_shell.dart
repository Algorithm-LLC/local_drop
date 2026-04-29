import 'package:flutter/material.dart';
import 'package:local_drop/l10n/app_localizations.dart';

import '../../models/transfer_models.dart';
import '../../state/app_controller.dart';
import '../../widgets/incoming_transfer_dialog.dart';
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
  String? _activeIncomingReviewTransferId;

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
                body: _buildBodyWithIncomingBanner(
                  context,
                  IndexedStack(index: selectedIndex, children: pages),
                ),
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
                    child: _buildBodyWithIncomingBanner(
                      context,
                      IndexedStack(index: selectedIndex, children: pages),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildBodyWithIncomingBanner(BuildContext context, Widget child) {
    final pending = widget.controller.pendingIncomingTransferSessions;
    if (pending.isEmpty) {
      return child;
    }
    final session = pending.first;
    return Column(
      children: <Widget>[
        _IncomingRequestBanner(
          session: session,
          onReview: () => _showIncomingApprovalDialog(session),
        ),
        Expanded(child: child),
      ],
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

  Future<void> _showIncomingApprovalDialog(
    IncomingTransferSession session,
  ) async {
    if (_activeIncomingReviewTransferId == session.transferId) {
      return;
    }
    setState(() {
      _activeIncomingReviewTransferId = session.transferId;
    });
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AnimatedBuilder(
            animation: widget.controller,
            builder: (context, _) {
              final current = widget.controller.pendingIncomingTransferSessions
                  .cast<IncomingTransferSession?>()
                  .firstWhere(
                    (item) => item?.transferId == session.transferId,
                    orElse: () => null,
                  );
              if (current == null) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (Navigator.of(dialogContext).canPop()) {
                    Navigator.of(dialogContext).pop();
                  }
                });
                return const SizedBox.shrink();
              }
              return IncomingTransferDialog(
                controller: widget.controller,
                session: current,
              );
            },
          );
        },
      );
    } finally {
      if (mounted) {
        setState(() {
          _activeIncomingReviewTransferId = null;
        });
      }
    }
  }
}

class _IncomingRequestBanner extends StatelessWidget {
  const _IncomingRequestBanner({
    required this.session,
    required this.onReview,
  });

  final IncomingTransferSession session;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      bottom: false,
      child: Material(
        color: colorScheme.tertiaryContainer.withValues(alpha: 0.92),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: <Widget>[
              Icon(Icons.download_for_offline, color: colorScheme.tertiary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${l10n.incomingRequestsTitle}: ${session.senderNickname}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: onReview,
                child: const Text('Review'),
              ),
            ],
          ),
        ),
      ),
    );
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
