import '../delegate.dart';
import '../exceptions.dart';

/// The current process platform, including its ABI (not the host CPU's ABI).
final class TaskPlatform {
  /// Construct a platform snapshot. A null OS version means it is unknown.
  const TaskPlatform({
    required this.operatingSystem,
    required this.architecture,
    this.version,
    this.gpu,
    this.simulator = false,
  });

  /// Dart operating system name, or `web` outside native platforms.
  final String operatingSystem;

  /// Process architecture, e.g. `arm64` or `x64`.
  final String architecture;

  /// Product version such as `14.0`, rather than the Darwin kernel version.
  final String? version;

  /// The GPU's OpenGL ES renderer and vendor where an adapter names them (the
  /// Android vision adapter does), e.g. `Mali-G715 (ARM)`; null when unknown.
  /// A task that fails on one GPU family can then declare it unsupported.
  final String? gpu;

  /// Whether this process runs in Apple's iOS Simulator rather than on a
  /// device. The target is still `ios/arm64`, but a GPU path can differ.
  final bool simulator;

  /// `operatingSystem/architecture`, the key used by runtime target tables.
  String get target => '$operatingSystem/$architecture';

  @override
  String toString() =>
      'TaskPlatform($target${version == null ? '' : ' $version'}'
      '${gpu == null ? '' : ', $gpu'}${simulator ? ', simulator' : ''})';
}

/// Names this device's GPU for [TaskPlatform.gpu]. An adapter package that can
/// read it sets this when it registers, before the platform is first read; it
/// is called once, with the rest of the platform.
Future<String?> Function()? taskPlatformGpuReader;

/// Minimum product version for one process target, e.g. `macos/arm64: 14.0`.
///
/// A null version means any version of that operating system is accepted.
typedef RuntimeTargets = Map<String, String?>;

/// Process targets where core bundles Google's MediaPipe engine, which serves
/// the Audio Classifier and every text task: the classifier, embedder
/// (EmbeddingGemma included), language detector, Proofreader and Summarizer
/// (on macOS once the app sets `tasks_runtime: true`).
///
/// This mirrors the build-time release tables in core's hook code; the two are
/// kept in step so that a platform is never reported supported without a
/// runtime, or bundled without a validated support claim.
const tasksRuntimeTargets = <String, String?>{
  'macos/arm64': '14.0',
  'linux/x64': null,
  'windows/x64': null,
  // Through the adapter over Google's iOS SDK that core builds.
  'ios/arm64': '15.0',
};

/// Why [task] cannot run in this process on [operatingSystem]
/// ([TaskPlatform.operatingSystem]): core did not bundle Google's engine.
String tasksRuntimeUnavailable(String task, String operatingSystem) =>
    operatingSystem == 'macos'
    ? "On macOS, $task runs on Google's MediaPipe engine, which "
          'mediapipe_core bundles only when the app opts in, since it '
          "is about 95 MB. Add this to the app's pubspec.yaml:\n"
          '  hooks:\n'
          '    user_defines:\n'
          '      mediapipe_core:\n'
          '        tasks_runtime: true'
    : "$task runs on Google's MediaPipe engine, which "
          'mediapipe_core bundles by default on $operatingSystem. '
          'Remove tasks_runtime: false from '
          "hooks.user_defines.mediapipe_core in the app's pubspec.yaml.";

/// The part of [tasksRuntimeTargets] whose engine also serves the stateful
/// Interactive Segmenter: Google's macOS library. That task is validated
/// there only.
const macosTasksRuntimeTargets = <String, String?>{'macos/arm64': '14.0'};

/// The official MediaPipe release behind core's engine on [platform]:
/// Google's Android SDKs, the pinned Windows wheel and the macOS library are
/// 1.0.0 (1.0.1's macOS detector graphs abort on some Macs), its other
/// runtimes (iOS included) 1.0.1.
String tasksRuntimeVersionOn(TaskPlatform platform) =>
    switch (platform.operatingSystem) {
      'android' || 'windows' || 'macos' => '1.0.0',
      _ => '1.0.1',
    };

/// Declared package support for one task on a platform: which [Delegate]s run
/// there and why the others do not. This is not an inference self-test.
///
/// Model validity, native-asset opt-in, and available memory are checked when
/// creating a task. Querying support does not download assets or initialize
/// the GPU.
final class TaskCapabilities {
  /// Describe delegates whose validated target sets differ.
  ///
  /// Each delegate is checked against its own minimum OS version. Unsupported
  /// delegates use [unavailableReasons], or the target mismatch diagnostic.
  factory TaskCapabilities.onTargets({
    required TaskPlatform platform,
    required Map<Delegate, RuntimeTargets> delegates,
    required Map<Delegate, String> unavailableReasons,
    required String runtimeVersion,
  }) {
    final supported = <Delegate>{};
    final reasons = <Delegate, String>{};
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

  /// Describe CPU support on every target in [targets], with the GPU explained
  /// as unavailable by [gpuUnavailableReason] on targets that are supported.
  ///
  /// Targets not in the table, unknown OS versions and versions older than the
  /// table's minimum fail closed for every delegate.
  factory TaskCapabilities.cpuOnTargets({
    required TaskPlatform platform,
    required String gpuUnavailableReason,
    RuntimeTargets targets = tasksRuntimeTargets,
    String runtimeVersion = '1.0.1',
  }) {
    final platformReason = _platformReason(platform, targets);
    return TaskCapabilities._(
      platform,
      Set.unmodifiable({if (platformReason == null) Delegate.cpu}),
      Map.unmodifiable({
        Delegate.cpu: ?platformReason,
        Delegate.gpu: platformReason ?? gpuUnavailableReason,
      }),
      targets,
      runtimeVersion: runtimeVersion,
    );
  }

  /// Describe the shared 1.0.1 distribution's validated macOS CPU support.
  ///
  /// Equivalent to [TaskCapabilities.cpuOnTargets] with
  /// [macosTasksRuntimeTargets].
  factory TaskCapabilities.macosCpu({
    required TaskPlatform platform,
    required String gpuUnavailableReason,
  }) => TaskCapabilities.cpuOnTargets(
    platform: platform,
    gpuUnavailableReason: gpuUnavailableReason,
    targets: macosTasksRuntimeTargets,
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
  final Set<Delegate> supportedDelegates;

  /// A human-readable explanation for each unavailable delegate.
  final Map<Delegate, String> unavailableReasons;

  /// Pinned upstream runtime version behind these tasks.
  final String runtimeVersion;

  final RuntimeTargets _targets;

  /// Whether at least one delegate is supported on this platform.
  bool get isSupported => supportedDelegates.isNotEmpty;

  /// Process targets with a validated runtime, and their minimum OS versions.
  RuntimeTargets get supportedTargets => Map.unmodifiable(_targets);

  /// Minimum product version of the operating system the packaged native
  /// runtime requires, if any: the current platform's when it is supported,
  /// otherwise the first supported target's.
  String? get minimumOperatingSystemVersion => _targets[_reference];

  String get _reference => _targets.containsKey(platform.target)
      ? platform.target
      : _targets.keys.first;

  @override
  String toString() =>
      'TaskCapabilities($platform, supported: $supportedDelegates, '
      'runtime $runtimeVersion)';

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

/// Fails with the capability query's reason when [delegate] is unavailable,
/// so every task's `create` refuses a delegate the same way on every
/// platform.
void requireDelegate(TaskCapabilities capabilities, Delegate delegate) {
  if (capabilities.supportedDelegates.contains(delegate)) return;
  throw RuntimeUnavailableException(
    'The ${delegate.name.toUpperCase()} delegate is unavailable here.',
    fix:
        capabilities.unavailableReasons[delegate] ??
        'Choose a delegate the capability query reports as supported.',
  );
}
