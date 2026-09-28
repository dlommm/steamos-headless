# syntax=docker/dockerfile:1
#
# SteamOS userspace built from Valve's own package repositories, running
# gamescope + Steam Big Picture headless and streamed with Sunshine.
#
# One image for AMD and NVIDIA: the GPU is detected when the container starts.
#   docker build -t steamos-docker .

# "latest" = highest numbered SteamOS release in Valve's repos / newest
# Sunshine GitHub release, resolved at build time. Pin e.g. 3.8 or
# 2026.914.233613 for reproducible builds.
ARG STEAMOS_VERSION=latest
ARG SUNSHINE_VERSION=latest

# ---------------------------------------------------------------------------
# 1. Bootstrap: use Arch's pacman to install a minimal SteamOS `base` into
#    /rootfs, trusting Valve's (holo) and Arch's signing keys.
# ---------------------------------------------------------------------------
FROM archlinux:latest AS bootstrap
ARG STEAMOS_VERSION
ENV MIRROR=https://steamdeck-packages.steamos.cloud/archlinux-mirror

COPY rootfs/etc/pacman.conf /etc/pacman.steamos.conf
COPY rootfs/etc/pacman.d/steamos-mirrorlist /etc/pacman.d/steamos-mirrorlist

RUN set -eux; \
    ver="${STEAMOS_VERSION}"; \
    if [ "$ver" = latest ]; then \
        ver=$(curl -fsSL "$MIRROR/" | grep -oE 'href="jupiter-[0-9]+\.[0-9]+/"' \
              | grep -oE '[0-9]+\.[0-9]+' | sort -uV | tail -1); \
    fi; \
    echo "SteamOS repos: $ver"; \
    STEAMOS_VERSION="$ver"; \
    sed -i "s/@VERSION@/${STEAMOS_VERSION}/g" /etc/pacman.steamos.conf; \
    keyring=$(curl -fsSL "$MIRROR/holo-${STEAMOS_VERSION}/os/x86_64/" \
        | grep -oE 'holo-keyring-[0-9][^"]*-any\.pkg\.tar\.zst' | sort -uV | tail -1); \
    curl -fsSL -o /tmp/holo-keyring.pkg.tar.zst "$MIRROR/holo-${STEAMOS_VERSION}/os/x86_64/$keyring"; \
    pacman -U --noconfirm /tmp/holo-keyring.pkg.tar.zst; \
    pacman-key --init; \
    pacman-key --populate archlinux holo; \
    mkdir -p /rootfs/var/lib/pacman /rootfs/etc/pacman.d; \
    pacman --config /etc/pacman.steamos.conf --root /rootfs --noconfirm -Sy base holo-keyring; \
    cp /etc/pacman.steamos.conf /rootfs/etc/pacman.conf; \
    cp /etc/pacman.d/steamos-mirrorlist /rootfs/etc/pacman.d/; \
    cp -a /etc/pacman.d/gnupg /rootfs/etc/pacman.d/; \
    echo "STEAMOS_VERSION=${STEAMOS_VERSION}" > /rootfs/etc/steamos-docker-release; \
    rm -rf /rootfs/var/cache/pacman/pkg/*

# ---------------------------------------------------------------------------
# 2. SteamOS image: Steam, gamescope, Valve's Mesa (AMD), the NVIDIA GBM/EGL
#    glue (the NVIDIA driver itself is installed at start to match the host),
#    sway (headless capture surface for Sunshine), PipeWire, and Sunshine.
# ---------------------------------------------------------------------------
FROM scratch
ARG SUNSHINE_VERSION
COPY --from=bootstrap /rootfs/ /

RUN set -eux; \
    pacman -Syu --noconfirm --needed \
        steam-jupiter-stable gamescope \
        mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon \
        vulkan-icd-loader lib32-vulkan-icd-loader \
        libglvnd lib32-libglvnd egl-wayland egl-gbm \
        sway seatd xorg-xwayland \
        pipewire pipewire-pulse wireplumber lib32-pipewire \
        dbus avahi nss-mdns systemd-libs sudo which curl jq kmod libxcvt \
        ttf-liberation noto-fonts \
        mangohud lib32-mangohud gamemode lib32-gamemode; \
    pacman -Q steam-jupiter-stable gamescope mesa vulkan-radeon \
        | awk '{gsub(/-/,"_",$1); print toupper($1) "=" $2}' >> /etc/steamos-docker-release; \
    yes | pacman -Scc >/dev/null; \
    rm -rf /var/cache/pacman/pkg/*

# Sunshine: the AppImage bundles its own libs, so it doesn't depend on the
# Arch snapshot SteamOS is built on. Extract it instead of needing FUSE.
RUN set -eux; \
    cd /opt; \
    if [ "${SUNSHINE_VERSION}" = latest ]; then \
        url=$(curl -fsSL https://api.github.com/repos/LizardByte/Sunshine/releases/latest \
              | jq -r '.assets[] | select(.name | test("^Sunshine_.*_x86_64\\.AppImage$")) | .browser_download_url'); \
    else \
        url="https://github.com/LizardByte/Sunshine/releases/download/v${SUNSHINE_VERSION}/Sunshine_${SUNSHINE_VERSION}_x86_64.AppImage"; \
    fi; \
    echo "Sunshine: $url"; \
    echo "SUNSHINE_URL=$url" >> /etc/steamos-docker-release; \
    echo "SUNSHINE_VERSION=$(echo "$url" | sed -E 's|.*/download/v([^/]+)/.*|\1|')" >> /etc/steamos-docker-release; \
    curl -fsSL -o sunshine.AppImage "$url"; \
    chmod +x sunshine.AppImage; \
    ./sunshine.AppImage --appimage-extract >/dev/null; \
    mv squashfs-root sunshine; \
    rm sunshine.AppImage; \
    ln -s /opt/sunshine/AppRun /usr/local/bin/sunshine

# `deck` (uid 1000) is the default user on real SteamOS.
RUN set -eux; \
    useradd -m -u 1000 -G video,input,audio,wheel -s /bin/bash deck; \
    echo 'deck ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/deck; \
    mkdir -p /run/user/1000 && chown deck:deck /run/user/1000 && chmod 700 /run/user/1000

COPY rootfs/usr/ /usr/
COPY rootfs/etc/steamos-docker/ /etc/steamos-docker/
RUN chmod +x /usr/local/bin/*

ENV XDG_RUNTIME_DIR=/run/user/1000 \
    STEAMOS_RESOLUTION=1920x1080 \
    STEAMOS_REFRESH=60 \
    STEAM_ARGS="-gamepadui -steamos3" \
    SUNSHINE_USER=admin \
    SUNSHINE_PASS="" \
    GPU_VENDOR=auto

VOLUME ["/home/deck"]
ENTRYPOINT ["/usr/local/bin/entrypoint"]
