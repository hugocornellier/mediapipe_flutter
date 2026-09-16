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

  /// `operatingSystem/architecture`, the key used by runtime target tables.
  String get target => '$operatingSystem/$architecture';
}

/// Minimum product version for one process target, e.g. `macos/arm64: 14.0`.
///
/// A null version means any version of that operating system is accepted.
typedef RuntimeTargets = Map<String, String?>;

/// Process targets the shared official 1.0.1 runtime has been validated on.
///
/// This mirrors the build-time release table in core's hook code; the two are
/// kept in step so that a platform is never reported supported without a
/// runtime, or bundled without a validated support claim.
const tasksRuntimeTargets = <String, String?>{'macos/arm64': '14.0'};

/// Declared package support on a platform. This is not an inference self-test.
///
/// Model validity, native-asset opt-in, and available memory are checked when
/// creating a task. Querying support does not download assets or initialize GPU.
final class TaskCapabilities<D extends Enum> {
  /// Describe delegates whose validated target sets differ.
  ///
  /// Each delegate is checked against its own minimum OS version. Unsupported
  /// delegates use [unavailableReasons], or the target mismatch diagnostic.
  factory TaskCapabilities.onTargets({
    required TaskPlatform platform,
    required Map<D, RuntimeTargets> delegates,
    required Map<D, String> unavailableReasons,
    required String runtimeVersion,
  }) {
    final supported = <D>{};
    final reasons = <D, String>{};
    final targets = <String, String?>{};
    for (final entry in delegates.entries) {
      for (final target in entry.value.entries) {
        if (!targets.containsKey(target.key) ||
            target.value == null ||
            (targets[target.key] != null &&
                _compareVersions(target.value!, targets[target.key]!) < 0)) {
          targets[target.key] = target.value;
        }
      }
      final reason = _platformReason(platform, entry.value);
      if (reason == null) {
        supported.add(entry.key);
      } else {
        reasons[entry.key] = entry.value.containsKey(platform.target)
            ? reason
            : unavailableReasons[entry.key] ?? reason;
      }
    }
    return TaskCapabilities._(
      platform,
      Set.unmodifiable(supported),
      Map.unmodifiable(reasons),
      Map.unmodifiable(targets),
      runtimeVersion: runtimeVersion,
    );
  }

  /// Describe CPU support on every target in [targets], with GPU explained as
  /// unavailable by [gpuUnavailableReason] on targets that are supported.
  ///
  /// Targets not in the table, unknown OS versions and versions older than the
  /// table's minimum fail closed for every delegate.
  factory TaskCapabilities.cpuOnTargets({
    required TaskPlatform platform,
    required D cpu,
    required D gpu,
    required String gpuUnavailableReason,
    RuntimeTargets targets = tasksRuntimeTargets,
    String runtimeVersion = '1.0.1',
  }) {
    final platformReason = _platformReason(platform, targets);
    return TaskCapabilities._(
      platform,
      Set.unmodifiable({if (platformReason == null) cpu}),
      Map.unmodifiable({
        cpu: ?platformReason,
        gpu: platformReason ?? gpuUnavailableReason,
      }),
      targets,
      runtimeVersion: runtimeVersion,
    );
  }

  /// Describe GPU support on every target in [targets], with CPU explained as
  /// unavailable by [cpuUnavailableReason] on targets that are supported.
  ///
  /// The mirror of [TaskCapabilities.cpuOnTargets], for a task whose CPU path
  /// is the broken one. Targets not in the table, unknown OS versions and
  /// versions older than the table's minimum fail closed for every delegate.
  factory TaskCapabilities.gpuOnTargets({
    required TaskPlatform platform,
    required D cpu,
    required D gpu,
    required String cpuUnavailableReason,
    RuntimeTargets targets = tasksRuntimeTargets,
    String runtimeVersion = '1.0.1',
  }) {
    final platformReason = _platformReason(platform, targets);
    return TaskCapabilities._(
      platform,
      Set.unmodifiable({if (platformReason == null) gpu}),
      Map.unmodifiable({
        gpu: ?platformReason,
        cpu: platformReason ?? cpuUnavailableReason,
      }),
      targets,
      runtimeVersion: runtimeVersion,
    );
  }

  /// Describe the shared 1.0.1 distribution's validated macOS CPU support.
  ///
  /// Equivalent to [TaskCapabilities.cpuOnTargets] with the shared runtime's
  /// target table.
  factory TaskCapabilities.macosCpu({
    required TaskPlatform platform,
    required D cpu,
    required D gpu,
    required String gpuUnavailableReason,
  }) => TaskCapabilities.cpuOnTargets(
    platform: platform,
    cpu: cpu,
    gpu: gpu,
    gpuUnavailableReason: gpuUnavailableReason,
  );

  const TaskCapabilities._(
    this.platform,
    this.supportedDelegates,
    this.unavailableReasons,
    this._targets, {
    required this.runtimeVersion,
  });

  /// Current process platform used to evaluate support.
  final TaskPlatform platform;

  /// Delegates supported by this package on the current process platform.
  final Set<D> supportedDelegates;

  /// A human-readable explanation for each unavailable delegate.
  final Map<D, String> unavailableReasons;

  /// Pinned upstream runtime version behind these tasks.
  final String runtimeVersion;

  final RuntimeTargets _targets;

  /// Whether at least one delegate is supported on this platform.
  bool get isSupported => supportedDelegates.isNotEmpty;

  /// Process targets with a validated runtime, and their minimum OS versions.
  RuntimeTargets get supportedTargets => Map.unmodifiable(_targets);

  /// Operating system required by the packaged native runtime.
  ///
  /// The current platform's OS when it is supported, otherwise the first
  /// supported target's OS.
  String get requiredOperatingSystem => _reference.split('/').first;

  /// Process architecture required by the packaged native runtime.
  String get requiredArchitecture => _reference.split('/').last;

  /// Minimum product version on [requiredOperatingSystem], if any.
  String? get minimumOperatingSystemVersion => _targets[_reference];

  String get _reference => _targets.containsKey(platform.target)
      ? platform.target
      : _targets.keys.first;

  static String? _platformReason(
    TaskPlatform platform,
    RuntimeTargets targets,
  ) {
    if (!targets.containsKey(platform.target)) {
      final supported = targets.entries
          .map((e) => e.value == null ? e.key : '${e.key} (${e.value}+)')
          .join(', ');
      return 'Requires one of $supported. This process is ${platform.target}.';
    }
    final minimum = targets[platform.target];
    if (minimum == null) return null;
    final name = _displayName(platform.operatingSystem);
    final major = int.tryParse(platform.version?.split('.').first ?? '');
    if (major == null) {
      return 'Could not verify the required $name version ($minimum or later).';
    }
    if (_compareVersions(platform.version!, minimum) < 0) {
      return 'Requires $name $minimum or later; found ${platform.version}.';
    }
    return null;
  }

  static String _displayName(String operatingSystem) =>
      switch (operatingSystem) {
        'macos' => 'macOS',
        'ios' => 'iOS',
        'android' => 'Android',
        'windows' => 'Windows',
        'linux' => 'Linux',
        _ => operatingSystem,
      };

  static int _compareVersions(String a, String b) {
    final left = a.split('.').map(int.tryParse).toList();
    final right = b.split('.').map(int.tryParse).toList();
    for (var i = 0; i < left.length || i < right.length; i++) {
      final l = i < left.length ? left[i] ?? 0 : 0;
      final r = i < right.length ? right[i] ?? 0 : 0;
      if (l != r) return l.compareTo(r);
    }
    return 0;
  }
}
