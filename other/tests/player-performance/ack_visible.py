"""Acknowledge a CUA-observed trial and align the timed media interval."""
import argparse
import json
from pathlib import Path
import time
import subprocess
from benchmark import BASE, Engine

parser = argparse.ArgumentParser()
parser.add_argument('trial_name')
parser.add_argument('--tag', default='visible-final')
args = parser.parse_args()
request = json.loads((BASE / args.tag / 'awaiting-visibility.json').read_text())
output = Path(request['output'])
assert output.name == args.trial_name, 'Visible trial changed; inspect the new window first'
assert not (output / 'visible').exists(), 'Trial already acknowledged'
processes = subprocess.check_output(['ps', '-axo', 'pid,comm'], text=True)
owned = [int(line.strip().split(maxsplit=1)[0]) for line in processes.splitlines()
         if str(BASE) + '/' in line and line.rstrip().endswith('/Contents/MacOS/IINA')]
assert owned == [request['pid']], ('Extra owned player process', owned, request['pid'])
apps = json.loads((BASE / 'apps.json').read_text())
app = next(x for x in apps.values() if x['bundle'] == request['bundle'])
engine = Engine(app['socket'])
engine.set('pause', False)
engine.command('seek', '5', 'absolute+exact')
def ready():
    position = engine.get('time-pos')
    return engine.get('seeking') is False and isinstance(position, (int, float)) and 4.9 <= position < 6
engine.wait(ready)
view = engine.get('osd-dimensions')
engine.close()
assert view and (view['w'], view['h']) == (1920, 1080), 'Unequal render viewport'
(output / 'visibility.json').write_text(json.dumps({'observed_via': 'CUA native video-window inspection and raise',
    'time': time.monotonic(), 'osd_dimensions': view, 'fixed_seek_before_warmup': 5,
    'owned_player_pids': owned}, indent=2))
(output / 'visible').touch()
print(output.name, view)
