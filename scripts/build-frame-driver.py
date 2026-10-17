#!/usr/bin/env python3
"""Build the presentation changes against an existing, matching Wine build.

Only replace a runtime after stopping its bottle and verifying its manifest.
--compat-patch preserves the optional Sevoflurane UI suppression integration.
"""
import argparse, hashlib, json, shlex, shutil, subprocess
from pathlib import Path

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--wine-source',type=Path,required=True)
p.add_argument('--wine-build',type=Path,required=True)
p.add_argument('--patched-source',type=Path,required=True)
p.add_argument('--compat-patch',type=Path)
p.add_argument('--output',type=Path,required=True)
a=p.parse_args()
source=a.wine_source.resolve();build=a.wine_build.resolve();output=a.output.resolve()
output.mkdir(parents=True,exist_ok=False)
stage=output/'source';driver=stage/'dlls/winemac.drv';driver.mkdir(parents=True)
changed=['d3dmetal_objc']
for path in (a.patched_source/'dlls/winemac.drv').iterdir():
    if path.is_file():shutil.copy2(path,driver/path.name)
if a.compat_patch:
    for name in ['cocoa_window.m','cocoa_status_item.m']:
        shutil.copy2(source/'dlls/winemac.drv'/name,driver/name)
    subprocess.run(['patch','--batch','-p1','-i',str(a.compat_patch.resolve())],cwd=stage,check=True)
    changed+=['cocoa_app','cocoa_window','cocoa_status_item']
lines=(build/'Makefile').read_text().replace('\\\n',' ').splitlines()
variables=dict(line.split(' = ',1) for line in lines if line.startswith(('CC = ','CFLAGS = ','LDFLAGS = ')))
def command(target):
    i=next(i for i,line in enumerate(lines) if line.startswith(target+':'))
    value=lines[i+1].strip().replace('$@','COEDITOR_OUTPUT')
    for key,val in variables.items():value=value.replace('$('+key+')',val)
    assert '$(' not in value,value
    return shlex.split(value)
for stem in changed:
    args=command('dlls/winemac.drv/'+stem+'.o')
    args[args.index('COEDITOR_OUTPUT')]=str(output/(stem+'.o'))
    at=next(i for i,v in enumerate(args) if v.endswith('/'+stem+'.m'))
    args[at]=str(driver/(stem+'.m'))
    subprocess.run(args,cwd=build,check=True)
args=command('dlls/winemac.drv/winemac.so')
args[args.index('COEDITOR_OUTPUT')]=str(output/'winemac.so')
for stem in changed:args[args.index('dlls/winemac.drv/'+stem+'.o')]=str(output/(stem+'.o'))
subprocess.run(args,cwd=build,check=True)
candidate=output/'winemac.so'
subprocess.run(['codesign','--force','--sign','-',str(candidate)],check=True)
subprocess.run(['codesign','--verify','--strict',str(candidate)],check=True)
def exports(path):return sorted(l.split()[-1] for l in subprocess.check_output(['nm','-gU',str(path)],text=True).splitlines())
assert exports(candidate)==exports(build/'dlls/winemac.drv/winemac.so'),'Exported ABI changed'
result={'sha256':hashlib.sha256(candidate.read_bytes()).hexdigest(),'exports_unchanged':True,'signature_valid':True,'sevo_ui_preserved':bool(a.compat_patch)}
(output/'validation.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result,indent=2))
