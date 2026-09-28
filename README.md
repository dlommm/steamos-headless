# SteamOS Headless (Docker)

SteamOS in a container, streamed to any device with Moonlight. **One image for AMD and
NVIDIA.** The GPU is detected when the container starts, and on NVIDIA the driver matching
the host is loaded automatically.

- **Real SteamOS packages.** Built from Valve's SteamOS repositories
  (`steamdeck-packages.steamos.cloud`), the same packages the Steam Deck recovery image is
  made from: Valve's Steam client, gamescope and Mesa.
- **Headless.** Runs on a server with no monitor. Steam Big Picture runs in gamescope and
  Sunshine streams it.
- **Resolution follows the client.** A phone, a 4K TV and a 1440p/144 Hz PC each get their
  own resolution and refresh rate when they connect.
- **No limits.** No CPU, RAM or shared-memory caps. It uses every core and all memory the host
  gives it. Games render and the stream is encoded on the GPU (NVENC / VA-API), not the CPU.

```
docker pull registry.ohhcloud.com/dlomm/arch-steam-headless:latest
```

## Install

| Platform | Guide | Template |
|---|---|---|
| Ubuntu, Debian, Fedora, Arch, any Linux | [docs/install/linux.md](docs/install/linux.md) | [deploy/compose.yaml](deploy/compose.yaml) |
| TrueNAS SCALE 24.10+ | [docs/install/truenas.md](docs/install/truenas.md) | [deploy/truenas/compose.yaml](deploy/truenas/compose.yaml) |
| Unraid | [docs/install/unraid.md](docs/install/unraid.md) | [deploy/unraid/steamos-headless.xml](deploy/unraid/steamos-headless.xml) |
| Proxmox VE | [docs/install/proxmox.md](docs/install/proxmox.md) | VM → Linux guide |
| Portainer / Dockge | Paste [deploy/compose.yaml](deploy/compose.yaml) as a stack | |

Every platform needs the same three things on the host:

1. **A GPU driver:** `amdgpu` (built in everywhere) or the NVIDIA driver with
   `nvidia-drm.modeset=1`. The NVIDIA Container Toolkit is **not** needed.
2. **The udev rule** in [`host/60-steamos-docker.rules`](host/60-steamos-docker.rules) so
   Moonlight controllers, keyboard and mouse work.
3. **Docker**, running the container privileged with host networking (the templates do this).

Then open `https://<server-ip>:47990`, create the Sunshine login, pair Moonlight, and launch
**Steam Big Picture**.

## Images, versions and releases

GitLab CI builds the image and publishes it to
`registry.ohhcloud.com/dlomm/arch-steam-headless` with these tags:

| Tag | Meaning |
|---|---|
| `latest` | Newest build |
| `2026.09.28.3` | A specific build (date + pipeline number). Never changes |
| `steamos-3.9` | Newest build for that SteamOS release |

Each build also creates a **GitLab Release** listing the exact SteamOS, Steam client,
gamescope, Mesa and Sunshine versions inside.

Builds always pull the newest SteamOS release and the newest Sunshine release. A weekly
pipeline schedule (Build → Pipeline schedules) keeps `latest` current. To update a server:

```bash
docker compose pull && docker compose up -d
docker exec steamos cat /etc/steamos-docker-release   # what's inside
```

SteamOS "latest" is the highest numbered release in Valve's repos, which can be a preview.
Use the `steamos-3.8` tag to stay on a specific series.

## Configuration

| Variable | Default | |
|---|---|---|
| `GPU_VENDOR` | `auto` | `nvidia` / `amd` to choose on hosts with both GPUs |
| `RENDER_NODE` | auto | Force a device, e.g. `/dev/dri/renderD129` |
| `STEAMOS_RESOLUTION` / `STEAMOS_REFRESH` | `1920x1080` / `60` | Size at boot, before any client connects |
| `SUNSHINE_USER` / `SUNSHINE_PASS` | `admin` / empty | Sets the web UI login at start if a password is given |
| `STEAM_ARGS` | `-gamepadui -steamos3` | Add `-steamdeck` to make games treat it as a Deck |
| `MDNS_INTERFACE` | default route | Network interface for Moonlight auto-discovery |
| `AVAHI` | `1` | `0` disables auto-discovery (add the host by IP in Moonlight) |

`/home/deck` holds the Steam library, Steam login, and Sunshine config and pairings. Put it on
a fast SSD/NVMe.

## How it works

```
Moonlight ──► Sunshine ──(wlr-screencopy)──► sway (headless output, resized per client)
                 │                               └── gamescope ── Steam -gamepadui -steamos3
                 └──(uinput)──► virtual pad/kbd/mouse ──► libinput (sway) + Steam
```

At start the container:

1. Reports the CPU threads and RAM it can see, and warns if something caps them.
2. Detects the GPU. On NVIDIA it installs the userspace driver matching the host kernel module
   (including the 32-bit libraries Steam needs), cached in `/var/cache/nvidia`.
3. Starts D-Bus, Avahi (Moonlight discovery), PipeWire, and sway on a headless output.
4. Starts Steam in gamescope right away, so updates and login happen before anyone connects.
5. Starts Sunshine with the matching encoder: NVENC on NVIDIA, VA-API on AMD.

When a client launches **Steam Big Picture**, the display is resized to that client. Steam is
only restarted if the resolution changed, so reconnecting from the same device is instant.

**Why not Bazzite, the Deck recovery image, or Apollo?** A container uses the host's kernel.
Bazzite images and the recovery image are whole bootable OSes (kernel, firmware, updater).
Bazzite's NVIDIA variant also bundles a driver that must exactly match the host's.
Apollo's virtual display is Windows-only. On Linux, Sunshine plus the per-client resize does
the same job.

## Build locally

```bash
cp .env.example .env
docker compose build            # STEAMOS_VERSION / SUNSHINE_VERSION from .env
docker compose up -d
```

Docker caches build steps. `docker compose build --pull --no-cache` picks up new releases.

## Security

The container runs `privileged` with host networking and host IPC. It needs raw GPU and input
devices, uinput to create virtual controllers, and user namespaces for Steam's pressure-vessel
sandbox. Treat it like a game console on your LAN, not an isolated service. Sunshine's virtual
input devices are created on the host kernel, so a desktop session on the host would also
receive them. It's intended for dedicated or headless hosts.

## Limitations

- Headless only. No output to a monitor attached to the host.
- SteamOS system features do nothing in a container: OS updates, the power menu, switch to
  desktop, and Deck hardware controls. The OS is updated by pulling a newer image.
- Games whose anti-cheat blocks Linux/Proton won't work, same as on a Steam Deck.
