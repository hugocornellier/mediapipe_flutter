"""Reviewed official 1.0.0 runtimes used by independent reference generators."""
import platform

RUNTIMES = {
    ('Darwin', 'arm64'): ('libmediapipe.dylib',
        'aa1314b6cc3eb2ce3b610808433930c016e19cdc0f62cbb3f10cc7e912b6f72f'),
    ('Linux', 'x86_64'): ('libmediapipe.so',
        '35ef4187d381addb1309f0f9dedd32613127fa98d1ad1f5ddeea57595cdbcaf0'),
    ('Windows', 'AMD64'): ('libmediapipe.dll',
        'a8970c645c8c87c25ec9965cb5c898e803c6c42f7192b7de9a0541c62ae48cef'),
}

LIBRARY_NAME, LIBRARY_SHA256 = RUNTIMES[(platform.system(), platform.machine())]
