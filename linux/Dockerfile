# The Linux build and try-out environment, used only on this Mac through OrbStack or Docker (never a hosted
# runner): Swift 6.4 on Ubuntu 26.04, which has the GTK 4.20+ and libadwaita that Adwaita for Swift needs, plus
# Broadway to show the window in a browser, and ffmpeg to run a real task.
FROM swift:6.4-resolute
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      libgtk-4-dev libadwaita-1-dev libgtk-4-bin libsqlite3-dev pkg-config fonts-dejavu-core dpkg-dev \
      ffmpeg \
    && rm -rf /var/lib/apt/lists/*
