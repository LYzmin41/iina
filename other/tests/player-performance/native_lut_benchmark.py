"""Profile the production LUT popup/import with a native, engine-free fixture.

The actual AppKit control and library code run unchanged. Only player/engine and
file chooser dependencies are fixtures. Full-app checks remain separate.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / 'build/stability-2026-10-19'


def extract(text, marker):
    start = text.index(marker)
    end, depth = text.index('{', start) + 1, 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end]


MAIN = r'''
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let player = PlayerCore()
let popup = VideoLUTPopUp(player: player)
Utility.nextFile = URL(fileURLWithPath: CommandLine.arguments[2])
var completed = false
var started: UInt64 = 0
var measurementStart = 0.0
var result: [String: Any] = [:]
DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
  started = DispatchTime.now().uptimeNanoseconds
  measurementStart = ProcessInfo.processInfo.systemUptime
  popup.selectItem(withTag: -1)
  _ = NSApp.sendAction(popup.action!, to: popup.target, from: popup)
}
let deadline = Date().addingTimeInterval(120)
while !completed && Date() < deadline {
  RunLoop.current.run(until: Date().addingTimeInterval(0.01))
  if started > 0 && (!player.mpv.filters.isEmpty || !Utility.alerts.isEmpty) {
    result = ["elapsed_s": Double(DispatchTime.now().uptimeNanoseconds - started) / 1e9,
              "measurement_start_s": measurementStart,
              "measurement_end_s": ProcessInfo.processInfo.systemUptime,
              "applied": !player.mpv.filters.isEmpty,
              "selected_path": popup.selectedItem?.representedObject as? String ?? "",
              "alerts": Utility.alerts]
    completed = true
  }
}
precondition(completed, "LUT import did not complete")
// Let the outstanding probe callback record any main-thread stall.
RunLoop.current.run(until: Date().addingTimeInterval(0.15))
try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys, .prettyPrinted])
  .write(to: URL(fileURLWithPath: CommandLine.arguments[3]))
'''


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=Path, default=ROOT)
    parser.add_argument('--tag', required=True)
    parser.add_argument('--size', type=int, default=65)
    parser.add_argument('--repetitions', type=int, default=3)
    args = parser.parse_args()
    output = BASE / args.tag
    output.mkdir(exist_ok=False)
    fixture = BASE / ('identity-' + str(args.size) + '.cube')
    if not fixture.exists():
        with fixture.open('w') as target:
            target.write('TITLE "Performance identity"\nLUT_3D_SIZE ' + str(args.size) + '\n')
            for b in range(args.size):
                for g in range(args.size):
                    for r in range(args.size):
                        target.write(f'{r/(args.size-1):.7f} {g/(args.size-1):.7f} {b/(args.size-1):.7f}\n')
    support = (ROOT / 'other/tests/video-lut/popup-support.swift').read_text()
    support = support.replace('// PRODUCTION_SAVED_LUT', extract((args.source / 'iina/PlayerCore.swift').read_text(), '  func detachSavedVideoLUT('))
    video = (args.source / 'iina/SidebarVideoPane.swift').read_text()
    (output / 'main.swift').write_text(support + '\n' + extract(video, 'final class VideoLUTPopUp:') + '\n' +
                                     extract(video, 'enum VideoLUTLibraryActions {') + '\n' + MAIN)
    files = ['TrackSelectionState.swift', 'TrackAudioProcessing.swift', 'TrackVideoProcessing.swift',
             'TrackProcessingState.swift']
    subprocess.run(['xcrun', 'swiftc', '-O', *[str(ROOT / 'iina' / x) for x in files],
                    str(args.source / 'iina/VideoLUT.swift'), str(output / 'main.swift'), '-o', str(output / 'probe')], check=True)
    results = []
    for index in range(args.repetitions):
        trial = output / str(index)
        trial.mkdir()
        env = dict(os.environ, DYLD_INSERT_LIBRARIES=str(BASE / 'main_queue_probe.dylib'),
                   LYINA_PERF_TRACE=str(trial / 'main-queue.csv'))
        subprocess.run([str(output / 'probe'), str(trial / 'profile'), str(fixture), str(trial / 'result.json')], env=env, check=True, timeout=125)
        from benchmark import read_csv
        queue = read_csv(trial / 'main-queue.csv')
        result = json.loads((trial / 'result.json').read_text())
        queue = [x for x in queue if result['measurement_start_s'] <= x['monotonic_s'] <= result['measurement_end_s'] + .1]
        result['main_queue_max_ms'] = max(x['latency_ms'] or 0 for x in queue)
        result['main_pending_max_ms'] = max(x['pending_ms'] or 0 for x in queue)
        result['source_bytes'] = fixture.stat().st_size
        results.append(result)
        print(json.dumps(result), flush=True)
    (output / 'results.json').write_text(json.dumps(results, indent=2))


if __name__ == '__main__':
    main()
