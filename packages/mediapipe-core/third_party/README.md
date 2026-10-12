# Google's notices

`LICENSE` and `NOTICE` are the files Google ships with its MediaPipe 1.1.1
development build of October 9, 2026, the build whose libraries every family
bundles (`lib/src/native_assets/family_runtimes.dart`). Google's delivery has
the same two files for every family, so core carries them once, unmodified.
An app that bundles any family's library redistributes them with it.

`NOTICE` opens with Google's MediaPipe Tasks privacy notice; the repository's
`doc/privacy_and_licenses.md` describes the usage logging it covers.

Decision Maker's Windows library comes from Google's 1.1.0 Python wheel,
under the same Apache-2.0 license.

To update, replace both files with the ones from the build the hooks pin.
