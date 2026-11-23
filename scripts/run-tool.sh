#!/usr/bin/env bash
set -euo pipefail
project_dir=$(cd "${1:?Pass project directory}" && pwd)
shared_dir=$(cd "$(dirname "$0")/.." && pwd)
shift
docker image inspect benro-dev-tools:bookworm >/dev/null 2>&1 || \
  docker build -t benro-dev-tools:bookworm "$shared_dir"
exec docker run --pull never --rm --user "$(id -u):$(id -g)" \
  --cap-drop ALL --security-opt no-new-privileges --network none --tmpfs /tmp:exec \
  -v "$project_dir:/project" -v "$shared_dir:/benro-dev-env:ro" \
  benro-dev-tools:bookworm "$@"
