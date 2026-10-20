# Player performance investigation

These tools compare disposable copies of installed IINA and LYINA. They never
write personal preferences or change the installed applications. Run from the
worktree containing the changes. Evidence is kept in
`build/stability-2026-10-19/`; the fixture manifest records the media parameters.

Prepare the probe and sampler:

```sh
clang -O2 -fblocks -dynamiclib main_queue_probe.c -o main_queue_probe.dylib
clang -O2 process_usage.c -o process_usage
python3 prepare.py
python3 benchmark.py --tag baseline --seconds 12 --repetitions 3
python3 summarize.py ../../../build/stability-2026-10-19/baseline/results.json
```

Place the compiled binaries in the evidence directory before running the Python
scripts. `prepare.py` uses APFS clones and separate bundle identifiers, removes
file/URL associations and re-signs only the disposable copies for injection.
Profiles have matched options, no plugins/history/resume, hardware decoding,
960 × 540 requested geometry and enabled animations. The final visible profiles
use OSC auto-hide after 0.5 seconds and explicitly select VideoToolbox rather than
copy mode. Their actual render viewport is verified as 1920 × 1080 before timing.

For visible trials, run from the repository root:

```sh
caffeinate -di python3 other/tests/player-performance/benchmark.py --apps original,before,after --seconds 8 --repetitions 2 --visible --tag visible-final
```

`--visible` waits for a CUA inspection before each trial, up to 180 seconds. Read
`awaiting-visibility.json`, select the exact app path in a separate CUA call, then
raise the exposed video window and inspect a fresh screenshot. Do not acknowledge
an idle window or rely only on an AX title. After the expected video is visible:

```sh
python3 other/tests/player-performance/ack_visible.py TRIAL_NAME --tag visible-final
python3 other/tests/player-performance/next_visible.py --tag visible-final --expected 18
```

Acknowledgement checks the owned PID/viewport and aligns the fixed seek before
warmup. The next helper waits at most 35 seconds; it performs no UI actions. The
benchmark recreates only its owned test preference domain for each visible run
and checks actual decoder/filter state. Do not overlap phases with other tests,
builds or GUI interaction. `--fixtures single-1080p60.mp4` permits a focused repeat;
use a fresh tag and an expected count matching the selected matrix.

Accepted 2026-10-19 data combines 4K/multiaudio from `visible-final` and 1080p from
`visible-1080-confirmed`. The exact composition and exclusions are documented in
the investigation report and `final-visible-results.json`.

Measurements:

- CPU is process CPU time divided by elapsed time; 100% means one occupied core.
  The sampler converts this host's Mach-time counters to nanoseconds using the
  timebase. A busy-loop calibration against `CLOCK_PROCESS_CPUTIME_ID` is saved
  with the evidence. Do not treat raw `proc_pid_rusage` counters as nanoseconds.
- Physical footprint and resident memory are sampled every 250 ms. Footprint is
  the reported memory metric; short allocation peaks can fall between samples.
- A bounded 20 Hz GCD probe records main-queue scheduling latency and outstanding
  request age. This is neither click-to-display latency nor animation frame rate.
  It adds matched wakeups, so include an uninjected control and do not infer idle
  battery use from instrumented measurements.
- Media readiness means an engine video output is configured and playback has
  resumed. It is a startup proxy, not an observed first visible frame.
- Playing/paused phases exclude two seconds of warmup and verify actual pause
  state and timeline progress. Trial order alternates between repetitions.
- Stress waits for engine restart and the requested position/path. IPC operations
  exercise the real engine and its application event handlers; native-menu,
  keyboard, file-chooser and window interactions require separate UI checks.
- Error paths retain a bounded stack sample. Process teardown in this harness is
  a signal to an owned test process, not validation of ordinary Cocoa shutdown.

`native_lut_benchmark.py` compiles the real optimized LUT library and AppKit popup
with test dependencies for the player, engine and chooser. It isolates import
parsing from engine LUT application. Full-application checks are reported
separately. Keep compilation, fixture encoding, unrelated tests and GUI work out
of process measurement windows.
