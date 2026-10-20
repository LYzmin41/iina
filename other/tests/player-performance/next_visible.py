"""Wait briefly for the next full-app trial requiring a CUA visibility check."""
import argparse
import json
from pathlib import Path
import time
from benchmark import BASE

parser = argparse.ArgumentParser()
parser.add_argument('--tag', default='visible-final')
parser.add_argument('--expected', type=int, default=18)
args = parser.parse_args()
base = BASE / args.tag
deadline = time.monotonic() + 35
while time.monotonic() < deadline:
    try:
        request = json.loads((base / 'awaiting-visibility.json').read_text())
        results = json.loads((base / 'results.json').read_text()) if (base / 'results.json').exists() else []
    except json.JSONDecodeError:
        time.sleep(.1)
        continue
    if not (Path(request['output']) / 'visible').exists() or len(results) == args.expected:
        break
    time.sleep(.25)
print(json.dumps({'next': Path(request['output']).name, 'bundle': request['bundle'], 'completed': len(results),
                  'errors': [x['error'] for x in results if x['error']]}))
