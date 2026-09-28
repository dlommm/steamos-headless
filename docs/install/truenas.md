# Install on TrueNAS SCALE

Requires TrueNAS SCALE **24.10 (Electric Eel) or newer**, where apps run on Docker.

## 1. GPU

**NVIDIA:** Apps → Configuration → Settings → check **Install NVIDIA Drivers** → Save.
Then turn on DRM modesetting (System → Shell):

```bash
midclt call system.advanced.update '{"kernel_extra_options": "nvidia-drm.modeset=1"}'
```

Reboot, then check `cat /sys/module/nvidia_drm/parameters/modeset` prints `Y`.

Don't set `NVIDIA_VISIBLE_DEVICES` or add GPU resources for this app in the YAML. The
container gets the GPU through privileged mode and installs the matching driver itself.

**AMD:** nothing to install. TrueNAS includes the `amdgpu` driver.

Don't assign the GPU to a VM (or to another app that isolates it); the container needs it on
the host.

## 2. Input permissions

TrueNAS resets `/etc` on updates, so add the udev rule as a startup script:
System → Advanced Settings → Init/Shutdown Scripts → Add

- Type: **Command**
- When: **Post Init**
- Command:

```bash
printf '%s\n' 'KERNEL=="uinput", SUBSYSTEM=="misc", MODE="0660", GROUP="input", OPTIONS+="static_node=uinput"' 'KERNEL=="uhid", SUBSYSTEM=="misc", MODE="0660", GROUP="input"' > /etc/udev/rules.d/60-steamos-docker.rules && udevadm control --reload && udevadm trigger
```

Run the same command once in System → Shell (or reboot).

## 3. Datasets

Datasets → Add Dataset under your pool (ideally an SSD pool for game load times):

- `apps/steamos/home`: Steam client, login, settings and Sunshine pairings (and games, unless you add a games dataset)
- `apps/steamos/nvidia-cache`: NVIDIA driver cache
- Optional, on an HDD pool: a `games` dataset for the game library. Uncomment the `/games` line
  in the YAML. See [storage](../storage.md).

## 4. Install the app

Apps → Discover Apps → **⋮** (top right) → **Install via YAML**. Name it `steamos`, paste
[`deploy/truenas/compose.yaml`](../../deploy/truenas/compose.yaml), and replace `tank` with
your pool name. Save.

Open `https://<truenas-ip>:47990`, create the Sunshine login, then pair Moonlight.

## Updating

Apps → steamos → **Update** when TrueNAS shows one, or Apps → steamos → ⋮ → **Pull image**
and restart.

## Notes

- TrueNAS's web UI uses ports 80/443, and Sunshine uses 47984-48010, so they don't clash
  on the host network.
- The container logs (Apps → steamos → Logs) show the detected GPU, CPU threads and RAM.
