#!/usr/bin/env python3
"""Load an explicit project-local VM profile and execute the shared launcher."""
import json,os,re,sys
from pathlib import Path
root=Path(sys.argv[1]).resolve()
p=json.loads((root/'benro-project.json').read_text())['vm_profile']
if not re.fullmatch(r'[a-zA-Z0-9][a-zA-Z0-9_.-]+',p['name']): raise ValueError('Invalid container name')
ports=[p[k] for k in ['ssh','web','api','websocket']]
if any(type(v) is not int or not 1024<=v<=65535 for v in ports) or len(set(ports))!=4: raise ValueError('Invalid or duplicate ports')
for other in root.parent.glob('*/benro-project.json'):
 if other.parent.resolve()==root:continue
 q=json.loads(other.read_text()).get('vm_profile',{})
 if q.get('name')==p['name'] or set(ports)&{q.get(k) for k in ['ssh','web','api','websocket']}:raise ValueError('VM profile conflicts with '+str(other))
env={**os.environ,'BENRO_PROJECT_DIR':str(root),'BENRO_VM_NAME':p['name']}
for key,value in zip(['SSH','WEB','API','WS'],ports):env['BENRO_'+key+'_PORT']=str(value)
os.execve('/bin/bash',['bash',str(Path(__file__).with_name('vm.sh')),*sys.argv[2:]],env)
