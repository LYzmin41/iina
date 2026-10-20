# Recorded local performance comparisons

These measurements were recorded on 2026-10-19, before subsequent interface
changes. They describe those local tests, not a fresh benchmark of the downloadable
2026-10-20 preview and not a guarantee of whole-player performance parity.

## Method

Apple M4 Pro, 12 CPU cores, 24 GiB RAM, macOS 27.0.1, AC power. Compared installed
IINA 1.5.0 (180) with the then-current arm64 Release LYINA candidate. Disposable
profiles used matched settings: no plugins, history, resume, autoload or filters;
VideoToolbox hardware decoding; muted audio; the same requested window geometry
and verified render viewport. Animations remained enabled.

The final visible series included 18 accepted trials across original IINA,
LYINA before optimization and LYINA after optimization: two trials per application
and fixture, alternating order. Each received a visible-window acknowledgement,
the same seek position and two seconds of warmup before eight-second playing and
paused phases. Values below are medians of the two final-version trials.

CPU is process CPU time divided by elapsed time: 100% means one occupied core.
Memory is physical footprint in MiB.

| Fixture | IINA CPU | LYINA CPU | IINA memory | LYINA memory |
| --- | ---: | ---: | ---: | ---: |
| 1080p60 H.264, one AAC track | 18.07% | 19.20% | 407.35 | 403.91 |
| 4K30 HEVC, one AAC track | 13.77% | 11.62% | 678.26 | 705.11 |
| 720p H.264, four stereo Opus tracks | 10.60% | 10.69% | 336.98 | 338.31 |

No final playing/paused phase increased the engine's frame-drop,
decoder-frame-drop or delayed-frame counters. No crash or permanent hang occurred
in this final visible series. These counters do not measure compositor animation
quality. The short trials do not establish battery life, long-term thermal
behavior, absence of memory leaks, or results on other hardware.

## Costs and interpretation

Ordinary playback was in the same broad CPU/memory range in these samples.
1080p used 1.13 additional percentage points of one core; 4K footprint was about
27 MiB higher. Those variations and the limited sample size preclude claiming
zero overhead or a general improvement.

Multitrack processing is not free. A separate headless audio control measured
about 1.71 additional percentage points of one core for a connected four-input
mixer compared with native single-track selection. A burst replacement test also
showed slower file preparation in LYINA. Those controls have different methods
and visibility limits and should not be treated as the full-app playback delta.

The investigation corrected two measured LUT UI hotspots: synchronous validation
and repeated menu reconstruction. It did not remove features or disconnect
inactive mixer inputs to obtain the reported results.

Harnesses and method are available in `other/tests/player-performance/`.
Broader tests of the current preview, input devices, macOS versions, network media,
HDR composition, and long sessions remain welcome.
