# SteamOS in Docker (AMD + NVIDIA)

Headless SteamOS for streaming with Moonlight. The images are built from **Valve's own
SteamOS package repositories** (`steamdeck-packages.steamos.cloud`), the same packages the
Steam Deck recovery image is made from. They run Steam Big Picture in gamescope and stream it
with Sunshine.

| Image | GPU stack |
|---|---|
| `steamos-docker:amd` | Valve's SteamOS Mesa build (RADV Vulkan, radeonsi VA-API encoding) |
| `steamos-docker:nvidia` | NVIDIA userspace driver matching the host, installed at start (NVENC encoding) |

## How it fits together

```
Moonlight ──► Sunshine ──(wlr-screencopy)──► sway (headless output, resized per client)
                 │                               └── gamescope ── Steam -gamepadui -steamos3
                 └──(uinput)──► virtual pad/kbd/mouse ──► libinput (sway) + Steam
```

- **Resolution follows the client.** When a device connects, the "Steam Big Picture" app
  resizes the display to that device's resolution and refresh rate. If Steam is already
  running at that size it isn't restarted, so reconnecting is instant. This is the Apollo
  virtual-display feature, done on Linux with Sunshine.
- **Steam starts at boot**, before anyone connects, so updates and login happen ahead of time.
- Why not the kernel, Bazzite, or Apollo: a container uses the host's kernel. Bazzite images
  are meant to boot bare metal. Apollo is Windows-only.

## Host requirements

Any Linux host with Docker and a GPU. Nothing else is installed on the host except:

1. **Udev rule for virtual input** (once):
   ```bash
   sudo cp host/60-steamos-docker.rules /etc/udev/rules.d/
   sudo udevadm control --reload && sudo udevadm trigger
   ```
2. **NVIDIA only:** the proprietary or open NVIDIA kernel driver loaded, with DRM modesetting:
   ```bash
   cat /sys/module/nvidia_drm/parameters/modeset   # must print Y
   # if not: add nvidia-drm.modeset=1 to the kernel command line and reboot
   ```
   The NVIDIA Container Toolkit is **not** required. The container downloads the userspace
   driver that exactly matches the host's version from download.nvidia.com, including the
   32-bit libraries Steam needs, and caches it in the `nvidia-cache` volume.
3. **AMD only:** the in-kernel `amdgpu` driver (standard everywhere).

## Run

**Prebuilt images:** GitLab CI builds both images into this project's container registry
(`:amd`, `:nvidia`, plus dated tags like `:amd-20260927`). Set `IMAGE_REPO` in `.env` to the
registry path, then use `pull` instead of `--build`:

```bash
docker compose --profile amd pull && docker compose --profile amd up -d
```

**Build locally:**

```bash
cp .env.example .env          # optional: set SUNSHINE_PASS, versions, etc.
docker compose --profile amd up -d --build       # AMD
docker compose --profile nvidia up -d --build    # NVIDIA
docker compose logs -f
```

1. Open `https://<host-ip>:47990` and log in (or create the Sunshine account).
2. In Moonlight, add the host and enter the PIN in Sunshine's web UI → PIN.
3. Launch **Steam Big Picture**. Log in to Steam once; it's saved in the home volume.

## Versions and updating

Both `STEAMOS_VERSION` and `SUNSHINE_VERSION` default to `latest`, resolved at **build time**:

- SteamOS `latest` = the highest numbered release in Valve's repos (e.g. `3.9`). Valve
  doesn't publish a "stable" pointer, so this can be a preview release. Set
  `STEAMOS_VERSION=3.8` to pin.
- Sunshine `latest` = the newest GitHub release.

GitLab CI builds without the cache, so every pipeline picks up the newest releases. Add a
weekly pipeline schedule (Build → Pipeline schedules) to stay current automatically, then
`docker compose pull` on the host. Local builds cache steps, so to pull new versions:

```bash
docker compose --profile amd build --pull --no-cache && docker compose --profile amd up -d
docker exec steamos-amd cat /etc/steamos-docker-release   # shows what was built
```

Steam itself updates on its own inside the container.

## Configuration

| Variable | Default | |
|---|---|---|
| `STEAMOS_RESOLUTION` / `STEAMOS_REFRESH` | `1920x1080` / `60` | Size at boot before any client connects |
| `SUNSHINE_USER` / `SUNSHINE_PASS` | `admin` / empty | Sets the web UI login on start if a password is given |
| `STEAM_ARGS` | `-gamepadui -steamos3` | Add `-steamdeck` to make games treat it as a Deck |
| `RENDER_NODE` | auto | Force a GPU, e.g. `/dev/dri/renderD129` on multi-GPU hosts |

Persistent data (Steam library, Steam login, Sunshine config and pairings) lives in the
`steamos-<vendor>-home` volume at `/home/deck`. For a big library, bind-mount a disk instead,
e.g. `- /mnt/games:/home/deck`.

## Security

The container runs `privileged` with host networking. It needs raw GPU and input devices,
uinput to create virtual controllers, and user namespaces for Steam's pressure-vessel
sandbox. Treat it like a game console on your LAN, not an isolated service. Sunshine's
virtual input devices are created on the host kernel, so a desktop session on the host would
also receive them. This is intended for dedicated or headless hosts.

## Limitations

- Headless only. No output to a monitor attached to the host.
- SteamOS system features do nothing in a container: OS updates, the power menu, switch to
  desktop, and Deck hardware controls. The OS is updated by rebuilding the image.
- Anti-cheat games that block Linux/Proton won't work, same as on a Steam Deck.
