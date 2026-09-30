import 'download_asset.dart';

/// A model could not be downloaded from any configured source.
final class ModelDownloadException implements Exception {
  /// Preserves every attempted source and its failure.
  const ModelDownloadException(this.failures, this.hint);

  /// One failure per attempted URL.
  final List<DownloadFailure> failures;

  /// A platform-specific network configuration hint, when applicable.
  final String? hint;

  @override
  String toString() =>
      'Model download failed: ${DownloadException(failures)}'
      '${hint == null ? '' : ' $hint'}';
}
