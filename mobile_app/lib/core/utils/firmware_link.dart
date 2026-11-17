/// Parsing rules for firmware links. Kept separate from the downloader so the
/// URL handling can be unit-tested without network or filesystem access.
library;

enum FirmwareLinkKind { direct, githubRelease }

/// A concrete download target plus optional GitHub release metadata.
class FirmwareLink {
  final FirmwareLinkKind kind;

  /// Direct URL for [FirmwareLinkKind.direct].
  final Uri? directUri;

  /// Repository coordinates for [FirmwareLinkKind.githubRelease].
  final String? owner;
  final String? repo;

  /// Specific release tag, or null for "latest".
  final String? tag;

  const FirmwareLink._({
    required this.kind,
    this.directUri,
    this.owner,
    this.repo,
    this.tag,
  });

  const FirmwareLink.direct(Uri uri)
      : this._(kind: FirmwareLinkKind.direct, directUri: uri);

  const FirmwareLink.release({
    required String owner,
    required String repo,
    String? tag,
  }) : this._(
          kind: FirmwareLinkKind.githubRelease,
          owner: owner,
          repo: repo,
          tag: tag,
        );

  bool get isGithubRelease => kind == FirmwareLinkKind.githubRelease;

  /// Parses a user-supplied link. Accepts full `https://` URLs as well as
  /// `github.com/...` without a scheme.
  ///
  /// Supported forms:
  ///   https://raw.githubusercontent.com/o/r/ref/path/file.bin
  ///   https://github.com/o/r/blob/ref/path/file.bin
  ///   https://github.com/o/r/raw/ref/path/file.bin
  ///   https://github.com/o/r/releases/download/tag/file.bin
  ///   https://github.com/o/r/releases/latest
  ///   https://github.com/o/r/releases/tag/v1.3.2
  ///   https://github.com/o/r
  ///   any other https URL ending in .bin
  static FirmwareLink? parse(String input) {
    var raw = input.trim();
    if (raw.isEmpty) return null;
    if (!raw.contains('://')) raw = 'https://$raw';

    final uri = Uri.tryParse(raw);
    if (uri == null || uri.scheme.toLowerCase() != 'https') return null;
    if (uri.host.isEmpty) return null;

    final host = uri.host.toLowerCase();
    final path = uri.path.toLowerCase();

    if (host == 'github.com') {
      final seg = uri.pathSegments;
      if (seg.length < 2) return null;

      final owner = seg[0];
      final repo = seg[1];

      // GitHub HTML "blob"/"raw" pages -> raw.githubusercontent.com.
      if (seg.length >= 5 && (seg[2] == 'blob' || seg[2] == 'raw')) {
        final ref = seg[3];
        final filePath = seg.sublist(4).join('/');
        final rawUri = Uri.https(
          'raw.githubusercontent.com',
          '/$owner/$repo/$ref/$filePath',
        );
        if (!rawUri.path.toLowerCase().endsWith('.bin')) return null;
        return FirmwareLink.direct(rawUri);
      }

      if (seg.length >= 6 &&
          seg[2] == 'releases' &&
          (seg[3] == 'download' ||
              (seg[3] == 'latest' && seg[4] == 'download')) &&
          seg.last.toLowerCase().endsWith('.bin')) {
        return FirmwareLink.direct(uri);
      }

      if (seg.length >= 5 && seg[2] == 'releases' && seg[3] == 'tag') {
        return FirmwareLink.release(owner: owner, repo: repo, tag: seg[4]);
      }

      // Repository root or /releases or /releases/latest.
      return FirmwareLink.release(owner: owner, repo: repo);
    }

    if (host == 'raw.githubusercontent.com' ||
        host == 'objects.githubusercontent.com' ||
        path.endsWith('.bin')) {
      if (!path.endsWith('.bin')) return null;
      return FirmwareLink.direct(uri);
    }

    return null;
  }

  /// A short name for logs/UI.
  String get label {
    if (isGithubRelease) {
      final suffix = tag == null ? 'latest' : tag!;
      return 'github.com/$owner/$repo@$suffix';
    }
    final uri = directUri!;
    final segments = uri.pathSegments;
    return segments.isEmpty ? uri.host : segments.last;
  }
}
