#!/usr/bin/env python3
"""Install a verified protocol-2 winemac driver into the existing 26.3 environment.

Stop the Steam bottle first. This does not replace Wine, games, configuration,
Sevoflurane, or their permissions. Keep one rollback driver outside the payload.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile


def digest(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def exports(p):
    return sorted(line.split()[-1] for line in subprocess.check_output(['nm', '-gU', str(p)], text=True).splitlines() if line.split())


def atomic(p, data):
    fd, name = tempfile.mkstemp(prefix='.wheel-install-', dir=p.parent)
    try:
        with os.fdopen(fd, 'wb') as f:
            f.write(data)
        os.chmod(name, 0o755 if p.suffix == '.so' else 0o644)
        os.replace(name, p)
    finally:
        Path(name).unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('candidate', type=Path, help='Cloud-built winemac.so from the verified matching artifact')
    parser.add_argument('--sha256', required=True, help='SHA256 of the verified downloaded candidate')
    args = parser.parse_args()
    candidate = args.candidate.resolve()
    if digest(candidate) != args.sha256:
        raise SystemExit('Candidate hash mismatch')
    root = Path.home()/'Library/Application Support/CrossOver'
    support = root/'CustomRuntimes/.tuner-support'
    manifest_path = support/'manifest.json'
    manifest = json.loads(manifest_path.read_text())
    if manifest['baseVersion'] not in ('26.3', '26.3.0'):
        raise SystemExit('Only the existing CrossOver 26.3 ABI is supported')
    component = next(c for c in manifest['components'] if c['target'].endswith('/winemac.so'))
    target = root/component['target']
    payload = support/component['payload']
    if digest(target) != component['sha256'] or digest(payload) != component['sha256']:
        raise SystemExit('Installed driver or payload differs from the maintenance manifest')
    if b'[CXWheelBridge]' not in candidate.read_bytes():
        raise SystemExit('Not a protocol-2 wheel driver')
    subprocess.run(['codesign', '--verify', '--strict', str(candidate)], check=True)
    if exports(candidate) != exports(target):
        raise SystemExit('Wine exported ABI differs; nothing installed')
    # All Wine clients and its server using this runtime must be stopped first.
    commands = subprocess.check_output(['ps', '-axo', 'command='], text=True)
    runtime = str(root/'CustomRuntimes'/manifest['runtime'])
    if any(runtime in row and ('wineloader' in row or 'wineserver' in row) for row in commands.splitlines()):
        raise SystemExit('The bottle is still running; stop Steam and its Wine server first')
    previous = component['sha256']
    backup = support/'Backups/wheel-1.5.2/winemac.so'
    if not backup.exists():
        backup.parent.mkdir(parents=True, exist_ok=True)
        atomic(backup, target.read_bytes())
    elif digest(backup) != previous and manifest.get('wheelBridgeVersion') != 2:
        raise SystemExit('Unexpected rollback driver; preserve it and inspect manually')
    component['sha256'] = args.sha256
    component['allowedBefore'] = sorted(set(component['allowedBefore']+[previous]))
    manifest['wheelBridgeVersion'] = 2
    atomic(payload, candidate.read_bytes())
    atomic(manifest_path, (json.dumps(manifest, indent=2)+'\n').encode())
    atomic(target, candidate.read_bytes())
    assert digest(target) == digest(payload) == args.sha256
    print('Installed protocol-2 wheel driver; input and frame settings preserved')


if __name__ == '__main__':
    main()
