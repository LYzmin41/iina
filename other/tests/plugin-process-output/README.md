# Plugin process output regression

Run `python3 other/tests/plugin-process-output/run.py` on macOS. The harness
extracts the production exec method and pipe collector, then uses real Process,
Pipe and JavaScriptCore instances. It verifies main-thread callbacks, output EOF
ordering, large simultaneous streams, result/error behavior and empty output.

For an earlier source, set `PLUGIN_PROCESS_SOURCE` to JavascriptAPIUtils.swift
and optionally `PLUGIN_PROCESS_OUTPUT` to a separate generated-output directory.
The pre-correction method fails the callback-thread check. Native cold-cache
Audio Normalize/IInfo reproduction evidence is documented in
`docs/testing/2026-10-20-playing-crop-motion.md`.
