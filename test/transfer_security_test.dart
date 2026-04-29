import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_drop/core/constants/network_constants.dart';
import 'package:local_drop/models/device_profile.dart';
import 'package:local_drop/models/discovery_health.dart';
import 'package:local_drop/models/network_interface_snapshot.dart';
import 'package:local_drop/models/peer_presence_models.dart';
import 'package:local_drop/models/transfer_diagnostics_snapshot.dart';
import 'package:local_drop/services/discovery_target_planner.dart';
import 'package:local_drop/services/local_identity_service.dart';
import 'package:local_drop/services/peer_trust_service.dart';
import 'package:local_drop/services/transfer_client.dart';

void main() {
  test('discovery rescan interval stays calm for mobile stability', () {
    expect(
      NetworkConstants.discoveryRescanInterval,
      greaterThanOrEqualTo(const Duration(seconds: 6)),
    );
    expect(
      NetworkConstants.discoveryHeartbeatInterval,
      greaterThanOrEqualTo(const Duration(seconds: 6)),
    );
    expect(
      NetworkConstants.discoveryBurstScanMinInterval,
      greaterThanOrEqualTo(const Duration(seconds: 10)),
    );
  });

  test('direct UDP discovery targets subnet hosts only during burst scans', () {
    final quietTargets = DiscoveryTargetPlanner.buildTargets(
      interfaces: const <NetworkInterfaceSnapshot>[
        NetworkInterfaceSnapshot(
          interfaceName: 'wlan0',
          address: '192.168.10.13',
          prefixLength: 24,
        ),
      ],
      scanPorts: const <int>[41937],
      multicastAddress: NetworkConstants.discoveryMulticastAddress,
    );
    expect(
      quietTargets.map((target) => target.address),
      isNot(contains('192.168.10.25')),
    );

    final burstTargets = DiscoveryTargetPlanner.buildTargets(
      interfaces: const <NetworkInterfaceSnapshot>[
        NetworkInterfaceSnapshot(
          interfaceName: 'wlan0',
          address: '192.168.10.13',
          prefixLength: 24,
        ),
      ],
      scanPorts: const <int>[41937],
      multicastAddress: NetworkConstants.discoveryMulticastAddress,
      includeSubnetHosts: true,
    );
    final burstAddresses = burstTargets
        .map((target) => target.address)
        .toSet();

    expect(burstAddresses, contains('192.168.10.25'));
    expect(burstAddresses, isNot(contains('192.168.10.13')));
    expect(burstAddresses, contains('192.168.10.255'));
  });

  test('transfer client blocks peers without HTTPS and fingerprint', () async {
    final client = TransferClient();
    final legacyPeer = _peer(
      capabilities: const <String>[
        NetworkConstants.protocolCapabilityQueuedApproval,
      ],
      certFingerprint: '',
      securePort: null,
    );

    final snapshot = await client.probeRecipient(recipient: legacyPeer);

    expect(snapshot.status, PeerAvailabilityStatus.securityFailure);
    expect(snapshot.errorMessage, contains('HTTPS transfer'));
  });

  test('transfer client probes secure ports from discovery sources', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'localdrop_transfer_probe_test_',
    );
    HttpServer? server;
    StreamSubscription<HttpRequest>? subscription;
    try {
      final identity = await LocalIdentityService(
        identityDirectoryProvider: () async => tempDir,
      ).loadOrCreate();
      server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        identity.buildServerContext(),
      );
      subscription = server.listen((request) async {
        if (request.uri.path != '/v1/transfer/health') {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          return;
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(<String, Object?>{
            'status': 'ok',
            'appVersion': '1.0.0',
            'protocolVersion': NetworkConstants.protocolVersion,
            'capabilities': const <String>[
              NetworkConstants.protocolCapabilityQueuedApproval,
              NetworkConstants.protocolCapabilityHttpsTransfer,
              NetworkConstants.protocolCapabilityPinAuth,
            ],
            'activePort': server!.port,
            'securePort': server.port,
            'nickname': 'Android',
            'deviceId': 'android-1',
            'platform': 'android',
            'certFingerprint': identity.fingerprint,
            'preferredAddressFamily': 'ipv4',
          }),
        );
        await request.response.close();
      });

      final client = TransferClient();
      final snapshot = await client.probeRecipient(
        recipient: _peer(
          deviceId: 'android-1',
          nickname: 'Android',
          platform: 'android',
          ipAddress: InternetAddress.loopbackIPv4.address,
          ipAddresses: const <String>[],
          activePort: 1,
          securePort: null,
          certFingerprint: identity.fingerprint,
          discoverySources: <DeviceDiscoverySource>[
            DeviceDiscoverySource(
              backendKind: DiscoveryBackendKind.udpLan,
              ipAddresses: <String>[InternetAddress.loopbackIPv4.address],
              activePort: 1,
              securePort: server.port,
              preferredAddressFamily: 'ipv4',
              lastSeen: DateTime.now(),
            ),
          ],
        ),
      );

      expect(snapshot.status, PeerAvailabilityStatus.ready);
      expect(snapshot.selectedPort, server.port);
    } finally {
      await subscription?.cancel();
      await server?.close(force: true);
      await tempDir.delete(recursive: true);
    }
  });

  test('transfer client tries preferred verified HTTPS route first', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'localdrop_preferred_route_test_',
    );
    HttpServer? server;
    StreamSubscription<HttpRequest>? subscription;
    try {
      final identity = await LocalIdentityService(
        identityDirectoryProvider: () async => tempDir,
      ).loadOrCreate();
      server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        identity.buildServerContext(),
      );
      subscription = server.listen((request) async {
        if (request.uri.path != '/v1/transfer/health') {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          return;
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(<String, Object?>{
            'status': 'ok',
            'appVersion': '1.0.0',
            'protocolVersion': NetworkConstants.protocolVersion,
            'capabilities': const <String>[
              NetworkConstants.protocolCapabilityQueuedApproval,
              NetworkConstants.protocolCapabilityHttpsTransfer,
              NetworkConstants.protocolCapabilityPinAuth,
            ],
            'activePort': server!.port,
            'securePort': server.port,
            'nickname': 'Android',
            'deviceId': 'android-lease',
            'platform': 'android',
            'certFingerprint': identity.fingerprint,
            'preferredAddressFamily': 'ipv4',
          }),
        );
        await request.response.close();
      });

      final client = TransferClient();
      final snapshot = await client.probeRecipient(
        recipient: _peer(
          deviceId: 'android-lease',
          nickname: 'Android',
          platform: 'android',
          ipAddress: '192.0.2.10',
          ipAddresses: const <String>['192.0.2.10'],
          activePort: 1,
          securePort: 1,
          certFingerprint: identity.fingerprint,
        ),
        preferredAvailability: PeerAvailabilitySnapshot(
          deviceId: 'android-lease',
          nickname: 'Android',
          status: PeerAvailabilityStatus.ready,
          updatedAt: DateTime.now(),
          selectedAddress: InternetAddress.loopbackIPv4.address,
          selectedPort: server.port,
          addressFamily: 'ipv4',
          protocolVersion: NetworkConstants.protocolVersion,
          appVersion: '1.0.0',
          capabilities: const <String>[
            NetworkConstants.protocolCapabilityQueuedApproval,
            NetworkConstants.protocolCapabilityHttpsTransfer,
          ],
        ),
      );

      expect(snapshot.status, PeerAvailabilityStatus.ready);
      expect(snapshot.selectedAddress, InternetAddress.loopbackIPv4.address);
      expect(snapshot.selectedPort, server.port);
    } finally {
      await subscription?.cancel();
      await server?.close(force: true);
      await tempDir.delete(recursive: true);
    }
  });

  test('trusted fingerprint is enforced and null trust allows re-pairing', () {
    final trusted = TrustedPeerRecord(
      deviceId: 'peer-1',
      nickname: 'Laptop',
      certFingerprint: 'ABCDEF123456',
      firstTrustedAt: DateTime.utc(2026, 1, 1),
      lastVerifiedAt: DateTime.utc(2026, 1, 2),
    );

    expect(
      PeerTrustService.statusForDevice(device: _peer(), trustedPeer: trusted),
      PeerTrustStatus.trusted,
    );
    expect(
      PeerTrustService.statusForDevice(
        device: _peer(certFingerprint: '111111123456'),
        trustedPeer: trusted,
      ),
      PeerTrustStatus.identityChanged,
    );
    expect(
      PeerTrustService.statusForDevice(device: _peer(), trustedPeer: null),
      PeerTrustStatus.untrusted,
    );
    expect(
      PeerTrustService.statusForDevice(
        device: _peer(certFingerprint: ''),
        trustedPeer: trusted,
      ),
      PeerTrustStatus.missingFingerprint,
    );
  });
}

DeviceProfile _peer({
  String deviceId = 'peer-1',
  String nickname = 'Laptop',
  String platform = 'windows',
  String ipAddress = '192.168.1.20',
  List<String> ipAddresses = const <String>['192.168.1.20'],
  List<String> capabilities = const <String>[
    NetworkConstants.protocolCapabilityQueuedApproval,
    NetworkConstants.protocolCapabilityHttpsTransfer,
  ],
  String certFingerprint = 'ABCDEF123456',
  int activePort = NetworkConstants.primaryPort,
  int? securePort = NetworkConstants.primaryPort,
  List<DeviceDiscoverySource> discoverySources =
      const <DeviceDiscoverySource>[],
}) {
  return DeviceProfile(
    deviceId: deviceId,
    nickname: nickname,
    platform: platform,
    ipAddress: ipAddress,
    ipAddresses: ipAddresses,
    activePort: activePort,
    securePort: securePort,
    certFingerprint: certFingerprint,
    appVersion: '1.0.0',
    protocolVersion: NetworkConstants.protocolVersion,
    capabilities: capabilities,
    preferredAddressFamily: 'ipv4',
    lastSeen: DateTime.now(),
    discoverySources: discoverySources,
  );
}
