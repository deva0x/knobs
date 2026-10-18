#!/usr/bin/env bash
# The Linux app, built and run in a local container on this Mac (OrbStack or Docker; never a hosted runner).
#   scripts/linux.sh image   build the knobs-linux-dev image from linux/Dockerfile
#   scripts/linux.sh build   compile the app with warnings as errors. The repo is mounted at /knobs: SwiftPM
#                            names a path dependency after its folder, and the package expects "knobs".
#   scripts/linux.sh run     start it under GTK's Broadway backend; open http://localhost:8085 to use it
#   scripts/linux.sh stop    stop the running app
set -euo pipefail
cd "$(dirname "$0")/.."

image=knobs-linux-dev
container=knobs-linux
port=8085

if ! command -v docker >/dev/null || ! docker info >/dev/null 2>&1; then
    echo "FAIL: no local Docker. Start OrbStack (or Docker Desktop) and run this again." >&2
    exit 1
fi

case "${1:-}" in
image)
    docker build -t "$image" linux
    ;;
build)
    docker image inspect "$image" >/dev/null 2>&1 || docker build -t "$image" linux
    docker run --rm -v "$PWD:/knobs" -w /knobs/linux "$image" swift build -Xswiftc -warnings-as-errors
    ;;
run)
    docker rm -f "$container" >/dev/null 2>&1 || true
    # --init reaps the tools that Cancel kills, as systemd does on a desktop. Settings live in the repo's
    # gitignored .cache, so they survive a restart of the container.
    docker run -d --init --name "$container" -p "$port:$port" -v "$PWD:/knobs" \
        -e KNOBS_MANIFESTS=/knobs/Manifests -e XDG_DATA_HOME=/knobs/.cache/linux-data \
        -e GSETTINGS_BACKEND=memory "$image" bash -c \
        "gtk4-broadwayd --address 0.0.0.0 :5 & sleep 1; GDK_BACKEND=broadway BROADWAY_DISPLAY=:5 /knobs/linux/.build/debug/knobs"
    echo "Knobs is running in the container. Open http://localhost:$port"
    ;;
stop)
    docker rm -f "$container" >/dev/null
    ;;
*)
    echo "usage: scripts/linux.sh image|build|run|stop" >&2
    exit 64
    ;;
esac
