"""Keep an owned instrumented test app alive for separately controlled UI checks."""
import argparse
import json
from pathlib import Path
import time
from benchmark import BASE, Trial

parser = argparse.ArgumentParser()
parser.add_argument('app')
parser.add_argument('--tag', required=True)
parser.add_argument('--fixture', default='multiaudio.mkv')
args = parser.parse_args()
apps = json.loads((BASE / 'apps.json').read_text())
trial = Trial(apps[args.app], BASE / 'Media' / args.fixture, BASE / args.tag)
error = None
try:
    trial.start()
    print(json.dumps({'pid': trial.process.pid, 'bundle': trial.app['bundle'],
                      'output': str(trial.output)}), flush=True)
    deadline = time.monotonic() + 1200
    progress = []
    while trial.process.poll() is None and not (trial.output / 'stop').exists() and time.monotonic() < deadline:
        progress.append({'time': time.monotonic(), 'position': trial.engine.get('time-pos'),
                         'pause': trial.engine.get('pause'), 'path': trial.engine.get('path')})
        time.sleep(.5)
except Exception as caught:
    if trial.process.poll() is None:
        error = caught
finally:
    (trial.output / 'progress.json').write_text(json.dumps(progress, indent=2))
    (trial.output / 'exit.json').write_text(json.dumps({'normal_process_exit': trial.process.poll(),
                                                     'stop_requested': (trial.output / 'stop').exists()}))
    result = trial.finish(error)
    print(json.dumps({'error': result['error'], 'actions': len(result['actions'])}), flush=True)
