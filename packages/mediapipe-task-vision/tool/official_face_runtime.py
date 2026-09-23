"""Reviewed official runtimes used by independent reference generators.

Linux uses 1.0.1, the first Linux wheel built with GPU. Upstream never tagged
1.0.1, so its references carry no source revision; the wheel and library
digests identify it.
"""
import platform

RUNTIMES = {
    ('Darwin', 'arm64'): ('libmediapipe.dylib',
        'aa1314b6cc3eb2ce3b610808433930c016e19cdc0f62cbb3f10cc7e912b6f72f',
        '1.0.0', '6d31f1ebc3284db74d211d62bdc4f0a0c29ea120'),
    ('Linux', 'x86_64'): ('libmediapipe.so',
        'b72e6d61a79d1080d29a96ba95e3cfa3e43f6c433c0acc3bc9b3eb7ac0ba103a',
        '1.0.1', None),
    ('Windows', 'AMD64'): ('libmediapipe.dll',
        'a8970c645c8c87c25ec9965cb5c898e803c6c42f7192b7de9a0541c62ae48cef',
        '1.0.0', '6d31f1ebc3284db74d211d62bdc4f0a0c29ea120'),
}

LIBRARY_NAME, LIBRARY_SHA256, VERSION, SOURCE_REVISION = RUNTIMES[
    (platform.system(), platform.machine())]
RUNTIME = 'mediapipe==' + VERSION
