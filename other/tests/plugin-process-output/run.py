#!/usr/bin/env python3
from pathlib import Path
import os
import subprocess

root = Path(__file__).resolve().parents[3]
tests = Path(__file__).resolve().parent
out = Path(os.environ.get("PLUGIN_PROCESS_OUTPUT", root / "build/plugin-process-output-tests"))
out.mkdir(parents=True, exist_ok=True)
source = Path(os.environ.get("PLUGIN_PROCESS_SOURCE", root / "iina/JavascriptAPIUtils.swift")).read_text()
start = source.index("  func exec(", source.index("class JavascriptAPIUtils:"))
opening = source.index("{", start)
depth, end = 1, opening + 1
while depth:
    depth += (source[end] == "{") - (source[end] == "}")
    end += 1
prefix = source[:source.index("@objc protocol")]
fixture = (tests / "main.swift").read_text().replace("// PRODUCTION_EXEC", source[start:end])
path = out / "main.swift"
path.write_text(prefix + fixture)
subprocess.run(["xcrun", "swiftc", str(path), "-o", str(out / "tests")], check=True)
subprocess.run([str(out / "tests")], check=True, timeout=40)
