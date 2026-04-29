import '../core/security/fingerprint_codes.dart';
import '../models/device_profile.dart';
import '../models/peer_presence_models.dart';

class PeerTrustService {
  const PeerTrustService._();

  static PeerTrustStatus statusForDevice({
    required DeviceProfile device,
    TrustedPeerRecord? trustedPeer,
  }) {
    final fingerprint = device.certFingerprint.trim();
    if (fingerprint.isEmpty) {
      return PeerTrustStatus.missingFingerprint;
    }
    if (trustedPeer == null) {
      return PeerTrustStatus.untrusted;
    }
    if (!certificateFingerprintsMatch(trustedPeer.certFingerprint, fingerprint)) {
      return PeerTrustStatus.identityChanged;
    }
    return PeerTrustStatus.trusted;
  }
}
