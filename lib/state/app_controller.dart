import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:uuid/uuid.dart';

import '../core/constants/network_constants.dart';
import '../core/storage/app_store.dart';
import '../models/app_preferences.dart';
import '../models/device_profile.dart';
import '../models/discovery_health.dart';
import '../models/network_interface_snapshot.dart';
import '../models/peer_presence_models.dart';
import '../models/send_draft.dart';
import '../models/transfer_diagnostics_snapshot.dart';
import '../models/transfer_models.dart';
import '../services/discovery_service.dart';
import '../services/local_identity_service.dart';
import '../services/local_network_platform_service.dart';
import '../services/payload_builder.dart';
import '../services/transport_log_service.dart';
import '../services/transfer_client.dart';
import '../services/transfer_server.dart';

enum NetworkStartupState { idle, warmingUp, ready, degraded, failed }

class AppController extends ChangeNotifier {
  AppController({
    AppStore? store,
    LocalIdentityService? identityService,
    DiscoveryService? discoveryService,
    LocalNetworkPlatformService? localNetworkPlatformService,
    TransferClient? transferClient,
    PayloadBuilder? payloadBuilder,
    TransferServer? transferServer,
    TransportLogService? transportLogService,
    Future<String> Function()? appVersionLoader,
    Duration? discoveryRescanInterval,
    Duration? discoveryWatchdogThreshold,
    Duration? transportVerifiedPeerLeaseDuration,
    Duration? checkingPeerAvailabilityStaleTimeout,
  }) : _store = store ?? AppStore(),
       _identityService = identityService ?? LocalIdentityService(),
       _transferClient = transferClient ?? TransferClient(),
       _payloadBuilder = payloadBuilder ?? PayloadBuilder(),
       _transportLogService = transportLogService ?? TransportLogService(),
       _appVersionLoader = appVersionLoader ?? _loadAppVersionFromPlatform,
       _discoveryRescanInterval =
           discoveryRescanInterval ?? NetworkConstants.discoveryRescanInterval,
       _discoveryWatchdogThreshold =
           discoveryWatchdogThreshold ??
           NetworkConstants.discoveryWatchdogThreshold,
       _transportVerifiedPeerLeaseDuration =
           transportVerifiedPeerLeaseDuration ?? const Duration(seconds: 90),
       _checkingPeerAvailabilityStaleTimeout =
           checkingPeerAvailabilityStaleTimeout ?? const Duration(seconds: 6),
       _transferServer =
           transferServer ??
           TransferServer(
             onIncomingSessionChanged: (_) {},
             onProgress: (_) {},
             onRecord: (_) {},
             onDiagnostics: (_) {},
             resolveSaveDirectory: () async => '',
             nicknameProvider: () => 'LocalDrop',
           ) {
    _localNetworkPlatformService =
        localNetworkPlatformService ?? LocalNetworkPlatformService();
    _discoveryService =
        discoveryService ??
        DiscoveryService(
          loadInterfaces: _localNetworkPlatformService.listActiveInterfaces,
          platformService: _localNetworkPlatformService,
          logger: (message) {
            unawaited(
              _logTransportEvent(
                'discovery',
                message,
                data: <String, Object?>{
                  'backend': _discoveryHealth.backend,
                  'paused': _discoveryHealth.isPaused,
                },
              ),
            );
          },
        );
  }

  static const String _defaultAppVersion = '1.0.0';

  final AppStore _store;
  final LocalIdentityService _identityService;
  final TransferClient _transferClient;
  final PayloadBuilder _payloadBuilder;
  final TransportLogService _transportLogService;
  final Future<String> Function() _appVersionLoader;
  final TransferServer _transferServer;
  late final LocalNetworkPlatformService _localNetworkPlatformService;
  late final DiscoveryService _discoveryService;
  final Duration _discoveryRescanInterval;
  final Duration _discoveryWatchdogThreshold;
  final Duration _transportVerifiedPeerLeaseDuration;
  final Duration _checkingPeerAvailabilityStaleTimeout;

  static const Duration _stablePeerAvailabilityProbeCooldown = Duration(
    seconds: 12,
  );
  static const Duration _pendingPeerAvailabilityProbeCooldown = Duration(
    seconds: 3,
  );
  static const Duration _zeroPeerHealthSweepCooldown = Duration(seconds: 8);
  static const Duration _supplementalHealthSweepCooldown = Duration(
    seconds: 6,
  );
  static const int _zeroPeerHealthSweepConcurrency = 24;

  final Uuid _uuid = const Uuid();
  final Map<String, TransferProgress> _activeTransfers =
      <String, TransferProgress>{};
  final Map<String, IncomingTransferSession> _incomingSessionsById =
      <String, IncomingTransferSession>{};
  final Map<String, bool> _cancelTransferByKey = <String, bool>{};
  final Map<String, PeerAvailabilitySnapshot> _peerAvailabilityById =
      <String, PeerAvailabilitySnapshot>{};
  final Map<String, TransferDiagnosticsSnapshot> _diagnosticsByContextId =
      <String, TransferDiagnosticsSnapshot>{};
  final Map<String, TransportVerifiedPeerLease> _transportVerifiedPeerLeases =
      <String, TransportVerifiedPeerLease>{};
  final Map<String, Future<PeerAvailabilitySnapshot>>
  _peerAvailabilityProbeFutures = <String, Future<PeerAvailabilitySnapshot>>{};
  final Map<String, int> _peerAvailabilityProbeGenerations = <String, int>{};

  StreamSubscription<List<DeviceProfile>>? _discoverySubscription;
  StreamSubscription<DiscoveryHealth>? _discoveryHealthSubscription;
  Timer? _discoveryRescanTimer;
  bool _isDiscoveryRestarting = false;
  bool _isDiscoveryForegroundPaused = false;
  int _discoveryScanInFlightCount = 0;
  DateTime? _lastHealthyDiscoveryAt;
  bool _watchdogSoftRefreshPendingHardRestart = false;
  DateTime? _lastZeroPeerHealthSweepAt;
  bool _zeroPeerHealthSweepInFlight = false;
  bool _initialized = false;
  bool _isInitializing = false;
  String? _fatalError;
  NetworkStartupState _networkStartupState = NetworkStartupState.idle;
  bool _isNetworkWarmupInProgress = false;
  bool _hasStartedNetworkWarmup = false;
  bool _hasAttemptedFirewallSetupThisLaunch = false;
  bool _hasFirewallSetupIssue = false;
  int? _localBootstrapDurationMs;

  AppPreferences _preferences = const AppPreferences(
    nickname: '',
    themePreference: AppThemePreference.system,
    saveDirectory: null,
  );
  String _appVersion = _defaultAppVersion;
  LocalIdentity? _identity;
  int _activePort = NetworkConstants.primaryPort;
  List<DeviceProfile> _discoveredNearbyDevices = const <DeviceProfile>[];
  List<DeviceProfile> _nearbyDevices = const <DeviceProfile>[];
  DiscoveryHealth _discoveryHealth = const DiscoveryHealth();
  List<TransferRecord> _history = const <TransferRecord>[];
  SendDraft _sendDraft = const SendDraft.empty();

  bool get isInitialized => _initialized;
  bool get isInitializing => _isInitializing;
  String? get fatalError => _fatalError;
  NetworkStartupState get networkStartupState => _networkStartupState;
  bool get isNetworkWarmupInProgress => _isNetworkWarmupInProgress;
  bool get isNetworkReady =>
      _networkStartupState == NetworkStartupState.ready ||
      _networkStartupState == NetworkStartupState.degraded;

  AppPreferences get preferences => _preferences;
  LocalIdentity? get identity => _identity;
  int get activePort => _activePort;
  List<DeviceProfile> get nearbyDevices => _nearbyDevices;
  DiscoveryHealth get discoveryHealth => _discoveryHealth;
  Map<String, TransportVerifiedPeerLease> get transportVerifiedPeerLeases =>
      Map<String, TransportVerifiedPeerLease>.unmodifiable(
        _transportVerifiedPeerLeases,
      );
  DiscoveryBackendState get discoveryBackendState =>
      _discoveryHealth.backendState;
  SendDraft get sendDraft => _sendDraft;
  List<TransferRecord> get history => _history;
  bool get needsOnboarding => _preferences.needsOnboarding;
  String? get diagnosticsLogPath => _transportLogService.logFilePath;
  bool get isDiscoveryPaused => _discoveryHealth.isPaused;
  int get verifiedSendReadyPeerCount =>
      _discoveryHealth.verifiedSendReadyPeerCount;

  List<TransferProgress> get activeTransfers =>
      _activeTransfers.values.toList(growable: false)
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  List<IncomingTransferSession> get incomingTransferSessions =>
      _incomingSessionsById.values.toList(growable: false)..sort((a, b) {
        final pendingOrder = a.isPending == b.isPending
            ? 0
            : (a.isPending ? -1 : 1);
        if (pendingOrder != 0) {
          return pendingOrder;
        }
        return b.receivedAt.compareTo(a.receivedAt);
      });

  List<IncomingTransferSession> get pendingIncomingTransferSessions =>
      incomingTransferSessions
          .where((item) => item.isPending)
          .toList(growable: false);

  List<TransferDiagnosticsSnapshot> get recentDiagnostics =>
      _diagnosticsByContextId.values.toList(growable: false)
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  TransferProgress? get currentOutgoingSendProgress {
    final outgoing = activeTransfers.where((item) => !item.isIncoming);
    if (outgoing.isEmpty) {
      return null;
    }
    return outgoing.first;
  }

  TransferStage? get currentOutgoingTransferStage =>
      currentOutgoingSendProgress?.stage;

  String? get currentOutgoingTransferError =>
      currentOutgoingSendProgress?.errorMessage;

  TransferDiagnosticsSnapshot? get currentOutgoingTransferDiagnostics {
    final progress = currentOutgoingSendProgress;
    if (progress == null) {
      return null;
    }
    return diagnosticsForTransfer(progress.transferId);
  }

  String get localNickname {
    final nickname = _preferences.nickname.trim();
    if (nickname.isNotEmpty) {
      return nickname;
    }
    return 'LocalDrop';
  }

  static Future<String> _loadAppVersionFromPlatform() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final version = info.version.trim();
      return version.isEmpty ? _defaultAppVersion : version;
    } catch (_) {
      return _defaultAppVersion;
    }
  }

  Future<void> initialize() async {
    if (_initialized || _isInitializing) {
      return;
    }
    _isInitializing = true;
    notifyListeners();
    final bootstrapStopwatch = Stopwatch()..start();
    try {
      await _store.init();
      _preferences = await _store.loadPreferences();
      _history = _store.loadTransferHistory().reversed.toList(growable: false);
      _appVersion = await _appVersionLoader();
      _initialized = true;
      _fatalError = null;
      _localBootstrapDurationMs = bootstrapStopwatch.elapsedMilliseconds;
    } catch (error) {
      _fatalError = error.toString();
      unawaited(
        _logTransportEvent(
          'startup',
          'Initialization failed',
          data: <String, Object?>{'error': error.toString()},
        ),
      );
    } finally {
      _isInitializing = false;
      notifyListeners();
    }
  }

  Future<void> ensureNetworkWarmupStarted() async {
    if (!_initialized ||
        needsOnboarding ||
        _isNetworkWarmupInProgress ||
        _networkStartupState == NetworkStartupState.ready ||
        _networkStartupState == NetworkStartupState.degraded) {
      return;
    }

    _isNetworkWarmupInProgress = true;
    _hasStartedNetworkWarmup = true;
    _networkStartupState = NetworkStartupState.warmingUp;
    notifyListeners();

    try {
      await _initializeTransportLogging();
      await _logLocalBootstrapTimingIfNeeded();
      await _runStartupPhase('identity-load', () async {
        _identity = await _identityService.loadOrCreate();
      });
      await _runStartupPhase('multicast-lock', () async {
        await _localNetworkPlatformService.acquireMulticastLock();
      });
      _configureTransferServices();
      await _runStartupPhase('transfer-server-start', () async {
        await _startServersWithFallback();
      });
      await _refreshFirewallSetup();
      await _runStartupPhase('discovery-start', () async {
        await _startOrRestartDiscovery();
      });
      await _runStartupPhase('first-scan', () async {
        await _scanNearbyDevices(
          forcePeerAvailability: true,
          burstAnnounce: true,
        );
      });
      _startDiscoveryRescanLoop();
      _networkStartupState = _discoveryHealth.firewallSetupResult.isFailure
          ? NetworkStartupState.degraded
          : NetworkStartupState.ready;
      _fatalError = null;
      unawaited(_runInitialHealthSweepInBackground());
    } catch (error) {
      _networkStartupState = NetworkStartupState.failed;
      _discoveryHealth = _discoveryHealth.copyWith(
        lastError: error.toString(),
        hasBlockingIssue: true,
      );
      await _logTransportEvent(
        'startup',
        'Network warmup failed',
        data: <String, Object?>{'error': error.toString()},
      );
    } finally {
      _isNetworkWarmupInProgress = false;
      notifyListeners();
    }
  }

  Future<void> _runInitialHealthSweepInBackground() async {
    final stopwatch = Stopwatch()..start();
    try {
      await _runForegroundHealthSweepIfNeeded();
      await _logTransportEvent(
        'startup',
        'Initial health sweep completed',
        data: <String, Object?>{
          'durationMs': stopwatch.elapsedMilliseconds,
          'visiblePeerCount': _nearbyDevices.length,
          'discoveredPeerCount': _discoveredNearbyDevices.length,
        },
      );
    } catch (error) {
      await _logTransportEvent(
        'startup',
        'Initial health sweep failed',
        data: <String, Object?>{
          'durationMs': stopwatch.elapsedMilliseconds,
          'error': error.toString(),
        },
      );
    }
  }

  void _configureTransferServices() {
    _transferServer
      ..onIncomingSessionChanged = _upsertIncomingTransferSession
      ..onProgress = _upsertTransferProgress
      ..onRecord = _addRecord
      ..onDiagnostics = _upsertTransferDiagnostics
      ..onTrace = _handleTransferServerTrace
      ..resolveSaveDirectory = _resolveSaveDirectory
      ..nicknameProvider = () {
        return localNickname;
      }
      ..appVersion = _appVersion;

    _transferClient.onTrace ??= (message, {data}) {
      unawaited(_logTransportEvent('transfer-client', message, data: data));
    };
    _transferClient.senderDeviceIdProvider = () => _identity?.deviceId ?? '';
    _transferClient.senderNicknameProvider = () => localNickname;
    _transferClient.senderFingerprintProvider = () =>
        _identity?.fingerprint ?? '';
    _transferClient.senderPlatformProvider = () => Platform.operatingSystem;
    _transferClient.senderAppVersionProvider = () => _appVersion;
    _transferClient.senderActivePortProvider = () => _activePort;
    _transferClient.senderSecurePortProvider = () => _transferServer.securePort;
  }

  Future<void> _initializeTransportLogging() async {
    try {
      await _runStartupPhase('transport-log-init', () async {
        await _transportLogService.initialize();
      });
    } catch (_) {
      // Logging must never block the app from becoming usable.
    }
  }

  Future<void> _logLocalBootstrapTimingIfNeeded() async {
    final durationMs = _localBootstrapDurationMs;
    if (durationMs == null) {
      return;
    }
    _localBootstrapDurationMs = null;
    await _logTransportEvent(
      'startup',
      'Local bootstrap completed',
      data: <String, Object?>{'durationMs': durationMs},
    );
  }

  Future<void> _runStartupPhase(
    String phase,
    Future<void> Function() action,
  ) async {
    final stopwatch = Stopwatch()..start();
    try {
      await action();
      await _logTransportEvent(
        'startup',
        'Startup phase completed',
        data: <String, Object?>{
          'phase': phase,
          'durationMs': stopwatch.elapsedMilliseconds,
        },
      );
    } catch (error) {
      await _logTransportEvent(
        'startup',
        'Startup phase failed',
        data: <String, Object?>{
          'phase': phase,
          'durationMs': stopwatch.elapsedMilliseconds,
          'error': error.toString(),
        },
      );
      rethrow;
    }
  }

  Future<void> _startServersWithFallback() async {
    var identity = _identity!;
    var regeneratedIdentity = false;
    while (true) {
      Exception? lastError;
      for (final port in NetworkConstants.scanPorts) {
        try {
          await _transferServer.start(port: port, identity: identity);
          _activePort = port;
          unawaited(
            _logTransportEvent(
            'transfer-server',
            'Transfer server started',
            data: <String, Object?>{
              'port': port,
              'securePort': _transferServer.securePort,
              'hasIpv4Listener': _transferServer.hasIpv4Listener,
              'hasIpv6Listener': _transferServer.hasIpv6Listener,
              'hasSecureListener': _transferServer.hasSecureListener,
              'fingerprint': identity.fingerprint,
            },
          ),
          );
          _identity = identity;
          return;
        } catch (error) {
          unawaited(
            _logTransportEvent(
              'transfer-server',
              'Transfer server failed to start on candidate port',
              data: <String, Object?>{'port': port, 'error': error.toString()},
            ),
          );
          lastError = Exception('Failed to bind $port: $error');
        }
      }

      if (!regeneratedIdentity && _isLeafCertParseFailure(lastError)) {
        regeneratedIdentity = true;
        await _logTransportEvent(
          'identity',
          'Regenerating local identity after TLS certificate parse failure',
          data: <String, Object?>{
            'previousFingerprint': identity.fingerprint,
            'error': lastError.toString(),
          },
        );
        identity = await _identityService.regenerate();
        await _logTransportEvent(
          'identity',
          'Local identity regenerated',
          data: <String, Object?>{'fingerprint': identity.fingerprint},
        );
        continue;
      }

      throw lastError ?? StateError('Unable to bind transfer server port.');
    }
  }

  bool _isLeafCertParseFailure(Object? error) {
    final text = error?.toString().toLowerCase() ?? '';
    return text.contains('cannot_parse_leaf_cert');
  }

  void _startDiscoveryRescanLoop() {
    _discoveryRescanTimer?.cancel();
    _discoveryRescanTimer = Timer.periodic(
      _discoveryRescanInterval,
      (_) => unawaited(_handleDiscoveryTick()),
    );
  }

  Future<String> _resolveSaveDirectory() async {
    return _preferences.saveDirectory ??
        await _store.resolveDefaultSaveDirectory();
  }

  Future<void> saveNickname(String nickname) async {
    final value = nickname.trim();
    if (value.isEmpty) {
      return;
    }
    final completedOnboarding = needsOnboarding;
    _preferences = _preferences.copyWith(nickname: value);
    await _store.savePreferences(_preferences);
    notifyListeners();
    if (completedOnboarding) {
      unawaited(ensureNetworkWarmupStarted());
    }
  }

  Future<void> setThemePreference(AppThemePreference preference) async {
    _preferences = _preferences.copyWith(themePreference: preference);
    await _store.savePreferences(_preferences);
    notifyListeners();
  }

  Future<void> pickSaveDirectory() async {
    final selected = await FilePicker.platform.getDirectoryPath();
    if (selected == null || selected.trim().isEmpty) {
      return;
    }
    _preferences = _preferences.copyWith(saveDirectory: selected);
    await _store.savePreferences(_preferences);
    notifyListeners();
  }

  Future<void> useDefaultSaveDirectory() async {
    final resolvedDefaultPath = await _store.resolveDefaultSaveDirectory();
    _preferences = _preferences.copyWith(saveDirectory: resolvedDefaultPath);
    await _store.savePreferences(_preferences);
    notifyListeners();
  }

  Future<void> requestIncomingDialogAttention() async {
    if (!Platform.isMacOS) {
      return;
    }
    await _localNetworkPlatformService.activateAppWindow();
  }

  Future<List<TransferItem>> pickItemsForType(TransferPayloadType type) {
    return _payloadBuilder.pickByType(type);
  }

  Future<TransferItem?> buildTextItem(String text) {
    return _payloadBuilder.fromText(text: text, type: TransferPayloadType.text);
  }

  Future<TransferItem?> buildClipboardItem() {
    return _payloadBuilder.fromClipboard();
  }

  void triggerDiscoveryScan() {
    unawaited(refreshNearbyDevices());
  }

  Future<void> refreshNearbyDevices() async {
    if (_identity == null ||
        _networkStartupState == NetworkStartupState.failed) {
      await ensureNetworkWarmupStarted();
      return;
    }
    if (_isNetworkWarmupInProgress) {
      return;
    }
    await _performDiscoveryRefresh(
      restartBackend: !_discoveryService.isRunning,
      forcePeerAvailability: true,
    );
  }

  Future<void> restartDiscovery() async {
    if (_identity == null || _isDiscoveryRestarting) {
      return;
    }
    _isDiscoveryRestarting = true;
    try {
      await _performDiscoveryRefresh(
        restartBackend: true,
        forcePeerAvailability: true,
      );
    } finally {
      _isDiscoveryRestarting = false;
    }
  }

  Future<void> repairWindowsFirewall() async {
    await _refreshFirewallSetup(force: true);
  }

  Future<void> _handleDiscoveryTick() async {
    if (_identity == null || _isDiscoveryForegroundPaused) {
      return;
    }
    if (!_discoveryService.isRunning) {
      await restartDiscovery();
      return;
    }
    final shouldUsePresenceBurst =
        _discoveredNearbyDevices.isEmpty && _nearbyDevices.isEmpty;
    await _scanNearbyDevices(burstAnnounce: shouldUsePresenceBurst);
    await _runForegroundHealthSweepIfNeeded();
    await _runDiscoveryWatchdogIfNeeded();
  }

  Future<void> _performDiscoveryRefresh({
    required bool restartBackend,
    bool forcePeerAvailability = false,
  }) async {
    if (_identity == null) {
      return;
    }
    if (restartBackend || !_discoveryService.isRunning) {
      await _startOrRestartDiscovery();
    }
    await _scanNearbyDevices(
      forcePeerAvailability: forcePeerAvailability,
      burstAnnounce: true,
    );
    await _runForegroundHealthSweepIfNeeded();
  }

  Future<int> addDraftItemsFromType(TransferPayloadType type) async {
    final items = await _payloadBuilder.pickByType(type);
    _sendDraft = _sendDraft.addItems(items);
    notifyListeners();
    return items.length;
  }

  Future<int> addDraftItemsFromPaths(List<String> paths) async {
    final items = await _payloadBuilder.fromPaths(paths);
    _sendDraft = _sendDraft.addItems(items);
    notifyListeners();
    return items.length;
  }

  Future<bool> addDraftTextItem(String text) async {
    final item = await _payloadBuilder.fromText(
      text: text,
      type: TransferPayloadType.text,
    );
    if (item == null) {
      return false;
    }
    _sendDraft = _sendDraft.addItems(<TransferItem>[item]);
    notifyListeners();
    return true;
  }

  Future<bool> addDraftClipboardItem() async {
    final item = await _payloadBuilder.fromClipboard();
    if (item == null) {
      return false;
    }
    _sendDraft = _sendDraft.addItems(<TransferItem>[item]);
    notifyListeners();
    return true;
  }

  void removeDraftItem(String itemId) {
    _sendDraft = _sendDraft.removeItem(itemId);
    if (!_sendDraft.hasItems) {
      _sendDraft = _sendDraft.copyWith(step: SendStep.selectContent);
    }
    notifyListeners();
  }

  void clearSendDraft() {
    _sendDraft = const SendDraft.empty();
    notifyListeners();
  }

  bool openRecipientStep() {
    if (!_sendDraft.hasItems || _sendDraft.isSending || !isNetworkReady) {
      return false;
    }
    _sendDraft = _sendDraft.copyWith(step: SendStep.chooseDevice);
    triggerDiscoveryScan();
    notifyListeners();
    return true;
  }

  void backToContentStep() {
    if (_sendDraft.isSending) {
      return;
    }
    _sendDraft = _sendDraft.copyWith(step: SendStep.selectContent);
    notifyListeners();
  }

  Future<SendAttemptResult> sendDraftToDevice(String deviceId) async {
    if (_identity == null) {
      return const SendAttemptResult.failure(SendFailureReason.unknown);
    }
    if (_sendDraft.isSending) {
      return const SendAttemptResult.failure(SendFailureReason.busy);
    }

    triggerDiscoveryScan();
    final recipient = _nearbyDevices.cast<DeviceProfile?>().firstWhere(
      (item) => item?.deviceId == deviceId,
      orElse: () => null,
    );
    final precheck = await validateSendDraftBeforeSend(
      draft: _sendDraft,
      recipient: recipient,
    );
    if (precheck != null) {
      unawaited(
        _logTransportEvent(
          'outgoing-transfer',
          'Send draft blocked before transfer start',
          data: <String, Object?>{
            'deviceId': deviceId,
            'failureReason': precheck.name,
          },
        ),
      );
      return SendAttemptResult.failure(precheck);
    }

    final availability = await _ensurePeerAvailability(recipient!, force: true);
    final availabilityFailure = _sendFailureForAvailability(availability);
    if (availabilityFailure != null) {
      unawaited(
        _logTransportEvent(
          'outgoing-transfer',
          'Send draft blocked by availability check',
          data: <String, Object?>{
            'deviceId': deviceId,
            'failureReason': availabilityFailure.name,
            'availabilityStatus': availability.status.name,
            'selectedAddress': availability.selectedAddress,
            'selectedPort': availability.selectedPort,
            'errorMessage': availability.errorMessage,
          },
        ),
      );
      return SendAttemptResult.failure(
        availabilityFailure,
        details: availability.errorMessage,
      );
    }

    final transferId = '${_uuid.v4()}_${deviceId.substring(0, 6)}';
    final offer = TransferOffer(
      transferId: transferId,
      senderDeviceId: _identity!.deviceId,
      senderNickname: localNickname,
      senderFingerprint: _identity!.fingerprint,
      senderAppVersion: _appVersion,
      protocolVersion: NetworkConstants.protocolVersion,
      createdAt: DateTime.now(),
      items: _sendDraft.items,
    );

    final cancelKey = _cancelKey(transferId, recipient.deviceId);
    _cancelTransferByKey[cancelKey] = false;
    _sendDraft = _sendDraft.copyWith(isSending: true);
    notifyListeners();
    unawaited(
      _logTransportEvent(
        'outgoing-transfer',
        'Starting outgoing transfer',
        data: <String, Object?>{
          'transferId': transferId,
          'deviceId': recipient.deviceId,
          'nickname': recipient.nickname,
          'selectedAddress': availability.selectedAddress,
          'selectedPort': availability.selectedPort,
          'addressFamily': availability.addressFamily,
          'itemCount': offer.items.length,
          'totalBytes': offer.totalBytes,
        },
      ),
    );

    final record = await _transferClient.sendTransfer(
      recipient: recipient,
      offer: offer,
      onProgress: _upsertTransferProgress,
      isCanceled: () => _cancelTransferByKey[cancelKey] ?? false,
      onDiagnostics: _upsertTransferDiagnostics,
      preferredAvailability: availability,
      diagnosticsLogPath: _transportLogService.logFilePath,
    );
    _cancelTransferByKey.remove(cancelKey);
    _addRecord(record);
    unawaited(
      _logTransportEvent(
        'outgoing-transfer',
        'Outgoing transfer finished',
        data: <String, Object?>{
          'transferId': record.transferId,
          'deviceId': record.peerDeviceId,
          'status': record.status.name,
          'stage': record.stage?.name,
          'terminalReason': record.terminalReason?.name,
          'errorMessage': record.errorMessage,
        },
      ),
    );

    if (record.status == TransferStatus.completed) {
      await _persistHistory();
      _sendDraft = const SendDraft.empty();
      notifyListeners();
      return const SendAttemptResult.success();
    }

    final failureReason = mapSendFailure(
      status: record.status,
      terminalReason: record.terminalReason,
      errorMessage: record.errorMessage,
    );
    _sendDraft = _sendDraft.copyWith(isSending: false);
    notifyListeners();
    return SendAttemptResult.failure(
      failureReason,
      details: record.errorMessage,
    );
  }

  Future<void> sendItems({
    required List<DeviceProfile> recipients,
    required List<TransferItem> items,
  }) async {
    if (recipients.isEmpty || items.isEmpty || _identity == null) {
      return;
    }

    final pending = <Future<TransferRecord>>[];
    for (final recipient in recipients) {
      final availability = await _ensurePeerAvailability(
        recipient,
        force: true,
      );
      final transferId = '${_uuid.v4()}_${recipient.deviceId.substring(0, 6)}';
      final offer = TransferOffer(
        transferId: transferId,
        senderDeviceId: _identity!.deviceId,
        senderNickname: localNickname,
        senderFingerprint: _identity!.fingerprint,
        senderAppVersion: _appVersion,
        protocolVersion: NetworkConstants.protocolVersion,
        createdAt: DateTime.now(),
        items: items,
      );
      final availabilityFailure = _sendFailureForAvailability(availability);
      if (availabilityFailure != null) {
        pending.add(
          Future<TransferRecord>.value(
            _failedRecordForAvailability(
              recipient: recipient,
              offer: offer,
              availability: availability,
            ),
          ),
        );
        continue;
      }
      final cancelKey = _cancelKey(transferId, recipient.deviceId);
      _cancelTransferByKey[cancelKey] = false;
      pending.add(
        _transferClient.sendTransfer(
          recipient: recipient,
          offer: offer,
          onProgress: _upsertTransferProgress,
          isCanceled: () => _cancelTransferByKey[cancelKey] ?? false,
          onDiagnostics: _upsertTransferDiagnostics,
          preferredAvailability: availability,
          diagnosticsLogPath: _transportLogService.logFilePath,
        ),
      );
    }

    final records = await Future.wait(pending);
    for (final record in records) {
      _addRecord(record);
      _cancelTransferByKey.remove(
        _cancelKey(record.transferId, record.peerDeviceId),
      );
    }
    await _persistHistory();
  }

  void cancelTransfer(TransferProgress progress) {
    final key = _cancelKey(progress.transferId, progress.peerDeviceId);
    _cancelTransferByKey[key] = true;
    _upsertTransferProgress(
      progress.copyWith(
        status: TransferStatus.canceled,
        updatedAt: DateTime.now(),
        stage: TransferStage.failed,
        terminalReason: TransferTerminalReason.canceled,
      ),
    );
    _upsertTransferDiagnostics(
      (diagnosticsForTransfer(progress.transferId) ??
              TransferDiagnosticsSnapshot(
                contextId: progress.transferId,
                peerDeviceId: progress.peerDeviceId,
                peerNickname: progress.peerNickname,
                isIncoming: progress.isIncoming,
                stage: TransferStage.failed,
                updatedAt: DateTime.now(),
              ))
          .copyWith(
            stage: TransferStage.failed,
            updatedAt: DateTime.now(),
            terminalReason: TransferTerminalReason.canceled,
            errorMessage: 'Transfer canceled.',
            logFilePath: _transportLogService.logFilePath,
          ),
    );
  }

  Future<void> retryTransfer(TransferRecord record) async {
    final recipient = _nearbyDevices.cast<DeviceProfile?>().firstWhere(
      (item) => item?.deviceId == record.peerDeviceId,
      orElse: () => null,
    );
    if (record.isIncoming || recipient == null) {
      return;
    }
    final reusableItems = <TransferItem>[];
    for (final item in record.items) {
      if (item.isText) {
        reusableItems.add(item);
        continue;
      }
      final path = item.sourcePath;
      if (path != null && await File(path).exists()) {
        reusableItems.add(item);
      }
    }
    if (reusableItems.isEmpty) {
      return;
    }
    await sendItems(
      recipients: <DeviceProfile>[recipient],
      items: reusableItems,
    );
  }

  String displayNameForDevice(DeviceProfile device) {
    final duplicate = _nearbyDevices.where(
      (item) => item.nickname.toLowerCase() == device.nickname.toLowerCase(),
    );
    if (duplicate.length > 1) {
      return '${device.nickname} · ${device.shortSuffix}';
    }
    return device.nickname;
  }

  Future<IncomingActionResult> acceptIncoming(String transferId) async {
    final session = _incomingSessionsById[transferId];
    if (session == null) {
      return const IncomingActionResult.failure(
        'This transfer request is no longer available.',
      );
    }
    if (!session.isPending) {
      return const IncomingActionResult.failure(
        'This transfer request is no longer pending.',
      );
    }
    unawaited(
      _logTransportEvent(
        'incoming-transfer',
        'Accept tapped',
        data: <String, Object?>{
          'transferId': session.transferId,
          'senderDeviceId': session.senderDeviceId,
          'senderNickname': session.senderNickname,
          'remoteAddress': session.remoteAddress,
        },
      ),
    );
    try {
      await _transferServer.acceptIncoming(transferId);
      _touchTransportVerifiedPeerLease(
        deviceId: session.senderDeviceId,
        fallbackProfile: _profileForIncomingSession(session),
        selectedAddress: session.remoteAddress,
        addressFamily: _addressFamilyFor(session.remoteAddress),
      );
      await _persistHistory();
      unawaited(
        _logTransportEvent(
          'incoming-transfer',
          'Accept succeeded',
          data: <String, Object?>{
            'transferId': session.transferId,
            'senderDeviceId': session.senderDeviceId,
            'senderNickname': session.senderNickname,
          },
        ),
      );
      notifyListeners();
      return const IncomingActionResult.success();
    } catch (error) {
      final message = _incomingActionFailureMessage(
        fallback: 'Could not accept the transfer.',
        error: error,
      );
      unawaited(
        _logTransportEvent(
          'incoming-transfer',
          'Accept failed',
          data: <String, Object?>{
            'transferId': session.transferId,
            'senderDeviceId': session.senderDeviceId,
            'senderNickname': session.senderNickname,
            'error': error.toString(),
          },
        ),
      );
      notifyListeners();
      return IncomingActionResult.failure(message);
    }
  }

  Future<IncomingActionResult> declineIncoming(String transferId) async {
    final session = _incomingSessionsById[transferId];
    if (session == null) {
      return const IncomingActionResult.failure(
        'This transfer request is no longer available.',
      );
    }
    if (!session.isPending) {
      return const IncomingActionResult.failure(
        'This transfer request is no longer pending.',
      );
    }
    unawaited(
      _logTransportEvent(
        'incoming-transfer',
        'Decline tapped',
        data: <String, Object?>{
          'transferId': session.transferId,
          'senderDeviceId': session.senderDeviceId,
          'senderNickname': session.senderNickname,
          'remoteAddress': session.remoteAddress,
        },
      ),
    );
    try {
      await _transferServer.declineIncoming(transferId);
      unawaited(
        _logTransportEvent(
          'incoming-transfer',
          'Decline succeeded',
          data: <String, Object?>{
            'transferId': session.transferId,
            'senderDeviceId': session.senderDeviceId,
            'senderNickname': session.senderNickname,
          },
        ),
      );
      notifyListeners();
      return const IncomingActionResult.success();
    } catch (error) {
      final message = _incomingActionFailureMessage(
        fallback: 'Could not decline the transfer.',
        error: error,
      );
      unawaited(
        _logTransportEvent(
          'incoming-transfer',
          'Decline failed',
          data: <String, Object?>{
            'transferId': session.transferId,
            'senderDeviceId': session.senderDeviceId,
            'senderNickname': session.senderNickname,
            'error': error.toString(),
          },
        ),
      );
      notifyListeners();
      return IncomingActionResult.failure(message);
    }
  }

  PeerAvailabilitySnapshot availabilityForDevice(String deviceId) {
    final existing = _peerAvailabilityById[deviceId];
    if (existing != null) {
      return existing;
    }
    final device = _nearbyDevices.cast<DeviceProfile?>().firstWhere(
      (item) => item?.deviceId == deviceId,
      orElse: () => null,
    );
    return PeerAvailabilitySnapshot(
      deviceId: deviceId,
      nickname: device?.nickname ?? '',
      status: PeerAvailabilityStatus.unknown,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  TransferDiagnosticsSnapshot? diagnosticsForTransfer(String transferId) {
    return _diagnosticsByContextId[transferId];
  }

  Future<void> refreshPeerAvailability(String deviceId) async {
    final device = _nearbyDevices.cast<DeviceProfile?>().firstWhere(
      (item) => item?.deviceId == deviceId,
      orElse: () => null,
    );
    if (device == null) {
      return;
    }
    await _ensurePeerAvailability(device, force: true, replaceInFlight: true);
  }

  void _upsertIncomingTransferSession(IncomingTransferSession session) {
    _incomingSessionsById[session.transferId] = session;
    _touchTransportVerifiedPeerLease(
      deviceId: session.senderDeviceId,
      fallbackProfile: _profileForIncomingSession(session),
      selectedAddress: session.remoteAddress,
      addressFamily: _addressFamilyFor(session.remoteAddress),
    );
    if (!session.isPending &&
        session.status != TransferDecisionStatus.accepted) {
      Future<void>.delayed(const Duration(seconds: 8), () {
        final latest = _incomingSessionsById[session.transferId];
        if (latest != null && latest.status == session.status) {
          _incomingSessionsById.remove(session.transferId);
          notifyListeners();
        }
      });
    }
    notifyListeners();
  }

  void _upsertTransferProgress(TransferProgress progress) {
    final key = _progressKey(progress);
    _activeTransfers[key] = progress;
    if (progress.isIncoming && _isTerminal(progress.status)) {
      _incomingSessionsById.remove(progress.transferId);
    }
    if (_isTerminal(progress.status)) {
      Future<void>.delayed(const Duration(seconds: 6), () {
        if ((_activeTransfers[key]?.status) == progress.status) {
          _activeTransfers.remove(key);
          notifyListeners();
        }
      });
    }
    notifyListeners();
  }

  void _addRecord(TransferRecord record) {
    if (record.isIncoming) {
      _incomingSessionsById.remove(record.transferId);
    }
    _history = <TransferRecord>[record, ..._history];
    unawaited(_persistHistory());
    notifyListeners();
  }

  void _upsertTransferDiagnostics(TransferDiagnosticsSnapshot snapshot) {
    final enriched = snapshot.copyWith(
      updatedAt: DateTime.now(),
      logFilePath: snapshot.logFilePath ?? _transportLogService.logFilePath,
    );
    _diagnosticsByContextId[enriched.contextId] = enriched;
    _refreshTransportVerifiedPeerLeaseFromDiagnostics(enriched);
    unawaited(
      _logTransportEvent(
        enriched.isIncoming ? 'incoming-transfer' : 'outgoing-transfer',
        '${enriched.peerNickname} ${enriched.stage.name}',
        data: <String, Object?>{
          'contextId': enriched.contextId,
          'peerDeviceId': enriched.peerDeviceId,
          'stage': enriched.stage.name,
          'address': enriched.selectedAddress,
          'port': enriched.selectedPort,
          'addressFamily': enriched.addressFamily,
          'offerStatus': enriched.offerStatus,
          'decisionStatus': enriched.decisionStatus?.name,
          'uploadStatus': enriched.uploadStatus,
          'terminalReason': enriched.terminalReason?.name,
          'httpRoute': enriched.lastHttpRoute,
          'httpStatusCode': enriched.lastHttpStatusCode,
          'errorMessage': enriched.errorMessage,
        },
      ),
    );
    notifyListeners();
  }

  Future<void> _persistHistory() async {
    await _store.saveTransferHistory(
      _history.take(200).toList(growable: false),
    );
  }

  bool _isTerminal(TransferStatus status) {
    return status == TransferStatus.completed ||
        status == TransferStatus.failed ||
        status == TransferStatus.canceled ||
        status == TransferStatus.declined;
  }

  String _progressKey(TransferProgress progress) {
    final direction = progress.isIncoming ? 'in' : 'out';
    return '$direction:${progress.transferId}:${progress.peerDeviceId}';
  }

  String _cancelKey(String transferId, String peerDeviceId) {
    return '$transferId:$peerDeviceId';
  }

  Future<void> _startOrRestartDiscovery() async {
    if (_identity == null) {
      return;
    }
    await _discoverySubscription?.cancel();
    await _discoveryHealthSubscription?.cancel();
    _discoverySubscription = _discoveryService.devicesStream.listen((devices) {
      if (_shouldPreserveVisibleNearbyDevices(devices)) {
        _refreshComputedDiscoveryHealth();
        notifyListeners();
        return;
      }
      _discoveredNearbyDevices = devices;
      _rebuildVisibleNearbyDevices();
      _syncPeerAvailability(_nearbyDevices);
      if (_discoveredNearbyDevices.isNotEmpty) {
        _markHealthyDiscoveryActivity();
      }
      notifyListeners();
    });
    _discoveryHealthSubscription = _discoveryService.healthStream.listen((
      health,
    ) {
      _applyDiscoveryHealth(health);
      notifyListeners();
    });
    await _discoveryService.start(
      deviceId: _identity!.deviceId,
      activePort: _activePort,
      securePort: _transferServer.securePort,
      nicknameProvider: () => localNickname,
      fingerprintProvider: () => _identity!.fingerprint,
      appVersion: _appVersion,
    );
    _lastHealthyDiscoveryAt = DateTime.now();
    _watchdogSoftRefreshPendingHardRestart = false;
    _discoveredNearbyDevices = _discoveryService.currentDevices;
    _rebuildVisibleNearbyDevices();
    _syncPeerAvailability(_nearbyDevices);
    _applyDiscoveryHealth(_discoveryService.currentHealth);
    notifyListeners();
  }

  Future<void> _scanNearbyDevices({
    bool forcePeerAvailability = false,
    bool burstAnnounce = false,
  }) async {
    if (!_discoveryService.isRunning) {
      return;
    }
    _discoveryScanInFlightCount += 1;
    try {
      await _discoveryService.scanNow(burstAnnounce: burstAnnounce);
      final snapshotDevices = _discoveryService.currentDevices;
      final shouldPreserveVisibleDevices = _shouldPreserveVisibleNearbyDevices(
        snapshotDevices,
      );
      if (!shouldPreserveVisibleDevices) {
        _discoveredNearbyDevices = snapshotDevices;
      }
      _rebuildVisibleNearbyDevices();
      if (_discoveredNearbyDevices.isNotEmpty) {
        _markHealthyDiscoveryActivity();
      }
      _syncPeerAvailability(_nearbyDevices, force: forcePeerAvailability);
      _applyDiscoveryHealth(_discoveryService.currentHealth);
      notifyListeners();
    } finally {
      _discoveryScanInFlightCount -= 1;
    }
  }

  Future<void> _refreshFirewallSetup({bool force = false}) async {
    if (!force && _hasAttemptedFirewallSetupThisLaunch) {
      return;
    }
    _hasAttemptedFirewallSetupThisLaunch = true;
    final stopwatch = Stopwatch()..start();
    final result = await _localNetworkPlatformService.ensureFirewallRules();
    _hasFirewallSetupIssue = result.isFailure;
    _discoveryHealth = _discoveryHealth.copyWith(
      firewallSetupResult: result,
      lastError: result.status == FirewallSetupStatus.failed
          ? result.message
          : _discoveryHealth.lastError,
    );
    if (!result.isFailure &&
        _networkStartupState == NetworkStartupState.degraded) {
      _networkStartupState = NetworkStartupState.ready;
    }
    await _logTransportEvent(
      'startup',
      force ? 'Firewall repair completed' : 'Firewall setup completed',
      data: <String, Object?>{
        'durationMs': stopwatch.elapsedMilliseconds,
        'status': result.status.name,
        'message': result.message,
      },
    );
    notifyListeners();
  }

  void _syncPeerAvailability(
    List<DeviceProfile> devices, {
    bool force = false,
  }) {
    final activeIds = devices.map((item) => item.deviceId).toSet();
    _peerAvailabilityById.removeWhere((key, _) => !activeIds.contains(key));
    _peerAvailabilityProbeFutures.removeWhere(
      (key, _) => !activeIds.contains(key),
    );
    _peerAvailabilityProbeGenerations.removeWhere(
      (key, _) => !activeIds.contains(key),
    );
    _refreshComputedDiscoveryHealth();
    for (final device in devices) {
      unawaited(
        _ensurePeerAvailability(device, force: force, replaceInFlight: force),
      );
    }
  }

  Future<void> _runForegroundHealthSweepIfNeeded() async {
    if (_identity == null ||
        _isDiscoveryForegroundPaused ||
        _zeroPeerHealthSweepInFlight) {
      return;
    }
    final now = DateTime.now();
    final sweepCooldown =
        _nearbyDevices.isEmpty && _discoveredNearbyDevices.isEmpty
        ? _zeroPeerHealthSweepCooldown
        : _supplementalHealthSweepCooldown;
    if (_lastZeroPeerHealthSweepAt != null &&
        now.difference(_lastZeroPeerHealthSweepAt!) < sweepCooldown) {
      return;
    }

    _zeroPeerHealthSweepInFlight = true;
    _lastZeroPeerHealthSweepAt = now;
    try {
      final interfaces = await _localNetworkPlatformService
          .listActiveInterfaces();
      final targets = _buildZeroPeerHealthSweepTargets(interfaces);
      if (targets.isEmpty) {
        return;
      }

      final localDeviceId = _identity?.deviceId;
      final discovered = <String, TransferHealthPeerSnapshot>{};
      var nextIndex = 0;

      Future<void> worker() async {
        while (nextIndex < targets.length) {
          final current = targets[nextIndex];
          nextIndex += 1;
          final snapshot = await _transferClient.discoverPeerAt(
            address: current.address,
            port: current.port,
            useTls: true,
          );
          if (snapshot == null) {
            continue;
          }
          if (snapshot.profile.deviceId == localDeviceId) {
            continue;
          }
          final wasNewPeer =
              discovered.putIfAbsent(
                snapshot.profile.deviceId,
                () => snapshot,
              ) ==
              snapshot;
          if (!wasNewPeer) {
            continue;
          }
          final promoted = _promoteHealthSweepPeer(snapshot);
          if (promoted) {
            notifyListeners();
          }
        }
      }

      final workerCount = targets.length < _zeroPeerHealthSweepConcurrency
          ? targets.length
          : _zeroPeerHealthSweepConcurrency;
      await Future.wait(
        List<Future<void>>.generate(workerCount, (_) => worker()),
      );
    } finally {
      _zeroPeerHealthSweepInFlight = false;
    }
  }

  Future<PeerAvailabilitySnapshot> _ensurePeerAvailability(
    DeviceProfile device, {
    bool force = false,
    bool replaceInFlight = false,
  }) async {
    final existing = _peerAvailabilityById[device.deviceId];
    final candidateIdentityChanged =
        existing == null ||
        _hasMaterialPeerAvailabilityTargetChange(device, existing);
    final isFreshEnough =
        existing != null &&
        DateTime.now().difference(existing.updatedAt) <
            _peerAvailabilityProbeCooldownFor(existing.status);
    final isCheckingStale =
        existing != null &&
        existing.status == PeerAvailabilityStatus.checking &&
        DateTime.now().difference(existing.updatedAt) >=
            _checkingPeerAvailabilityStaleTimeout;
    if (!force &&
        existing != null &&
        existing.status != PeerAvailabilityStatus.unknown &&
        existing.status != PeerAvailabilityStatus.checking &&
        isFreshEnough &&
        !candidateIdentityChanged) {
      return existing;
    }
    final inFlightProbe = _peerAvailabilityProbeFutures[device.deviceId];
    if (inFlightProbe != null) {
      final shouldReplaceInFlightProbe =
          (replaceInFlight &&
              (force || isCheckingStale || candidateIdentityChanged)) ||
          isCheckingStale ||
          candidateIdentityChanged;
      if (!shouldReplaceInFlightProbe) {
        unawaited(
          _logTransportEvent(
            'peer-availability',
            'Awaiting in-flight peer availability probe',
            data: <String, Object?>{
              'deviceId': device.deviceId,
              'nickname': device.nickname,
              'force': force,
              'replaceInFlight': replaceInFlight,
            },
          ),
        );
        return inFlightProbe;
      }
      unawaited(
        _logTransportEvent(
          'peer-availability',
          'Replacing in-flight peer availability probe',
          data: <String, Object?>{
            'deviceId': device.deviceId,
            'nickname': device.nickname,
            'force': force,
            'replaceInFlight': replaceInFlight,
            'candidateIdentityChanged': candidateIdentityChanged,
            'checkingWasStale': isCheckingStale,
          },
        ),
      );
    }

    final probeGeneration = _nextPeerAvailabilityProbeGeneration(
      device.deviceId,
    );
    final probeFuture = _probePeerAvailability(
      device,
      existing,
      generation: probeGeneration,
    );
    _peerAvailabilityProbeFutures[device.deviceId] = probeFuture;
    try {
      return await probeFuture;
    } finally {
      if (identical(
        _peerAvailabilityProbeFutures[device.deviceId],
        probeFuture,
      )) {
        _peerAvailabilityProbeFutures.remove(device.deviceId);
      }
    }
  }

  Future<PeerAvailabilitySnapshot> _probePeerAvailability(
    DeviceProfile device,
    PeerAvailabilitySnapshot? existing, {
    required int generation,
  }) async {
    final shouldShowCheckingState =
        existing == null ||
        existing.status == PeerAvailabilityStatus.unknown ||
        existing.status == PeerAvailabilityStatus.checking;
    if (_isCurrentPeerAvailabilityProbeGeneration(
      device.deviceId,
      generation,
    )) {
      if (shouldShowCheckingState) {
        _peerAvailabilityById[device.deviceId] =
            (existing ??
                    PeerAvailabilitySnapshot(
                      deviceId: device.deviceId,
                      nickname: device.nickname,
                      status: PeerAvailabilityStatus.unknown,
                      updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
                    ))
                .copyWith(
                  nickname: device.nickname,
                  status: PeerAvailabilityStatus.checking,
                  updatedAt: DateTime.now(),
                  selectedAddress: device.ipAddress,
                  selectedPort: device.activePort,
                  addressFamily: device.preferredAddressFamily,
                  errorMessage: null,
                  protocolVersion: device.protocolVersion,
                  appVersion: device.appVersion,
                  capabilities: device.capabilities,
                );
        notifyListeners();
      } else {
        _peerAvailabilityById[device.deviceId] = existing.copyWith(
          nickname: device.nickname,
          selectedAddress: existing.selectedAddress ?? device.ipAddress,
          selectedPort: existing.selectedPort ?? device.activePort,
          addressFamily:
              existing.addressFamily ?? device.preferredAddressFamily,
          protocolVersion: device.protocolVersion,
          appVersion: device.appVersion,
          capabilities: device.capabilities,
        );
      }
    }

    try {
      final snapshot = await _transferClient.probeRecipient(
        recipient: device,
        preferredAvailability: existing,
      );
      if (_isCurrentPeerAvailabilityProbeGeneration(
        device.deviceId,
        generation,
      )) {
        _peerAvailabilityById[device.deviceId] = snapshot;
        _touchTransportVerifiedPeerLease(
          deviceId: snapshot.deviceId,
          fallbackProfile: device,
          selectedAddress: snapshot.selectedAddress,
          selectedPort: snapshot.selectedPort,
          addressFamily: snapshot.addressFamily,
          timestamp: snapshot.updatedAt,
        );
        _discoveryHealth = _discoveryHealth.copyWith(
          resolvedAddressFamily:
              snapshot.addressFamily ?? _discoveryHealth.resolvedAddressFamily,
        );
        _refreshComputedDiscoveryHealth();
        unawaited(
          _logTransportEvent(
            'peer-availability',
            'Peer availability updated',
            data: <String, Object?>{
              'deviceId': snapshot.deviceId,
              'nickname': snapshot.nickname,
              'status': snapshot.status.name,
              'discoveryBackends': device.contributingBackends
                  .map((item) => item.name)
                  .toList(growable: false),
              'candidateAddresses': device.ipAddresses,
              'selectedAddress': snapshot.selectedAddress,
              'selectedPort': snapshot.selectedPort,
              'addressFamily': snapshot.addressFamily,
              'errorMessage': snapshot.errorMessage,
              'protocolVersion': snapshot.protocolVersion,
              'appVersion': snapshot.appVersion,
            },
          ),
        );
      } else {
        unawaited(
          _logTransportEvent(
            'peer-availability',
            'Discarded stale peer availability update',
            data: <String, Object?>{
              'deviceId': snapshot.deviceId,
              'nickname': snapshot.nickname,
              'status': snapshot.status.name,
            },
          ),
        );
      }
      return snapshot;
    } catch (error) {
      final failed = PeerAvailabilitySnapshot(
        deviceId: device.deviceId,
        nickname: device.nickname,
        status: PeerAvailabilityStatus.unreachable,
        updatedAt: DateTime.now(),
        selectedAddress: device.ipAddress,
        selectedPort: device.activePort,
        addressFamily: device.preferredAddressFamily,
        errorMessage: error.toString(),
        protocolVersion: device.protocolVersion,
        appVersion: device.appVersion,
        capabilities: device.capabilities,
      );
      if (_isCurrentPeerAvailabilityProbeGeneration(
        device.deviceId,
        generation,
      )) {
        _peerAvailabilityById[device.deviceId] = failed;
        _refreshComputedDiscoveryHealth();
        unawaited(
          _logTransportEvent(
            'peer-availability',
            'Peer availability probe failed',
            data: <String, Object?>{
              'deviceId': device.deviceId,
              'nickname': device.nickname,
              'discoveryBackends': device.contributingBackends
                  .map((item) => item.name)
                  .toList(growable: false),
              'candidateAddresses': device.ipAddresses,
              'error': error.toString(),
            },
          ),
        );
      } else {
        unawaited(
          _logTransportEvent(
            'peer-availability',
            'Discarded stale peer availability failure',
            data: <String, Object?>{
              'deviceId': device.deviceId,
              'nickname': device.nickname,
              'error': error.toString(),
            },
          ),
        );
      }
      return failed;
    } finally {
      if (_isCurrentPeerAvailabilityProbeGeneration(
        device.deviceId,
        generation,
      )) {
        _refreshComputedDiscoveryHealth();
        notifyListeners();
      }
    }
  }

  Future<void> pauseDiscoveryForBackground() async {
    if (!_initialized ||
        _isDiscoveryForegroundPaused ||
        _isNetworkWarmupInProgress ||
        !_hasStartedNetworkWarmup ||
        _identity == null) {
      return;
    }
    _isDiscoveryForegroundPaused = true;
    _lastHealthyDiscoveryAt = null;
    _watchdogSoftRefreshPendingHardRestart = false;
    await _discoveryService.pauseForBackground();
    await _localNetworkPlatformService.releaseMulticastLock();
    _peerAvailabilityProbeFutures.clear();
    _peerAvailabilityProbeGenerations.clear();
    _discoveredNearbyDevices = const <DeviceProfile>[];
    _nearbyDevices = const <DeviceProfile>[];
    _applyDiscoveryHealth(_discoveryService.currentHealth);
    notifyListeners();
  }

  Future<void> resumeDiscoveryFromForeground() async {
    if (!_initialized) {
      return;
    }
    if (_isNetworkWarmupInProgress) {
      return;
    }
    if (!_hasStartedNetworkWarmup || _identity == null) {
      await ensureNetworkWarmupStarted();
      return;
    }
    _isDiscoveryForegroundPaused = false;
    await _localNetworkPlatformService.acquireMulticastLock();
    await _discoveryService.resumeFromForeground();
    if (_discoveryService.isRunning) {
      await refreshNearbyDevices();
      return;
    }
    await restartDiscovery();
  }

  Duration _peerAvailabilityProbeCooldownFor(PeerAvailabilityStatus? status) {
    return switch (status) {
      PeerAvailabilityStatus.ready ||
      PeerAvailabilityStatus.incompatible ||
      PeerAvailabilityStatus.securityFailure =>
        _stablePeerAvailabilityProbeCooldown,
      _ => _pendingPeerAvailabilityProbeCooldown,
    };
  }

  int _nextPeerAvailabilityProbeGeneration(String deviceId) {
    final next = (_peerAvailabilityProbeGenerations[deviceId] ?? 0) + 1;
    _peerAvailabilityProbeGenerations[deviceId] = next;
    return next;
  }

  bool _isCurrentPeerAvailabilityProbeGeneration(
    String deviceId,
    int generation,
  ) {
    return _peerAvailabilityProbeGenerations[deviceId] == generation;
  }

  bool _hasMaterialPeerAvailabilityTargetChange(
    DeviceProfile device,
    PeerAvailabilitySnapshot snapshot,
  ) {
    if (snapshot.protocolVersion != device.protocolVersion) {
      return true;
    }
    final advertisedPorts = <int>{
      if (device.activePort > 0) device.activePort,
      if ((device.securePort ?? 0) > 0) device.securePort!,
    };
    final selectedPort = snapshot.selectedPort ?? device.activePort;
    if (!advertisedPorts.contains(selectedPort)) {
      return true;
    }
    final candidateAddresses = _canonicalAddressSet(<String>[
      ...device.ipAddresses,
      device.ipAddress,
    ]);
    if (candidateAddresses.isEmpty) {
      return false;
    }
    final selectedAddress = snapshot.selectedAddress?.trim() ?? '';
    if (selectedAddress.isEmpty) {
      return true;
    }
    return !candidateAddresses.contains(selectedAddress);
  }

  bool _shouldProbePeerAvailabilityFromServerHint(DeviceProfile device) {
    final existing = _peerAvailabilityById[device.deviceId];
    if (existing == null) {
      return true;
    }
    if (existing.status == PeerAvailabilityStatus.unknown ||
        existing.status == PeerAvailabilityStatus.checking) {
      return true;
    }
    return _hasMaterialPeerAvailabilityTargetChange(device, existing);
  }

  List<String> _canonicalAddressSet(Iterable<String> values) {
    final unique = <String>{};
    for (final value in values) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      unique.add(trimmed);
    }
    final sorted = unique.toList(growable: false)
      ..sort((a, b) {
        final familyCompare = _addressFamilyPriority(
          a,
        ).compareTo(_addressFamilyPriority(b));
        if (familyCompare != 0) {
          return familyCompare;
        }
        return a.compareTo(b);
      });
    return sorted;
  }

  bool _sameProfileIdentity(DeviceProfile a, DeviceProfile b) {
    final aCapabilities = List<String>.from(a.capabilities)..sort();
    final bCapabilities = List<String>.from(b.capabilities)..sort();
    return a.deviceId == b.deviceId &&
        a.nickname == b.nickname &&
        a.platform == b.platform &&
        a.activePort == b.activePort &&
        a.securePort == b.securePort &&
        a.certFingerprint == b.certFingerprint &&
        a.appVersion == b.appVersion &&
        a.protocolVersion == b.protocolVersion &&
        a.preferredAddressFamily == b.preferredAddressFamily &&
        listEquals(
          _canonicalAddressSet(<String>[...a.ipAddresses, a.ipAddress]),
          _canonicalAddressSet(<String>[...b.ipAddresses, b.ipAddress]),
        ) &&
        listEquals(aCapabilities, bCapabilities);
  }

  bool _sameTransportLeaseIdentity(
    TransportVerifiedPeerLease a,
    TransportVerifiedPeerLease b,
  ) {
    return a.deviceId == b.deviceId &&
        a.selectedAddress == b.selectedAddress &&
        a.selectedPort == b.selectedPort &&
        a.addressFamily == b.addressFamily;
  }

  SendFailureReason? _sendFailureForAvailability(
    PeerAvailabilitySnapshot availability,
  ) {
    return switch (availability.status) {
      PeerAvailabilityStatus.ready => null,
      PeerAvailabilityStatus.incompatible =>
        SendFailureReason.incompatibleVersion,
      PeerAvailabilityStatus.securityFailure =>
        SendFailureReason.certificateMismatch,
      PeerAvailabilityStatus.unreachable =>
        SendFailureReason.transferUnreachable,
      PeerAvailabilityStatus.checking => SendFailureReason.transferUnreachable,
      PeerAvailabilityStatus.unknown => SendFailureReason.transferUnreachable,
    };
  }

  TransferRecord _failedRecordForAvailability({
    required DeviceProfile recipient,
    required TransferOffer offer,
    required PeerAvailabilitySnapshot availability,
  }) {
    final now = DateTime.now();
    final terminalReason = switch (availability.status) {
      PeerAvailabilityStatus.incompatible =>
        TransferTerminalReason.incompatibleProtocol,
      PeerAvailabilityStatus.securityFailure =>
        TransferTerminalReason.tlsVerificationFailed,
      _ => TransferTerminalReason.discoveryVisibleButUnreachable,
    };
    final errorMessage =
        availability.errorMessage ??
        switch (terminalReason) {
          TransferTerminalReason.incompatibleProtocol =>
            'Update LocalDrop on both devices.',
          TransferTerminalReason.tlsVerificationFailed =>
            'Security verification failed.',
          _ => 'Receiver discovered, but transfer port could not be reached.',
        };
    final diagnostics = TransferDiagnosticsSnapshot(
      contextId: offer.transferId,
      peerDeviceId: recipient.deviceId,
      peerNickname: recipient.nickname,
      isIncoming: false,
      stage: TransferStage.failed,
      updatedAt: now,
      selectedAddress: availability.selectedAddress ?? recipient.ipAddress,
      selectedPort: availability.selectedPort ?? recipient.activePort,
      addressFamily:
          availability.addressFamily ?? recipient.preferredAddressFamily,
      terminalReason: terminalReason,
      errorMessage: errorMessage,
      logFilePath: _transportLogService.logFilePath,
    );
    _upsertTransferDiagnostics(diagnostics);
    return TransferRecord(
      transferId: offer.transferId,
      peerDeviceId: recipient.deviceId,
      peerNickname: recipient.nickname,
      isIncoming: false,
      items: offer.items,
      status: TransferStatus.failed,
      totalBytes: offer.totalBytes,
      transferredBytes: 0,
      startedAt: now,
      endedAt: now,
      stage: TransferStage.failed,
      terminalReason: terminalReason,
      errorMessage: errorMessage,
    );
  }

  void _handleTransferServerTrace(
    String message, {
    Map<String, Object?>? data,
  }) {
    final remoteAddress = (data?['remoteAddress'] as String?)?.trim();
    final peerDeviceId = (data?['peerDeviceId'] as String?)?.trim();
    var touchedLease = false;
    if (remoteAddress != null &&
        remoteAddress.isNotEmpty &&
        !_isLoopbackAddress(remoteAddress)) {
      touchedLease = _touchTransportVerifiedPeerLeaseByAddress(
        remoteAddress,
        preferExistingSelectedAddress: true,
      );
      if (!touchedLease) {
        touchedLease = _touchTransportVerifiedPeerLeaseFromPeerHint(
          remoteAddress: remoteAddress,
          data: data,
          preferExistingSelectedAddress: true,
        );
      }
    }
    if (touchedLease) {
      _refreshComputedDiscoveryHealth();
      final hintedPeer = (peerDeviceId == null || peerDeviceId.isEmpty)
          ? _deviceByAddress(remoteAddress ?? '')
          : _bestKnownProfileForDeviceId(peerDeviceId);
      if (hintedPeer != null &&
          _shouldProbePeerAvailabilityFromServerHint(hintedPeer)) {
        unawaited(_ensurePeerAvailability(hintedPeer));
      }
      notifyListeners();
    }
    unawaited(_logTransportEvent('transfer-server', message, data: data));
  }

  void _refreshTransportVerifiedPeerLeaseFromDiagnostics(
    TransferDiagnosticsSnapshot snapshot,
  ) {
    final statusCode = snapshot.lastHttpStatusCode;
    if (statusCode == null || statusCode < 200 || statusCode >= 300) {
      return;
    }
    _touchTransportVerifiedPeerLease(
      deviceId: snapshot.peerDeviceId,
      fallbackProfile: _profileForTransportSnapshot(snapshot),
      selectedAddress: snapshot.selectedAddress,
      selectedPort: snapshot.selectedPort,
      addressFamily: snapshot.addressFamily,
      timestamp: snapshot.updatedAt,
    );
  }

  bool _touchTransportVerifiedPeerLeaseByAddress(
    String address, {
    DateTime? timestamp,
    bool preferExistingSelectedAddress = false,
  }) {
    final device = _deviceByAddress(address);
    if (device == null) {
      return false;
    }
    return _touchTransportVerifiedPeerLease(
      deviceId: device.deviceId,
      fallbackProfile: device,
      selectedAddress: address,
      addressFamily: _addressFamilyFor(address),
      timestamp: timestamp,
      preferExistingSelectedAddress: preferExistingSelectedAddress,
    );
  }

  bool _touchTransportVerifiedPeerLeaseFromPeerHint({
    required String remoteAddress,
    Map<String, Object?>? data,
    bool preferExistingSelectedAddress = false,
  }) {
    final deviceId = (data?['peerDeviceId'] as String?)?.trim() ?? '';
    if (deviceId.isEmpty || deviceId == _identity?.deviceId) {
      return false;
    }
    final nickname = (data?['peerNickname'] as String?)?.trim() ?? '';
    final fingerprint = (data?['peerFingerprint'] as String?)?.trim() ?? '';
    final securePort = (data?['peerSecurePort'] as num?)?.toInt();
    final activePort =
        (data?['peerActivePort'] as num?)?.toInt() ?? _activePort;
    final fallbackProfile =
        _bestKnownProfileForDeviceId(deviceId) ??
        DeviceProfile(
          deviceId: deviceId,
          nickname: nickname.isNotEmpty ? nickname : 'LocalDrop',
          platform:
              (data?['peerPlatform'] as String?)?.trim().isNotEmpty ?? false
              ? (data?['peerPlatform'] as String).trim()
              : 'unknown',
          ipAddress: remoteAddress,
          ipAddresses: <String>[remoteAddress],
          activePort: activePort > 0
              ? activePort
              : NetworkConstants.primaryPort,
          securePort: securePort,
          certFingerprint: fingerprint,
          appVersion: (data?['peerAppVersion'] as String?) ?? '',
          protocolVersion: NetworkConstants.protocolVersion,
          capabilities: <String>[
            NetworkConstants.protocolCapabilityQueuedApproval,
            if (securePort != null && securePort > 0)
              NetworkConstants.protocolCapabilityHttpsTransfer,
          ],
          preferredAddressFamily: _addressFamilyFor(remoteAddress),
          lastSeen: DateTime.now(),
        );
    return _touchTransportVerifiedPeerLease(
      deviceId: deviceId,
      fallbackProfile: fallbackProfile,
      selectedAddress: remoteAddress,
      selectedPort: activePort,
      addressFamily: _addressFamilyFor(remoteAddress),
      preferExistingSelectedAddress: preferExistingSelectedAddress,
    );
  }

  bool _touchTransportVerifiedPeerLease({
    required String deviceId,
    required DeviceProfile fallbackProfile,
    String? selectedAddress,
    int? selectedPort,
    String? addressFamily,
    DateTime? timestamp,
    bool preferExistingSelectedAddress = false,
  }) {
    if (deviceId.trim().isEmpty) {
      return false;
    }
    final now = timestamp ?? DateTime.now();
    final existing = _transportVerifiedPeerLeases[deviceId];
    final bestProfile =
        _bestKnownProfileForDeviceId(deviceId) ??
        existing?.profile ??
        fallbackProfile;
    final candidateAddresses = _canonicalAddressSet(<String>[
      ...bestProfile.ipAddresses,
      bestProfile.ipAddress,
      ...fallbackProfile.ipAddresses,
      fallbackProfile.ipAddress,
      selectedAddress ?? '',
      existing?.selectedAddress ?? '',
    ]);
    final existingSelectedAddress = existing?.selectedAddress?.trim() ?? '';
    final availability = _peerAvailabilityById[deviceId];
    final canPreserveExistingSelectedAddress =
        preferExistingSelectedAddress &&
        existing != null &&
        availability?.status == PeerAvailabilityStatus.ready &&
        existingSelectedAddress.isNotEmpty &&
        candidateAddresses.contains(existingSelectedAddress) &&
        ((selectedAddress?.trim().isEmpty ?? true) ||
            candidateAddresses.contains(selectedAddress!.trim())) &&
        (selectedPort == null || selectedPort == existing.selectedPort);
    final effectiveSelectedAddress = canPreserveExistingSelectedAddress
        ? existing.selectedAddress
        : selectedAddress ?? existing?.selectedAddress;
    final effectiveSelectedPort = canPreserveExistingSelectedAddress
        ? existing.selectedPort
        : selectedPort ??
            existing?.selectedPort ??
            _peerAvailabilityById[deviceId]?.selectedPort ??
            bestProfile.activePort;
    final effectiveAddressFamily = canPreserveExistingSelectedAddress
        ? existing.addressFamily
        : addressFamily ??
            existing?.addressFamily ??
            _peerAvailabilityById[deviceId]?.addressFamily ??
            bestProfile.preferredAddressFamily;
    final lease =
        (existing ??
                TransportVerifiedPeerLease(
                  deviceId: deviceId,
                  profile: bestProfile,
                  lastSuccessfulActivityAt: now,
                ))
            .copyWith(
              profile: bestProfile,
              lastSuccessfulActivityAt: now,
              selectedAddress: effectiveSelectedAddress,
              selectedPort: effectiveSelectedPort,
              addressFamily: effectiveAddressFamily,
            );
    final materiallyChanged =
        existing == null ||
        !_sameTransportLeaseIdentity(existing, lease) ||
        !_sameProfileIdentity(existing.profile, bestProfile);
    _transportVerifiedPeerLeases[deviceId] = lease;
    if (materiallyChanged) {
      _rebuildVisibleNearbyDevices();
      _refreshComputedDiscoveryHealth();
    }
    return materiallyChanged;
  }

  void _pruneExpiredTransportVerifiedPeerLeases() {
    final now = DateTime.now();
    _transportVerifiedPeerLeases.removeWhere((_, lease) {
      return now.difference(lease.lastSuccessfulActivityAt) >
          _transportVerifiedPeerLeaseDuration;
    });
  }

  void _rebuildVisibleNearbyDevices() {
    _pruneExpiredTransportVerifiedPeerLeases();
    if (_isDiscoveryForegroundPaused) {
      _nearbyDevices = const <DeviceProfile>[];
      return;
    }
    final mergedById = <String, DeviceProfile>{
      for (final device in _discoveredNearbyDevices) device.deviceId: device,
    };
    for (final entry in _transportVerifiedPeerLeases.entries) {
      final discovered = mergedById[entry.key];
      mergedById[entry.key] = _mergeProfileWithTransportLease(
        base: discovered ?? entry.value.profile,
        lease: entry.value,
      );
    }
    final merged = mergedById.values.toList(growable: false)
      ..sort((a, b) {
        final nick = a.nickname.toLowerCase().compareTo(
          b.nickname.toLowerCase(),
        );
        if (nick != 0) {
          return nick;
        }
        return b.lastSeen.compareTo(a.lastSeen);
      });
    _nearbyDevices = merged;
  }

  DeviceProfile _mergeProfileWithTransportLease({
    required DeviceProfile base,
    required TransportVerifiedPeerLease lease,
  }) {
    final ipAddresses = _canonicalAddressSet(<String>[
      ...base.ipAddresses,
      ...lease.profile.ipAddresses,
      base.ipAddress,
      lease.profile.ipAddress,
      lease.selectedAddress ?? '',
    ]);
    final preferredAddressFamily =
        lease.addressFamily ?? base.preferredAddressFamily;
    final selectedAddress =
        lease.selectedAddress ??
        _preferredAddressForFamily(ipAddresses, preferredAddressFamily) ??
        (base.ipAddress.trim().isNotEmpty
            ? base.ipAddress
            : lease.profile.ipAddress);
    final activePort =
        lease.selectedPort ??
        (base.activePort > 0 ? base.activePort : lease.profile.activePort);
    return base.copyWith(
      nickname: base.nickname.trim().isNotEmpty
          ? base.nickname
          : lease.profile.nickname,
      platform: base.platform.trim().isNotEmpty && base.platform != 'unknown'
          ? base.platform
          : lease.profile.platform,
      ipAddress: selectedAddress,
      ipAddresses: ipAddresses,
      activePort: activePort,
      certFingerprint: base.certFingerprint.trim().isNotEmpty
          ? base.certFingerprint
          : lease.profile.certFingerprint,
      appVersion: base.appVersion.trim().isNotEmpty
          ? base.appVersion
          : lease.profile.appVersion,
      protocolVersion: base.protocolVersion.trim().isNotEmpty
          ? base.protocolVersion
          : lease.profile.protocolVersion,
      capabilities: base.capabilities.isNotEmpty
          ? base.capabilities
          : lease.profile.capabilities,
      securePort: base.securePort ?? lease.profile.securePort,
      preferredAddressFamily: preferredAddressFamily,
      lastSeen: lease.lastSuccessfulActivityAt.isAfter(base.lastSeen)
          ? lease.lastSuccessfulActivityAt
          : base.lastSeen,
      discoverySources: base.discoverySources.isNotEmpty
          ? base.discoverySources
          : lease.profile.discoverySources,
    );
  }

  DeviceProfile _profileForIncomingSession(IncomingTransferSession session) {
    return _bestKnownProfileForDeviceId(session.senderDeviceId) ??
        DeviceProfile(
          deviceId: session.senderDeviceId,
          nickname: session.senderNickname,
          platform: 'unknown',
          ipAddress: session.remoteAddress,
          ipAddresses: session.remoteAddress.trim().isEmpty
              ? const <String>[]
              : <String>[session.remoteAddress],
          activePort: _bestKnownPortForDevice(session.senderDeviceId),
          securePort: _bestKnownProfileForDeviceId(session.senderDeviceId)?.securePort,
          certFingerprint: session.senderFingerprint,
          appVersion: session.senderAppVersion,
          protocolVersion: session.protocolVersion,
          capabilities: const <String>[
            NetworkConstants.protocolCapabilityQueuedApproval,
          ],
          preferredAddressFamily: _addressFamilyFor(session.remoteAddress),
          lastSeen: DateTime.now(),
        );
  }

  DeviceProfile _profileForTransportSnapshot(
    TransferDiagnosticsSnapshot snapshot,
  ) {
    return _bestKnownProfileForDeviceId(snapshot.peerDeviceId) ??
        DeviceProfile(
          deviceId: snapshot.peerDeviceId,
          nickname: snapshot.peerNickname,
          platform: 'unknown',
          ipAddress: snapshot.selectedAddress ?? '',
          ipAddresses: (snapshot.selectedAddress ?? '').trim().isEmpty
              ? const <String>[]
              : <String>[snapshot.selectedAddress!],
          activePort:
              snapshot.selectedPort ??
              _bestKnownPortForDevice(snapshot.peerDeviceId),
          securePort: _bestKnownProfileForDeviceId(snapshot.peerDeviceId)?.securePort,
          certFingerprint: '',
          appVersion:
              _peerAvailabilityById[snapshot.peerDeviceId]?.appVersion ?? '',
          protocolVersion:
              _peerAvailabilityById[snapshot.peerDeviceId]?.protocolVersion ??
              NetworkConstants.protocolVersion,
          capabilities:
              _peerAvailabilityById[snapshot.peerDeviceId]?.capabilities ??
              const <String>[],
          preferredAddressFamily:
              snapshot.addressFamily ??
              _peerAvailabilityById[snapshot.peerDeviceId]?.addressFamily ??
              _addressFamilyFor(snapshot.selectedAddress),
          lastSeen: snapshot.updatedAt,
        );
  }

  DeviceProfile? _bestKnownProfileForDeviceId(String deviceId) {
    for (final device in _nearbyDevices) {
      if (device.deviceId == deviceId) {
        return device;
      }
    }
    for (final device in _discoveredNearbyDevices) {
      if (device.deviceId == deviceId) {
        return device;
      }
    }
    return _transportVerifiedPeerLeases[deviceId]?.profile;
  }

  DeviceProfile? _deviceByAddress(String address) {
    for (final device in _nearbyDevices) {
      if (device.ipAddress == address || device.ipAddresses.contains(address)) {
        return device;
      }
    }
    for (final device in _discoveredNearbyDevices) {
      if (device.ipAddress == address || device.ipAddresses.contains(address)) {
        return device;
      }
    }
    for (final lease in _transportVerifiedPeerLeases.values) {
      if (lease.selectedAddress == address ||
          lease.profile.ipAddress == address ||
          lease.profile.ipAddresses.contains(address)) {
        return lease.profile;
      }
    }
    return null;
  }

  int _bestKnownPortForDevice(String deviceId) {
    return _peerAvailabilityById[deviceId]?.selectedPort ??
        _bestKnownProfileForDeviceId(deviceId)?.activePort ??
        _transportVerifiedPeerLeases[deviceId]?.selectedPort ??
        _transportVerifiedPeerLeases[deviceId]?.profile.activePort ??
        NetworkConstants.primaryPort;
  }

  String _addressFamilyFor(String? address) {
    final parsed = address == null ? null : InternetAddress.tryParse(address);
    if (parsed?.type == InternetAddressType.IPv6) {
      return 'ipv6';
    }
    return 'ipv4';
  }

  int _addressFamilyPriority(String address) {
    return _addressFamilyFor(address) == 'ipv4' ? 0 : 1;
  }

  List<_HealthSweepTarget> _buildZeroPeerHealthSweepTargets(
    List<NetworkInterfaceSnapshot> interfaces,
  ) {
    final localAddresses = <String>{
      for (final snapshot in interfaces) snapshot.address.trim(),
    };
    final targets = <String, _HealthSweepTarget>{};

    void addTarget(String address, int port) {
      if (address.trim().isEmpty ||
          localAddresses.contains(address) ||
          _isKnownSweepAddress(address)) {
        return;
      }
      final target = _HealthSweepTarget(address: address, port: port);
      targets.putIfAbsent(target.key, () => target);
    }

    final eligibleInterfaces = interfaces.where(
      (item) => item.isEligibleForDiscovery,
    );
    for (final port in NetworkConstants.scanPorts) {
      for (final snapshot in eligibleInterfaces) {
        for (final host in _expandSweepHosts(snapshot)) {
          addTarget(host, port);
        }
      }
    }

    return targets.values.toList(growable: false);
  }

  bool _promoteHealthSweepPeer(TransferHealthPeerSnapshot snapshot) {
    final deviceId = snapshot.profile.deviceId;
    final existing = _peerAvailabilityById[deviceId];
    final isSameReadyPeer =
        existing != null &&
        existing.status == PeerAvailabilityStatus.ready &&
        existing.selectedAddress == snapshot.selectedAddress &&
        existing.selectedPort == snapshot.selectedPort &&
        existing.addressFamily == snapshot.addressFamily &&
        existing.nickname == snapshot.profile.nickname &&
        existing.protocolVersion == snapshot.profile.protocolVersion &&
        existing.appVersion == snapshot.profile.appVersion;

    _peerAvailabilityProbeFutures.remove(deviceId);
    _nextPeerAvailabilityProbeGeneration(deviceId);
    _peerAvailabilityById[deviceId] = PeerAvailabilitySnapshot(
      deviceId: deviceId,
      nickname: snapshot.profile.nickname,
      status: PeerAvailabilityStatus.ready,
      updatedAt: DateTime.now(),
      selectedAddress: snapshot.selectedAddress,
      selectedPort: snapshot.selectedPort,
      addressFamily: snapshot.addressFamily,
      protocolVersion: snapshot.profile.protocolVersion,
      appVersion: snapshot.profile.appVersion,
      capabilities: snapshot.profile.capabilities,
    );

    _touchTransportVerifiedPeerLease(
      deviceId: deviceId,
      fallbackProfile: snapshot.profile,
      selectedAddress: snapshot.selectedAddress,
      selectedPort: snapshot.selectedPort,
      addressFamily: snapshot.addressFamily,
    );
    _markHealthyDiscoveryActivity();
    return !isSameReadyPeer;
  }

  bool _isKnownSweepAddress(String address) {
    if (_isLoopbackAddress(address)) {
      return true;
    }
    for (final device in _nearbyDevices) {
      if (device.ipAddress == address || device.ipAddresses.contains(address)) {
        return true;
      }
    }
    for (final device in _discoveredNearbyDevices) {
      if (device.ipAddress == address || device.ipAddresses.contains(address)) {
        return true;
      }
    }
    for (final lease in _transportVerifiedPeerLeases.values) {
      if (lease.selectedAddress == address ||
          lease.profile.ipAddress == address ||
          lease.profile.ipAddresses.contains(address)) {
        return true;
      }
    }
    return false;
  }

  Iterable<String> _expandSweepHosts(NetworkInterfaceSnapshot snapshot) sync* {
    final local = _parseIpv4(snapshot.address);
    if (local == null) {
      return;
    }
    final effectivePrefix = snapshot.prefixLength < 24
        ? 24
        : snapshot.prefixLength > 30
        ? 30
        : snapshot.prefixLength;
    final ip = _ipv4ToInt(local);
    final mask = effectivePrefix == 0
        ? 0
        : (0xFFFFFFFF << (32 - effectivePrefix)) & 0xFFFFFFFF;
    final network = ip & mask;
    final broadcast = network | (~mask & 0xFFFFFFFF);
    for (var host = network + 1; host < broadcast; host += 1) {
      if (host == ip) {
        continue;
      }
      yield _ipv4FromInt(host);
    }
  }

  List<int>? _parseIpv4(String value) {
    final segments = value.split('.');
    if (segments.length != 4) {
      return null;
    }
    final parts = <int>[];
    for (final segment in segments) {
      final parsed = int.tryParse(segment);
      if (parsed == null || parsed < 0 || parsed > 255) {
        return null;
      }
      parts.add(parsed);
    }
    return parts;
  }

  int _ipv4ToInt(List<int> parts) {
    return (parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3];
  }

  String _ipv4FromInt(int value) {
    return <String>[
      ((value >> 24) & 0xFF).toString(),
      ((value >> 16) & 0xFF).toString(),
      ((value >> 8) & 0xFF).toString(),
      (value & 0xFF).toString(),
    ].join('.');
  }

  String? _preferredAddressForFamily(
    List<String> addresses,
    String? preferredAddressFamily,
  ) {
    if (addresses.isEmpty) {
      return null;
    }
    final expectedType = preferredAddressFamily == 'ipv6'
        ? InternetAddressType.IPv6
        : InternetAddressType.IPv4;
    for (final address in addresses) {
      final parsed = InternetAddress.tryParse(address);
      if (parsed?.type == expectedType) {
        return address;
      }
    }
    return addresses.first;
  }

  bool _isLoopbackAddress(String address) {
    final parsed = InternetAddress.tryParse(address);
    return parsed?.isLoopback ?? false;
  }

  String _incomingActionFailureMessage({
    required String fallback,
    required Object error,
  }) {
    final details = error.toString().trim();
    if (details.isEmpty) {
      return fallback;
    }
    return '$fallback $details';
  }

  Future<void> _logTransportEvent(
    String category,
    String message, {
    Map<String, Object?>? data,
  }) async {
    try {
      await _transportLogService.log(category, message, data: data);
    } catch (_) {
      // Logging must never interrupt transfer flows.
    }
  }

  @override
  void dispose() {
    _discoveryRescanTimer?.cancel();
    _discoverySubscription?.cancel();
    _discoveryHealthSubscription?.cancel();
    unawaited(_localNetworkPlatformService.releaseMulticastLock());
    unawaited(_discoveryService.stop());
    _discoveryService.dispose();
    unawaited(_transferServer.stop());
    unawaited(_transportLogService.dispose());
    super.dispose();
  }

  void _applyDiscoveryHealth(DiscoveryHealth health) {
    final previous = _discoveryHealth;
    _discoveryHealth = _reconcileDiscoveryHealth(health);
    _trackHealthyDiscoveryFromHealth(
      previous: previous,
      next: _discoveryHealth,
    );
  }

  void _refreshComputedDiscoveryHealth() {
    _discoveryHealth = _reconcileDiscoveryHealth(_discoveryHealth);
  }

  int get _verifiedPeerCount {
    final activeIds = _nearbyDevices.map((item) => item.deviceId).toSet();
    return _peerAvailabilityById.values
        .where(
          (item) =>
              activeIds.contains(item.deviceId) &&
              item.status == PeerAvailabilityStatus.ready,
        )
        .length;
  }

  DiscoveryHealth _reconcileDiscoveryHealth(DiscoveryHealth health) {
    final visibleDeviceCount = _nearbyDevices.length;
    final effectiveDiscoveredCount =
        health.discoveredDeviceCount >= visibleDeviceCount
        ? health.discoveredDeviceCount
        : visibleDeviceCount;
    return health.copyWith(
      firewallSetupResult: _discoveryHealth.firewallSetupResult,
      discoveredDeviceCount: effectiveDiscoveredCount,
      verifiedSendReadyPeerCount: _verifiedPeerCount,
      hasBlockingIssue: health.hasBlockingIssue || _hasFirewallSetupIssue,
    );
  }

  bool _shouldPreserveVisibleNearbyDevices(List<DeviceProfile> devices) {
    return devices.isEmpty &&
        _discoveredNearbyDevices.isNotEmpty &&
        _discoveryScanInFlightCount > 0 &&
        !_isDiscoveryRestarting &&
        _discoveryService.isRunning &&
        !_isDiscoveryForegroundPaused;
  }

  void _markHealthyDiscoveryActivity() {
    _lastHealthyDiscoveryAt = DateTime.now();
    _watchdogSoftRefreshPendingHardRestart = false;
  }

  void _trackHealthyDiscoveryFromHealth({
    required DiscoveryHealth previous,
    required DiscoveryHealth next,
  }) {
    final previousScan = previous.lastScanAt;
    final nextScan = next.lastScanAt;
    final hasFreshScan =
        nextScan != null &&
        (previousScan == null || nextScan.isAfter(previousScan));
    final hasHealthySignal =
        next.hasHealthyBackend || _discoveredNearbyDevices.isNotEmpty;
    if (hasFreshScan && hasHealthySignal) {
      _markHealthyDiscoveryActivity();
    }
  }

  Future<void> _runDiscoveryWatchdogIfNeeded() async {
    if (_identity == null ||
        _isDiscoveryForegroundPaused ||
        _isDiscoveryRestarting ||
        !_discoveryService.isRunning) {
      return;
    }

    final lastHealthyAt = _lastHealthyDiscoveryAt;
    if (lastHealthyAt == null) {
      _lastHealthyDiscoveryAt = DateTime.now();
      return;
    }

    final unhealthyFor = DateTime.now().difference(lastHealthyAt);
    if (unhealthyFor < _discoveryWatchdogThreshold) {
      return;
    }

    if (!_watchdogSoftRefreshPendingHardRestart) {
      _watchdogSoftRefreshPendingHardRestart = true;
      await _logTransportEvent(
        'discovery-watchdog',
        'Discovery watchdog triggered a soft refresh',
        data: <String, Object?>{
          'unhealthyForMs': unhealthyFor.inMilliseconds,
          'visiblePeerCount': _nearbyDevices.length,
          'hasHealthyBackend': _discoveryHealth.hasHealthyBackend,
          'isRunning': _discoveryHealth.isRunning,
          'lastScanAt': _discoveryHealth.lastScanAt?.toIso8601String(),
        },
      );
      await _performDiscoveryRefresh(
        restartBackend: false,
        forcePeerAvailability: true,
      );
      return;
    }

    await _logTransportEvent(
      'discovery-watchdog',
      'Discovery watchdog escalated to a hard restart',
      data: <String, Object?>{
        'unhealthyForMs': unhealthyFor.inMilliseconds,
        'visiblePeerCount': _nearbyDevices.length,
        'hasHealthyBackend': _discoveryHealth.hasHealthyBackend,
        'isRunning': _discoveryHealth.isRunning,
        'lastScanAt': _discoveryHealth.lastScanAt?.toIso8601String(),
      },
    );
    _watchdogSoftRefreshPendingHardRestart = false;
    await restartDiscovery();
  }
}

class _HealthSweepTarget {
  const _HealthSweepTarget({required this.address, required this.port});

  final String address;
  final int port;

  String get key => '$address:$port';
}
