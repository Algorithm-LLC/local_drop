import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/asn1.dart';
import 'package:uuid/uuid.dart';

class LocalIdentity {
  const LocalIdentity({
    required this.deviceId,
    required this.certificatePem,
    required this.privateKeyPem,
    required this.fingerprint,
  });

  final String deviceId;
  final String certificatePem;
  final String privateKeyPem;
  final String fingerprint;

  SecurityContext buildServerContext() {
    return SecurityContext(withTrustedRoots: false)
      ..useCertificateChainBytes(utf8.encode(certificatePem))
      ..usePrivateKeyBytes(utf8.encode(privateKeyPem));
  }
}

class LocalIdentityService {
  LocalIdentityService({
    Future<Directory> Function()? identityDirectoryProvider,
  }) : _identityDirectoryProvider = identityDirectoryProvider;

  static const String _identityDirName = 'identity';
  static const String _deviceFileName = 'device_id.txt';
  static const String _certFileName = 'device_cert.pem';
  static const String _keyFileName = 'device_key.pem';
  static const String _identityVersionFileName = 'identity_version.txt';
  static const String _currentIdentityVersion = '2';
  static const int _certificateDays = 3650;

  final Future<Directory> Function()? _identityDirectoryProvider;

  Future<LocalIdentity> loadOrCreate() async {
    final identityDir = await _resolveIdentityDirectory();
    final deviceFile = File(p.join(identityDir.path, _deviceFileName));
    final deviceId = await _resolveDeviceId(deviceFile);
    final certFile = File(p.join(identityDir.path, _certFileName));
    final keyFile = File(p.join(identityDir.path, _keyFileName));
    final versionFile = File(
      p.join(identityDir.path, _identityVersionFileName),
    );

    if (await certFile.exists() &&
        await keyFile.exists() &&
        await _hasCurrentIdentityVersion(versionFile)) {
      try {
        return _buildIdentity(
          deviceId: deviceId,
          certificatePem: await certFile.readAsString(),
          privateKeyPem: await keyFile.readAsString(),
        );
      } catch (_) {
        await _deleteIfExists(certFile);
        await _deleteIfExists(keyFile);
      }
    }

    await _deleteIfExists(certFile);
    await _deleteIfExists(keyFile);
    return _generateAndPersistIdentity(
      deviceId: deviceId,
      certFile: certFile,
      keyFile: keyFile,
      versionFile: versionFile,
    );
  }

  Future<LocalIdentity> regenerate() async {
    final identityDir = await _resolveIdentityDirectory();
    final deviceFile = File(p.join(identityDir.path, _deviceFileName));
    final deviceId = await _resolveDeviceId(deviceFile);
    return _generateAndPersistIdentity(
      deviceId: deviceId,
      certFile: File(p.join(identityDir.path, _certFileName)),
      keyFile: File(p.join(identityDir.path, _keyFileName)),
      versionFile: File(p.join(identityDir.path, _identityVersionFileName)),
    );
  }

  Future<String> _resolveDeviceId(File file) async {
    if (await file.exists()) {
      final existing = (await file.readAsString()).trim();
      if (existing.isNotEmpty) {
        return existing;
      }
    }
    final generated = const Uuid().v4().replaceAll('-', '');
    await file.writeAsString(generated, flush: true);
    return generated;
  }

  static String normalizePeerFingerprint(String value) =>
      _normalizeFingerprint(value);

  Future<Directory> _resolveIdentityDirectory() async {
    final provided = await _identityDirectoryProvider?.call();
    if (provided != null) {
      if (!await provided.exists()) {
        await provided.create(recursive: true);
      }
      return provided;
    }
    final supportDir = await getApplicationSupportDirectory();
    final identityDir = Directory(
      p.join(supportDir.path, 'LocalDrop', _identityDirName),
    );
    if (!await identityDir.exists()) {
      await identityDir.create(recursive: true);
    }
    return identityDir;
  }

  LocalIdentity _buildIdentity({
    required String deviceId,
    required String certificatePem,
    required String privateKeyPem,
  }) {
    _validateKeyPair(
      certificatePem: certificatePem,
      privateKeyPem: privateKeyPem,
    );
    final certificateBytes = _pemToDerBytes(certificatePem);
    final fingerprint = _normalizeFingerprint(
      sha256.convert(certificateBytes).toString(),
    );

    return LocalIdentity(
      deviceId: deviceId,
      certificatePem: certificatePem,
      privateKeyPem: privateKeyPem,
      fingerprint: fingerprint,
    );
  }

  Future<LocalIdentity> _generateAndPersistIdentity({
    required String deviceId,
    required File certFile,
    required File keyFile,
    required File versionFile,
  }) async {
    final keyPair = CryptoUtils.generateRSAKeyPair(keySize: 2048);
    final privateKey = keyPair.privateKey as RSAPrivateKey;
    final publicKey = keyPair.publicKey as RSAPublicKey;
    final certPem = _generateTlsCertificatePem(
      deviceId: deviceId,
      privateKey,
      publicKey,
    );
    final keyPem = CryptoUtils.encodeRSAPrivateKeyToPem(privateKey);
    await certFile.writeAsString(certPem, flush: true);
    await keyFile.writeAsString(keyPem, flush: true);
    await versionFile.writeAsString(_currentIdentityVersion, flush: true);
    return _buildIdentity(
      deviceId: deviceId,
      certificatePem: certPem,
      privateKeyPem: keyPem,
    );
  }

  void _validateKeyPair({
    required String certificatePem,
    required String privateKeyPem,
  }) {
    final certModulus = X509Utils.getModulusFromRSAX509Pem(certificatePem);
    final keyModulus = CryptoUtils.getModulusFromRSAPrivateKeyPem(
      privateKeyPem,
    );
    if (certModulus != keyModulus) {
      throw StateError('Local identity certificate and private key mismatch.');
    }
  }

  Future<void> _deleteIfExists(File file) async {
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<bool> _hasCurrentIdentityVersion(File file) async {
    if (!await file.exists()) {
      return false;
    }
    return (await file.readAsString()).trim() == _currentIdentityVersion;
  }

  String _generateTlsCertificatePem(
    RSAPrivateKey privateKey,
    RSAPublicKey publicKey, {
    required String deviceId,
  }) {
    final now = DateTime.now().toUtc();
    final notBefore = now.subtract(const Duration(days: 1));
    final notAfter = now.add(const Duration(days: _certificateDays));
    final subject = _distinguishedName(<String, String>{
      '2.5.4.10': 'LocalDrop',
      '2.5.4.3': 'localdrop-$deviceId',
    });
    final signatureAlgorithm = _rsaSha256AlgorithmIdentifier();

    final tbs = ASN1Sequence()
      ..add(_explicit(0, ASN1Integer.fromtInt(2).encode()))
      ..add(ASN1Integer(_randomSerialNumber()))
      ..add(signatureAlgorithm)
      ..add(subject)
      ..add(
        ASN1Sequence()
          ..add(ASN1UtcTime(notBefore))
          ..add(ASN1UtcTime(notAfter)),
      )
      ..add(subject)
      ..add(
        ASN1Object.fromBytes(
          CryptoUtils.encodeRSAPublicKeyToDERBytes(publicKey),
        ),
      )
      ..add(_explicit(3, _certificateExtensions().encode()));

    final tbsBytes = tbs.encode();
    final signature = CryptoUtils.rsaSign(privateKey, tbsBytes);
    final certificate = ASN1Sequence()
      ..add(tbs)
      ..add(_rsaSha256AlgorithmIdentifier())
      ..add(ASN1BitString(stringValues: signature));

    return _pemForDer(
      '-----BEGIN CERTIFICATE-----',
      '-----END CERTIFICATE-----',
      certificate.encode(),
    );
  }

  ASN1Sequence _distinguishedName(Map<String, String> valuesByOid) {
    final name = ASN1Sequence();
    for (final entry in valuesByOid.entries) {
      name.add(
        ASN1Set(
          elements: <ASN1Object>[
            ASN1Sequence(
              elements: <ASN1Object>[
                ASN1ObjectIdentifier.fromIdentifierString(entry.key),
                ASN1UTF8String(utf8StringValue: entry.value),
              ],
            ),
          ],
        ),
      );
    }
    return name;
  }

  ASN1Sequence _rsaSha256AlgorithmIdentifier() {
    return ASN1Sequence()
      ..add(ASN1ObjectIdentifier.fromIdentifierString('1.2.840.113549.1.1.11'))
      ..add(ASN1Null());
  }

  ASN1Sequence _certificateExtensions() {
    return ASN1Sequence()
      ..add(_extension('2.5.29.19', (ASN1Sequence()).encode()))
      ..add(
        _extension(
          '2.5.29.15',
          (ASN1BitString(stringValues: <int>[0xA0])..unusedbits = 5).encode(),
          critical: true,
        ),
      )
      ..add(
        _extension(
          '2.5.29.37',
          (ASN1Sequence()
                ..add(
                  ASN1ObjectIdentifier.fromIdentifierString(
                    '1.3.6.1.5.5.7.3.1',
                  ),
                )
                ..add(
                  ASN1ObjectIdentifier.fromIdentifierString(
                    '1.3.6.1.5.5.7.3.2',
                  ),
                ))
              .encode(),
        ),
      )
      ..add(
        _extension(
          '2.5.29.17',
          (ASN1Sequence()
                ..add(ASN1IA5String(stringValue: 'localdrop.local', tag: 0x82)))
              .encode(),
        ),
      );
  }

  ASN1Sequence _extension(
    String oid,
    Uint8List valueDer, {
    bool critical = false,
  }) {
    final extension = ASN1Sequence()
      ..add(ASN1ObjectIdentifier.fromIdentifierString(oid));
    if (critical) {
      extension.add(ASN1Boolean(true));
    }
    extension.add(ASN1OctetString(octets: valueDer));
    return extension;
  }

  ASN1Object _explicit(int index, Uint8List encodedValue) {
    return ASN1Object(tag: 0xA0 + index)..valueBytes = encodedValue;
  }

  BigInt _randomSerialNumber() {
    final random = Random.secure();
    final bytes = Uint8List.fromList(
      List<int>.generate(16, (_) => random.nextInt(256)),
    );
    bytes[0] &= 0x7f;
    final value = bytes.fold<BigInt>(
      BigInt.zero,
      (acc, byte) => (acc << 8) | BigInt.from(byte),
    );
    return value == BigInt.zero ? BigInt.one : value;
  }

  String _pemForDer(String begin, String end, List<int> der) {
    final encoded = base64.encode(der);
    final lines = <String>[];
    for (var i = 0; i < encoded.length; i += 64) {
      final endIndex = i + 64 > encoded.length ? encoded.length : i + 64;
      lines.add(encoded.substring(i, endIndex));
    }
    return '$begin\n${lines.join('\n')}\n$end\n';
  }

  static String _normalizeFingerprint(String value) {
    return value.replaceAll(RegExp('[^A-Fa-f0-9]'), '').toUpperCase();
  }

  Uint8List _pemToDerBytes(String pem) {
    final normalized = pem
        .replaceAll(RegExp(r'-----BEGIN [^-]+-----'), '')
        .replaceAll(RegExp(r'-----END [^-]+-----'), '')
        .replaceAll(RegExp(r'\s+'), '');
    return base64.decode(normalized);
  }
}
