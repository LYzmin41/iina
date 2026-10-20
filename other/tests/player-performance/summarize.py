"""Summarize repeated, matched runs without hiding their ranges."""
from collections import defaultdict
import json
from pathlib import Path
import statistics
import sys

groups = defaultdict(list)
for filename in sys.argv[1:]:
    for row in json.loads(Path(filename).read_text()):
        app = row['app']['bundle'].split('.')[3]
        fixture = Path(row['fixture']).name
        for phase, metrics in row['metrics'].items():
            groups[fixture, app, phase].append((row, metrics))

result = []
for (fixture, app, phase), rows in groups.items():
    item = dict(fixture=fixture, app=app, phase=phase, trials=len(rows))
    for key in ['cpu_mean_percent', 'footprint_median_mib', 'main_queue_p95_ms',
                'main_queue_max_ms', 'main_pending_max_ms']:
        values = [m[key] for _, m in rows if m[key] is not None]
        item[key] = {'median': statistics.median(values), 'min': min(values), 'max': max(values)} if values else None
    starts = [row['startup_ready_s'] for row, _ in rows]
    item['startup_ready_s'] = {'median': statistics.median(starts), 'min': min(starts), 'max': max(starts)}
    item['errors'] = [row['error'] for row, _ in rows if row['error']]
    drops = []
    for row, _ in rows:
        details = next(x for x in row['phases'] if x['name'] == phase)
        drops.append({key: details['final'][key] - details['initial'][key]
                      for key in ['frame-drop-count', 'decoder-frame-drop-count', 'vo-delayed-frame-count']
                      if details['final'][key] is not None and details['initial'][key] is not None})
    item['drop_deltas'] = drops
    result.append(item)
print(json.dumps(result, indent=2))
