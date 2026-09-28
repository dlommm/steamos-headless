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
    # Valve's mirror occasionally stalls a download; retry instead of failing.
    n=0; until pacman --config /etc/pacman.steamos.conf --root /rootfs --noconfirm -Sy base holo-keyring; do \
        n=$((n+1)); [ "$n" -lt 4 ] || exit 1; echo "pacman failed, retry $n/3"; sleep 15; done; \
    cp /etc/pacman.steamos.conf /rootfs/etc/pacman.conf; \
    cp /etc/pacman.d/steamos-mirrorlist /rootfs/etc/pacman.d/; \
    cp -a /etc/pacman.d/gnupg /rootfs/etc/pacman.d/; \
    echo "STEAMOS_VERSION=${STEAMOS_VERSION}" > /rootfs/etc/steamos-docker-release; \
    rm -rf /rootfs/var/cache/pacman/pkg/*

# ---------------------------------------------------------------------------
# 1b. gamescope with an upstream fix SteamOS's package doesn't have yet.
#     Nested in sway, gamescope hides its window when nothing has focus (e.g.
#     while Steam restarts) and could then wait forever for a configure that
#     never comes: Steam keeps running but the stream is black. Fixed upstream
#     by 6867f50 ("only await a configure after a real unmap"). This builds the
#     exact upstream tag of the packaged version plus that fix. If the package
#     already has it, or anything here fails, /out stays empty and the image
#     keeps the packaged binary.
# ---------------------------------------------------------------------------
FROM scratch AS gamescope-build
COPY --from=bootstrap /rootfs/ /
ARG GAMESCOPE_FIX=6867f50
RUN set -eux; \
    n=0; until pacman -Syu --noconfirm --needed gamescope base-devel git meson ninja cmake \
        glslang vulkan-headers wayland-protocols libinput libxkbcommon seatd \
        xcb-util-wm xcb-util-errors xcb-util-renderutil hwdata; do \
        n=$((n+1)); [ "$n" -lt 4 ] || exit 1; echo "pacman failed, retry $n/3"; sleep 15; done; \
    mkdir -p /out; \
    ver=$(pacman -Q gamescope | awk '{print $2}' | sed 's/-[0-9]*$//'); \
    build() { \
        git clone -q --depth 1 --recurse-submodules --shallow-submodules --branch "$ver" \
            https://github.com/ValveSoftware/gamescope.git /src || return 1; \
        cd /src; \
        curl -fsSL -o /tmp/fix.patch "https://github.com/ValveSoftware/gamescope/commit/${GAMESCOPE_FIX}.patch" || return 1; \
        if git apply -R --check /tmp/fix.patch 2>/dev/null; then \
            echo "gamescope $ver already has ${GAMESCOPE_FIX}; keeping the package"; return 0; \
        fi; \
        git apply /tmp/fix.patch || return 1; \
        meson setup build --prefix=/usr --buildtype=release \
            -Dpipewire=enabled -Denable_openvr_support=false -Denable_tests=false \
            -Denable_gamescope_wsi_layer=false -Dbenchmark=disabled || return 1; \
        ninja -C build src/gamescope || return 1; \
        install -m755 build/src/gamescope /out/gamescope; \
        echo "GAMESCOPE_PATCHED=${ver}+${GAMESCOPE_FIX}" > /out/release; \
    }; \
    build || { echo "WARNING: patched gamescope build failed; using the packaged binary"; rm -rf /out/*; }; \
    touch /out/release

# ---------------------------------------------------------------------------
# 2. SteamOS image: Steam, gamescope, Valve's Mesa (AMD), the NVIDIA GBM/EGL
#    glue (the NVIDIA driver itself is installed at start to match the host),
#    sway (headless capture surface for Sunshine), PipeWire, and Sunshine.
# ---------------------------------------------------------------------------
FROM scratch
ARG SUNSHINE_VERSION
ARG IMAGE_VERSION=dev
COPY --from=bootstrap /rootfs/ /

RUN set -eux; \
    n=0; until pacman -Syu --noconfirm --needed \
        steam-jupiter-stable gamescope \
        mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon \
        vulkan-icd-loader lib32-vulkan-icd-loader \
        libglvnd lib32-libglvnd egl-wayland egl-gbm \
        sway seatd xorg-xwayland \
        pipewire pipewire-pulse wireplumber lib32-pipewire \
        dbus avahi nss-mdns networkmanager openssh systemd-libs sudo which curl jq kmod libxcvt \
        ttf-liberation noto-fonts \
        mangohud lib32-mangohud gamemode lib32-gamemode \
        plasma-desktop plasma-workspace kwin plasma-nm plasma-pa kscreen breeze breeze-gtk \
        xdg-desktop-portal-kde steamdeck-kde-presets kdialog qt6-tools qt6-wayland \
        dolphin konsole kate ark spectacle discover flatpak \
        xdg-utils lib32-libxkbcommon python-dbus python-gobject libva-nvidia-driver \
        jupiter-hw-support jupiter-legacy-support jupiter-dock-updater-bin steamos-customizations-jupiter \
        holo-session-selection steamos-alias holo-glibc-locales steamos-networking-tools \
        steam-im-modules ibus steam_notif_daemon xdg-desktop-portal-holo xdg-desktop-portal-gamescope; do \
        n=$((n+1)); [ "$n" -lt 4 ] || exit 1; echo "pacman failed, retry $n/3"; sleep 15; done; \
    pacman -Q steam-jupiter-stable gamescope mesa vulkan-radeon plasma-workspace \
        | awk '{gsub(/-/,"_",$1); print toupper($1) "=" $2}' >> /etc/steamos-docker-release; \
    # SteamOS's Return to Gaming Mode icon calls "qdbus"; Qt 6 names it qdbus6.
    command -v qdbus >/dev/null || ln -s "$(command -v qdbus6 || echo /usr/lib/qt6/bin/qdbus)" /usr/local/bin/qdbus; \
    # What steamos-set-plasma-theme.service does at boot on a Deck (it checks
    # the board name, which a container can't have): default to the Steam
    # Deck variant of Vapor, with the Deck wallpaper, launcher logo and splash.
    kwriteconfig6 --file /etc/xdg/kdeglobals --group KDE --key LookAndFeelPackage com.valve.vapor.deck.desktop; \
    kwriteconfig6 --file /etc/xdg/kdeglobals --group KDE --key DefaultDarkLookAndFeel com.valve.vapor.deck.desktop; \
    yes | pacman -Scc >/dev/null; \
    rm -rf /var/cache/pacman/pkg/*

# The patched gamescope from stage 1b, if it was built (see there).
COPY --from=gamescope-build /out/ /tmp/gamescope-build/
RUN set -eux; \
    if [ -x /tmp/gamescope-build/gamescope ]; then \
        install -m755 /tmp/gamescope-build/gamescope /usr/bin/gamescope; \
        setcap 'CAP_SYS_NICE=eip' /usr/bin/gamescope || true; \
        cat /tmp/gamescope-build/release >> /etc/steamos-docker-release; \
    fi; \
    rm -rf /tmp/gamescope-build

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
    echo "IMAGE_VERSION=${IMAGE_VERSION}" >> /etc/steamos-docker-release; \
    useradd -m -u 1000 -G video,input,audio,wheel -s /bin/bash deck; \
    echo 'deck ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/deck; \
    mkdir -p /run/user/1000 && chown deck:deck /run/user/1000 && chmod 700 /run/user/1000

COPY rootfs/usr/ /usr/
COPY rootfs/etc/steamos-docker/ /etc/steamos-docker/
RUN chmod +x /usr/local/bin/*

ENV XDG_RUNTIME_DIR=/run/user/1000 \
    LANG=en_US.UTF-8 \
    STEAMOS_RESOLUTION=1920x1080 \
    STEAMOS_REFRESH=60 \
    SUNSHINE_USER=admin \
    SUNSHINE_PASS="" \
    GPU_VENDOR=auto \
    STEAM_LIBRARIES=/games

VOLUME ["/home/deck"]
ENTRYPOINT ["/usr/local/bin/entrypoint"]
