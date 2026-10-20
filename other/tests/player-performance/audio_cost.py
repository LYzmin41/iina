"""Isolate zero-gain mixer decoding cost; no player UI or real audio device."""
import argparse
import ctypes as C
import json
import os
from pathlib import Path
import subprocess
import sys
import time
from benchmark import BASE

parser = argparse.ArgumentParser()
parser.add_argument('--mode', choices=['stock', 'custom-native', 'custom-mixer'])
parser.add_argument('--seconds', type=float, default=8)
parser.add_argument('--repetitions', type=int, default=2)
args = parser.parse_args()
if args.mode is None:
    results = []
    for repeat in range(args.repetitions):
        order = ['stock', 'custom-native', 'custom-mixer']
        if repeat % 2:
            order.reverse()
        for mode in order:
            app = '/Applications/IINA.app' if mode == 'stock' else '/Applications/LYINA.app'
            env = dict(os.environ, DYLD_LIBRARY_PATH=app + '/Contents/Frameworks')
            run = subprocess.run([sys.executable, __file__, '--mode', mode, '--seconds', str(args.seconds)],
                                 capture_output=True, text=True, env=env, check=True, timeout=args.seconds + 20)
            row = json.loads(run.stdout)
            results.append(dict(repeat=repeat, **row))
            print(json.dumps(results[-1]), flush=True)
    (BASE / 'audio-cost.json').write_text(json.dumps(results, indent=2))
    raise SystemExit(0)

app = '/Applications/IINA.app' if args.mode == 'stock' else '/Applications/LYINA.app'
m = C.CDLL(app + '/Contents/Frameworks/libmpv.2.dylib')
class Event(C.Structure):
    _fields_ = [('id', C.c_int), ('error', C.c_int), ('userdata', C.c_ulonglong), ('data', C.c_void_p)]
m.mpv_create.restype = C.c_void_p
for name, params, result in [
    ('mpv_initialize', [C.c_void_p], C.c_int),
    ('mpv_set_option_string', [C.c_void_p, C.c_char_p, C.c_char_p], C.c_int),
    ('mpv_set_property_string', [C.c_void_p, C.c_char_p, C.c_char_p], C.c_int),
    ('mpv_get_property_string', [C.c_void_p, C.c_char_p], C.c_void_p),
    ('mpv_free', [C.c_void_p], None),
    ('mpv_command', [C.c_void_p, C.POINTER(C.c_char_p)], C.c_int),
    ('mpv_wait_event', [C.c_void_p, C.c_double], C.POINTER(Event)),
    ('mpv_terminate_destroy', [C.c_void_p], None)]:
    f = getattr(m, name)
    f.argtypes, f.restype = params, result
p = m.mpv_create()
options = {'config': 'no', 'terminal': 'no', 'vo': 'null', 'vid': 'no', 'ao': 'null',
           'audio-display': 'no', 'audio-channels': 'stereo', 'audio-samplerate': '48000',
           'aid': '1', 'loop-file': 'inf'}
if args.mode == 'custom-mixer':
    pilots = json.loads((BASE / 'baseline/results.json').read_text())
    trial = next(x for x in pilots if '.before.' in x['app']['bundle'] and x['fixture'].endswith('multiaudio.mkv'))
    options['lavfi-complex'] = trial['phases'][0]['final']['lavfi-complex']
for key, value in options.items():
    assert m.mpv_set_option_string(p, key.encode(), value.encode()) >= 0, key
assert m.mpv_initialize(p) >= 0
command = (C.c_char_p * 3)(b'loadfile', str(BASE / 'Media/multiaudio.mkv').encode(), None)
assert m.mpv_command(p, command) >= 0
def drain(seconds):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        event = m.mpv_wait_event(p, .05).contents
        assert event.id != 7, ('unexpected end', event.error)
def position():
    value = m.mpv_get_property_string(p, b'time-pos')
    assert value, 'No audio timeline'
    text = C.string_at(value)
    m.mpv_free(value)
    return float(text)
try:
    drain(2)
    first_position = position()
    wall, cpu = time.monotonic(), time.process_time()
    drain(args.seconds)
    elapsed, used = time.monotonic() - wall, time.process_time() - cpu
    last_position = position()
    assert abs((last_position - first_position) - elapsed) < .5, 'Audio did not advance in real time'
    print(json.dumps({'mode': args.mode, 'seconds': elapsed, 'cpu_percent_one_core': used / elapsed * 100,
                      'time_pos_start': first_position, 'time_pos_end': last_position}))
finally:
    m.mpv_terminate_destroy(p)
