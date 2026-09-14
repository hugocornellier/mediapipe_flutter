/// The current process platform, including its ABI (not the host CPU's ABI).
final class TaskPlatform {
  /// Construct a platform snapshot. A null OS version means it is unknown.
  const TaskPlatform({
    required this.operatingSystem,
    required this.architecture,
    this.version,
  });

  /// Dart operating system name, or `web` outside native platforms.
  final String operatingSystem;

  /// Process architecture, e.g. `arm64` or `x64`.
  final String architecture;

  /// Product version such as `14.0`, rather than the Darwin kernel version.
  final String? version;
}

/// Declared package support on a platform. This is not an inference self-test.
///
/// Model validity, native-asset opt-in, and available memory are checked when
/// creating a task. Querying support does not download assets or initialize GPU.
final class TaskCapabilities<D extends Enum> {
  /// Describe the shared 1.0.1 distribution's validated macOS CPU support.
  factory TaskCapabilities.macosCpu({
    required TaskPlatform platform,
    required D cpu,
    required D gpu,
    required String gpuUnavailableReason,
  }) {
    final major = int.tryParse(platform.version?.split('.').first ?? '');
    final String? platformReason;
    if (platform.operatingSystem != 'macos' ||
        platform.architecture != 'arm64') {
      platformReason =
          'Requires macOS 14 or later and an arm64 process. '
          'This process is ${platform.operatingSystem} ${platform.architecture}.';
    } else if (major == null) {
      platformReason =
          'Could not verify the required macOS version (14 or later).';
    } else if (major < 14) {
      platformReason = 'Requires macOS 14 or later; found ${platform.version}.';
    } else {
      platformReason = null;
    }
    return TaskCapabilities._(
      platform,
      Set.unmodifiable({if (platformReason == null) cpu}),
      Map.unmodifiable({
        cpu: ?platformReason,
        gpu: platformReason ?? gpuUnavailableReason,
      }),
    );
  }

  const TaskCapabilities._(
    this.platform,
    this.supportedDelegates,
    this.unavailableReasons,
  );

  /// Current process platform used to evaluate support.
  final TaskPlatform platform;

  /// Delegates supported by this package on the current process platform.
  final Set<D> supportedDelegates;

  /// A human-readable explanation for each unavailable delegate.
  final Map<D, String> unavailableReasons;

  /// Whether at least one delegate is supported on this platform.
  bool get isSupported => supportedDelegates.isNotEmpty;

  /// Pinned upstream runtime used by these four modern tasks.
  String get runtimeVersion => '1.0.1';

  /// Operating system required by the packaged native runtime.
  String get requiredOperatingSystem => 'macos';

  /// Process architecture required by the packaged native runtime.
  String get requiredArchitecture => 'arm64';

  /// Minimum macOS product version.
  String get minimumOperatingSystemVersion => '14.0';
}
