#!/usr/bin/env python3
"""Ensure standalone test headers are exactly the corresponding new patch files."""
from pathlib import Path
import hashlib,json
root=Path(__file__).resolve().parents[1]
manifest=json.loads((root/'patches/wine-26.3/files.json').read_text())
for item in manifest['files']:
    name=Path(item['path']).name
    if name in ('cx_tuner_config.h','mouse_fraction.h','wheel_raw.h','cx_frame_control.h'):
        assert hashlib.sha256((root/'tests'/name).read_bytes()).hexdigest()==item['after'], name
print('PASS: test headers match patched Wine sources')

bridge=next(i for i in manifest['files'] if i['path'].endswith('/wheel_bridge.h'))
assert hashlib.sha256((root/'Sources/WheelBridge/wheel_bridge.h').read_bytes()).hexdigest()==bridge['after']
patch=(root/'patches/wine-26.3/coeditor.patch').read_text()
client=(root/'Sources/WheelBridge/wine_client.m.inc').read_text()
assert all('+'+line in patch for line in client.splitlines() if line), 'Wine client source drift'
print('PASS: shared bridge layout and Wine client match shipped patch')

activation=next(i for i in manifest['files'] if i['path'].endswith('/wheel_activation.h'))
assert hashlib.sha256((root/'Sources/WheelBridge/wheel_activation.h').read_bytes()).hexdigest()==activation['after']
print('PASS: shared on-demand activation protocol matches patched Wine')
