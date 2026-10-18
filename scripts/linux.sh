#!/usr/bin/env bash
# The Linux app, built and run in a local container on this Mac (OrbStack or Docker; never a hosted runner).
#   scripts/linux.sh image   build the knobs-linux-dev image from linux/Dockerfile
#   scripts/linux.sh build   compile the app with warnings as errors. The repo is mounted at /knobs: SwiftPM
#                            names a path dependency after its folder, and the package expects "knobs".
#   scripts/linux.sh run     start it under GTK's Broadway backend; open http://localhost:8085 to use it
#   scripts/linux.sh stop    stop the running app
#   scripts/linux.sh package <version> [arm64|amd64]
#                            build release binaries and write dist/linux/knobs_<version>_<arch>.deb (Ubuntu 26.04),
#                            knobs-<version>-1.fc44.<arch>.rpm (Fedora 44) and a .tar.gz of the installed files, for
#                            this Mac's architecture unless one is named. amd64 also writes the Arch package.
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
        echo "usage: scripts/linux.sh package <version> [arm64|amd64]; the version must match project.yml ($project_version)" >&2
        exit 64
    fi
    host=$(uname -m | sed -e 's/aarch64/arm64/' -e 's/x86_64/amd64/')
    platform="${3:-$host}"
    case "$platform" in arm64 | amd64) ;; *) echo "architecture must be arm64 or amd64" >&2; exit 64 ;; esac
    # The other architecture runs emulated (Rosetta in OrbStack) and gets its own image tags and build folders.
    suffix=""
    if [ "$platform" != "$host" ]; then suffix="-$platform"; fi
    ubuntu="$image$suffix"
    fedora="knobs-linux-fedora$suffix"
    docker build -q --platform "linux/$platform" -t "$ubuntu" linux >/dev/null
    docker build -q --platform "linux/$platform" -t "$fedora" -f linux/Dockerfile.fedora linux >/dev/null
    # Each distribution builds its own binary against its own GTK. Ubuntu has no Swift runtime package, so the
    # runtime is linked in; Fedora ships it as swift-lang-runtime (and no static copy), which rpm then requires,
    # in /usr/lib64, so the toolchain's library folder is left out of the binary's search path.
    release="swift build -c release -Xswiftc -warnings-as-errors"
    mkdir -p linux/.build dist/linux
    deb_stage=$(mktemp -d linux/.build/deb-stage.XXXXXX)
    docker run --rm --platform "linux/$platform" -v "$PWD:/knobs" -w /knobs/linux "$ubuntu" bash -c \
        "$release --static-swift-stdlib --scratch-path .build/ubuntu$suffix \
        && packaging/package-deb.sh .build/ubuntu$suffix/release/knobs $version /knobs/$deb_stage/knobs \
        && packaging/package-tarball.sh .build/ubuntu$suffix/release/knobs $version /knobs/dist/linux"
    docker run --rm -v "$PWD:/knobs" "$image" \
        dpkg-deb --root-owner-group --build "/knobs/$deb_stage/knobs" "/knobs/dist/linux/knobs_${version}_$platform.deb"
    docker run --rm --platform "linux/$platform" -v "$PWD:/knobs" -w /knobs/linux "$fedora" bash -c \
        "$release -Xswiftc -no-toolchain-stdlib-rpath --scratch-path .build/fedora$suffix \
        && packaging/package-rpm.sh .build/fedora$suffix/release/knobs $version /knobs/dist/linux"
    # Arch publishes x86_64 images only, so its package comes with the amd64 build, from the Ubuntu binary.
    if [ "$platform" = amd64 ]; then
        docker build -q --platform linux/amd64 -t knobs-linux-arch -f linux/Dockerfile.arch linux >/dev/null
        docker run --rm --platform linux/amd64 -v "$PWD:/knobs" knobs-linux-arch \
            /knobs/linux/packaging/package-arch.sh "/knobs/dist/linux/knobs-$version-linux-x86_64.tar.gz" "$version" /knobs/dist/linux
    fi
    ls -l dist/linux
    ;;
*)
    echo "usage: scripts/linux.sh image|build|run|stop|package <version> [arm64|amd64]" >&2
    exit 64
    ;;
esac
