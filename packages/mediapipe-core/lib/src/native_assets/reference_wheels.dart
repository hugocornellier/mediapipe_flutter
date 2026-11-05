/// Google's official Python wheel the tests treat as ground truth on a host.
///
/// The reference tools run Google's own Python API from this wheel, and the
/// tests compare the family libraries with what it answered. Each receipt
/// records the wheel's and its C library's digests, which the tests check
/// against these pins. It is Google's `mediapipe-nightly` 1.1.0 release
/// candidate, a release older than the family libraries
/// (`familyRuntimeVersion`, Google's 1.2.2 release of November 2). Google
/// published 1.1.0 itself on October 6, 2026 and a 1.1.1 nightly on
/// October 13; the pins move with the next regeneration of every fixture,
/// once Google says whether the Metal output since 1.1.1 is intended.
typedef ReferenceWheel = ({
  String version,
  String url,
  String wheelSha256,
  String libraryName,
  String librarySha256,
});

/// Google's wheel for each host that generates references.
const referenceWheels = <String, ReferenceWheel>{
  'macos/arm64': (
    version: '1.1.0rc20260925',
    url:
        'https://files.pythonhosted.org/packages/22/e7/'
        '4ab757489c2a167e7e84ff627389e7476c12e4b4998a332a7189d8b98eb0/'
        'mediapipe_nightly-1.1.0rc20260925-py3-none-macosx_11_0_arm64.whl',
    wheelSha256:
        '357a587c9ecfe73150a955cefd3715d01c1b5b58d70f9b09b1a80cb7f8761b2c',
    libraryName: 'libmediapipe.dylib',
    librarySha256:
        'a9d0e783f1aef73aae4a0e2df46154ced7d3dcb9ccd36989c092592921afcad6',
  ),
  'linux/x64': (
    version: '1.1.0rc20260925',
    url:
        'https://files.pythonhosted.org/packages/eb/ec/'
        '2caa83a45c295839e03a3dcbc3f2c883d5e07e128b1975a109420420b829/'
        'mediapipe_nightly-1.1.0rc20260925-py3-none-manylinux_2_28_x86_64.whl',
    wheelSha256:
        '634184cef1c39beb1bf0d0997a20e564c952303afc4cb42d18f2050a549393a2',
    libraryName: 'libmediapipe.so',
    librarySha256:
        '273e2ea1757c0e88e580c64829160f7711fdcd89ac2673a8fbbcab3058926087',
  ),
  'windows/x64': (
    version: '1.1.0rc20260925',
    url:
        'https://files.pythonhosted.org/packages/e4/e9/'
        '1fb04b4463213710ed62f1be71b22670d82a2d46316126cc6e8fb9b841c5/'
        'mediapipe_nightly-1.1.0rc20260925-py3-none-win_amd64.whl',
    wheelSha256:
        'b3ce6b3b4a3e870195930cbd96f626f49ad192ab591df0d9846a24302f64c0ff',
    libraryName: 'libmediapipe.dll',
    librarySha256:
        '67671f2f1bb5bf5ffcf6c1e7567859247f8fac7f111878b7b9b7e30f4bd8e103',
  ),
};

/// Google's wheel for the tasks [referenceWheels]' 1.1.0 has not got: the
/// Audio Transcriber and Text to Speech, new in Google's 1.2.2 C API. It is
/// Google's `mediapipe-nightly` 1.2.2 release candidate of November 3, a
/// day newer than the family libraries' 1.2.2 release build of November 2,
/// with the same C headers; Google publishes no 1.2.2 wheel of its own.
const speechReferenceWheels = <String, ReferenceWheel>{
  'macos/arm64': (
    version: '1.2.2rc20261103',
    url:
        'https://files.pythonhosted.org/packages/03/c1/'
        'd23e279d1703f76980061c12e0760282d41d6b7dc30c918f8112cdbc36a2/'
        'mediapipe_nightly-1.2.2rc20261103-py3-none-macosx_11_0_arm64.whl',
    wheelSha256:
        '0faed967eb0c18f68d1935607de5736170cac933c0f5fb7cb36a743ce3beb533',
    libraryName: 'libmediapipe.dylib',
    librarySha256:
        '10b6bdaa7efc9e74b352de88d7ae8e8fb1f12d3d2f869e4533c68d6019a3bba1',
  ),
  'linux/x64': (
    version: '1.2.2rc20261103',
    url:
        'https://files.pythonhosted.org/packages/c6/b2/'
        '96ec0c347c327e3f93db7883b09c2cdfaa2f8c3e30686a33fa9bb934498d/'
        'mediapipe_nightly-1.2.2rc20261103-py3-none-manylinux_2_28_x86_64.whl',
    wheelSha256:
        'b7256eca2d521e7cb4c6d4a9e03357632df00692e37beb31a7d0aec8dc0c57bf',
    libraryName: 'libmediapipe.so',
    librarySha256:
        '78c8d7bcb6d26c3eaca80fb039413cd78a21cf7c7d86bf89d923ab6b0b6ff538',
  ),
  'windows/x64': (
    version: '1.2.2rc20261103',
    url:
        'https://files.pythonhosted.org/packages/11/4c/'
        '64444faaf03d135d285b9fc32fc13427843b7aed02fd746b81cd935cea8d/'
        'mediapipe_nightly-1.2.2rc20261103-py3-none-win_amd64.whl',
    wheelSha256:
        'e7179e2e85bd575b41497527590c9ccf391ad2b4349bde81c4245c88e03f5db7',
    libraryName: 'libmediapipe.dll',
    librarySha256:
        '31e12af83fd79c6c214a649586805e09cd00f373ed510c27fc1c48dbe004443e',
  ),
};

/// The [referenceWheels] row for [target] (such as `macos/arm64`), or null
/// where no host generates references.
ReferenceWheel? referenceWheel(String target) => referenceWheels[target];

/// The [speechReferenceWheels] row for [target], or null where no host
/// generates speech references.
ReferenceWheel? speechReferenceWheel(String target) =>
    speechReferenceWheels[target];
