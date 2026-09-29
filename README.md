<p align="center"><img src="docs/logos/steamosheadless.png" alt="SteamOS-Headless" width="160"></p>

# SteamOS-Headless

**A full SteamOS clone, headless, in Docker.** It's the Steam Deck's operating system, built
from Valve's own packages, running on a server with no monitor. You play it from any device
through [Moonlight](https://moonlight-stream.org). It has Gaming Mode, Desktop Mode, the Deck's
Steam client and Valve's own session and system scripts, so it looks and behaves like a Steam
Deck.

**One image for AMD and NVIDIA.** The GPU is detected when the container starts. On NVIDIA,
the container installs the driver version that matches the host.

```
docker pull dendlomm/steamos-headless:latest
```

## Features

- **Real SteamOS, not a lookalike.** Built from Valve's SteamOS repositories
  (`steamdeck-packages.steamos.cloud`), the same packages the Steam Deck recovery image is
  made from: Valve's Steam client, gamescope, Mesa, the KDE Plasma desktop and SteamOS's
  system packages. Steam's **Settings → System** shows it as SteamOS.
- **Gaming Mode and Desktop Mode.** Steam's Deck interface runs in gamescope, and SteamOS's
  Plasma desktop runs with the Steam Deck theme. **Switch to Desktop** and **Return to Gaming
  Mode** work as on a Deck, and Moonlight can start either one directly.
- **Headless.** No monitor, dummy plug or desktop on the host. Sunshine streams the session
  to Moonlight on a phone, TV, PC, tablet or handheld.
- **Resolution follows the client.** A phone, a 4K TV and a 1440p/144 Hz PC each get their
  own resolution and refresh rate when they connect.
- **Full speed.** No CPU, RAM or shared-memory caps. Games render and the stream is encoded
  on the GPU (NVENC on NVIDIA, VA-API on AMD).
- **Your data survives updates.** Steam, your login, games, settings and Moonlight pairings
  live in folders on the host. Pulling a new image never wipes them.
- **Deck add-ons on request.** Decky Loader and its plugins, EmuDeck, Heroic, Lutris,
  GeForce NOW, Xbox Cloud Gaming and any Flathub app can be installed at start
  ([add-ons](docs/add-ons.md)).

## Quick start

On any Linux host with Docker and an AMD or NVIDIA GPU (NVIDIA needs `nvidia-drm.modeset=1`,
see the [Linux guide](docs/install/linux.md)):

```bash
mkdir -p ~/steamos && cd ~/steamos
curl -fsSLO https://raw.githubusercontent.com/dlommm/steamos-headless/main/deploy/linux/compose.yaml
# edit the paths marked CHANGE ME
docker compose up -d
docker compose logs -f
```

Then:

1. Open `https://<server-ip>:47990` and create the Sunshine login. The certificate is
   self-signed, so accept the browser's warning.
2. In Moonlight, select the server (it usually appears by itself; otherwise add it by IP).
   Moonlight shows a PIN: enter it in Sunshine's web UI under **PIN**.
3. Launch **Steam Big Picture** for Gaming Mode or **Desktop** for Desktop Mode. The first
   start runs Steam's setup: pick a language and time zone, and sign in.

The [usage guide](docs/usage.md) covers controllers, switching modes and everyday use.

## Install guides

| Platform | Guide | Template |
|---|---|---|
| Ubuntu, Debian, Fedora, Arch, any Linux | [docs/install/linux.md](docs/install/linux.md) | [deploy/linux/compose.yaml](deploy/linux/compose.yaml) |
| TrueNAS SCALE 24.10+ | [docs/install/truenas.md](docs/install/truenas.md) | [deploy/truenas/compose.yaml](deploy/truenas/compose.yaml) |
| Unraid 6.12+ / 7.x | [docs/install/unraid.md](docs/install/unraid.md) | [deploy/unraid/steamos-headless.xml](deploy/unraid/steamos-headless.xml) or [compose.yaml](deploy/unraid/compose.yaml) |
| Proxmox VE | [docs/install/proxmox.md](docs/install/proxmox.md) | VM → Linux guide |
| Portainer / Dockge | Paste [deploy/linux/compose.yaml](deploy/linux/compose.yaml) as a stack | |

Every platform needs the same three things on the host:

1. **A GPU driver:** `amdgpu` (built into every distro kernel) or the NVIDIA driver with
   `nvidia-drm.modeset=1`. The NVIDIA Container Toolkit is **not** needed. Leave out
   `--runtime=nvidia`, `NVIDIA_VISIBLE_DEVICES` and `NVIDIA_DRIVER_CAPABILITIES`: the
   container reaches the GPU through privileged mode and installs the matching driver itself,
   including the 32-bit libraries Steam needs, which the toolkit doesn't provide. If they're
   set anyway, it falls back to the toolkit's libraries and prints a warning.
2. **Docker**, running the container privileged, with host networking or its own LAN IP
   (macvlan, e.g. Unraid's Custom: br0). The templates do this.
3. **The udev rule** in [`host/60-steamos-headless.rules`](host/60-steamos-headless.rules),
   only if the log warns that `deck cannot write /dev/uinput`. A privileged container
   usually handles this itself.

## Configuration

Everything is optional. Set these as environment variables on the container.

| Variable | Default | What it does |
|---|---|---|
| `GPU_VENDOR` | `auto` | `nvidia` or `amd`, to choose on hosts with both |
| `GPU` | auto | PCI address of the card to use, e.g. `0000:c1:00.0` (copy it from the `GPUs found` table at the top of the log). Auto picks dedicated NVIDIA, then dedicated AMD, then integrated AMD. The other cards are hidden from the container, so two containers can each own one GPU |
| `GPU_ISOLATE` | `1` | `0` leaves the other GPUs visible |
| `NVIDIA_GPU` | | Older alternative to `GPU`: the card's index as in `nvidia-smi` |
| `RENDER_NODE` | auto | Force a device, e.g. `/dev/dri/renderD129` |
| `GAME_CPU_THREADS` | auto | How many CPU threads Windows (Proton) games see. On hosts with more than 16 threads, games see 16, one per physical core, chosen from the cores near this container's GPU; dozens of threads make many games slower. A number picks that many, `0` or `all` shows every thread. A `WINE_CPU_TOPOLOGY` in a game's launch options overrides it. See [troubleshooting](docs/troubleshooting.md#games-run-slowly-on-servers-with-many-cpu-threads) |
| `STEAMOS_RESOLUTION` / `STEAMOS_REFRESH` | `1920x1080` / `60` | Display size at the very first start. After that the container starts at the last client's size |
| `TZ` | `UTC` | Time zone, e.g. `America/New_York`. A time zone picked in Steam's settings takes priority and is kept |
| `SUNSHINE_USER` / `SUNSHINE_PASS` | `admin` / empty | Sets the Sunshine web UI login at start when a password is given. Empty: create it in the web UI |
| `SUNSHINE_NAME` | `SteamOS-Headless` | Name Moonlight shows for this server. Used when Sunshine's config is first created; change it later in the web UI |
| `SUNSHINE_ALLOWED_ORIGINS` | | Extra web UI addresses to trust, e.g. `https://steam.example.com` behind a reverse proxy. The server's own IPs and hostname are trusted automatically |
| `STEAM_LIBRARIES` | `/games` | Colon-separated folders registered as Steam libraries (skipped if not mounted). See [storage](docs/storage.md) |
| `PRELOAD_APPS` | empty | Deck add-ons to install, e.g. `decky,heroic,xcloud`. See [add-ons](docs/add-ons.md) |
| `PRELOAD_FLATPAKS` | empty | Other Flathub apps to install, by app ID |
| `DECKY_PLUGINS` | empty | Decky store plugins to install, by name, e.g. `CSS Loader,SteamGridDB` |
| `ADD_TO_STEAM` | the launchers | Which installed apps to add to Steam for Gaming Mode: `none`, or names/IDs; `default` stands for the launchers |
| `STEAM_ARGS` | Valve's `steam-launcher` | Run Steam with these arguments instead of Valve's launcher (`-steamos3 -steampal -steamdeck -gamepadui`) |
| `MDNS_INTERFACE` | default route | Network interface for Moonlight auto-discovery (Unraid's `shim-br0` is mapped to `br0`) |
| `AVAHI` | `1` | `0` turns off auto-discovery (add the server by IP in Moonlight) |
| `NETWORKMANAGER` | `1` | Runs NetworkManager in report-only mode so Steam's setup sees the connection; `0` turns it off |
| `SSH_AUTHORIZED_KEYS` | | Public key(s) allowed to SSH in as `deck`, for debugging (keys only, no passwords). Off when empty |
| `SSH_PORT` | `2222` | SSH port |
| `WLR_RENDERER` | auto | Renderer of the headless display: `gles2`, `vulkan` or `pixman`. Auto tries `gles2`, then `vulkan`, and keeps the first that passes the capture self-test. A renderer set here is used as-is, without the self-test |
| `RENDERER_FALLBACK` | `0` | `1` tries the next renderer when the capture self-test at start fails |
| `ALLOW_NO_GPU` | `0` | `1` keeps going without a usable GPU, with software rendering and encoding. For testing only |

## Documentation

| Guide | Covers |
|---|---|
| [Usage](docs/usage.md) | Moonlight, Gaming Mode and Desktop Mode, controllers, resolution, the power menu, updates |
| [Add-ons](docs/add-ons.md) | Decky Loader and plugins, EmuDeck, launchers, cloud gaming, Flathub apps |
| [Storage](docs/storage.md) | What's kept across updates, games on a separate drive, multiple libraries, reusing a library |
| [How it works](docs/how-it-works.md) | The display and streaming stack, the session manager, how SteamOS runs in a container |
| [Troubleshooting](docs/troubleshooting.md) | Log messages, which logs to collect, common problems |
| [Development](docs/development.md) | Building the image, repository layout, CI and releases |

## Images and versions

GitHub Actions builds the image and publishes it to Docker Hub as
[`dendlomm/steamos-headless`](https://hub.docker.com/r/dendlomm/steamos-headless):

| Tag | Meaning |
|---|---|
| `latest` | Newest build |
| `2026.09.28.3` | One specific build (date + build number). Never changes |
| `steamos-3.9` | Newest build for that SteamOS release |
| `branch-<name>` | Test build of a development branch |

Every build pulls the newest SteamOS release and the newest Sunshine release, and a weekly
build keeps `latest` current. Each release on the
[Releases page](https://github.com/dlommm/steamos-headless/releases) lists the exact SteamOS,
Steam client, gamescope, Mesa and Sunshine versions inside.

SteamOS "latest" is the highest numbered release in Valve's repositories, which can be a
preview. Use a `steamos-<x.y>` tag to stay on one series.

To update:

```bash
docker compose pull && docker compose up -d
docker exec steamos cat /etc/steamos-headless-release   # versions inside
```

## Security

The container runs **privileged** with host networking and host IPC. It needs raw GPU and
input devices, `uinput` to create virtual controllers, and user namespaces for Steam's
pressure-vessel sandbox. Treat it like a game console on your LAN, not an isolated service:

- Don't expose Sunshine's ports to the internet. Use a VPN (WireGuard, Tailscale) to play
  away from home.
- Set a strong Sunshine password. Anyone with it can pair a device and control the session.
- Sunshine's virtual input devices are created on the host kernel, so a desktop session on
  the host would receive them too. The image is meant for dedicated or headless hosts.
- Steam Deck actions that would touch the host (formatting, trimming or factory-resetting
  drives, writing hardware settings) are refused inside the container.

## Limitations

- Headless only: nothing is shown on a monitor attached to the host.
- Deck hardware controls (fan, TDP, brightness, battery) don't apply.
- SteamOS updates come from newer images. Steam client updates work as usual.
- Games whose anti-cheat blocks Linux or Proton don't work, same as on a Steam Deck.
- One SteamOS session per container. For separate players, run one container per GPU.

## Credits

SteamOS, Steam and the Steam Deck are trademarks of Valve Corporation. This project isn't
affiliated with or endorsed by Valve. It installs Valve's packages from Valve's public
repositories at build time. Streaming is by [Sunshine](https://github.com/LizardByte/Sunshine)
and [Moonlight](https://moonlight-stream.org).

## License

The files in this repository are under the [MIT License](LICENSE). The image also contains
software under its own licenses: SteamOS packages and the Steam client from Valve,
Sunshine (GPL-3.0), the NVIDIA driver (installed at start, under NVIDIA's license) and the
open-source components of SteamOS under theirs.
