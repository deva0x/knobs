#!/usr/bin/env bash
# The Linux app, built and run in a local container on this Mac (OrbStack or Docker; never a hosted runner).
#   scripts/linux.sh image   build the knobs-linux-dev image from linux/Dockerfile
#   scripts/linux.sh build   compile the app with warnings as errors. The repo is mounted at /knobs: SwiftPM
#                            names a path dependency after its folder, and the package expects "knobs".
#   scripts/linux.sh run     start it under GTK's Broadway backend; open http://localhost:8085 to use it
#   scripts/linux.sh stop    stop the running app
#   scripts/linux.sh package <version>
#                            build release binaries and write dist/linux/knobs_<version>_<arch>.deb (Ubuntu 26.04)
#                            and knobs-<version>-1.fc44.<arch>.rpm (Fedora 44), for this Mac's architecture
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
package)
    version="${2:-}"
    project_version=$(sed -n 's/^ *CFBundleShortVersionString: "\(.*\)"$/\1/p' project.yml)
    if [ "$version" != "$project_version" ]; then
        echo "usage: scripts/linux.sh package <version>; it must match project.yml ($project_version)" >&2
        exit 64
    fi
    docker build -q -t "$image" linux >/dev/null
    docker build -q -t knobs-linux-fedora -f linux/Dockerfile.fedora linux >/dev/null
    # Each distribution builds its own binary, with Swift's runtime linked in, against its own GTK.
    release="swift build -c release --static-swift-stdlib -Xswiftc -warnings-as-errors"
    docker run --rm -v "$PWD:/knobs" -w /knobs/linux "$image" bash -c \
        "$release --scratch-path .build/ubuntu && packaging/package-deb.sh .build/ubuntu/release/knobs $version /knobs/dist/linux"
    docker run --rm -v "$PWD:/knobs" -w /knobs/linux knobs-linux-fedora bash -c \
        "$release --scratch-path .build/fedora && packaging/package-rpm.sh .build/fedora/release/knobs $version /knobs/dist/linux"
    ls -l dist/linux
    ;;
*)
    echo "usage: scripts/linux.sh image|build|run|stop|package <version>" >&2
    exit 64
    ;;
esac
