class NetworkConstants {
  const NetworkConstants._();

  static const int primaryPort = 41937;
  static const List<int> scanPorts = [primaryPort];
  static const int mdnsPort = 5353;
  static const String discoveryMulticastAddress = '224.0.0.251';
  static const String discoveryServiceType = '_localdrop._tcp';
  static const String discoveryDomain = 'local';
  static const Duration discoveryRescanInterval = Duration(seconds: 6);
  static const Duration discoveryHeartbeatInterval = Duration(seconds: 6);
  static const Duration discoveryBurstScanMinInterval = Duration(seconds: 12);
  static const Duration discoveryDirectProbeMinInterval = Duration(seconds: 10);
  static const Duration discoveryAnnounceBurstSpacing = Duration(
    milliseconds: 250,
  );
  static const int discoveryAnnounceBurstCount = 3;
  static const Duration discoveryQueryTimeout = Duration(seconds: 2);
  static const Duration discoveryStaleTimeout = Duration(seconds: 45);
  static const Duration discoveryCleanupInterval = Duration(seconds: 2);
  static const Duration discoveryWatchdogThreshold = Duration(seconds: 30);
  static const Duration discoveryStartupWarmupDuration = Duration(seconds: 20);
  static const Duration approvalTimeout = Duration(seconds: 120);
  static const Duration approvalPollInterval = Duration(seconds: 1);
  static const Duration incomingSessionCleanupInterval = Duration(seconds: 2);
  static const Duration transferProgressMinInterval = Duration(
    milliseconds: 250,
  );
  static const int transferProgressMinByteDelta = 512 * 1024;
  static const int transferChunkSizeBytes = 1024 * 1024;
  static const String protocolVersion = 'localdrop.secure.v5';
  static const String protocolCapabilityQueuedApproval = 'queued-approval';
  static const String protocolCapabilityMdns = 'mdns';
  static const String protocolCapabilityHttpsTransfer = 'https-transfer';
  static const String protocolCapabilityPinAuth = 'pin-auth';
}
