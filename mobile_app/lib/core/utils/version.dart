/// Parses a dotted version string ("1.2.3", "v1.2", "1.2.3-beta1")
/// into its numeric parts (major/minor/patch). Trailing suffix is ignored.
List<int> parseVersion(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  final cleaned = raw.trim().replaceFirst(RegExp(r'^[vV]'), '');
  final parts = <int>[];
  for (final segment in cleaned.split('.')) {
    final match = RegExp(r'^\d+').firstMatch(segment);
    if (match == null) break;
    parts.add(int.parse(match.group(0)!));
    if (parts.length == 3) break;
  }
  return parts;
}

/// Compares two version strings numerically (major.minor.patch).
/// Returns -1 when [a] < [b], 1 when [a] > [b], 0 when equal.
/// An unparseable version is treated as older than any parseable one.
int compareVersions(String? a, String? b) {
  final pa = parseVersion(a);
  final pb = parseVersion(b);
  if (pa.isEmpty) return pb.isEmpty ? 0 : -1;
  if (pb.isEmpty) return 1;
  final length = pa.length > pb.length ? pa.length : pb.length;
  for (var i = 0; i < length; i++) {
    final na = i < pa.length ? pa[i] : 0;
    final nb = i < pb.length ? pb[i] : 0;
    if (na != nb) return na < nb ? -1 : 1;
  }
  return 0;
}

/// True when [a] is strictly newer than [b].
bool isVersionNewer(String? a, String? b) => compareVersions(a, b) > 0;

/// Freshness of a version vs the published one.
enum FirmwareFreshness { unknown, outdated, latest, newer }

/// Compute freshness from [running] vs [published] version strings.
FirmwareFreshness firmwareFreshness(String? running, String? published) {
  if (running == null || running.isEmpty || published == null || published.isEmpty) {
    return FirmwareFreshness.unknown;
  }
  final cmp = compareVersions(running, published);
  if (cmp < 0) return FirmwareFreshness.outdated;
  if (cmp == 0) return FirmwareFreshness.latest;
  return FirmwareFreshness.newer;
}