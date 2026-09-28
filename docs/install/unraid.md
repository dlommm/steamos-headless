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

> **Don't add** `--runtime=nvidia`, `NVIDIA_VISIBLE_DEVICES` or `NVIDIA_DRIVER_CAPABILITIES`,
> even though the Nvidia Driver plugin's instructions say to for other containers. This
> container gets the GPU through privileged mode and installs the full driver (including the
> 32-bit libraries Steam needs) matching the plugin's version by itself.

**AMD:** Apps → install **Radeon TOP** (by ich777), which loads the `amdgpu` driver at boot.
Check with `ls /dev/dri/renderD*`.

Don't bind the GPU to VFIO (Tools → System Devices) and don't pass it to a VM at the same time.

## 2. Input permissions

Only needed if the container log says `deck cannot write /dev/uinput`. A privileged
container (the default templates) sets this up itself.

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
[`deploy/unraid/compose.yaml`](../../deploy/unraid/compose.yaml) (already set up with Unraid
paths).

## Network type

Either works:

- **Host** (template default): Sunshine is at the Unraid server's IP.
- **Custom: br0** with its own fixed IP: Sunshine is at that IP (e.g. `https://172.16.0.34:47990`).
  Add `--hostname=steamos` to Extra Parameters so Moonlight shows a readable name. This is
  the way to run one container per GPU, since each Sunshine needs its own ports. Keep the
  `/run/udev` mapping: the container relays input hotplug events itself (the host's udev
  only announces new devices on the host network), and needs the host's udev data for that.

Don't use **Bridge**: Moonlight can't discover or reach Sunshine behind Docker's NAT. The log
warns if the container is on it.

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
