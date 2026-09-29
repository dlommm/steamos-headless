# Troubleshooting

## Start with the log

```bash
docker logs steamos          # or: docker compose logs -f
```

The top of the log shows the image version, the CPU threads and RAM the container sees, the
`GPUs found` table and which GPU and encoder were picked. Lines starting with `WARNING` or
`ERROR` say what's wrong and what to do. The table below explains each one.

More detailed logs are inside the container (`docker exec steamos cat <file>`):

| File | What's in it |
|---|---|
| `/run/steamos/session.log` | Session manager: which session started, when it ended |
| `/home/deck/.local/state/steamos-session.log` | Gaming Mode and Desktop Mode output: gamescope, Steam, Plasma |
| `/run/steamos/sunshine.log` | Sunshine: clients, pairing, encoder, stream errors |
| `/run/steamos/sway.log` | The headless display |
| `/var/log/nvidia-installer.log` | NVIDIA driver install |
| `/var/log/preload-flatpak.log` | Add-on (Flatpak) installs |
| `/var/log/decky-install.log` | Decky Loader and plugin installs |
| `/var/log/steamos-units/` | Services started through `systemctl`, such as Decky's |
| `/var/log/avahi.log` | Moonlight auto-discovery |

For a shell inside the container: `docker exec -it steamos bash`. For SSH as `deck`, set
`SSH_AUTHORIZED_KEYS` and connect to port `2222`.

## Log messages

| Message | Meaning and fix |
|---|---|
| `on Docker's internal bridge network; Moonlight can't discover or reach Sunshine` | Use host networking (`network_mode: host`, Unraid Network Type **Host**) or a macvlan/ipvlan network with its own LAN IP (Unraid **Custom: br0**) |
| `CPU is capped by cgroup` / `RAM is capped by cgroup` | The container has a CPU or memory limit. Remove `cpus`, `mem_limit` or the platform's resource limit to use the whole machine |
| `the container can't raise priorities (not privileged?)` | The container isn't privileged. Run it with `privileged: true` |
| `NVIDIA GPU has no render node; enable nvidia-drm.modeset=1 on the host` | Turn on DRM modesetting as in the install guide for your platform, reboot, and check that `cat /sys/module/nvidia_drm/parameters/modeset` prints `Y` |
| `no usable AMD or NVIDIA GPU found in /dev/dri` | The GPU isn't visible in the container. Check that it isn't bound to VFIO or passed to a VM, that the host driver is loaded (`ls /dev/dri`), and that the container is privileged |
| `GPU=... doesn't match any GPU above` | The `GPU` value isn't in the `GPUs found` table. Copy the PCI address from the table |
| `the GPU at ... isn't supported` | Only AMD and NVIDIA GPUs are supported. Intel GPUs aren't |
| `deck cannot write /dev/uinput; Moonlight input will not work` | Install the [udev rule](../host/60-steamos-headless.rules) on the host (see your platform's install guide), or run privileged |
| `avahi-daemon failed` | Auto-discovery is off. Add the server by IP in Moonlight. If another mDNS responder on the host holds the port, set `AVAHI=0` |
| `capture self-test FAILED with renderer ...` | The display can't hand frames to Sunshine with this renderer, so streams would be black. Try `RENDERER_FALLBACK=1`, or set `WLR_RENDERER` to `vulkan` or `pixman`, and please report it with the log |
| `every renderer failed the capture self-test earlier` | A previous start found no working renderer. Delete `/home/deck/.config/steamos-headless/renderer` to test again, e.g. after a driver update |
| `session keeps failing; waiting 30s` | Gaming Mode or Desktop Mode exits right after starting. See `/home/deck/.local/state/steamos-session.log` |

## Common problems

**Moonlight doesn't find the server.** Discovery uses mDNS, which only works on the same
network segment. Add the server by IP instead. Check that the container isn't on Docker's
bridge network, and that the host's firewall allows Sunshine's ports and UDP 5353 (see the
[Linux guide](install/linux.md#4-run)). On Unraid with Custom: br0, the container has its own
IP: use that one, not the server's.

**Can't open the web UI.** It's `https://` (not `http://`) on port 47990, with a self-signed
certificate. Behind a reverse proxy, add its address to `SUNSHINE_ALLOWED_ORIGINS`.

**Forgot the Sunshine password.** Set `SUNSHINE_PASS` (and optionally `SUNSHINE_USER`) and
restart the container. It's applied at every start.

**The stream is black.** Check the log for a capture self-test failure (see above). On NVIDIA,
check that the NVIDIA driver installed without errors (`/var/log/nvidia-installer.log`). If the
session log shows gamescope exiting, the GPU driver is usually the cause.

**The stream connects but shows the wrong size, or Steam restarts on connect.** Steam restarts
once when a client with a different resolution connects to Gaming Mode. That's expected; see
[usage](usage.md#resolution-and-refresh-rate). If it happens every time from the same device,
check that the device asks for the same resolution and frame rate each time.

**Controllers don't work, or only work after reconnecting.** Look for the `/dev/uinput`
warning. On a network with its own IP (macvlan), keep the `/run/udev` mount: the container
needs it to see new controllers.

**Steam says "no networks found" during setup.** Steam reads the connection from
NetworkManager. Check that `NETWORKMANAGER` isn't set to `0`.

**Games stutter or load slowly.** Put `/home/deck` on an SSD, and don't use Unraid's
`/mnt/user` for it (use a pool path such as `/mnt/cache/appdata/steamos`). Check the log for CPU
or RAM caps. In Moonlight, lower the bitrate if the network is the bottleneck (the stats
overlay, `Ctrl+Alt+Shift+S`, shows network and decode times).

**A game doesn't start.** Try a different Proton version in the game's **Properties →
Compatibility**, and check [ProtonDB](https://www.protondb.com). Games with anti-cheat that
blocks Linux don't work, as on a Steam Deck.

**The NVIDIA driver download fails.** The container downloads the driver matching the host
from NVIDIA. Check the container's internet access. Once downloaded, it's cached in
`/var/cache/nvidia`, so mount that folder to avoid downloading it again.

## Games run slowly on servers with many CPU threads

Symptom: the Steam overlay (**…** → Performance) shows a low GAMESCOPE frame rate with long frame
times, while the GPU is mostly idle and the stream itself is a steady 60 FPS in Moonlight.

Many game engines, Unity especially, start a busy-waiting worker thread for every CPU thread they
see. On a server CPU with dozens of threads, or with two workers on the two threads of one core,
those workers starve the game's main thread. On a 64-thread EPYC, Ori ran at 12 FPS seeing every
thread and 66 FPS seeing 8 threads on 8 separate cores.

So Windows games see `GAME_CPU_THREADS` threads (default 8), each on its own physical core. The
log shows the choice at start (`Windows games see 8 CPU threads...`). If a game needs more, set
`GAME_CPU_THREADS=16`, or give just that game its own list in **Properties → Launch options**,
e.g. `WINE_CPU_TOPOLOGY=12:0,1,2,3,4,5,6,7,8,9,10,11 %command%` (threads on separate cores: check
`/sys/devices/system/cpu/cpu0/topology/thread_siblings_list` for which ones share a core).

## Reporting a problem

Open an issue on [GitHub](https://github.com/dlommm/steamos-headless/issues) with:

- the platform (Unraid, TrueNAS, distro) and GPU model
- the image tag (`docker exec steamos cat /etc/steamos-headless-release`)
- the full container log from the start, and the more detailed log that matches the problem
  from the table above
