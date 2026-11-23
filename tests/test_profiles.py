import json
import os
import socket
from pathlib import Path
import subprocess
import tempfile
import unittest

RUNNER = Path(__file__).resolve().parents[1] / 'scripts/run-vm.py'
CLI = RUNNER.parents[1] / 'benro-dev'

class Profiles(unittest.TestCase):
    def test_tool_runner_builds_a_missing_image_before_offline_execution(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);binary=root/'docker';log=root/'calls'
            binary.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$DOCKER_TEST_LOG"\nif [ "$1 $2" = "image inspect" ]; then exit 1; fi\n')
            binary.chmod(0o755)
            env={**os.environ,'PATH':str(root)+os.pathsep+os.environ['PATH'],'DOCKER_TEST_LOG':str(log)}
            result=subprocess.run(['bash',str(RUNNER.with_name('run-tool.sh')),str(root),'true'],env=env,capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stderr)
            calls=log.read_text().splitlines()
            self.assertTrue(calls[0].startswith('image inspect '))
            self.assertTrue(calls[1].startswith('build -t benro-dev-tools:bookworm '))
            self.assertIn('--network none',calls[2])
    def test_initializer_skips_ports_used_by_other_applications(self):
        with tempfile.TemporaryDirectory() as tmp, socket.socket() as reserved:
            for port in range(22000,60000,4):
                try:
                    reserved.bind(('127.0.0.1',port))
                    break
                except OSError:
                    continue
            env={**os.environ,'BENRO_WORKSPACE':tmp}
            result=subprocess.run([str(CLI),'init','reserved-port'],env=env,capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stderr)
            profile=json.loads((Path(tmp)/'projects/reserved-port/benro-project.json').read_text())['vm_profile']
            self.assertNotIn(port,profile.values())
    def test_new_projects_have_separate_state_and_unique_ports(self):
        with tempfile.TemporaryDirectory() as tmp:
            env={**os.environ,'BENRO_WORKSPACE':tmp}
            for name in ['one','two']:
                result=subprocess.run([str(CLI),'init',name],env=env,capture_output=True,text=True)
                self.assertEqual(result.returncode,0,result.stderr)
            first=Path(tmp)/'projects/one';second=Path(tmp)/'projects/two'
            one=json.loads((first/'benro-project.json').read_text())['vm_profile']
            two=json.loads((second/'benro-project.json').read_text())['vm_profile']
            self.assertFalse(set(one.values()) & set(two.values()))
            for project in [first,second]:
                self.assertTrue((project/'.git').is_dir())
                self.assertTrue((project/'src/main.c').is_file())
                self.assertFalse((project/'state').exists())
                self.assertFalse((project/'artifacts').exists())
            original=(first/'src/main.c').read_bytes()
            result=subprocess.run([str(CLI),'init','one'],env=env,capture_output=True,text=True)
            self.assertNotEqual(result.returncode,0)
            self.assertEqual((first/'src/main.c').read_bytes(),original)
            result=subprocess.run([str(CLI),'init','../escape'],env=env,capture_output=True,text=True)
            self.assertNotEqual(result.returncode,0)
            self.assertFalse((Path(tmp)/'escape').exists())
    def test_valid_profile_works_outside_project(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / 'one'; root.mkdir()
            (root/'benro-project.json').write_text(json.dumps({'vm_profile': {
                'name':'isolated-one','ssh':2201,'web':8201,'api':5201,'websocket':5202}}))
            result = subprocess.run(['python3',str(RUNNER),str(root),'help'],cwd='/',capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stderr)
            self.assertIn('snapshot',result.stdout)
    def test_collision_is_rejected_before_docker(self):
        with tempfile.TemporaryDirectory() as tmp:
            for name in ['one','two']:
                root=Path(tmp)/name;root.mkdir()
                (root/'benro-project.json').write_text(json.dumps({'vm_profile': {
                    'name':'isolated-'+name,'ssh':2201,'web':8201,'api':5201,'websocket':5202}}))
            result=subprocess.run(['python3',str(RUNNER),str(root),'start'],capture_output=True,text=True)
            self.assertNotEqual(result.returncode,0)
            self.assertIn('conflicts',result.stderr)

if __name__=='__main__': unittest.main()
