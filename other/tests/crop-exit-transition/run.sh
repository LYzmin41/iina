#!/bin/bash
set -eu
test_dir="$(cd "$(dirname "$0")" && pwd)"
repo_dir="$(cd "$test_dir/../../.." && pwd)"
output_dir="$repo_dir/build/crop-exit-transition-tests"
mkdir -p "$output_dir/module-cache"
python3 - "$repo_dir" "$test_dir" "$output_dir" <<'PY'
from pathlib import Path
import sys
repo, tests, output = map(Path, sys.argv[1:])
def extract(text, marker):
    start = text.index(marker)
    end = text.index('{', start) + 1
    balance = 1
    while balance:
        balance += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end]
controller = (repo/'iina/MainWindowController.swift').read_text()
methods = '\n'.join(extract(controller, marker) for marker in [
    '  func prepareCropExit(', '  func finishCropExitTransition(', '  private func startCropExitAnimation(',
    '  func cancelCropExitTransition('])
overlay = extract((repo/'iina/InteractiveMode.swift').read_text(), 'final class CropExitOverlay:')
source = (tests/'main.swift').read_text().replace('// PRODUCTION_OVERLAY', overlay)
source = source.replace('// PRODUCTION_TRANSITION', methods)
layer = (repo/'iina/ViewLayer.swift').read_text()
snapshots = '\n'.join(extract(layer, marker) for marker in [
    '  private func takeSnapshotHandlers(', '  func cancelSnapshots(', '  func captureSnapshot('])
source = source.replace('// PRODUCTION_SNAPSHOT', snapshots)
(output/'main.swift').write_text(source)
PY
xcrun swiftc -module-cache-path "$output_dir/module-cache" "$output_dir/main.swift" -o "$output_dir/tests"
"$output_dir/tests"
