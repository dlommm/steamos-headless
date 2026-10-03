# How it works

SteamOS-Headless is SteamOS's userspace, installed from Valve's package repositories, running
on the host's kernel inside a privileged Docker container. On a Steam Deck the display is the
built-in panel and SteamOS's services come from systemd. Here the display is a virtual screen
that Sunshine streams, and a small set of container stand-ins provides what those services
would.

## The stack

```
Moonlight ──► Sunshine ──(wlr-screencopy)──► sway (headless output, sized per client)
                 │                               ├── Gaming Mode: gamescope ── Steam -gamepadui -steamos3
                 │                               └── Desktop Mode: KDE Plasma (SteamOS's) + Steam
                 └──(uinput)──► virtual pad/kbd/mouse ──► libinput (sway) + Steam
```

- **sway** provides a headless Wayland output: the "screen". Nothing is drawn on a monitor.
- **gamescope** runs nested in sway for Gaming Mode, started through Valve's own
  `gamescope-session`, exactly as on a Deck. Desktop Mode runs KDE Plasma's `kwin` nested
  in sway instead, the way Valve's `holo-nested-desktop` does.
- **Sunshine** captures sway's output (wlr-screencopy), encodes it on the GPU (NVENC or
  VA-API) and streams it to Moonlight. Input from Moonlight comes back as virtual devices
  (`uinput`), which sway and Steam see like real hardware.
- **PipeWire** carries the audio, which Sunshine streams alongside the picture. There's no
  sound card, so a "Stream (Moonlight)" sink is always there as the default output; audio
  moves to Sunshine's own sink when a client connects.

## What's in the image

The image is built in stages ([Dockerfile](../Dockerfile)):

1. An Arch Linux bootstrap stage uses `pacman` with Valve's repositories for one SteamOS
   release (`steamdeck-packages.steamos.cloud`: `jupiter-<version>`, `holo-<version>` and
   Valve's own snapshot of `core`, `extra` and `multilib`) to install the SteamOS package set
   into a fresh root. "latest" resolves to the highest numbered SteamOS release at build time.
2. gamescope is rebuilt from the exact upstream tag of the packaged version plus one upstream
   fix for nested use (without it the stream can stay black). If the package already has the
   fix, or the build fails, the packaged gamescope is kept.
3. That root becomes the final image, with Sunshine (the newest release from LizardByte's
   GitHub), the container's scripts from [`rootfs/`](../rootfs) and `/etc/os-release`
   filled in the way SteamOS fills it, so Steam's **Settings → System** shows the OS version
   and build.

The installed packages include Valve's Steam client (`steam-jupiter-stable`), gamescope and its
session scripts, Valve's Mesa build, KDE Plasma with `steamdeck-kde-presets` (the Deck's
desktop look), and SteamOS's system packages: `jupiter-hw-support`,
`steamos-customizations-jupiter`, `holo-session-selection`, `steamos-alias` and more. The
versions in a build are listed in `/etc/steamos-headless-release` and on each GitHub release.

## Start-up

The container's entrypoint ([`rootfs/usr/local/bin/entrypoint`](../rootfs/usr/local/bin/entrypoint)):

1. **Checks the environment.** Reports the CPU threads and RAM it can see and warns about
   caps, and warns if it's on Docker's bridge network, where Moonlight can't reach it.
2. **Picks the GPU.** Lists every GPU (the `GPUs found` table), picks one (dedicated NVIDIA,
   then dedicated AMD, then integrated AMD, or the one in `GPU`), and hides the others from
   the container so another container can use them.
3. **Installs the NVIDIA driver** when the GPU is NVIDIA. The userspace driver has to be the
   exact version of the host's kernel module, so it can't be part of the image. The matching
   installer (including the 32-bit libraries Steam needs) is downloaded from NVIDIA, cached
   in `/var/cache/nvidia` and installed at every start, which takes seconds once cached.
4. **Starts system services:** D-Bus, the logind stand-in, NetworkManager (report-only),
   Avahi (so Moonlight finds the server), seatd, the udev relay, and optionally SSH.
5. **Starts the user session:** PipeWire, Steam library registration and add-ons
   ([`steamos-preload`](add-ons.md)).
6. **Starts sway**, then the **session manager**, which brings up Gaming Mode right away,
   then **Sunshine** with the matching encoder.
7. **Self-tests the capture path.** Sunshine test-encodes captured frames when it starts. If
   sway can't import them with the current renderer, the log says so (with
   `RENDERER_FALLBACK=1` the next renderer is tried). The result is remembered in
   `/home/deck` per image and driver version, so later starts go straight to the renderer that
   worked.

## The session manager

On SteamOS, SDDM and systemd user units decide which session runs: Gaming Mode
(`gamescope-session`) or Desktop Mode (Plasma). The container's
[`steamos-session-manager`](../rootfs/usr/local/bin/steamos-session-manager) does the same job:

- It runs exactly one session at a time and starts the next one when it ends: the one that was
  asked for, else the default login mode, else Gaming Mode.
- Gaming Mode is run the way SteamOS's user units run it: Valve's `gamescope-session`, then
  Valve's `steam-launcher` (restarted whenever Steam exits while gamescope runs, with Valve's
  short-session tracker), plus `mangoapp`, `ibus` and Steam's notification daemon.
  On NVIDIA, `mangoapp` restarts whenever Steam changes the performance overlay level:
  MangoHud 0.8.3 only reads GPU temperature, clocks, power and VRAM for the fields enabled
  when it starts, so otherwise they stay at 0.
- In Desktop Mode, Steam starts without `-pipewire`, so Plasma doesn't ask to share the
  screen every time. Sunshine does the streaming.
- gamescope's panel flags (the Deck's 1280x800 screen) are replaced with the Moonlight
  client's resolution and refresh rate.
- Steam's **Switch to Desktop** runs Valve's `holo-session-select`, which calls
  `steamosctl`. The desktop's **Return to Gaming Mode** logs out. Both reach the manager
  through [`steamos-session-control`](../rootfs/usr/local/bin/steamos-session-control).
- If a session keeps failing right after starting, the manager waits before trying again
  instead of spinning.

When Moonlight launches an app, Sunshine runs
[`steamos-session`](../rootfs/usr/local/bin/steamos-session) with the client's resolution. It
resizes sway's output, starts or switches to the wanted session, and restarts Gaming Mode
only when the resolution changed. The last client's mode is saved in
`~/.config/steamos-headless/client-mode` and used at the next start.

## SteamOS services in container terms

Valve's scripts are used wherever possible. Where they expect an OS service the container
doesn't have, a stand-in answers the same way the real service would, acting on the container
instead of a Deck:

| SteamOS has | The container has | Behaviour |
|---|---|---|
| systemd (`systemctl`) | [`systemctl`](../rootfs/usr/local/bin/systemctl) + [`steamos-headless-unit`](../rootfs/usr/local/bin/steamos-headless-unit) | System units such as Decky's `plugin_loader` run under a small supervisor, logged to `/var/log/steamos-units`. Enabled units start with the container |
| logind | [`login1-shim`](../rootfs/usr/local/bin/login1-shim) | Restart restarts the session, Power Off stops it until the next connection, Suspend sleeps and wakes at once |
| `reboot` / `poweroff` / `halt` | Scripts of the same name | The same as logind's: they act on the session, never the host |
| polkit (`pkexec`) | [`pkexec`](../rootfs/usr/local/bin/pkexec) | Runs SteamOS's privileged helpers through sudo |
| SDDM + `steamos-manager` | [`steamosctl`](../rootfs/usr/local/bin/steamosctl) | Session switching and the default login mode |
| A/B OS updater (`atomupd`) | [`atomupd-manager`](../rootfs/usr/local/bin/atomupd-manager) | Always reports "no update": the OS is the image |
| `timedatectl` / `hostnamectl` | Scripts of the same name | The time zone applies and is remembered; the hostname is Docker's |
| NetworkManager | NetworkManager, report-only | Reports the connection so Steam's setup can continue; never changes the host's network |
| Drive and hardware helpers | Overrides in [`holo-polkit-helpers`](../rootfs/usr/bin/holo-polkit-helpers) | Formatting, trimming, factory reset and hardware writes are refused, because in a privileged container they'd act on the host |

## Input

Moonlight's gamepads, keyboard and mouse become virtual devices created by Sunshine through
`/dev/uinput` and `/dev/uhid`. These are created in the host kernel, and udev on the host
announces them.

With host networking the container sees those announcements directly. With its own network
namespace (macvlan, such as Unraid's Custom: br0) it doesn't, because udev's announcements
don't cross network namespaces. The [`udev-relay`](../rootfs/usr/local/bin/udev-relay) watches
the kernel's device events, waits for the host's udev to process each device (through the
mounted `/run/udev`) and re-announces it inside the container, so sway and Steam see hotplugged
controllers either way.

## Networking

Sunshine uses TCP 47984, 47989, 47990 (web UI), 48010 and UDP 47998-48000, 48002, 48010.
Avahi announces the server over mDNS (UDP 5353) so Moonlight finds it without typing an IP.

The container needs to be reachable on the LAN at its own address: host networking, or a
macvlan/ipvlan network with its own IP. Docker's default bridge network doesn't work, because
Moonlight can't discover or reach Sunshine through Docker's NAT.

## What's kept where

| Path | Holds | Kept across updates |
|---|---|---|
| `/home/deck` | Steam, games (without `/games`), settings, Flatpaks, Decky, Sunshine config and pairings, the container's own state in `~/.config/steamos-headless` | Yes (mounted from the host) |
| `/games` | Game library | Yes (mounted from the host) |
| `/var/cache/nvidia` | Downloaded NVIDIA installers | Yes (mounted from the host) |
| Everything else | SteamOS itself | No: it's the image |
