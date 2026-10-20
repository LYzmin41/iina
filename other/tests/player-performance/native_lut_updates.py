"""Measure real LUT-popup notification handling with a large managed library."""
import argparse
import json
from pathlib import Path
import subprocess
from native_lut_benchmark import ROOT, BASE, extract

parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path, default=ROOT)
parser.add_argument('--tag', required=True)
parser.add_argument('--entries', type=int, default=500)
parser.add_argument('--updates', type=int, default=120)
args = parser.parse_args()
output = BASE / args.tag
output.mkdir(exist_ok=False)
support = (ROOT / 'other/tests/video-lut/popup-support.swift').read_text()
support = support.replace('// PRODUCTION_SAVED_LUT', extract((args.source / 'iina/PlayerCore.swift').read_text(), '  func detachSavedVideoLUT('))
support = support.replace('func postNotification(_ name: Notification.Name) {}', '''
  var observers: [Notification.Name: [(Notification) -> Void]] = [:]
  func postNotification(_ name: Notification.Name) {
    for callback in observers[name] ?? [] { callback(Notification(name: name, object: self)) }
  }''')
support = support.replace('func observe(_ name: Notification.Name, block: @escaping (Notification) -> Void) {}',
                          'func observe(_ name: Notification.Name, block: @escaping (Notification) -> Void) { observers[name, default: []].append(block) }')
main = r'''
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let directory = Utility.appSupportDirUrl.appendingPathComponent("LUTs")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let data = Data("LUT_3D_SIZE 2\n0 0 0\n1 0 0\n0 1 0\n1 1 0\n0 0 1\n1 0 1\n0 1 1\n1 1 1\n".utf8)
for index in 0..<ENTRY_COUNT { try data.write(to: directory.appendingPathComponent("Look \(index).cube")) }
let player = PlayerCore()
let popup = VideoLUTPopUp(player: player)
RunLoop.current.run(until: Date().addingTimeInterval(0.1))
var durations = [Double]()
for _ in 0..<UPDATE_COUNT {
  autoreleasepool {
    let start = DispatchTime.now().uptimeNanoseconds
    player.postNotification(.iinaTrackSettingsChanged)
    durations.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6)
  }
}
let result: [String: Any] = ["durations_ms": durations, "items": popup.numberOfItems]
try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
  .write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
'''.replace('ENTRY_COUNT', str(args.entries)).replace('UPDATE_COUNT', str(args.updates))
video = (args.source / 'iina/SidebarVideoPane.swift').read_text()
(output / 'main.swift').write_text(support + '\n' + extract(video, 'final class VideoLUTPopUp:') + '\n' +
                                 extract(video, 'enum VideoLUTLibraryActions {') + '\n' + main)
files = ['TrackSelectionState.swift', 'TrackAudioProcessing.swift', 'TrackVideoProcessing.swift', 'TrackProcessingState.swift']
subprocess.run(['xcrun', 'swiftc', '-O', *[str(ROOT / 'iina' / x) for x in files],
                str(args.source / 'iina/VideoLUT.swift'), str(output / 'main.swift'), '-o', str(output / 'probe')], check=True)
subprocess.run([str(output / 'probe'), str(output / 'profile'), str(output / 'result.json')], check=True, timeout=120)
from benchmark import percentile
rows = json.loads((output / 'result.json').read_text())
values = rows['durations_ms']
print(json.dumps({'entries': args.entries, 'updates': len(values), 'median_ms': percentile(values, .5),
                  'p95_ms': percentile(values, .95), 'max_ms': max(values), 'total_ms': sum(values)}))
