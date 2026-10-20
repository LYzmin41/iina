"""Prepare isolated benchmark apps and matched preferences; no personal data."""
from pathlib import Path
import json
import plistlib
import subprocess
import sys

root = Path(__file__).resolve().parents[3]
out = root / 'build/stability-2026-10-19'
apps = {}
for key, installed, title in [('original', '/Applications/IINA.app', 'IINA Performance Original'),
                               ('before', '/Applications/LYINA.app', 'LYINA Performance Before')]:
    app = out / (title + '.app')
    bundle = 'org.lyzmin41.performance.' + key + '.20261019'
    if not app.exists():
        subprocess.run(['cp', '-cR', installed, str(app)], check=True)
        path = app / 'Contents/Info.plist'
        info = plistlib.loads(path.read_bytes())
        info.update(CFBundleIdentifier=bundle, CFBundleName=title, CFBundleDisplayName=title)
        info.pop('CFBundleURLTypes', None)
        info.pop('CFBundleDocumentTypes', None)
        path.write_bytes(plistlib.dumps(info))
        # Disposable copies permit matched profiler injection. Installed signatures
        # and runtime policy are never changed.
        subprocess.run(['codesign', '--force', '--sign', '-', '--options', '0',
                        '--preserve-metadata=entitlements', str(app)], check=True, capture_output=True)
        subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True, capture_output=True)
    socket = '/tmp/lyina-perf-' + key + '-20261019.sock'
    prefs = {'AppleLanguages': ['en'], 'iinaEnablePluginSystem': False,
             'enableAdvancedSettings': True, 'enableLogging': False,
             'pauseWhenOpen': False, 'pauseWhenInactive': False, 'pauseWhenMinimized': False,
             'recordPlaybackHistory': False, 'recordRecentFiles': False,
             'resumeLastPosition': False, 'autoAddFileToPlaylist': False, 'autoLoadOnlineSub': False,
             'SUEnableAutomaticChecks': False, 'SUHasLaunchedBefore': True,
             'hardwareDecoder': 1,
             'enableOSC': True, 'oscPosition': 0, 'disableAnimations': False,
             'enableControlBarAutoHide': False, 'resizeWindowTiming': 0,
             'resizeWindowOption': 2, 'usePhysicalResolution': False,
             'enableInitialVolume': True, 'initialVolume': 0, 'softVolume': 0.,
             'userOptions': [['input-ipc-server', socket], ['geometry', '960x540'],
                             ['volume', '0'], ['keep-open', 'yes'], ['loop-file', 'inf']]}
    pref_file = out / (key + '-preferences.plist')
    pref_file.write_bytes(plistlib.dumps(prefs))
    subprocess.run(['defaults', 'import', bundle, str(pref_file)], check=True)
    apps[key] = {'app': str(app), 'bundle': bundle, 'socket': socket}
(out / 'apps.json').write_text(json.dumps(apps, indent=2))
print('Prepared isolated original and before copies.')
