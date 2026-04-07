const Object _copySentinel = Object();

const Object _sentinel = Object();

enum DiscoveryBackendKind {
  androidNsd,
  appleBonjour,
  udpLan;

  static DiscoveryBackendKind fromName(String value) {
    return DiscoveryBackendKind.values.firstWhere(
      (item) => item.name == value,
      orElse: () => DiscoveryBackendKind.udpLan,
    );
  }
}

enum DiscoveryPauseReason {
  none,
  backgrounded,
  permissionsBlocked,
  backendFailed;

  static DiscoveryPauseReason fromName(String value) {
    return DiscoveryPauseReason.values.firstWhere(
      (item) => item.name == value,
      orElse: () => DiscoveryPauseReason.none,
    );
  }
}

class DiscoveryBackendState {
  const DiscoveryBackendState({
    this.activeBackends = const <DiscoveryBackendKind>[],
    this.healthyBackends = const <DiscoveryBackendKind>[],
    this.degradedBackends = const <DiscoveryBackendKind>[],
    this.peerCountsByBackend = const <String, int>{},
    this.lastErrorsByBackend = const <String, String?>{},
    this.lastLogsByBackend = const <String, String?>{},
    this.isRunning = false,
    this.isStarting = false,
    this.isBrowsing = false,
    this.isPublishing = false,
    this.lastError,
    this.lastPermissionIssue,
    this.lastBackendLogMessage,
  });

  final List<DiscoveryBackendKind> activeBackends;
  final List<DiscoveryBackendKind> healthyBackends;
  final List<DiscoveryBackendKind> degradedBackends;
  final Map<String, int> peerCountsByBackend;
  final Map<String, String?> lastErrorsByBackend;
  final Map<String, String?> lastLogsByBackend;
  final bool isRunning;
  final bool isStarting;
  final bool isBrowsing;
  final bool isPublishing;
  final String? lastError;
  final String? lastPermissionIssue;
  final String? lastBackendLogMessage;

  DiscoveryBackendKind? get backendKind =>
      activeBackends.isEmpty ? null : activeBackends.first;

  DiscoveryBackendKind? get fallbackBackendKind =>
      activeBackends.length < 2 ? null : activeBackends.last;

  bool get isFallbackActive => false;

  bool get hasHealthyBackend => healthyBackends.isNotEmpty;

  DiscoveryBackendState copyWith({
    Object? activeBackends = _copySentinel,
    Object? healthyBackends = _copySentinel,
    Object? degradedBackends = _copySentinel,
    Object? peerCountsByBackend = _copySentinel,
    Object? lastErrorsByBackend = _copySentinel,
    Object? lastLogsByBackend = _copySentinel,
    bool? isRunning,
    bool? isStarting,
    bool? isBrowsing,
    bool? isPublishing,
    Object? lastError = _copySentinel,
    Object? lastPermissionIssue = _copySentinel,
    Object? lastBackendLogMessage = _copySentinel,
  }) {
    return DiscoveryBackendState(
      activeBackends: identical(activeBackends, _copySentinel)
          ? this.activeBackends
          : List<DiscoveryBackendKind>.from(
              activeBackends as List<DiscoveryBackendKind>,
            ),
      healthyBackends: identical(healthyBackends, _copySentinel)
          ? this.healthyBackends
          : List<DiscoveryBackendKind>.from(
              healthyBackends as List<DiscoveryBackendKind>,
            ),
      degradedBackends: identical(degradedBackends, _copySentinel)
          ? this.degradedBackends
          : List<DiscoveryBackendKind>.from(
              degradedBackends as List<DiscoveryBackendKind>,
            ),
      peerCountsByBackend: identical(peerCountsByBackend, _copySentinel)
          ? this.peerCountsByBackend
          : Map<String, int>.from(peerCountsByBackend as Map<String, int>),
      lastErrorsByBackend: identical(lastErrorsByBackend, _copySentinel)
          ? this.lastErrorsByBackend
          : Map<String, String?>.from(
              lastErrorsByBackend as Map<String, String?>,
            ),
      lastLogsByBackend: identical(lastLogsByBackend, _copySentinel)
          ? this.lastLogsByBackend
          : Map<String, String?>.from(
              lastLogsByBackend as Map<String, String?>,
            ),
      isRunning: isRunning ?? this.isRunning,
      isStarting: isStarting ?? this.isStarting,
      isBrowsing: isBrowsing ?? this.isBrowsing,
      isPublishing: isPublishing ?? this.isPublishing,
      lastError: identical(lastError, _copySentinel)
          ? this.lastError
          : lastError as String?,
      lastPermissionIssue: identical(lastPermissionIssue, _copySentinel)
          ? this.lastPermissionIssue
          : lastPermissionIssue as String?,
      lastBackendLogMessage: identical(lastBackendLogMessage, _copySentinel)
          ? this.lastBackendLogMessage
          : lastBackendLogMessage as String?,
    );
  }
}

class DiscoveryHealth {
  const DiscoveryHealth({
    this.backend = 'mdns',
    this.isRunning = false,
    this.isStarting = false,
    this.isScanning = false,
    this.isBrowsing = false,
    this.isPublishing = false,
    this.boundPort,
    this.lastScanAt,
    this.lastPublishAt,
    this.packetsSent = 0,
    this.packetsReceived = 0,
    this.interfaceCount = 0,
    this.lastScanTargetCount = 0,
    this.discoveredDeviceCount = 0,
    this.lastError,
    this.lastPermissionIssue,
    this.resolvedAddressFamily,
    this.backendState = const DiscoveryBackendState(),
    this.isPaused = false,
    this.pauseReason = DiscoveryPauseReason.none,
    this.verifiedSendReadyPeerCount = 0,
    this.lastBackendLogMessage,
    this.firewallSetupResult = const FirewallSetupResult.notRequired(),
    this.hasBlockingIssue = false,
  });

  final String backend;
  final bool isRunning;
  final bool isStarting;
  final bool isScanning;
  final bool isBrowsing;
  final bool isPublishing;
  final int? boundPort;
  final DateTime? lastScanAt;
  final DateTime? lastPublishAt;
  final int packetsSent;
  final int packetsReceived;
  final int interfaceCount;
  final int lastScanTargetCount;
  final int discoveredDeviceCount;
  final String? lastError;
  final String? lastPermissionIssue;
  final String? resolvedAddressFamily;
  final DiscoveryBackendState backendState;
  final bool isPaused;
  final DiscoveryPauseReason pauseReason;
  final int verifiedSendReadyPeerCount;
  final String? lastBackendLogMessage;
  final FirewallSetupResult firewallSetupResult;
  final bool hasBlockingIssue;

  bool get firewallReady => firewallSetupResult.isConfigured;

  bool get hasHealthyBackend => backendState.healthyBackends.isNotEmpty;

  DiscoveryHealth copyWith({
    String? backend,
    bool? isRunning,
    bool? isStarting,
    bool? isScanning,
    bool? isBrowsing,
    bool? isPublishing,
    Object? boundPort = _sentinel,
    Object? lastScanAt = _sentinel,
    Object? lastPublishAt = _sentinel,
    int? packetsSent,
    int? packetsReceived,
    int? interfaceCount,
    int? lastScanTargetCount,
    int? discoveredDeviceCount,
    Object? lastError = _sentinel,
    Object? lastPermissionIssue = _sentinel,
    Object? resolvedAddressFamily = _sentinel,
    DiscoveryBackendState? backendState,
    bool? isPaused,
    DiscoveryPauseReason? pauseReason,
    int? verifiedSendReadyPeerCount,
    Object? lastBackendLogMessage = _sentinel,
    FirewallSetupResult? firewallSetupResult,
    bool? hasBlockingIssue,
  }) {
    return DiscoveryHealth(
      backend: backend ?? this.backend,
      isRunning: isRunning ?? this.isRunning,
      isStarting: isStarting ?? this.isStarting,
      isScanning: isScanning ?? this.isScanning,
      isBrowsing: isBrowsing ?? this.isBrowsing,
      isPublishing: isPublishing ?? this.isPublishing,
      boundPort: identical(boundPort, _sentinel)
          ? this.boundPort
          : boundPort as int?,
      lastScanAt: identical(lastScanAt, _sentinel)
          ? this.lastScanAt
          : lastScanAt as DateTime?,
      lastPublishAt: identical(lastPublishAt, _sentinel)
          ? this.lastPublishAt
          : lastPublishAt as DateTime?,
      packetsSent: packetsSent ?? this.packetsSent,
      packetsReceived: packetsReceived ?? this.packetsReceived,
      interfaceCount: interfaceCount ?? this.interfaceCount,
      lastScanTargetCount: lastScanTargetCount ?? this.lastScanTargetCount,
      discoveredDeviceCount:
          discoveredDeviceCount ?? this.discoveredDeviceCount,
      lastError: identical(lastError, _sentinel)
          ? this.lastError
          : lastError as String?,
      lastPermissionIssue: identical(lastPermissionIssue, _sentinel)
          ? this.lastPermissionIssue
          : lastPermissionIssue as String?,
      resolvedAddressFamily: identical(resolvedAddressFamily, _sentinel)
          ? this.resolvedAddressFamily
          : resolvedAddressFamily as String?,
      backendState: backendState ?? this.backendState,
      isPaused: isPaused ?? this.isPaused,
      pauseReason: pauseReason ?? this.pauseReason,
      verifiedSendReadyPeerCount:
          verifiedSendReadyPeerCount ?? this.verifiedSendReadyPeerCount,
      lastBackendLogMessage: identical(lastBackendLogMessage, _sentinel)
          ? this.lastBackendLogMessage
          : lastBackendLogMessage as String?,
      firewallSetupResult: firewallSetupResult ?? this.firewallSetupResult,
      hasBlockingIssue: hasBlockingIssue ?? this.hasBlockingIssue,
    );
  }
}

enum FirewallSetupStatus {
  notRequired,
  alreadyConfigured,
  configuredNow,
  denied,
  failed,
}

class FirewallSetupResult {
  const FirewallSetupResult({required this.status, this.message});

  const FirewallSetupResult.notRequired()
    : status = FirewallSetupStatus.notRequired,
      message = null;

  final FirewallSetupStatus status;
  final String? message;

  bool get isConfigured {
    return status == FirewallSetupStatus.notRequired ||
        status == FirewallSetupStatus.alreadyConfigured ||
        status == FirewallSetupStatus.configuredNow;
  }

  bool get isFailure {
    return status == FirewallSetupStatus.denied ||
        status == FirewallSetupStatus.failed;
  }

  bool get wasConfiguredNow => status == FirewallSetupStatus.configuredNow;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{'status': status.name, 'message': message};
  }

  factory FirewallSetupResult.fromJson(Map<dynamic, dynamic> json) {
    final statusName =
        (json['status'] as String?) ?? FirewallSetupStatus.failed.name;
    final status = FirewallSetupStatus.values.firstWhere(
      (item) => item.name == statusName,
      orElse: () => FirewallSetupStatus.failed,
    );
    return FirewallSetupResult(
      status: status,
      message: json['message'] as String?,
    );
  }
}
