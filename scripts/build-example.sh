#!/usr/bin/env bash
set -euo pipefail
sdk=/project/workspace/benro-sdk/sysroot
out=/project/workspace/build
[ -f "$sdk/PUBLIC-SDK-INPUTS.json" ] || { echo 'Prepare the SDK first with benro-dev sdk PROJECT prepare.' >&2; exit 1; }
mkdir -p "$out"
arm-linux-gnueabi-gcc --sysroot="$sdk" -B"$sdk/usr/lib/arm-linux-gnueabi/" \
  -nostdinc -isystem "$(arm-linux-gnueabi-gcc -print-file-name=include)" \
  -isystem "$sdk/usr/include/arm-linux-gnueabi" -isystem "$sdk/usr/include" \
  -march=armv7-a -mfpu=vfpv3-d16 -mfloat-abi=softfp \
  /project/src/main.c -o "$out/main"
arm-linux-gnueabi-readelf --version-info "$out/main" > "$out/versions.txt"
arm-linux-gnueabi-readelf -h "$out/main" > "$out/header.txt"
python3 - "$out" <<'PY'
import json,re,sys
from pathlib import Path
out=Path(sys.argv[1]);text=(out/'versions.txt').read_text()
versions=[tuple(map(int,v.split('.'))) for v in re.findall(r'GLIBC_([0-9.]+)',text)]
assert versions and max(versions)<=(2,24),versions
assert 'soft-float ABI' in (out/'header.txt').read_text()
(out/'abi-check.json').write_text(json.dumps({'result':'passed','glibc_max':max(versions),'physical_acceptance':False})+'\n')
PY
if [ "${1:-build}" = test ]; then
  qemu-arm-static -L "$sdk" "$out/main"
fi
