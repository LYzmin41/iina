# Persistent audio mixing in LYINA

`mpv-0.41.0-lavfi-complex-command.patch` adds an explicit setter for a named
runtime option in mpv's complex filter graph. Stock `af-command` only reaches
the ordinary audio output chain; its `all` label can report success without
reaching a complex mixer. Changing `lavfi-complex` itself refresh-seeks video.

The extension runs on mpv's command thread and uses libavfilter's runtime option
and command APIs. It retains only the latest value for each target/option until
that graph is destroyed. After seek/format reset it reapplies those values after
graph configuration and before output. Before configuration it validates options
without invoking filter callbacks that require configured input buffers.

The `refresh-audio` argument also evicts stale mixed sound from post-filter
lookahead. Timestamped decoded input history is replayed through fresh FFmpeg
filter buffers; playing audio joins the end of the existing device queue. The
video decoder and renderer keep running. Warm-up frames and sample-rounded
output trimming preserve the carried input's phase. A paused refresh may clear
only audio output buffers. This rebuilds filter buffers, not decoders, and does
not replace the graph option or seek the media.

Audio history is bounded to 12 seconds, 16 MiB per input, 64 MiB overall and
4096 frame references per input. The latest raw video frame per input supports
shared audio/video graphs; duplicate video output is suppressed. Seek resets
history. If history/timestamps do not cover the boundary, the setter still
applies without replay; very long filter chains can therefore retain latency.

The application checks both the command and its `refresh-audio` argument through
`command-list`. Unmodified or older extension engines
retain the original graph replacement path. Local files with multiple matching
channel layouts prepare their input pool once at opening; gains then implement
solo, membership changes and explicit None. All connected inputs must continue
decoding, including those at zero gain. Network files, passthrough, incompatible
channel layouts and foreign graphs retain their prior path. Newly attached or
removed streams, and video layer changes, can still require a topology rebuild.

Start with mpv v0.41.0 **and IINA's existing compatibility patches**, then apply
this patch (`patch -p1 -i /absolute/path/to/this.patch`). The baseline is
[iina/deps-buildscripts ee35579](https://github.com/iina/deps-buildscripts/tree/ee35579ded3ea95d839d85c2686d96dc505ee344/patches/mpv):
17448 (tone mapping default), 18092 (ICC/BT.1886 NaN), 18383 (CoreAudio cleanup)
and 18384 (CoreAudio channel mapping). A plain upstream build loses those fixes;
the missing ICC fix can turn the real OpenGL image black on a calibrated display.
Keep the existing dependency
ABIs and macOS deployment target. The local arm64 build uses the same enabled
features as the shipped engine: shared libmpv, LuaJIT, MuJS, lcms2, libbluray,
libarchive, uchardet, JPEG, rubberband, zimg, OpenGL and VideoToolbox; no CLI,
Vulkan, Cocoa callback backend, Touch Bar or media-player integration. Do not
link against newer Homebrew runtime libraries and rename them to bundled ABIs.
The final binary must resolve bundled libraries through `@rpath`, contain no
local build rpaths and pass the same app signing and packaging verification.
An external test dependency directory must not contain a competing libmpv:
`DYLD_LIBRARY_PATH` can override even an explicitly opened library filename.

Run the production model/AppKit suite with
`bash other/tests/multitrack-playback/run.sh`. Its `persistent-graphs.json`
contains the exact Swift-generated graph for `persistent-mix-probe.py`:

```sh
python3 other/tests/multitrack-playback/persistent-mix-probe.py \
  /absolute/path/to/patched/libmpv.2.dylib /absolute/path/to/four-tone-fixture.mkv \
  /absolute/output/directory /absolute/path/to/persistent-graphs.json
```

The probe records PCM without an output device and checks runtime additions,
removals, solo, None, seek, a setter immediately after seek, rejected commands,
rapid paused changes and stable input gain. `arealtime` only throttles this
test's PCM file writer; it is never installed in the player.

References: [mpv v0.41.0](https://github.com/mpv-player/mpv/tree/v0.41.0),
[FFmpeg amix commands](https://ffmpeg.org/ffmpeg-filters.html#amix).

To measure the actual output boundary, apply the test-only
`other/tests/multitrack-playback/audio-output-tap.patch` to a separate engine
build. Run `output-latency-probe.py LIB FIXTURE OUTPUT persistent-graphs.json CASE`
with `plain-phase-refresh`, `loudnorm-refresh`, `loudnorm-layers-refresh`, or
`loudnorm-stress-refresh`; omit `refresh` for the buffered baseline. The fixture
must contain the four 330/440/550/660 Hz tones. The probe captures generated PCM
before software mute through CoreAudio; it does not record a microphone. The
phase case checks a carried track across additions/removals. Stress covers
paused changes, a setter immediately after seek, rapid changes and 2x playback.
The tap and generated captures must never be packaged in the application.

## Independent subtitle role styles

Apply `mpv-0.41.0-secondary-subtitle-style.patch` after the compatibility and
lavfi-complex patches above. It adds opt-in `secondary-sub-style-override`,
`secondary-sub-scale`, and a separate `secondary-sub-*` style option group.
LYINA initializes both roles from the same saved subtitle preferences; edits
then target one role. Other clients keep stock inheritance unless they opt in.
The renderer uses the role when selecting font, size, colors, outline and scale;
source track swaps do not move those styles. Existing ASS override policies are
preserved, so authored ASS formatting still depends on the selected override
level. There are no new client API exports or runtime dependencies.

`other/tests/subtitle-controls/engine-probe.py LIB OUTPUT` renders real frames
with the software render API and checks independent styles, source swaps, seek,
reload and stock inheritance. Use the matching dependency directory described
above. The native subtitle suite covers role controls, reset isolation and font
chooser role capture.
