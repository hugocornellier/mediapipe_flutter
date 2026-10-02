/// The checks every classifier's settings get, in every family, before
/// Google's runtime sees them.
library;

/// Validates the settings every classifier takes (Image Classifier, Object
/// Detector, Text Classifier, Language Detector, Audio Classifier and Gesture
/// Recognizer's heads), as Google's runtime would.
void checkClassifierSettings({
  required int maxResults,
  required double scoreThreshold,
  required String? displayNamesLocale,
  required List<String> categoryAllowlist,
  required List<String> categoryDenylist,
}) {
  // MediaPipe treats a negative count as "no limit"; zero would return
  // nothing, which is a mistake rather than a useful configuration.
  if (maxResults == 0 || maxResults < -0x80000000 || maxResults > 0x7fffffff) {
    throw ArgumentError.value(
      maxResults,
      'maxResults',
      'Must be negative for no limit, or a positive count',
    );
  }
  if (!scoreThreshold.isFinite) {
    throw ArgumentError.value(
      scoreThreshold,
      'scoreThreshold',
      'Must be finite',
    );
  }
  if (categoryAllowlist.isNotEmpty && categoryDenylist.isNotEmpty) {
    throw ArgumentError(
      'Supply at most one of categoryAllowlist and categoryDenylist.',
    );
  }
  if (displayNamesLocale case final locale?) {
    checkLabel(locale, 'displayNamesLocale');
  }
  for (final name in [...categoryAllowlist, ...categoryDenylist]) {
    checkLabel(name, 'category');
  }
}

/// Requires a nonempty metadata label without NUL.
void checkLabel(String value, String name) {
  if (value.isEmpty || value.contains('\u0000')) {
    throw ArgumentError.value(value, name, 'Invalid metadata label');
  }
}
