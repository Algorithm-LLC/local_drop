import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
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
  static const String _identityDirName = 'identity';
  static const String _deviceFileName = 'device_id.txt';
  static const String _certFileName = 'device_cert.pem';
  static const String _keyFileName = 'device_key.pem';
  static const String _sharedCertificatePem = '''
-----BEGIN CERTIFICATE-----
MIIDWTCCAkGgAwIBAgIJAKPPaHNXKzqsMA0GCSqGSIb3DQEBCwUAMDwxCzAJBgNV
BAYTAlVTMRIwEAYDVQQKEwlMb2NhbERyb3AxGTAXBgNVBAMTEGxvY2FsZHJvcC1z
aGFyZWQwHhcNMjYwNDA2MTI0MjA5WhcNMzYwNDA3MTI0MjA5WjA8MQswCQYDVQQG
EwJVUzESMBAGA1UEChMJTG9jYWxEcm9wMRkwFwYDVQQDExBsb2NhbGRyb3Atc2hh
cmVkMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA4Zj4SyQAg8ANB8x3
KtRrFUdZZU6pKd07CbIi36i5VKMjWy75UltlNDcMXUn4/d5BZMlGzvVc/xvkk3eo
K0sF7X9FJqDKm24ieucmwVowP6Qy0kcIecW76krB2kc8V8ykP/+LHE6GPY+uZBmO
Ej59ziFBj8YjaWOICE9NaUno8Lf/KgUs77aCHBzgE4D5MUNTjaPDSNYVTylm0utJ
kBn3IRK1i8tEwUavG7YFn535sJimSx64M8mmKENCrjevuk13dQYFr7qjO+3xc3Wm
pg0BArtcicJxSEcnqp2PV7N/d4XgKeWyTqiLX9wP2fQm1d/9355IkpypT+Xwccls
a6p1ZQIDAQABo14wXDAMBgNVHRMBAf8EAjAAMA4GA1UdDwEB/wQEAwIFoDAdBgNV
HSUEFjAUBggrBgEFBQcDAQYIKwYBBQUHAwIwHQYDVR0RAQH/BBMwEYIPbG9jYWxk
cm9wLmxvY2FsMA0GCSqGSIb3DQEBCwUAA4IBAQC7Klnpm/J8yYXZTc27xccDNWpK
ExOBSgBvRgUxPOYNLWrX3l/3haWdxCqm5HpiZJGHoEn5a8hMs2hUbqy7tmNQQ3Qf
1dhxlpDGCjobj+KWYG9xyJ4BWkTD9GiltQmmNkk4UdH+YvtvAsbW5sK5IXANl9T8
MQfwXgZ+FrjP1oaoU5bbuUMrplgXLcha1b74AHOg0gRqBQQ+Qrd1evtQogW260yg
7lVoP+VkQtLEzYOcqFi3X45LOP6Yfniau9kSlOA+28ZeUJ9J++gEsaOUjmV+zuyE
3fF+Vy2Akw6XF+Lz+aBNhyFlskIZJhuwgnCYFtkJxeP5mOIvyk1aozH23atU
-----END CERTIFICATE-----
''';
  static const String _sharedPrivateKeyPem = '''
-----BEGIN PRIVATE KEY-----
MIIEwAIBADANBgkqhkiG9w0BAQEFAASCBKowggSmAgEAAoIBAQDhmPhLJACDwA0H
zHcq1GsVR1llTqkp3TsJsiLfqLlUoyNbLvlSW2U0NwxdSfj93kFkyUbO9Vz/G+ST
d6grSwXtf0UmoMqbbiJ65ybBWjA/pDLSRwh5xbvqSsHaRzxXzKQ//4scToY9j65k
GY4SPn3OIUGPxiNpY4gIT01pSejwt/8qBSzvtoIcHOATgPkxQ1ONo8NI1hVPKWbS
60mQGfchErWLy0TBRq8btgWfnfmwmKZLHrgzyaYoQ0KuN6+6TXd1BgWvuqM77fFz
daamDQECu1yJwnFIRyeqnY9Xs393heAp5bJOqItf3A/Z9CbV3/3fnkiSnKlP5fBx
yWxrqnVlAgMBAAECggEBAJ05KMHlY15uuCYZP2vgAokf4pOSEJ8WiZCmT1ukkRUF
ZRylTikxfQS44KsbZKY5AUYmaGzP33IDlHeZyt/xNz5flmfnY4yTYwBYnE/gdQPF
gY2+549GWUJdu2BOiSV/f3ECvYaKy0+YFSe6D6NzXeYMk06J/h/yt9liu0aHtgoc
Qg2aiw1BfJvdQZbI4JdzN9n/9VVSmtenFakfBKziXF1SdcurHjCdETGZzvGeZcQQ
RtlYy0fqQ+6jUliCicNKtrQNYC+XCfXJOWuSRc6+KUHMNnFnfD/J94Lz4eT/Q+Cu
Lgt248PCFszlkQD+/XOKv9zXh4Nyy2bBB97Gtn6Tc7kCgYEA/WhGcBkNbq4APeJZ
BCrUdGpUZj8bu8disIJniRusBsnFB7D/52T+SyAZjuMV0ap167TmPEj48hImjHOO
T/JWJXND3Jwfae7ismTrBkWwFReJz00LYaN2weN/ahVTQiV9UuJrvDJ7Z2KgNIjI
fqJJEQiI4l4VzrSBVPVvXT5b/8MCgYEA4+fa9eAhOWETVRn4sEXqa2w4WnD7gwck
rV4s+izNwP4F+Xbugin8+5e8nFZsvYzJ2hD1qI/tl5jVsRWynAvfdFxg75NhgbZP
K+Ipz2sog++lmFNtPBszS4fDTqFIkhFDLOvL+ic4CJB2WbSOrr6/c8O6P+3egqsE
Y7Tbhrkdy7cCgYEAu8F9HyWQzEbkKvYAmpPZYoA+FJwBwnoS51FXwUDdjxIEiJRe
p2Yu/B7GkRY0Xmr8gC5CwLwYp9NG+J3N/fJCXfEvgM+0ftre4OrhMH6F3rrYAt7E
5g0lurcC+ujeDY6VcsoMpR6KTKnIpeQLGbjIhnRaZ87qPYOEqBxJ7T59D90CgYEA
gBAWr7bjtHRiAp33akW/NeG3wMpf6f6nk2up5mIqs9mJzeYQm7+wUkevSkIeFFz6
R7jj8XX+0gKlgT5qANmDFMWcCsNMNTEWR9hsGgti1tBgwrmOVgoKxtRg4NwsBTgC
AUn2cnh7OgTDHCEjU/oHZquDCs1FDTO/4a8M9CUtIv0CgYEA+y09UUT8TfI1FCYu
H54lv2V8wD90Xak/DJlB6FHqhXCzncUyYbGCa5KpjN/LVKhpxhC5L36KpLxcD6Hb
2cx6+d4pvV71Clhn/B+AmGEKo7voKspjtHfP/ov48s2Xx3oH57yjlwSIm4sZw6ma
nbLkvwLrU4z8p9QrvQviTCr/V+8=
-----END PRIVATE KEY-----
''';

  Future<LocalIdentity> loadOrCreate() async {
    final identityDir = await _resolveIdentityDirectory();
    final deviceFile = File(p.join(identityDir.path, _deviceFileName));
    final deviceId = await _resolveDeviceId(deviceFile);
    await _cleanupLegacyIdentityFiles(identityDir);

    return _buildIdentity(
      deviceId: deviceId,
      certificatePem: _sharedCertificatePem,
      privateKeyPem: _sharedPrivateKeyPem,
    );
  }

  Future<LocalIdentity> regenerate() async {
    final identityDir = await _resolveIdentityDirectory();
    final deviceFile = File(p.join(identityDir.path, _deviceFileName));
    final deviceId = await _resolveDeviceId(deviceFile);
    await _cleanupLegacyIdentityFiles(identityDir);
    return _buildIdentity(
      deviceId: deviceId,
      certificatePem: _sharedCertificatePem,
      privateKeyPem: _sharedPrivateKeyPem,
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

  Future<void> _cleanupLegacyIdentityFiles(Directory identityDir) async {
    for (final fileName in <String>[_certFileName, _keyFileName]) {
      final file = File(p.join(identityDir.path, fileName));
      if (await file.exists()) {
        await file.delete();
      }
    }
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
