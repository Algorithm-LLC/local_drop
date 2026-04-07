import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'LAN transfer flow placeholder',
    (tester) async {
      // This integration suite is intentionally a scaffold:
      // real LAN tests require two active app instances and a shared network.
      expect(true, isTrue);
    },
    skip: true,
  );
}
