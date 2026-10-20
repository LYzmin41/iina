"""Matched full-app process/engine/main-queue measurements.

Uses JSON IPC for media-engine commands, not UI automation. UI scenarios are
performed separately through CUA. Reports main-queue scheduling, not input lag.
"""
import argparse
import csv
import ctypes
import json
import os
from pathlib import Path
import signal
import socket
import statistics
import subprocess
import time

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / 'build/stability-2026-10-19'

class Engine:
    def __init__(self, path):
        self.socket = socket.socket(socket.AF_UNIX)
        self.socket.settimeout(8)
        self.socket.connect(path)
        self.file = self.socket.makefile('rb')
        self.serial = 0
        self.events = []

    def command(self, *args):
        self.serial += 1
        self.socket.sendall((json.dumps({'command': list(args), 'request_id': self.serial}) + '\n').encode())
        while True:
            data = self.file.readline()
            if not data:
                raise RuntimeError('Engine IPC closed')
            value = json.loads(data)
            if 'event' in value:
                self.events.append({'time': time.monotonic(), **value})
            if value.get('request_id') == self.serial:
                return value

    def get(self, key):
        result = self.command('get_property', key)
        return result.get('data') if result.get('error') == 'success' else None

    def set(self, key, value):
        result = self.command('set_property', key, value)
        assert result.get('error') == 'success', result

    def wait(self, predicate, timeout=20):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if predicate():
                return
            time.sleep(.01)
        raise TimeoutError('Engine readiness timeout')

    def wait_restart(self, since, timeout=20):
        def ready():
            self.get('seeking')  # Drain asynchronous events through the same IPC client.
            return any(x['event'] == 'playback-restart' and x['time'] >= since for x in self.events)
        self.wait(ready, timeout)
        return next(x['time'] - since for x in self.events if x['event'] == 'playback-restart' and x['time'] >= since)

    def close(self):
        self.file.close()
        self.socket.close()

PROPERTIES = ['mpv-version', 'ffmpeg-version', 'hwdec-current', 'video-codec', 'audio-codec-name', 'vf',
              'osd-dimensions', 'window-scale',
              'video-out-params', 'audio-params', 'demuxer', 'duration', 'pause', 'time-pos',
              'frame-drop-count', 'decoder-frame-drop-count', 'mistimed-frame-count',
              'vo-delayed-frame-count', 'estimated-vf-fps', 'display-fps', 'avsync', 'lavfi-complex']

def snapshot(engine):
    return {name: engine.get(name) for name in PROPERTIES}

def percentile(values, fraction):
    if not values:
        return None
    values = sorted(values)
    point = (len(values) - 1) * fraction
    lo, hi = int(point), min(len(values) - 1, int(point) + 1)
    return values[lo] + (values[hi] - values[lo]) * (point - lo)

def read_csv(path):
    with path.open() as source:
        return [{key: float(value) if value else None for key, value in row.items()}
                for row in csv.DictReader(source)]

def metrics(phase, usage, queue):
    start, end = phase['start'], phase['end']
    samples = [x for x in usage if start <= x['monotonic_s'] <= end]
    assert len(samples) >= 2, ('insufficient process samples', phase['name'])
    cpu = [((b['user_ns'] + b['system_ns']) - (a['user_ns'] + a['system_ns'])) /
           (b['monotonic_s'] - a['monotonic_s']) / 1e7 for a, b in zip(samples, samples[1:])]
    first, last = samples[0], samples[-1]
    cpu_mean = (((last['user_ns'] + last['system_ns']) - (first['user_ns'] + first['system_ns'])) /
                ((last['monotonic_s'] - first['monotonic_s']) * 1e7))
    latency = [x['latency_ms'] for x in queue if start <= x['monotonic_s'] <= end and x['latency_ms'] is not None]
    pending = [x['pending_ms'] for x in queue if start <= x['monotonic_s'] <= end and x['pending_ms'] is not None]
    return {'cpu_mean_percent': cpu_mean, 'cpu_p95_percent': percentile(cpu, .95),
            'footprint_median_mib': statistics.median(x['footprint_bytes'] for x in samples) / 2**20,
            'footprint_peak_mib': max(x['footprint_bytes'] for x in samples) / 2**20,
            'rss_median_mib': statistics.median(x['resident_bytes'] for x in samples) / 2**20,
            'main_queue_p50_ms': percentile(latency, .5), 'main_queue_p95_ms': percentile(latency, .95),
            'main_queue_max_ms': max(latency, default=0), 'main_pending_max_ms': max(pending, default=0),
            'main_samples': len(latency), 'sampled_seconds': last['monotonic_s'] - first['monotonic_s']}

class Trial:
    def __init__(self, app, fixture, output, inject=True, visible=False):
        self.app, self.fixture, self.output = app, fixture, output
        self.phases, self.actions = [], []
        output.mkdir(parents=True, exist_ok=False)
        self.inject = inject
        self.visible = visible

    def start(self):
        app, fixture, output, inject = self.app, self.fixture, self.output, self.inject
        if self.visible:
            assert app['bundle'].startswith('org.lyzmin41.performance.')
            key = app['bundle'].split('.')[3]
            profile = BASE / (key + '-visible-preferences.plist')
            # Import alone can retain values changed by a preceding GUI trial.
            # Recreate only this owned test domain before launching its process.
            subprocess.run(['defaults', 'delete', app['bundle']], capture_output=True)
            subprocess.run(['defaults', 'import', app['bundle'], str(profile)], check=True)
        Path(app['socket']).unlink(missing_ok=True)
        env = dict(os.environ)
        if inject:
            env.update(DYLD_INSERT_LIBRARIES=str(BASE / 'main_queue_probe.dylib'),
                       LYINA_PERF_TRACE=str(output / 'main-queue.csv'))
        self.started = time.monotonic()
        self.log = (output / 'app.log').open('w')
        self.process = subprocess.Popen([str(Path(app['app']) / 'Contents/MacOS/IINA'), str(fixture)],
                                        stdout=self.log, stderr=subprocess.STDOUT, env=env, start_new_session=True)
        self.usage_log = (output / 'usage.csv').open('w')
        self.sampler = subprocess.Popen([str(BASE / 'process_usage'), str(self.process.pid)], stdout=self.usage_log)
        (output / 'process.json').write_text(json.dumps({'pid': self.process.pid, 'started': self.started, 'app': app}, indent=2))
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            if self.process.poll() is not None:
                raise RuntimeError('App exited at startup')
            if Path(app['socket']).exists():
                break
            time.sleep(.02)
        else:
            raise TimeoutError('IPC socket not created')
        self.engine = Engine(app['socket'])
        self.engine.wait(lambda: isinstance(self.engine.get('video-out-params'), dict)
                         and self.engine.get('pause') is False)
        self.ready_seconds = time.monotonic() - self.started
        if self.visible:
            # The controller uses CUA to inspect and foreground the actual video
            # window, then acknowledges it. No UI automation runs in this script.
            request = {'pid': self.process.pid, 'bundle': app['bundle'], 'fixture': fixture.name,
                       'output': str(output)}
            (output.parent / 'awaiting-visibility.json').write_text(json.dumps(request, indent=2))
            deadline = time.monotonic() + 180
            while not (output / 'visible').exists():
                if self.process.poll() is not None or time.monotonic() > deadline:
                    raise TimeoutError('No CUA visible-window acknowledgement')
                time.sleep(.05)
        self.initial = snapshot(self.engine)
        if inject:
            assert (output / 'main-queue.csv').exists(), 'DYLD instrumentation did not load'

    def phase(self, name, duration, playing):
        self.engine.set('pause', not playing)
        # Predefined warmup excludes decoder/render reconfiguration from steady state.
        time.sleep(2)
        assert self.engine.get('pause') == (not playing), 'Playback state differs from requested phase'
        phase = {'name': name, 'start': time.monotonic(), 'initial': snapshot(self.engine), 'progress': []}
        if self.visible:
            assert phase['initial']['hwdec-current'] == 'videotoolbox', 'Unequal decoder mode'
            assert phase['initial']['vf'] == [], 'Unexpected video filters in playback comparison'
        until = phase['start'] + duration
        while time.monotonic() < until:
            phase['progress'].append([time.monotonic(), self.engine.get('time-pos')])
            time.sleep(.5)
        phase['end'] = time.monotonic()
        phase['final'] = snapshot(self.engine)
        if playing:
            positions = [x[1] for x in phase['progress'] if isinstance(x[1], (float, int))]
            assert len(set(positions)) > 1, 'Playing phase has no timeline progress'
        self.phases.append(phase)

    def stress(self, second_fixture, count):
        self.engine.set('pause', False)
        self.engine.set('loop-file', 'inf')
        for operation in ['seek', 'load']:
            for index in range(count):
                self.engine.get('time-pos')  # Drain events from the preceding operation.
                start = time.monotonic()
                if operation == 'seek':
                    target = 1 + (index * 7) % 23
                    result = self.engine.command('seek', str(target), 'absolute+exact')
                else:
                    path = second_fixture if index % 2 == 0 else self.fixture
                    result = self.engine.command('loadfile', str(path), 'replace')
                assert result.get('error') == 'success', result
                self.engine.wait_restart(start)
                def ready():
                    position = self.engine.get('time-pos')
                    if operation == 'seek':
                        return (self.engine.get('seeking') is False and isinstance(position, (int, float))
                                and target - .1 <= position < target + 2)
                    return self.engine.get('path') == str(path) and self.engine.get('seeking') is False
                self.engine.wait(ready)
                elapsed = time.monotonic() - start
                self.actions.append({'kind': operation, 'index': index, 'seconds': elapsed,
                                     'time': time.monotonic(), 'position': self.engine.get('time-pos')})
        # Engine IPC completion precedes Cocoa's asynchronous file-open resume.
        # Let the final open settle before measuring a sustained pause.
        settled = time.monotonic()
        time.sleep(3)
        for _ in range(15):
            self.engine.set('pause', True)
            time.sleep(1)
            if self.engine.get('pause') is True:
                time.sleep(1)
                if self.engine.get('pause') is True:
                    break
        else:
            raise TimeoutError('Final Cocoa open/resume work did not settle')
        self.post_stress_settle_s = time.monotonic() - settled
        self.phase('paused_after_stress', 8, False)

    def finish(self, error=None):
        if error is not None and self.process.poll() is None:
            subprocess.run(['sample', str(self.process.pid), '2', '10', '-file', str(self.output / 'failure.sample.txt')],
                           capture_output=True, timeout=8)
        if hasattr(self, 'engine'):
            self.engine.close()
        if self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=8)
            except subprocess.TimeoutExpired:
                self.process.kill(); self.process.wait(timeout=3)
        self.sampler.wait(timeout=3)
        self.usage_log.close(); self.log.close()
        usage = read_csv(self.output / 'usage.csv')
        queue = read_csv(self.output / 'main-queue.csv') if (self.output / 'main-queue.csv').exists() else []
        result = {'app': self.app, 'fixture': str(self.fixture), 'startup_ready_s': getattr(self, 'ready_seconds', None),
                  'initial': getattr(self, 'initial', {}), 'phases': self.phases, 'actions': self.actions,
                  'post_stress_settle_s': getattr(self, 'post_stress_settle_s', None),
                  'visible_window_acknowledged': self.visible and (self.output / 'visible').exists(),
                  'error': str(error) if error else None,
                  'metrics': {phase['name']: metrics(phase, usage, queue) for phase in self.phases}}
        (self.output / 'result.json').write_text(json.dumps(result, indent=2))
        return result

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--apps', default='original,before')
    parser.add_argument('--fixtures', default='single-1080p60.mp4,single-4k30.mp4,multiaudio.mkv')
    parser.add_argument('--seconds', type=float, default=12)
    parser.add_argument('--repetitions', type=int, default=3)
    parser.add_argument('--tag', required=True)
    parser.add_argument('--stress', type=int, default=0)
    parser.add_argument('--no-injection', action='store_true')
    parser.add_argument('--visible', action='store_true')
    args = parser.parse_args()
    apps = json.loads((BASE / 'apps.json').read_text())
    output = BASE / args.tag
    output.mkdir(exist_ok=False)
    results = []
    for fixture_name in args.fixtures.split(','):
        fixture = BASE / 'Media' / fixture_name
        for repeat in range(args.repetitions):
            order = args.apps.split(',')
            if repeat % 2:
                order.reverse()
            for key in order:
                trial = None
                try:
                    trial = Trial(apps[key], fixture, output / (fixture.stem + '-' + key + '-' + str(repeat)), not args.no_injection, args.visible)
                    trial.start()
                    trial.phase('playing', args.seconds, True)
                    trial.phase('paused', args.seconds, False)
                    if args.stress:
                        trial.stress(BASE / 'Media/single-1080p60.mp4', args.stress)
                    result = trial.finish()
                except Exception as error:
                    if trial is not None:
                        result = trial.finish(error)
                    else:
                        raise
                results.append(result)
                (output / 'results.json').write_text(json.dumps(results, indent=2))
                print(json.dumps({'fixture': fixture.name, 'app': key, 'repeat': repeat,
                                  'ready_s': result['startup_ready_s'], 'metrics': result['metrics'], 'error': result['error']}), flush=True)

if __name__ == '__main__':
    main()
