import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_drop/core/constants/network_constants.dart';
import 'package:local_drop/models/app_preferences.dart';
import 'package:local_drop/models/transfer_models.dart';
import 'package:local_drop/services/local_identity_service.dart';
import 'package:local_drop/services/transfer_pin_service.dart';

void main() {
  test(
    'local identity persists and regenerates per-device certificates',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'localdrop_identity_test_',
      );
      try {
        final service = LocalIdentityService(
          identityDirectoryProvider: () async => tempDir,
        );
        final first = await service.loadOrCreate();
        final reloaded = await service.loadOrCreate();

        expect(reloaded.deviceId, first.deviceId);
        expect(reloaded.fingerprint, first.fingerprint);
        expect(first.privateKeyPem, contains('BEGIN PRIVATE KEY'));

        final regenerated = await service.regenerate();
        expect(regenerated.deviceId, first.deviceId);
        expect(regenerated.fingerprint, isNot(first.fingerprint));
      } finally {
        await tempDir.delete(recursive: true);
      }
    },
  );

  test('PIN proof accepts correct PIN and rejects wrong PIN', () {
    final settings = TransferPinService.createSettings('123456', iterations: 2);
    final challenge = TransferPinChallenge(
      algorithm: settings.algorithm,
      saltBase64: settings.saltBase64,
      iterations: settings.iterations,
      nonce: TransferPinService.newNonce(),
      expiresAt: DateTime.now().add(const Duration(minutes: 1)),
    );

    final validAuth = TransferPinService.buildAuth(
      pin: '123456',
      challenge: challenge,
    );
    final invalidAuth = TransferPinService.buildAuth(
      pin: '654321',
      challenge: challenge,
    );

    expect(
      TransferPinService.verifyAuth(settings: settings, auth: validAuth),
      isTrue,
    );
    expect(
      TransferPinService.verifyAuth(settings: settings, auth: invalidAuth),
      isFalse,
    );
  });

  test('async PIN proof matches the synchronous verifier', () async {
    final settings = await TransferPinService.createSettingsAsync(
      '123456',
      iterations: 2,
    );
    final challenge = TransferPinChallenge(
      algorithm: settings.algorithm,
      saltBase64: settings.saltBase64,
      iterations: settings.iterations,
      nonce: TransferPinService.newNonce(),
      expiresAt: DateTime.now().add(const Duration(minutes: 1)),
    );

    final auth = await TransferPinService.buildAuthAsync(
      pin: '123456',
      challenge: challenge,
    );

    expect(
      TransferPinService.verifyAuth(settings: settings, auth: auth),
      isTrue,
    );
  });

  test('PIN policy accepts 6 to 12 digits only', () {
    expect(TransferPinService.isValidPin('12345'), isFalse);
    expect(TransferPinService.isValidPin('123456'), isTrue);
    expect(TransferPinService.isValidPin('123456789012'), isTrue);
    expect(TransferPinService.isValidPin('1234567890123'), isFalse);
    expect(TransferPinService.isValidPin('12345a'), isFalse);
  });

  test('legacy stored PIN policy requires reset', () {
    const legacy = AppPreferences(
      nickname: 'Laptop',
      themePreference: AppThemePreference.system,
      saveDirectory: null,
      transferPinAlgorithm: TransferPinService.algorithm,
      transferPinSaltBase64: 'salt',
      transferPinHashBase64: 'hash',
      transferPinIterations: 120000,
    );
    final current = legacy.copyWith(
      transferPinPolicyVersion: TransferPinService.currentPolicyVersion,
    );

    expect(legacy.hasTransferPin, isTrue);
    expect(legacy.hasCurrentTransferPin, isFalse);
    expect(legacy.needsOnboarding, isTrue);
    expect(current.hasCurrentTransferPin, isTrue);
    expect(current.needsOnboarding, isFalse);
  });

  test('TransferOffer serializes PIN auth', () {
    final offer = TransferOffer(
      transferId: 'transfer-1',
      senderDeviceId: 'sender',
      senderNickname: 'Sender',
      senderFingerprint: 'ABC',
      senderAppVersion: '1.0.0',
      protocolVersion: NetworkConstants.protocolVersion,
      createdAt: DateTime.utc(2026, 1, 1),
      items: const <TransferItem>[],
      pinAuth: const TransferPinAuth(
        algorithm: TransferPinService.algorithm,
        nonce: 'nonce',
        proofBase64: 'proof',
      ),
    );

    final decoded = TransferOffer.fromJson(offer.toJson());

    expect(decoded.pinAuth?.algorithm, TransferPinService.algorithm);
    expect(decoded.pinAuth?.nonce, 'nonce');
    expect(decoded.pinAuth?.proofBase64, 'proof');
  });
}
