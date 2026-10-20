#!/usr/bin/env python3
"""Stage an existing verified LYINA bundle for an experimental distribution."""

import argparse
import hashlib
import json
import plistlib
import subprocess
from pathlib import Path


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def executable_sections(path):
    """Compare code/data separately from the embedded signing envelope."""
    output = subprocess.check_output(["otool", "-l", str(path)], text=True)
    data = path.read_bytes()
    result = {}
    for block in output.split("Section\n")[1:]:
        values = {}
        for line in block.splitlines()[:16]:
            fields = line.split()
            if len(fields) == 2:
                values[fields[0]] = fields[1]
        if not {"sectname", "segname", "size", "offset"} <= values.keys():
            continue
        size = int(values["size"], 16)
        offset = int(values["offset"])
        if offset and size:
            result[values["segname"] + "/" + values["sectname"]] = (
                hashlib.sha256(data[offset:offset + size]).hexdigest())
    if not result:
        raise SystemExit("No executable sections found")
    return result


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("source", type=Path)
parser.add_argument("destination", type=Path)
args = parser.parse_args()
source = args.source.resolve()
destination = args.destination.resolve()
if destination.exists():
    raise SystemExit("Destination must not exist")
subprocess.run(["codesign", "--verify", "--deep", "--strict", str(source)], check=True)
destination.parent.mkdir(parents=True, exist_ok=True)
subprocess.run(["cp", "-cR", str(source), str(destination)], check=True)
info_path = destination / "Contents/Info.plist"
info = plistlib.loads(info_path.read_bytes())
if info["CFBundleIdentifier"] != "org.lyzmin41.lyina":
    raise SystemExit("Expected the separate LYINA bundle identity")
info.update(SUEnableAutomaticChecks=False, SUAutomaticallyUpdate=False,
            SUAllowsAutomaticUpdates=False)
info.pop("SUFeedURL", None)
info.pop("CFBundleURLTypes", None)
for document in info.get("CFBundleDocumentTypes", []):
    document["LSHandlerRank"] = "Alternate"
info_path.write_bytes(plistlib.dumps(info))
subprocess.run(["codesign", "--force", "--sign", "-",
                "--preserve-metadata=entitlements,flags,runtime", str(destination)],
               check=True)
subprocess.run(["codesign", "--verify", "--deep", "--strict", str(destination)],
               check=True)
executable = Path("Contents/MacOS/IINA")
engine = Path("Contents/Frameworks/libmpv.2.dylib")
if executable_sections(source / executable) != executable_sections(destination / executable):
    raise SystemExit("Packaging changed application code/data sections")
if sha(source / engine) != sha(destination / engine):
    raise SystemExit("Packaging changed engine bytes")
print(json.dumps({"bundle_id": info["CFBundleIdentifier"],
                  "version": info["CFBundleShortVersionString"],
                  "signature": "ad-hoc; not notarized",
                  "source_executable_sha256": sha(source / executable),
                  "executable_code_data_unchanged": True,
                  "executable_sha256": sha(destination / "Contents/MacOS/IINA"),
                  "libmpv_sha256": sha(destination / "Contents/Frameworks/libmpv.2.dylib")},
                 indent=2))
