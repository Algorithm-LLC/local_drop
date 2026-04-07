import 'dart:io';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:local_drop/l10n/app_localizations.dart';

import '../core/theme/app_theme.dart';
import '../features/home/home_shell.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../models/transfer_models.dart';
import '../state/app_controller.dart';

class LocalDropApp extends StatefulWidget {
  const LocalDropApp({super.key});

  @override
  State<LocalDropApp> createState() => _LocalDropAppState();
}

class _LocalDropAppState extends State<LocalDropApp>
    with WidgetsBindingObserver {
  late final AppController _controller;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  String? _activeIncomingDialogTransferId;
  bool _scheduledInitialNetworkWarmup = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = AppController();
    _controller.addListener(_onControllerChanged);
    unawaited(_initializeController());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!(Platform.isAndroid || Platform.isIOS)) {
      return;
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      unawaited(_controller.pauseDiscoveryForBackground());
      return;
    }
    if (state == AppLifecycleState.resumed) {
      unawaited(_controller.resumeDiscoveryFromForeground());
      _presentIncomingDialogIfNeeded();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    _scheduleNetworkWarmupAfterFirstFrame();
    _presentIncomingDialogIfNeeded();
  }

  Future<void> _initializeController() async {
    await _controller.initialize();
    _scheduleNetworkWarmupAfterFirstFrame();
  }

  void _scheduleNetworkWarmupAfterFirstFrame() {
    if (!mounted ||
        _scheduledInitialNetworkWarmup ||
        !_controller.isInitialized ||
        _controller.needsOnboarding) {
      return;
    }
    _scheduledInitialNetworkWarmup = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(_controller.ensureNetworkWarmupStarted());
    });
  }

  void _presentIncomingDialogIfNeeded() {
    if (!mounted || !_controller.isInitialized) {
      return;
    }
    final pending = _controller.pendingIncomingTransferSessions;
    if (pending.isEmpty) {
      return;
    }
    final session = pending.first;
    if (_activeIncomingDialogTransferId == session.transferId) {
      return;
    }

    final navigator = _navigatorKey.currentState;
    final dialogContext = navigator?.overlay?.context;
    if (navigator == null || dialogContext == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _presentIncomingDialogIfNeeded();
        }
      });
      return;
    }

    _activeIncomingDialogTransferId = session.transferId;
    unawaited(_controller.requestIncomingDialogAttention());
    unawaited(
      showDialog<void>(
        context: dialogContext,
        barrierDismissible: false,
        builder: (context) {
          return AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final current = _controller.pendingIncomingTransferSessions
                  .cast<IncomingTransferSession?>()
                  .firstWhere(
                    (item) => item?.transferId == session.transferId,
                    orElse: () => null,
                  );
              if (current == null) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  }
                });
                return const SizedBox.shrink();
              }
              return _IncomingTransferDialog(
                controller: _controller,
                session: current,
              );
            },
          );
        },
      ).whenComplete(() {
        _activeIncomingDialogTransferId = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _presentIncomingDialogIfNeeded();
          }
        });
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return MaterialApp(
          navigatorKey: _navigatorKey,
          debugShowCheckedModeBanner: false,
          title: 'LocalDrop',
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: _controller.preferences.themePreference.toThemeMode,
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const <Locale>[Locale('en')],
          home: _buildHome(),
        );
      },
    );
  }

  Widget _buildHome() {
    if (_controller.fatalError != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_controller.fatalError!),
          ),
        ),
      );
    }
    if (!_controller.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_controller.needsOnboarding) {
      return OnboardingScreen(controller: _controller);
    }
    return HomeShell(controller: _controller);
  }
}

class _IncomingTransferDialog extends StatefulWidget {
  const _IncomingTransferDialog({
    required this.controller,
    required this.session,
  });

  final AppController controller;
  final IncomingTransferSession session;

  @override
  State<_IncomingTransferDialog> createState() =>
      _IncomingTransferDialogState();
}

class _IncomingTransferDialogState extends State<_IncomingTransferDialog> {
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final session = widget.session;
    final remaining = session.remainingApprovalTime.inSeconds;
    return AlertDialog(
      title: Text(l10n.incomingRequestsTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            l10n.incomingRequestMessage(
              session.senderNickname,
              session.items.length,
            ),
          ),
          const SizedBox(height: 8),
          Text(l10n.incomingRequestSize(_formatBytes(session.totalBytes))),
          const SizedBox(height: 8),
          Text(l10n.incomingRequestExpiresIn(remaining.clamp(0, 60))),
          if ((_errorMessage ?? '').trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              _errorMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _isSubmitting ? null : _handleDecline,
          child: Text(l10n.declineButton),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : _handleAccept,
          child: Text(l10n.acceptButton),
        ),
      ],
    );
  }

  Future<void> _handleAccept() async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    final result = await widget.controller.acceptIncoming(
      widget.session.transferId,
    );
    if (!mounted) {
      return;
    }
    if (result.success) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _isSubmitting = false;
      _errorMessage = result.message ?? 'Could not accept the transfer.';
    });
  }

  Future<void> _handleDecline() async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    final result = await widget.controller.declineIncoming(
      widget.session.transferId,
    );
    if (!mounted) {
      return;
    }
    if (result.success) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _isSubmitting = false;
      _errorMessage = result.message ?? 'Could not decline the transfer.';
    });
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
}
