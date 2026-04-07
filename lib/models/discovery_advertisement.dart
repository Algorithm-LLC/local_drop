class DiscoveryAdvertisement {
  const DiscoveryAdvertisement({
    required this.instanceName,
    required this.serviceType,
    required this.domain,
    required this.port,
    required this.txtRecords,
  });

  final String instanceName;
  final String serviceType;
  final String domain;
  final int port;
  final Map<String, String> txtRecords;

  String get fullServiceType => '$serviceType.$domain';
}
