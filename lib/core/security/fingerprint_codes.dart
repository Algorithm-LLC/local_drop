String normalizeCertificateFingerprint(String value) {
  return value.replaceAll(RegExp(r'[^A-Fa-f0-9]'), '').toUpperCase();
}

String shortSecurityCodeForFingerprint(String value) {
  final normalized = normalizeCertificateFingerprint(value);
  if (normalized.length < 12) {
    return normalized.isEmpty ? 'Not available' : normalized;
  }
  return '${normalized.substring(0, 4)} '
      '${normalized.substring(4, 8)} '
      '${normalized.substring(8, 12)}';
}

bool certificateFingerprintsMatch(String left, String right) {
  final normalizedLeft = normalizeCertificateFingerprint(left);
  final normalizedRight = normalizeCertificateFingerprint(right);
  return normalizedLeft.isNotEmpty && normalizedLeft == normalizedRight;
}
