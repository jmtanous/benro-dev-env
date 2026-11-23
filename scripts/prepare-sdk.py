#!/usr/bin/env python3
"""Fetch pinned public ARM build inputs or extract them into a fresh sysroot.

This creates host build inputs only. It never installs packages or runs their
maintainer scripts and must never be pointed at a physical mount filesystem.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
from urllib.parse import urlsplit
from urllib.request import urlopen

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--project', type=Path, required=True)
parser.add_argument('--fetch', action='store_true')
parser.add_argument('--output', type=Path, help='Fresh build sysroot; requires dpkg-deb')
args = parser.parse_args()
if not args.fetch and args.output is None:
    parser.error('Select --fetch or --output')
pins = json.loads((root/'public-sdk.json').read_text())
cache = args.project.resolve()/'workspace/benro-sdk/downloads/public-sdk'
cache.mkdir(parents=True, exist_ok=True)
archives = []
for package in pins['packages']:
    path = cache/Path(urlsplit(package['url']).path).name
    if not path.exists():
        if not args.fetch:
            raise SystemExit('Missing cached input; run with --fetch: '+path.name)
        with urlopen(package['url'], timeout=60) as response:
            data = response.read()
    else:
        data = path.read_bytes()
    if hashlib.sha256(data).hexdigest() != package['sha256']:
        raise SystemExit('Source hash mismatch: '+path.name)
    if not path.exists():
        path.write_bytes(data)
    archives.append(path)
if args.output is not None:
    if args.output.exists():
        raise SystemExit('Refusing to overwrite existing sysroot')
    args.output.mkdir(parents=True)
    for archive in archives:
        subprocess.run(['dpkg-deb', '--extract', str(archive), str(args.output)], check=True)
    # Debian development symlinks assume installation at /. In an isolated
    # sysroot they must remain inside that sysroot, or ld silently falls back
    # to static archives (libm.a introduces private loader symbol references).
    for link in args.output.rglob('*'):
        if link.is_symlink() and os.readlink(link).startswith('/'):
            target = args.output/os.readlink(link).lstrip('/')
            relative = os.path.relpath(target, link.parent)
            link.unlink()
            link.symlink_to(relative)
    (args.output/'PUBLIC-SDK-INPUTS.json').write_text(json.dumps(pins, indent=2)+'\n')
print(json.dumps({'verified_packages': len(archives), 'extracted': args.output is not None}))
