#!/usr/bin/env python3
"""Check exact baseline before patching; --verify checks an already patched tree."""
import argparse, hashlib, json, subprocess
from pathlib import Path
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('source',type=Path)
parser.add_argument('--verify',action='store_true')
args=parser.parse_args()
repo=Path(__file__).resolve().parents[1]
metadata=json.loads((repo/'patches/wine-26.3/files.json').read_text())
source=args.source.resolve()
def check(stage):
    for item in metadata['files']:
        path=source/item['path']
        actual=hashlib.sha256(path.read_bytes()).hexdigest() if path.exists() else None
        if actual!=item[stage]:
            raise SystemExit(f"Mismatch ({stage}): {item['path']}. Expected {item[stage]}, found {actual}")
if args.verify:
    check('after')
else:
    check('before')
    patch=repo/'patches/wine-26.3/coeditor.patch'
    command=['patch','--batch','-p1','-i',str(patch)]
    subprocess.run(command+['--dry-run'],cwd=source,check=True)
    subprocess.run(command,cwd=source,check=True)
    check('after')
print(f"PASS: {len(metadata['files'])} source files ({metadata['base']})")
