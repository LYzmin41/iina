#!/usr/bin/env python3
"""Prepare an isolated IINA bundle/profile after a local Nightly build."""
import pathlib
import plistlib
import shutil
import subprocess

root = pathlib.Path(__file__).resolve().parents[3]
lab = root / 'build/osc-lab'
app = lab / 'IINA OSC Lab.app'
source = root / 'build/DerivedData/Build/Products/Nightly/IINA.app'
if not source.exists():
    raise SystemExit('Build Nightly with -derivedDataPath build/DerivedData first.')
if app.exists():
    raise SystemExit('Lab bundle already exists. Reuse it; do not replace a running lab app.')
shutil.copytree(source, app, symlinks=True)
info_path = app / 'Contents/Info.plist'
with info_path.open('rb') as stream:
    info = plistlib.load(stream)
info.update(CFBundleIdentifier='org.iina.osc-position-lab', CFBundleName='IINA OSC Lab',
            CFBundleDisplayName='IINA OSC Lab', SUEnableAutomaticChecks=False)
info.pop('CFBundleURLTypes', None)
with info_path.open('wb') as stream:
    plistlib.dump(info, stream)
home = lab / 'home'
prefs = home / 'Library/Preferences'
prefs.mkdir(parents=True, exist_ok=True)
(lab / 'tmp').mkdir(exist_ok=True)
profile_path = prefs / 'org.iina.osc-position-lab.plist'
with profile_path.open('wb') as stream:
    plistlib.dump({'iinaEnablePluginSystem': False, 'enableControlBarAutoHide': False,
                  'useLiquidGlassOSC': False, 'pauseWhenOpen': True,
                  'recordPlaybackHistory': False, 'recordRecentFiles': False,
                  'resumeLastPosition': False, 'SUEnableAutomaticChecks': False,
                  'controlBarPositionHorizontal': 0.7, 'controlBarPositionVertical': 0.4,
                  'AppleLanguages': ['en']}, stream)
# CF preferences uses its service's home even with CFFIXED_USER_HOME. This domain
# is dedicated to the test app; production com.colliderli.iina is never accessed.
subprocess.run(['defaults', 'import', 'org.iina.osc-position-lab', str(profile_path)], check=True)
with (lab / 'fixture.y4m').open('wb') as stream:
    stream.write(b'YUV4MPEG2 W640 H360 F25:1 Ip A1:1 C420jpeg\n')
    frame = b'FRAME\n' + bytes([100]) * (640 * 360) + bytes([128]) * (640 * 360 // 2)
    for _ in range(250):
        stream.write(frame)
subprocess.run(['codesign', '--force', '--deep', '--sign', '-', str(app)], check=True)
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
print(f'Prepared {app}. Use the direct executable with CFFIXED_USER_HOME={home}.')
