# Install on Unraid

For Unraid 6.12+ / 7.x.

## 1. GPU

**NVIDIA:** Apps → install **Nvidia Driver** (by ich777), pick the latest production driver,
and reboot. Then turn on DRM modesetting (Terminal):

```bash
mkdir -p /boot/config/modprobe.d
echo 'options nvidia-drm modeset=1' > /boot/config/modprobe.d/nvidia-drm.conf
```

Reboot, then check `cat /sys/module/nvidia_drm/parameters/modeset` prints `Y`.

**AMD:** Apps → install **Radeon TOP** (by ich777), which loads the `amdgpu` driver at boot.
Check with `ls /dev/dri/renderD*`.

Don't bind the GPU to VFIO (Tools → System Devices) and don't pass it to a VM at the same time.

## 2. Input permissions

Unraid's root filesystem is rebuilt at every boot, so add the udev rule to the `go` file:

```bash
cat >> /boot/config/go <<'EOF'
# steamos-headless: allow Sunshine virtual input
printf '%s\n' 'KERNEL=="uinput", SUBSYSTEM=="misc", MODE="0660", GROUP="input", OPTIONS+="static_node=uinput"' 'KERNEL=="uhid", SUBSYSTEM=="misc", MODE="0660", GROUP="input"' > /etc/udev/rules.d/60-steamos-docker.rules
udevadm control --reload && udevadm trigger
EOF
```

Run those last two lines once now too (or reboot).

## 3. Add the container

**Option A: template (recommended)**

```bash
wget -O /boot/config/plugins/dockerMan/templates-user/my-steamos-headless.xml \
  https://gitlab.ohhcloud.com/dlomm/arch-steam-headless/-/raw/main/deploy/unraid/steamos-headless.xml
```

Docker → **Add Container** → Template: **steamos-headless** → set the Sunshine password →
Apply.

**Option B: Compose Manager plugin**

Apps → install **Docker Compose Manager** → Docker → Add New Stack → paste
[`deploy/compose.yaml`](../../deploy/compose.yaml) and change the paths to e.g.
`/mnt/cache/appdata/steamos`.

## Storage

- **Steam home:** a **pool/cache path** (`/mnt/cache/appdata/steamos`), not `/mnt/user/...`.
  The user-share FUSE layer is slow for the Steam client and shader caches.
- **Games library (optional):** set it to a share on the array, e.g. `/mnt/user/games` (share
  primary storage: Array). It's added to Steam automatically. In Steam → Settings → Storage,
  make it the default. See [storage](../storage.md).

## Updating

Docker tab → **Check for Updates** → apply, or enable auto-update with the CA Auto Update
plugin.

Open `https://<unraid-ip>:47990`, create the Sunshine login, then pair Moonlight.
