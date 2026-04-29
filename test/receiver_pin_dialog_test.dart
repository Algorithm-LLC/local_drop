import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_drop/widgets/receiver_pin_dialog.dart';

void main() {
  testWidgets('receiver PIN dialog lays out security-code comparison', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                onPressed: () {
                  showReceiverPinDialog(
                    context,
                    peerNickname: 'Laptop',
                    requiresSecurityConfirmation: true,
                    peerSecurityCode: 'ABCD EFGH IJKL',
                    localSecurityCode: '1234 5678 90AB',
                  );
                },
                child: const Text('Open'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Security code check'), findsOneWidget);
    expect(find.text('ABCD EFGH IJKL'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
