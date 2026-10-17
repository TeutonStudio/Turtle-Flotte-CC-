#!/usr/bin/env python3
"""Build the deterministic download manifest after changing runtime files."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
files = []
for path in sorted((ROOT / "v2").glob("*.lua")):
    content = path.read_bytes()
    checksum = 1
    for byte in content:
        checksum = (checksum * 31 + byte) % 2147483647
    files.append({"path": path.relative_to(ROOT).as_posix(), "bytes": len(content), "checksum": checksum})
installer_content = (ROOT / "init.lua").read_bytes()
installer_checksum = 1
for byte in installer_content:
    installer_checksum = (installer_checksum * 31 + byte) % 2147483647
(ROOT / "manifest.json").write_text(json.dumps({
    "format": 2, "version": "2.0.0", "files": files,
    "installer": {"bytes": len(installer_content), "checksum": installer_checksum},
}, indent=2) + "\n")
