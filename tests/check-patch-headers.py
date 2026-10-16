#!/usr/bin/env python3
"""Ensure standalone test headers are exactly the corresponding new patch files."""
from pathlib import Path
import hashlib,json
root=Path(__file__).resolve().parents[1]
manifest=json.loads((root/'patches/wine-26.3/files.json').read_text())
for item in manifest['files']:
    name=Path(item['path']).name
    if name in ('cx_tuner_config.h','mouse_fraction.h','wheel_raw.h'):
        assert hashlib.sha256((root/'tests'/name).read_bytes()).hexdigest()==item['after'], name
print('PASS: test headers match patched Wine sources')
