#!/usr/bin/env python3
"""Install/update the per-user maintenance LaunchAgent for an existing app."""
import argparse, os, plistlib, subprocess
from pathlib import Path
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--app',type=Path,default=Path('/Applications/COEditor.app'))
args=parser.parse_args()
executable=args.app.resolve()/'Contents/MacOS/CrossOverTuner'
if not executable.is_file(): raise SystemExit('Build/install the app first')
root=Path.home()/'Library/Application Support/CrossOver'
support=root/'CustomRuntimes/.tuner-support'
if not (support/'manifest.json').is_file(): raise SystemExit('Prepare a local patched runtime manifest first; see docs/BUILDING.md')
label='local.crossover.tuner-maintenance'
agent=Path.home()/'Library/LaunchAgents'/f'{label}.plist'
value=dict(Label=label,ProgramArguments=[str(executable),'--maintain'],RunAtLoad=True,ThrottleInterval=10,
 WatchPaths=['/Applications/CrossOver.app','/Applications/CrossOver.app/Contents/Info.plist',str(root/'Bottles/Steam/cxbottle.conf')],
 StandardOutPath=str(support/'maintenance.log'),StandardErrorPath=str(support/'maintenance-error.log'))
agent.parent.mkdir(parents=True,exist_ok=True)
agent.write_bytes(plistlib.dumps(value))
(support/agent.name).write_bytes(plistlib.dumps(value))
domain=f'gui/{os.getuid()}'
subprocess.run(['launchctl','bootout',f'{domain}/{label}'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
subprocess.run(['launchctl','bootstrap',domain,str(agent)],check=True)
print('Installed:',agent)
