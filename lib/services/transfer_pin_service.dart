import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart' as pc;

import '../models/transfer_models.dart';

class TransferPinSettings {
  const TransferPinSettings({
    required this.algorithm,
    required this.saltBase64,
    required this.hashBase64,
    required this.iterations,
  });

  final String algorithm;
  final String saltBase64;
  final String hashBase64;
  final int iterations;

  bool get isValid =>
      algorithm == TransferPinService.algorithm &&
      saltBase64.trim().isNotEmpty &&
      hashBase64.trim().isNotEmpty &&
      iterations > 0;
}

class TransferPinService {
  const TransferPinService._();

  static const String algorithm = 'localdrop-pin-pbkdf2-sha256-v1';
  static const int currentPolicyVersion = 2;
  static const int minPinLength = 6;
  static const int maxPinLength = 12;
  static const int defaultIterations = 600000;
  static const int _derivedKeyLength = 32;

  static const String pinRequirementsLabel = '6 to 12 digits';

  static bool isValidPin(String value) => RegExp(r'^\d{6,12}$').hasMatch(value);

  static TransferPinSettings createSettings(
    String pin, {
    int iterations = defaultIterations,
  }) {
    _checkPin(pin);
    final salt = _randomBytes(16);
    final hash = _pbkdf2Sha256(
      utf8.encode(pin),
      salt,
      iterations,
      _derivedKeyLength,
    );
    return TransferPinSettings(
      algorithm: algorithm,
      saltBase64: base64Encode(salt),
      hashBase64: base64Encode(hash),
      iterations: iterations,
    );
  }

  static Future<TransferPinSettings> createSettingsAsync(
    String pin, {
    int iterations = defaultIterations,
  }) async {
    _checkPin(pin);
    final saltBase64 = base64Encode(_randomBytes(16));
    final json = await Isolate.run<Map<String, dynamic>>(
      () => _createPinSettingsInBackground(<String, Object?>{
        'pin': pin,
        'saltBase64': saltBase64,
        'iterations': iterations,
      }),
    );
    return TransferPinSettings(
      algorithm: (json['algorithm'] as String?) ?? '',
      saltBase64: (json['saltBase64'] as String?) ?? '',
      hashBase64: (json['hashBase64'] as String?) ?? '',
      iterations: (json['iterations'] as num?)?.toInt() ?? 0,
    );
  }

  static TransferPinAuth buildAuth({
    required String pin,
    required TransferPinChallenge challenge,
  }) {
    _checkPin(pin);
    if (challenge.algorithm != algorithm) {
      throw StateError('Unsupported receiver PIN algorithm.');
    }
    final salt = base64Decode(challenge.saltBase64);
    final derived = _pbkdf2Sha256(
      utf8.encode(pin),
      salt,
      challenge.iterations,
      _derivedKeyLength,
    );
    return TransferPinAuth(
      algorithm: challenge.algorithm,
      nonce: challenge.nonce,
      proofBase64: _proofForHash(derived, challenge.nonce),
    );
  }

  static Future<TransferPinAuth> buildAuthAsync({
    required String pin,
    required TransferPinChallenge challenge,
  }) async {
    _checkPin(pin);
    if (challenge.algorithm != algorithm) {
      throw StateError('Unsupported receiver PIN algorithm.');
    }
    final json = await Isolate.run<Map<String, dynamic>>(
      () => _buildPinAuthInBackground(<String, Object?>{
        'pin': pin,
        'challenge': challenge.toJson(),
      }),
    );
    return TransferPinAuth.fromJson(json);
  }

  static bool verifyAuth({
    required TransferPinSettings settings,
    required TransferPinAuth auth,
  }) {
    if (!settings.isValid || auth.algorithm != settings.algorithm) {
      return false;
    }
    final storedHash = base64Decode(settings.hashBase64);
    final expected = _proofForHash(storedHash, auth.nonce);
    return _constantTimeEquals(
      base64DecodeSafe(auth.proofBase64),
      base64DecodeSafe(expected),
    );
  }

  static String newNonce() => base64UrlEncode(_randomBytes(24));

  static Uint8List base64DecodeSafe(String value) {
    try {
      return base64Decode(value);
    } catch (_) {
      return Uint8List(0);
    }
  }

  static void _checkPin(String pin) {
    if (!isValidPin(pin)) {
      throw ArgumentError('PIN must be $pinRequirementsLabel.');
    }
  }

  static String _proofForHash(List<int> hashBytes, String nonce) {
    final mac = Hmac(sha256, hashBytes);
    final digest = mac.convert(utf8.encode('localdrop-pin-v1:$nonce'));
    return base64Encode(digest.bytes);
  }

  static Uint8List _pbkdf2Sha256(
    List<int> password,
    List<int> salt,
    int iterations,
    int keyLength,
  ) {
    if (iterations <= 0 || keyLength <= 0) {
      throw ArgumentError('Invalid PBKDF2 parameters.');
    }
    final derivator = pc.PBKDF2KeyDerivator(
      pc.HMac(pc.SHA256Digest(), 64),
    )..init(
        pc.Pbkdf2Parameters(
          Uint8List.fromList(salt),
          iterations,
          keyLength,
        ),
      );
    return derivator.process(Uint8List.fromList(password));
  }

  static Uint8List _randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) {
      return false;
    }
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}

Map<String, dynamic> _createPinSettingsInBackground(
  Map<String, Object?> args,
) {
  final pin = args['pin'] as String;
  final saltBase64 = args['saltBase64'] as String;
  final iterations = (args['iterations'] as num).toInt();
  final salt = base64Decode(saltBase64);
  final hash = TransferPinService._pbkdf2Sha256(
    utf8.encode(pin),
    salt,
    iterations,
    TransferPinService._derivedKeyLength,
  );
  return <String, dynamic>{
    'algorithm': TransferPinService.algorithm,
    'saltBase64': saltBase64,
    'hashBase64': base64Encode(hash),
    'iterations': iterations,
  };
}

Map<String, dynamic> _buildPinAuthInBackground(Map<String, Object?> args) {
  final pin = args['pin'] as String;
  final challenge = TransferPinChallenge.fromJson(
    Map<String, dynamic>.from(args['challenge'] as Map<dynamic, dynamic>),
  );
  return TransferPinService.buildAuth(
    pin: pin,
    challenge: challenge,
  ).toJson();
}
