#!/usr/bin/env python3
"""Exercise real launchd socket activation without reading HID or requesting TCC."""
import argparse,ctypes,json,os,plistlib,re,shutil,socket,struct,subprocess,tempfile,time
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--app',type=Path,required=True)
p.add_argument('--client',type=Path,required=True)
a=p.parse_args();domain=f'gui/{os.getuid()}'
folder=Path(tempfile.mkdtemp(prefix='cxwheel-',dir='/tmp'));label=f'local.coeditor.wheel.test.{os.getpid()}'
state=folder/'state';state.mkdir();ipc=folder/'Library/Application Support/COEditor';ipc.mkdir(parents=True)
sock=ipc/'wheel.sock';plist=folder/'job.plist';children=[]
trusted=folder/'wine';shutil.copy2(a.client.resolve(),trusted)
alias=folder/'cs2.exe';second_alias=folder/'gameoverlayui64.exe';untrusted=folder/'copied-wine'
os.link(trusted,alias);os.link(trusted,second_alias);shutil.copy2(trusted,untrusted)
assert os.stat(alias).st_ino==os.stat(trusted).st_ino
assert os.stat(untrusted).st_ino!=os.stat(trusted).st_ino
libproc=ctypes.CDLL('/usr/lib/libproc.dylib')
libproc.proc_pidpath.argtypes=[ctypes.c_int,ctypes.c_void_p,ctypes.c_uint32]
def process_path(pid):
    path=ctypes.create_string_buffer(4096)
    assert libproc.proc_pidpath(pid,path,len(path))>0
    return Path(os.fsdecode(path.value))
config={'Label':label,'ProgramArguments':[str(a.app.resolve()/'Contents/Resources/COEditor Wheel.app/Contents/MacOS/COEditorWheel')],
        'RunAtLoad':False,'KeepAlive':False,'ThrottleInterval':1,
        'Sockets':{'WheelRequests':{'SockType':'dgram','SockPathName':str(sock),'SockPathMode':0o600}},
        'EnvironmentVariables':{'COEDITOR_WHEEL_TEST_NO_HID':'1','COEDITOR_WHEEL_TEST_DIRECTORY':str(state),'COEDITOR_WHEEL_TEST_CLIENT_PATH':str(trusted)},
        'StandardOutPath':str(folder/'stdout.log'),'StandardErrorPath':str(folder/'stderr.log')}
plist.write_bytes(plistlib.dumps(config));loaded=False

def job_pid():
    r=subprocess.run(['launchctl','print',domain+'/'+label],capture_output=True,text=True,check=True)
    m=re.search(r'^\s*pid = (\d+)\s*$',r.stdout,re.M)
    return int(m.group(1)) if m else None

def status():
    try:return json.loads((state/'status.json').read_text())
    except (OSError,ValueError):return {}

def until(predicate,timeout=8):
    end=time.monotonic()+timeout
    while time.monotonic()<end:
        if predicate():return
        time.sleep(.1)
    raise AssertionError(f'lifecycle timeout; pid={job_pid()}, status={status()}')

def client(seconds,bad=False,path=None):
    proc=subprocess.Popen([str(path or trusted),str(seconds)]+(['bad'] if bad else []),env={**os.environ,'HOME':str(folder)})
    children.append(proc);return proc

try:
    subprocess.run(['launchctl','bootstrap',domain,str(plist)],check=True);loaded=True
    time.sleep(.5);assert job_pid() is None,'reader launched without a game'
    first=client(60,path=alias);until(lambda:status().get('clients')==1);original=job_pid();assert original
    first_path=process_path(first.pid)
    second=client(6,path=second_alias);until(lambda:status().get('clients')==2);assert job_pid()==original
    second_path=process_path(second.pid)
    assert any(path!=trusted for path in [first_path,second_path]),'fixture did not exercise a noncanonical loader path'
    for path in [first_path,second_path]:assert os.path.samefile(path,trusted)
    time.sleep(1.5)
    assert status().get('clients')==2 and job_pid()==original,'hard-link aliases pruned live clients'
    first.kill();first.wait();until(lambda:status().get('clients')==1)
    assert job_pid()==original,'one game quitting killed the shared reader'
    assert second.wait(timeout=10)==0;until(lambda:job_pid() is None)
    time.sleep(1.2);assert job_pid() is None,'reader restarted itself without a game'
    invalid=client(2,True);until(lambda:job_pid() is not None);until(lambda:status().get('pid')==job_pid() and status().get('clients')==0);invalid.wait(timeout=5);until(lambda:job_pid() is None)
    copied=client(2,path=untrusted);until(lambda:job_pid() is not None);until(lambda:status().get('pid')==job_pid() and status().get('clients')==0);copied.wait(timeout=5);until(lambda:job_pid() is None)
    third=client(3);until(lambda:status().get('clients')==1);assert job_pid()!=original
    assert third.wait(timeout=6)==0;until(lambda:job_pid() is None)
    print('PASS: hard-link Wine aliases retained, copied binary rejected, no login process, demand wake, two games share one reader, crash cleanup, last-game exit, no idle restart, PID-birth rejection and next-game wake')
except Exception:
    if (folder/'stderr.log').exists():print((folder/'stderr.log').read_text())
    raise
finally:
    for proc in children:
        if proc.poll() is None:proc.kill();proc.wait()
    if loaded:subprocess.run(['launchctl','bootout',domain+'/'+label],check=False,capture_output=True)
    shutil.rmtree(folder)
