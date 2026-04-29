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
import '../widgets/incoming_transfer_dialog.dart';

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
              return IncomingTransferDialog(
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
