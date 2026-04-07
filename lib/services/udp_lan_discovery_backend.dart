import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/constants/network_constants.dart';
import '../models/device_profile.dart';
import '../models/discovery_health.dart';
import '../models/network_interface_snapshot.dart';
import 'discovery_backend.dart';
import 'discovery_packet_codec.dart';
import 'discovery_registry.dart';
import 'discovery_target_planner.dart';

class UdpLanDiscoveryBackend implements DiscoveryBackend {
  UdpLanDiscoveryBackend({
    required Future<List<NetworkInterfaceSnapshot>> Function() loadInterfaces,
    Duration? staleAfter,
    void Function(String message)? logger,
  }) : _loadInterfaces = loadInterfaces,
       _logger = logger,
       _registry = DiscoveryRegistry(
         staleAfter: staleAfter ?? NetworkConstants.discoveryStaleTimeout,
       );

  static const Set<String> _peerPacketTypes = <String>{
    'discovery_announce',
    'discovery_request',
    'discovery_response',
  };

  final Future<List<NetworkInterfaceSnapshot>> Function() _loadInterfaces;
  final void Function(String message)? _logger;
  final DiscoveryRegistry _registry;
  final StreamController<List<DeviceProfile>> _devicesController =
      StreamController<List<DeviceProfile>>.broadcast();
  final StreamController<DiscoveryHealth> _healthController =
      StreamController<DiscoveryHealth>.broadcast();

  RawDatagramSocket? _socket;
  Timer? _cleanupTimer;
  Timer? _heartbeatTimer;
  bool _heartbeatPulseInProgress = false;
  bool _scanInProgress = false;
  DiscoveryHealth _health = DiscoveryHealth(
    backend: 'udp-lan',
    backendState: DiscoveryBackendState(
      activeBackends: <DiscoveryBackendKind>[DiscoveryBackendKind.udpLan],
      peerCountsByBackend: <String, int>{DiscoveryBackendKind.udpLan.name: 0},
      lastErrorsByBackend: <String, String?>{},
      lastLogsByBackend: <String, String?>{},
    ),
  );
  late String _deviceId;
  late int _activePort;
  int? _securePort;
  late String Function() _nicknameProvider;
  late String Function() _fingerprintProvider;
  late String _appVersion;
  int _consecutiveZeroPeerScans = 0;
  List<NetworkInterfaceSnapshot> _lastNonEmptyInterfaces =
      const <NetworkInterfaceSnapshot>[];
  DateTime? _startupWarmupUntil;

  @override
  Stream<List<DeviceProfile>> get devicesStream => _devicesController.stream;

  @override
  Stream<DiscoveryHealth> get healthStream => _healthController.stream;

  @override
  List<DeviceProfile> get currentDevices => _registry.sorted();

  @override
  DiscoveryHealth get currentHealth => _health;

  @override
  bool get isRunning => _socket != null;

  @override
  DiscoveryBackendKind get backendKind => DiscoveryBackendKind.udpLan;

  @override
  Future<void> start({
    required String deviceId,
    required int activePort,
    int? securePort,
    required String Function() nicknameProvider,
    required String Function() fingerprintProvider,
    required String appVersion,
  }) async {
    await stop();
    _deviceId = deviceId;
    _activePort = activePort;
    _securePort = securePort;
    _nicknameProvider = nicknameProvider;
    _fingerprintProvider = fingerprintProvider;
    _appVersion = appVersion;
    _startupWarmupUntil = DateTime.now().add(
      NetworkConstants.discoveryStartupWarmupDuration,
    );

    _log('UDP LAN discovery binding to port $activePort.');
    _setHealth(
      _health.copyWith(
        backend: 'udp-lan',
        isStarting: true,
        boundPort: activePort,
        lastError: null,
        lastPermissionIssue: null,
        hasBlockingIssue: false,
        backendState: _buildBackendState(
          peerCount: 0,
          isStarting: true,
          lastBackendLogMessage: 'UDP LAN discovery starting.',
        ),
        lastBackendLogMessage: 'UDP LAN discovery starting.',
      ),
    );

    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        activePort,
        reuseAddress: true,
        reusePort: false,
      );
      _socket = socket;
      socket
        ..broadcastEnabled = true
        ..multicastLoopback = true
        ..readEventsEnabled = true
        ..writeEventsEnabled = false;

      await _joinMulticastGroups(socket);
      if (!identical(_socket, socket)) {
        return;
      }

      socket.listen(_handleSocketEvent, onError: _handleSocketError);
      _cleanupTimer = Timer.periodic(
        NetworkConstants.discoveryCleanupInterval,
        (_) => _cleanupRegistry(),
      );
      _startHeartbeat();

      final interfaces = await _safeInterfaces();
      if (!identical(_socket, socket)) {
        return;
      }

      _setHealth(
        _health.copyWith(
          isStarting: false,
          isRunning: true,
          isBrowsing: true,
          isPublishing: true,
          boundPort: activePort,
          interfaceCount: interfaces.length,
          lastError: null,
          lastPermissionIssue: null,
          hasBlockingIssue: false,
          backendState: _buildBackendState(
            peerCount: 0,
            isRunning: true,
            isBrowsing: true,
            isPublishing: true,
            isHealthy: true,
            lastBackendLogMessage: 'UDP LAN discovery started.',
          ),
          lastBackendLogMessage: 'UDP LAN discovery started.',
        ),
      );
      _log(
        'UDP LAN discovery started on port $activePort across ${interfaces.length} interface(s).',
      );
    } catch (error) {
      _log('UDP LAN discovery failed to start: $error');
      await stop();
      _setHealth(
        _health.copyWith(
          backend: 'udp-lan',
          boundPort: activePort,
          lastError: error.toString(),
          lastPermissionIssue: null,
          hasBlockingIssue: true,
          backendState: _buildBackendState(
            peerCount: 0,
            isDegraded: true,
            lastError: error.toString(),
            lastBackendLogMessage: 'UDP LAN discovery failed to start.',
          ),
          lastBackendLogMessage: 'UDP LAN discovery failed to start.',
        ),
      );
      rethrow;
    }
  }

  @override
  Future<void> stop() async {
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _consecutiveZeroPeerScans = 0;
    _lastNonEmptyInterfaces = const <NetworkInterfaceSnapshot>[];
    _startupWarmupUntil = null;
    _heartbeatPulseInProgress = false;
    _scanInProgress = false;
    _socket?.close();
    _socket = null;
    _registry.clear();
    _emitDevices();
    _setHealth(
      DiscoveryHealth(
        backend: 'udp-lan',
        backendState: DiscoveryBackendState(
          activeBackends: <DiscoveryBackendKind>[DiscoveryBackendKind.udpLan],
          peerCountsByBackend: <String, int>{
            DiscoveryBackendKind.udpLan.name: 0,
          },
          lastErrorsByBackend: <String, String?>{},
          lastLogsByBackend: <String, String?>{},
        ),
      ),
    );
  }

  @override
  Future<void> announceNow({bool burst = false}) async {
    if (_socket == null) {
      return;
    }

    final iterations = burst ? NetworkConstants.discoveryAnnounceBurstCount : 1;
    if (burst) {
      _log('UDP LAN discovery announce burst started.');
    }
    for (var index = 0; index < iterations; index++) {
      try {
        await _sendAnnouncementPacket();
      } catch (error) {
        _log('Failed to send UDP announcement burst: $error');
        _setHealth(
          _health.copyWith(
            lastError: error.toString(),
            hasBlockingIssue: true,
            backendState: _buildBackendState(
              peerCount: _peerCount,
              isRunning: _socket != null,
              isBrowsing: _socket != null,
              isPublishing: _socket != null,
              isDegraded: true,
              lastError: error.toString(),
              lastBackendLogMessage: 'UDP LAN discovery announce failed.',
            ),
            lastBackendLogMessage: 'UDP LAN discovery announce failed.',
          ),
        );
      }
      if (index + 1 < iterations) {
        await Future<void>.delayed(
          NetworkConstants.discoveryAnnounceBurstSpacing,
        );
      }
    }
    if (burst) {
      _log('UDP LAN discovery announce burst completed.');
    }
  }

  @override
  Future<void> scanNow({bool burstAnnounce = false}) async {
    final socket = _socket;
    if (socket == null || _scanInProgress) {
      return;
    }
    _scanInProgress = true;

    final shouldForceRecoveryBurst =
        !burstAnnounce &&
        (Platform.isAndroid || Platform.isIOS) &&
        _consecutiveZeroPeerScans >= 3;

    final startedAt = DateTime.now();
    _log(
      burstAnnounce || shouldForceRecoveryBurst
          ? 'UDP LAN discovery scan started with announce burst.'
          : 'UDP LAN discovery scan started.',
    );
    _setHealth(
      _health.copyWith(
        isScanning: true,
        lastError: null,
        lastPermissionIssue: null,
        hasBlockingIssue: false,
        backendState: _buildBackendState(
          peerCount: _peerCount,
          isRunning: true,
          isBrowsing: true,
          isPublishing: true,
          isHealthy: true,
          lastBackendLogMessage: 'UDP LAN discovery scan started.',
        ),
        lastBackendLogMessage: 'UDP LAN discovery scan started.',
      ),
    );

    try {
      if (burstAnnounce || shouldForceRecoveryBurst) {
        await announceNow(burst: true);
      }

      final interfaces = await _safeInterfaces();
      final targets = DiscoveryTargetPlanner.buildTargets(
        interfaces: interfaces,
        scanPorts: NetworkConstants.scanPorts,
        multicastAddress: NetworkConstants.discoveryMulticastAddress,
      );
      final sent = await _sendPayloadToTargets(
        socket: socket,
        type: 'discovery_request',
        targets: targets,
      );
      _consecutiveZeroPeerScans = _peerCount == 0
          ? _consecutiveZeroPeerScans + 1
          : 0;

      _setHealth(
        _health.copyWith(
          isScanning: false,
          isRunning: true,
          isBrowsing: true,
          isPublishing: true,
          packetsSent: _health.packetsSent + sent,
          lastScanTargetCount: targets.length,
          lastScanAt: startedAt,
          interfaceCount: interfaces.length,
          discoveredDeviceCount: _peerCount,
          resolvedAddressFamily: currentDevices.isEmpty
              ? _health.resolvedAddressFamily
              : currentDevices.first.preferredAddressFamily,
          lastError: null,
          hasBlockingIssue: false,
          backendState: _buildBackendState(
            peerCount: _peerCount,
            isRunning: true,
            isBrowsing: true,
            isPublishing: true,
            isHealthy: true,
            lastBackendLogMessage: 'UDP LAN discovery scan complete.',
          ),
          lastBackendLogMessage: 'UDP LAN discovery scan complete.',
        ),
      );
      _log(
        'UDP LAN discovery scan finished with ${targets.length} target(s) and $_peerCount peer(s).',
      );
    } catch (error) {
      _log('UDP LAN discovery scan failed: $error');
      _setHealth(
        _health.copyWith(
          isScanning: false,
          isRunning: _socket != null,
          isBrowsing: _socket != null,
          isPublishing: _socket != null,
          lastScanAt: startedAt,
          lastError: error.toString(),
          hasBlockingIssue: true,
          backendState: _buildBackendState(
            peerCount: _peerCount,
            isRunning: _socket != null,
            isBrowsing: _socket != null,
            isPublishing: _socket != null,
            isDegraded: true,
            lastError: error.toString(),
            lastBackendLogMessage: 'UDP LAN discovery scan failed.',
          ),
          lastBackendLogMessage: 'UDP LAN discovery scan failed.',
        ),
      );
      rethrow;
    } finally {
      _scanInProgress = false;
    }
  }

  @override
  void dispose() {
    unawaited(stop());
    _devicesController.close();
    _healthController.close();
  }

  Future<void> _joinMulticastGroups(RawDatagramSocket socket) async {
    try {
      socket.joinMulticast(
        InternetAddress(NetworkConstants.discoveryMulticastAddress),
      );
    } catch (error) {
      if (_isSocketClosed(error) || !identical(_socket, socket)) {
        return;
      }
      _log('Failed to join default UDP discovery multicast group: $error');
    }

    final actualInterfaces = await _matchingSystemInterfaces();
    for (final iface in actualInterfaces) {
      try {
        socket.joinMulticast(
          InternetAddress(NetworkConstants.discoveryMulticastAddress),
          iface,
        );
      } catch (error) {
        if (_isSocketClosed(error) || !identical(_socket, socket)) {
          return;
        }
        if (_isAddressAlreadyInUse(error)) {
          continue;
        }
        _log('Failed to join multicast on ${iface.name}: $error');
      }
    }
  }

  void _handleSocketEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) {
      return;
    }

    final datagram = _socket?.receive();
    if (datagram == null) {
      return;
    }

    try {
      final payload =
          jsonDecode(utf8.decode(datagram.data)) as Map<String, dynamic>;
      final packetType = (payload['type'] as String?) ?? '';
      if (!_peerPacketTypes.contains(packetType)) {
        return;
      }
      if (DiscoveryPacketCodec.isSelfPayload(
        payload,
        localDeviceId: _deviceId,
      )) {
        return;
      }

      final profile = DiscoveryPacketCodec.tryParseProfile(
        payload,
        datagram.address.address,
        protocolVersion: NetworkConstants.protocolVersion,
      );
      if (profile == null) {
        return;
      }

      _registry.upsert(profile);
      _consecutiveZeroPeerScans = 0;
      _log(
        'UDP LAN discovery received $packetType from ${profile.deviceId} at ${profile.ipAddress}.',
      );
      _emitDevices();
      _setHealth(
        _health.copyWith(
          isRunning: _socket != null,
          isBrowsing: _socket != null,
          isPublishing: _socket != null,
          packetsReceived: _health.packetsReceived + 1,
          discoveredDeviceCount: _peerCount,
          resolvedAddressFamily: profile.preferredAddressFamily,
          lastError: null,
          hasBlockingIssue: false,
          backendState: _buildBackendState(
            peerCount: _peerCount,
            isRunning: _socket != null,
            isBrowsing: _socket != null,
            isPublishing: _socket != null,
            isHealthy: true,
            lastBackendLogMessage: 'UDP LAN discovery received $packetType.',
          ),
          lastBackendLogMessage: 'UDP LAN discovery received $packetType.',
        ),
      );

      if (packetType == 'discovery_request') {
        unawaited(
          _respondToRequest(
            requestPayload: payload,
            remoteAddress: datagram.address,
            remotePort: datagram.port,
          ),
        );
      }
    } catch (error) {
      _log('Failed to parse UDP discovery packet: $error');
    }
  }

  void _handleSocketError(Object error) {
    final socketAlive = _socket != null;
    _setHealth(
      _health.copyWith(
        isRunning: socketAlive,
        isBrowsing: socketAlive,
        isPublishing: socketAlive,
        lastError: error.toString(),
        hasBlockingIssue: true,
        backendState: _buildBackendState(
          peerCount: _peerCount,
          isRunning: socketAlive,
          isBrowsing: socketAlive,
          isPublishing: socketAlive,
          isDegraded: true,
          lastError: error.toString(),
          lastBackendLogMessage: 'UDP LAN discovery socket error.',
        ),
        lastBackendLogMessage: 'UDP LAN discovery socket error.',
      ),
    );
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      NetworkConstants.discoveryHeartbeatInterval,
      (_) => unawaited(_runHeartbeatPulse()),
    );
    _log('UDP LAN discovery heartbeat enabled.');
  }

  Future<void> _runHeartbeatPulse() async {
    if (_heartbeatPulseInProgress || _socket == null) {
      return;
    }
    _heartbeatPulseInProgress = true;
    try {
      if (_peerCount == 0) {
        final warmupUntil = _startupWarmupUntil;
        final isWarmupActive =
            warmupUntil != null && DateTime.now().isBefore(warmupUntil);
        if (isWarmupActive) {
          await scanNow(burstAnnounce: true);
          return;
        }
        await announceNow();
        if (_socket == null) {
          return;
        }
        await scanNow();
        return;
      }
      await announceNow();
    } finally {
      _heartbeatPulseInProgress = false;
    }
  }

  Future<void> _sendAnnouncementPacket() async {
    final socket = _socket;
    if (socket == null) {
      return;
    }

    final interfaces = await _safeInterfaces();
    final targets = DiscoveryTargetPlanner.buildTargets(
      interfaces: interfaces,
      scanPorts: NetworkConstants.scanPorts,
      multicastAddress: NetworkConstants.discoveryMulticastAddress,
    );
    final sent = await _sendPayloadToTargets(
      socket: socket,
      type: 'discovery_announce',
      targets: targets,
    );

    _setHealth(
      _health.copyWith(
        isRunning: true,
        isBrowsing: true,
        isPublishing: true,
        packetsSent: _health.packetsSent + sent,
        interfaceCount: interfaces.length,
        lastPublishAt: DateTime.now(),
        lastError: null,
        hasBlockingIssue: false,
        backendState: _buildBackendState(
          peerCount: _peerCount,
          isRunning: true,
          isBrowsing: true,
          isPublishing: true,
          isHealthy: true,
          lastBackendLogMessage: 'UDP LAN discovery announce sent.',
        ),
        lastBackendLogMessage: 'UDP LAN discovery announce sent.',
      ),
    );
  }

  Future<int> _sendPayloadToTargets({
    required RawDatagramSocket socket,
    required String type,
    required List<DiscoverySendTarget> targets,
  }) async {
    final payload = utf8.encode(
      jsonEncode(
        DiscoveryPacketCodec.buildPayload(
          type: type,
          protocolVersion: NetworkConstants.protocolVersion,
          deviceId: _deviceId,
          nickname: _nicknameProvider(),
          platform: Platform.operatingSystem,
          activePort: _activePort,
          securePort: _securePort,
          certFingerprint: _fingerprintProvider(),
          appVersion: _appVersion,
          requestPort: _activePort,
          capabilities: _discoveryCapabilities,
          preferredAddressFamily: 'ipv4',
        ),
      ),
    );

    var sent = 0;
    for (final target in targets) {
      try {
        final address = InternetAddress(target.address);
        if (socket.send(payload, address, target.port) > 0) {
          sent += 1;
        }
      } catch (error) {
        _log('Failed to send UDP $type packet to ${target.key}: $error');
      }
    }
    return sent;
  }

  Future<void> _respondToRequest({
    required Map<String, dynamic> requestPayload,
    required InternetAddress remoteAddress,
    required int remotePort,
  }) async {
    final socket = _socket;
    if (socket == null) {
      return;
    }

    final requestPort = (requestPayload['requestPort'] as num?)?.toInt();
    final payload = utf8.encode(
      jsonEncode(
        DiscoveryPacketCodec.buildPayload(
          type: 'discovery_response',
          protocolVersion: NetworkConstants.protocolVersion,
          deviceId: _deviceId,
          nickname: _nicknameProvider(),
          platform: Platform.operatingSystem,
          activePort: _activePort,
          securePort: _securePort,
          certFingerprint: _fingerprintProvider(),
          appVersion: _appVersion,
          requestPort: _activePort,
          capabilities: _discoveryCapabilities,
          preferredAddressFamily: 'ipv4',
        ),
      ),
    );

    try {
      final sent = socket.send(
        payload,
        remoteAddress,
        requestPort ?? remotePort,
      );
      if (sent > 0) {
        _setHealth(
          _health.copyWith(
            isRunning: true,
            isBrowsing: true,
            isPublishing: true,
            packetsSent: _health.packetsSent + 1,
            lastPublishAt: DateTime.now(),
            lastError: null,
            hasBlockingIssue: false,
            backendState: _buildBackendState(
              peerCount: _peerCount,
              isRunning: true,
              isBrowsing: true,
              isPublishing: true,
              isHealthy: true,
              lastBackendLogMessage: 'UDP LAN discovery response sent.',
            ),
            lastBackendLogMessage: 'UDP LAN discovery response sent.',
          ),
        );
      }
    } catch (error) {
      _log('Failed to send UDP discovery response: $error');
      _setHealth(
        _health.copyWith(
          lastError: error.toString(),
          hasBlockingIssue: true,
          backendState: _buildBackendState(
            peerCount: _peerCount,
            isRunning: _socket != null,
            isBrowsing: _socket != null,
            isPublishing: _socket != null,
            isDegraded: true,
            lastError: error.toString(),
            lastBackendLogMessage: 'UDP LAN discovery response failed.',
          ),
          lastBackendLogMessage: 'UDP LAN discovery response failed.',
        ),
      );
    }
  }

  Future<List<NetworkInterfaceSnapshot>> _safeInterfaces() async {
    final interfaces = await _loadInterfaces();
    if (interfaces.isNotEmpty) {
      _lastNonEmptyInterfaces = interfaces;
      return interfaces;
    }
    if (_lastNonEmptyInterfaces.isNotEmpty) {
      return _lastNonEmptyInterfaces;
    }
    final system = await _matchingSystemInterfaces();
    final fallback = system
        .expand(
          (iface) => iface.addresses
              .where((addr) => addr.type == InternetAddressType.IPv4)
              .map(
                (addr) => NetworkInterfaceSnapshot(
                  interfaceName: iface.name,
                  address: addr.address,
                  prefixLength: 24,
                ),
              ),
        )
        .toList(growable: false);
    if (fallback.isNotEmpty) {
      _lastNonEmptyInterfaces = fallback;
    }
    return fallback;
  }

  Future<List<NetworkInterface>> _matchingSystemInterfaces() async {
    try {
      final snapshots = await _loadInterfaces();
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        includeLinkLocal: false,
        type: InternetAddressType.IPv4,
      );
      if (snapshots.isEmpty) {
        return interfaces;
      }
      final keys = snapshots
          .map((item) => '${item.interfaceName}|${item.address}')
          .toSet();
      return interfaces
          .where((iface) {
            return iface.addresses.any(
              (addr) => keys.contains('${iface.name}|${addr.address}'),
            );
          })
          .toList(growable: false);
    } catch (_) {
      return const <NetworkInterface>[];
    }
  }

  void _cleanupRegistry() {
    final previousPeerCount = _peerCount;
    _registry.removeStale(DateTime.now());
    final removedPeerCount = previousPeerCount - _peerCount;
    if (removedPeerCount > 0) {
      _log('UDP LAN discovery removed $removedPeerCount stale peer(s).');
    }
    _emitDevices();
    final socketAlive = _socket != null;
    _setHealth(
      _health.copyWith(
        isRunning: socketAlive,
        isBrowsing: socketAlive,
        isPublishing: socketAlive,
        discoveredDeviceCount: _peerCount,
        backendState: _buildBackendState(
          peerCount: _peerCount,
          isRunning: socketAlive,
          isBrowsing: socketAlive,
          isPublishing: socketAlive,
          isHealthy: socketAlive,
          lastError: _health.lastError,
          lastBackendLogMessage: _health.lastBackendLogMessage,
        ),
      ),
    );
  }

  int get _peerCount => _registry.sorted().length;

  List<String> get _discoveryCapabilities => <String>[
    NetworkConstants.protocolCapabilityQueuedApproval,
    if (_securePort != null && _securePort! > 0)
      NetworkConstants.protocolCapabilityHttpsTransfer,
    'udp-lan',
  ];

  DiscoveryBackendState _buildBackendState({
    required int peerCount,
    bool isRunning = false,
    bool isStarting = false,
    bool isBrowsing = false,
    bool isPublishing = false,
    bool isHealthy = false,
    bool isDegraded = false,
    String? lastError,
    String? lastPermissionIssue,
    String? lastBackendLogMessage,
  }) {
    return DiscoveryBackendState(
      activeBackends: <DiscoveryBackendKind>[DiscoveryBackendKind.udpLan],
      healthyBackends: isHealthy
          ? <DiscoveryBackendKind>[DiscoveryBackendKind.udpLan]
          : const <DiscoveryBackendKind>[],
      degradedBackends: isDegraded
          ? <DiscoveryBackendKind>[DiscoveryBackendKind.udpLan]
          : const <DiscoveryBackendKind>[],
      peerCountsByBackend: <String, int>{
        DiscoveryBackendKind.udpLan.name: peerCount,
      },
      lastErrorsByBackend: <String, String?>{
        DiscoveryBackendKind.udpLan.name: lastError,
      },
      lastLogsByBackend: <String, String?>{
        DiscoveryBackendKind.udpLan.name: lastBackendLogMessage,
      },
      isRunning: isRunning,
      isStarting: isStarting,
      isBrowsing: isBrowsing,
      isPublishing: isPublishing,
      lastError: lastError,
      lastPermissionIssue: lastPermissionIssue,
      lastBackendLogMessage: lastBackendLogMessage,
    );
  }

  void _emitDevices() {
    if (_devicesController.isClosed) {
      return;
    }
    _devicesController.add(_registry.sorted());
  }

  void _setHealth(DiscoveryHealth next) {
    _health = next;
    if (_healthController.isClosed) {
      return;
    }
    _healthController.add(next);
  }

  void _log(String message) {
    _logger?.call(message);
  }

  bool _isAddressAlreadyInUse(Object error) {
    final message = error.toString().toLowerCase();
    if (message.contains('address already in use')) {
      return true;
    }
    if (error is! SocketException) {
      return false;
    }
    final code = error.osError?.errorCode;
    return code == 98 || code == 10048;
  }

  bool _isSocketClosed(Object error) {
    final message = error.toString().toLowerCase();
    if (message.contains('socket has been closed')) {
      return true;
    }
    if (error is! SocketException) {
      return false;
    }
    final code = error.osError?.errorCode;
    return code == 9 || code == 10038;
  }
}
