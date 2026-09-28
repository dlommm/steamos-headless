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
| Ubuntu, Debian, Fedora, Arch, any Linux | [docs/install/linux.md](docs/install/linux.md) | [deploy/linux/compose.yaml](deploy/linux/compose.yaml) |
| TrueNAS SCALE 24.10+ | [docs/install/truenas.md](docs/install/truenas.md) | [deploy/truenas/compose.yaml](deploy/truenas/compose.yaml) |
| Unraid | [docs/install/unraid.md](docs/install/unraid.md) | [deploy/unraid/steamos-headless.xml](deploy/unraid/steamos-headless.xml) or [compose.yaml](deploy/unraid/compose.yaml) |
| Proxmox VE | [docs/install/proxmox.md](docs/install/proxmox.md) | VM → Linux guide |
| Portainer / Dockge | Paste [deploy/linux/compose.yaml](deploy/linux/compose.yaml) as a stack | |

Every platform needs the same three things on the host:

1. **A GPU driver:** `amdgpu` (built in everywhere) or the NVIDIA driver with
   `nvidia-drm.modeset=1`. The NVIDIA Container Toolkit is **not** needed. Leave out
   `--runtime=nvidia`, `NVIDIA_VISIBLE_DEVICES` and `NVIDIA_DRIVER_CAPABILITIES`: the container
   gets every GPU through privileged mode and installs the matching driver itself, including
   the 32-bit libraries Steam needs, which the toolkit doesn't provide. If they're set anyway,
   it falls back to the toolkit's libraries and prints a warning.
2. **The udev rule** in [`host/60-steamos-docker.rules`](host/60-steamos-docker.rules), only if
   the log warns that `deck cannot write /dev/uinput` (a privileged container handles it itself).
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
| `GPU` | auto | PCI address of the card to use, e.g. `0000:c1:00.0` (copy it from the `GPUs found` table at the top of the log). Auto picks dedicated NVIDIA, then dedicated AMD, then integrated AMD. The other cards are hidden from the container, so two containers can each own one GPU |
| `GPU_ISOLATE` | `1` | `0` leaves the other GPUs visible |
| `NVIDIA_GPU` | | Older alternative to `GPU`: index as in `nvidia-smi` |
| `SSH_AUTHORIZED_KEYS` | | Public key(s) to allow SSH into the container as `deck` (key only, for debugging). Off when empty |
| `SSH_PORT` | `2222` | SSH port inside the container |
| `RENDER_NODE` | auto | Force a device, e.g. `/dev/dri/renderD129` |
| `WLR_RENDERER` | `gles2` on NVIDIA | sway renderer for the headless display (`gles2`, `vulkan`, `pixman`) |
| `STEAMOS_RESOLUTION` / `STEAMOS_REFRESH` | `1920x1080` / `60` | Size at the very first boot; after that the container starts at the last client's size |
| `SUNSHINE_USER` / `SUNSHINE_PASS` | `admin` / empty | Sets the web UI login at start if a password is given |
| `STEAM_ARGS` | Valve's `steam-launcher` | Run Steam with these arguments instead of Valve's (`-steamos3 -steampal -steamdeck -gamepadui`) |
| `MDNS_INTERFACE` | default route | Network interface for Moonlight auto-discovery (Unraid's `shim-br0` is mapped to `br0`) |
| `SUNSHINE_ALLOWED_ORIGINS` | | Extra web UI addresses to trust, e.g. `https://steam.example.com` behind a reverse proxy. The server's own IPs and hostname are trusted automatically |
| `AVAHI` | `1` | `0` disables auto-discovery (add the host by IP in Moonlight) |
| `NETWORKMANAGER` | `1` | Runs NetworkManager in report-only mode so Steam's setup sees the connection; `0` disables it |
| `STEAM_LIBRARIES` | `/games` | Colon-separated folders registered as Steam libraries (skipped if not mounted) |
| `PRELOAD_APPS` | empty | Deck add-ons to install, comma-separated, e.g. `decky,heroic,xcloud` (every name: [Add-ons](#add-ons)) |
| `PRELOAD_FLATPAKS` | empty | Other Flathub apps to install, by app ID ([Add-ons](#preload_flatpaks)) |
| `DECKY_PLUGINS` | empty | Decky store plugins to install, by name, e.g. `CSS Loader,SteamGridDB` ([Add-ons](#decky_plugins)) |
| `ADD_TO_STEAM` | the launchers | Which installed apps to add to Steam for Gaming Mode: `none`, or names/IDs; `default` stands for the launchers ([Add-ons](#add_to_steam)) |

## Add-ons

Popular Steam Deck add-ons can be installed at start, each with its own official installer, as
on a Deck. **Nothing is installed unless you list it.** Each one is installed once and then
updates itself (Decky and its plugins from Decky's menu, Flatpak apps through Discover).
Removing a name from the list later doesn't uninstall anything.

```yaml
PRELOAD_APPS: decky,heroic,protonup,xcloud          # names from the table below
PRELOAD_FLATPAKS: com.spotify.Client                # any other Flathub app ID
DECKY_PLUGINS: CSS Loader,SteamGridDB,ProtonDB Badges
ADD_TO_STEAM: default,discord                       # which apps show up in Gaming Mode
```

### `PRELOAD_APPS`

Comma-separated. **In Steam** means it's added to Steam's library as a non-Steam game by default,
so it can be launched from Gaming Mode (see [`ADD_TO_STEAM`](#add_to_steam)).

| Name | Installs | In Steam | Notes |
|---|---|---|---|
| `decky` | [Decky Loader](https://decky.xyz) | | Plugin menu in Gaming Mode (**...** button). Decky's own installer; its `plugin_loader` service runs through the container's `systemctl`, so Decky's updater works too |
| `emudeck` | [EmuDeck](https://www.emudeck.com) installer | | Puts **Install EmuDeck** on the desktop. Its setup asks which emulators to install and where ROMs go, so run it from Desktop Mode. It adds your games to Steam itself (Steam ROM Manager) |
| `retrodeck` | [RetroDECK](https://retrodeck.net) (Flathub) | yes | All-in-one emulation frontend, an alternative to EmuDeck |
| `heroic` | [Heroic Games Launcher](https://heroicgameslauncher.com) (Flathub) | yes | Epic Games, GOG and Amazon. Sign in inside Heroic; it can add each game to Steam too |
| `lutris` | [Lutris](https://lutris.net) (Flathub) | yes | EA, Ubisoft, Battle.net and other launchers and stores |
| `bottles` | [Bottles](https://usebottles.com) (Flathub) | | Runs Windows programs and games in their own Wine prefixes |
| `protonup` | [ProtonUp-Qt](https://davidotek.github.io/protonup-qt/) (Flathub) | | Installs Proton-GE and other compatibility tools for Steam and Heroic/Lutris |
| `protontricks` | [Protontricks](https://github.com/Matoking/protontricks) (Flathub) | | Installs Windows components (fonts, runtimes) into a game's Proton prefix |
| `geforcenow` | [GeForce NOW](https://www.nvidia.com/geforce-now/) (NVIDIA's Flatpak repo) | yes | NVIDIA's native app, as on the Steam Deck |
| `xcloud` | Xbox Cloud Gaming via Microsoft Edge (Flathub) | yes | Set up as Microsoft's [Steam Deck guide](https://support.microsoft.com/en-us/topic/xbox-cloud-gaming-in-microsoft-edge-with-steam-deck-43dd011b-0ce8-4810-8302-965be6d53296): Edge may read controllers, and **Xbox Cloud Gaming** opens xbox.com/play full screen. In Steam, set its controller layout to *Gamepad with Mouse Trackpad* |
| `firefox` | [Firefox](https://www.mozilla.org/firefox/) (Flathub) | | The browser SteamOS offers on its desktop |
| `chrome` | [Google Chrome](https://www.google.com/chrome/) (Flathub) | | |
| `discord` | [Discord](https://discord.com) (Flathub) | | |
| `flatseal` | [Flatseal](https://github.com/tchx84/Flatseal) (Flathub) | | Flatpak permissions, e.g. letting Heroic, Lutris or Bottles see a `/games` drive |

Flatpak apps are installed for the `deck` user, so they live in `/home/deck` and survive image
updates. Progress goes to `/var/log/preload-flatpak.log`. Large apps take a few minutes after
the first start; Steam starts meanwhile.

### `PRELOAD_FLATPAKS`

Any other [Flathub](https://flathub.org) apps, by app ID (the last part of the app's Flathub
URL), comma-separated, e.g. `com.spotify.Client,org.videolan.VLC,tv.kodi.Kodi`. They're
installed like the ones above and not added to Steam unless listed in `ADD_TO_STEAM`.

### `DECKY_PLUGINS`

Plugins from Decky's store, by the name shown in the store, comma-separated, e.g.
`CSS Loader,SteamGridDB,ProtonDB Badges,HLTB for Deck,TabMaster,Audio Loader`. Listing any
installs Decky too. They're installed the way Decky's store installs them (checked against the
store's checksum) before Decky starts, and update from Decky's menu afterwards. Plugins that
tune Deck hardware (PowerTools, CPU/GPU or fan control) can't do anything in a container.

### `ADD_TO_STEAM`

Which of the installed apps get added to Steam's library as non-Steam games, so they can be
launched from Gaming Mode. Valve's own **Add to Steam** helper does it once Steam is running
with an account signed in, the first time only; remove a shortcut in Steam and it stays
removed.

| Value | Adds |
|---|---|
| empty (default) | The game launchers: those marked **In Steam** above that you installed |
| `none` | Nothing |
| `heroic,discord` | Exactly these (names from `PRELOAD_APPS`, or app IDs from `PRELOAD_FLATPAKS`) |
| `default,discord` | The launchers, plus these |

## Storage

`/home/deck` holds the Steam client, login, settings and Sunshine pairings. Put it on NVMe/SSD.
Mount a big drive at `/games` and it's **added to Steam as a library automatically**, so the
OS can live on NVMe and games on HDD. **Updates never wipe data**: pulling a new image keeps
both folders. See [docs/storage.md](docs/storage.md) for multiple drives, reusing an existing
library, and per-platform paths.

## How it works

```
Moonlight ──► Sunshine ──(wlr-screencopy)──► sway (headless output, resized per client)
                 │                               ├── Gaming Mode: gamescope ── Steam -gamepadui -steamos3
                 │                               └── Desktop Mode: KDE Plasma (SteamOS's) + Steam
                 └──(uinput)──► virtual pad/kbd/mouse ──► libinput (sway) + Steam
```

At start the container:

1. Reports the CPU threads and RAM it can see, and warns if something caps them.
2. Detects the GPU. On NVIDIA it installs the userspace driver matching the host kernel module
   (including the 32-bit libraries Steam needs), cached in `/var/cache/nvidia`.
3. Starts D-Bus, Avahi (Moonlight discovery), PipeWire, and sway on a headless output.
4. Starts the session manager, which runs Gaming Mode right away, so updates and login happen
   before anyone connects.
5. Starts Sunshine with the matching encoder: NVENC on NVIDIA, VA-API on AMD.

When a client launches **Steam Big Picture**, the display is resized to that client. Steam is
only restarted if the resolution changed, so reconnecting from the same device is instant. The
container remembers the last client's resolution and boots Gaming Mode at it, so the first
connection after a restart doesn't restart Steam either.

### Gaming Mode and Desktop Mode

Like a Deck, the container runs one session at a time, and a session manager keeps it running:

- **Switch to Desktop** in Steam's power menu opens SteamOS's KDE Plasma desktop, with the Steam
  desktop client. **Return to Gaming Mode** on the desktop goes back. In Moonlight, the
  **Desktop** app opens Desktop Mode and **Steam Big Picture** opens Gaming Mode.
- The desktop looks like a Deck's: Valve's **Vapor (Steam Deck)** theme, with the Steam Deck
  wallpapers, the Deck logo on the app launcher and the Deck splash screen.
- If Steam quits, restarts itself (after setup or an update) or crashes, the session comes back.
- **Restart** restarts the session, and **Shut Down** stops it until the next Moonlight
  connection. The container keeps running.
- Gaming Mode runs through Valve's own session scripts (`gamescope-session`, `steam-launcher`,
  mangoapp), so Steam sees the same environment and features as on a Deck.
- SteamOS's own system packages are installed (`jupiter-hw-support`, `steamos-customizations`,
  `holo-session-selection`, `steamos-alias`, `steamdeck-kde-presets`...), so every
  `steamos-*` helper Steam calls is Valve's script. What those scripts expect from the OS
  (systemd, polkit, SDDM, logind, the A/B updater) is provided in container terms: OS updates
  report "no update" (the OS is the image), the time zone applies, and formatting, trimming or
  factory-resetting drives is refused so it can't touch the host's disks.

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
- Deck hardware controls (fan, TDP, brightness, battery) don't apply. OS updates come from
  newer images, not Steam's updater.
- Games whose anti-cheat blocks Linux/Proton won't work, same as on a Steam Deck.
