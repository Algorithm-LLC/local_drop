import '../core/constants/network_constants.dart';

typedef PortBinder = Future<bool> Function(int port);

class PortAllocator {
  const PortAllocator();

  Future<int> selectAvailablePort({required PortBinder binder}) async {
    for (final port in NetworkConstants.scanPorts) {
      final available = await binder(port);
      if (available) {
        return port;
      }
    }
    throw StateError(
      'No available transfer ports (${NetworkConstants.scanPorts.join(', ')}).',
    );
  }
}
