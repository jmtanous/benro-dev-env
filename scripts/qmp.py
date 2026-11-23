#!/usr/bin/env python3
import json
import socket
import sys

with socket.socket(socket.AF_UNIX) as sock:
    sock.settimeout(5)
    sock.connect(sys.argv[1])
    reader = sock.makefile('rb')
    json.loads(reader.readline())
    for command in ('qmp_capabilities', sys.argv[2]):
        sock.sendall((json.dumps({'execute': command}) + '\n').encode())
        while True:
            response = json.loads(reader.readline())
            if 'error' in response:
                raise RuntimeError(response['error'])
            if 'return' in response:
                break
