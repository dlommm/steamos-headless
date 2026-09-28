# Install on Ubuntu, Debian, Fedora, Arch (any Linux with Docker)

## 1. Docker

| Distro | Command |
|---|---|
| Ubuntu / Debian | `curl -fsSL https://get.docker.com \| sudo sh` |
| Fedora | `sudo dnf install docker-ce docker-compose-plugin` (after adding Docker's repo), or `curl -fsSL https://get.docker.com \| sudo sh` |
| Arch | `sudo pacman -S docker docker-compose` |

```bash
sudo systemctl enable --now docker
```

## 2. GPU driver on the host

**AMD:** nothing to do. The `amdgpu` kernel driver is built into every distro kernel.
Check with `ls /dev/dri/renderD*`.

**NVIDIA:** install the driver on the host (the container matches its version automatically)
and turn on DRM modesetting:

| Distro | Install driver |
|---|---|
| Ubuntu | `sudo ubuntu-drivers install` |
| Debian | `sudo apt install nvidia-driver` (non-free repo enabled) |
| Fedora | RPM Fusion: `sudo dnf install akmod-nvidia` |
| Arch | `sudo pacman -S nvidia-open` (or `nvidia` for older cards) |

```bash
echo 'options nvidia-drm modeset=1 fbdev=1' | sudo tee /etc/modprobe.d/nvidia-drm.conf
# rebuild the initramfs so it applies at boot:
sudo update-initramfs -u        # Ubuntu / Debian
sudo dracut --force             # Fedora
sudo mkinitcpio -P              # Arch
sudo reboot
cat /sys/module/nvidia_drm/parameters/modeset   # must print Y
```

`modeset=1` only adds `/dev/dri` nodes for the card. CUDA and AI containers keep working
unchanged, and datacenter cards like the L4 work too (their driver is downloaded from NVIDIA's
Data Center archive automatically).

**Multiple NVIDIA GPUs:** by default the container uses any NVIDIA card. To keep one card for
AI containers, set `NVIDIA_GPU: "1"` (index as shown by `nvidia-smi`, or a PCI address like
`0000:c1:00.0`). The container then only sees that card, and you can pin the AI containers to
the other one with `NVIDIA_VISIBLE_DEVICES=0`. If you never run both at once you don't need
this, but stop this container before large AI jobs: an idle Steam still holds some VRAM.

The NVIDIA Container Toolkit is **not** needed, and `--runtime=nvidia`,
`NVIDIA_VISIBLE_DEVICES` and `NVIDIA_DRIVER_CAPABILITIES` should be left out. The container
gets the GPU through privileged mode and installs the matching driver itself, including the
32-bit libraries Steam needs, which the toolkit doesn't provide.

## 3. Input permissions (once)

Lets Sunshine create virtual controllers, keyboard and mouse:

```bash
sudo curl -fsSL -o /etc/udev/rules.d/60-steamos-docker.rules \
  https://gitlab.ohhcloud.com/dlomm/arch-steam-headless/-/raw/main/host/60-steamos-docker.rules
sudo udevadm control --reload && sudo udevadm trigger
```

## 4. Run

```bash
mkdir -p ~/steamos && cd ~/steamos
curl -fsSLO https://gitlab.ohhcloud.com/dlomm/arch-steam-headless/-/raw/main/deploy/linux/compose.yaml
# edit the paths marked CHANGE ME: Steam home on NVMe/SSD, optionally games on an HDD
# (see ../storage.md)
docker compose up -d
docker compose logs -f     # shows detected GPU, CPU threads and RAM
```

Open `https://<server-ip>:47990`, create the Sunshine login, then pair Moonlight.

**Firewall:** with host networking, open Sunshine's ports if the host runs a firewall:
TCP 47984, 47989, 47990, 48010 and UDP 47998-48000, 48002, 48010, plus UDP 5353 (mDNS).

```bash
sudo ufw allow 47984:48010/tcp && sudo ufw allow 47998:48010/udp && sudo ufw allow 5353/udp   # Ubuntu
sudo firewall-cmd --permanent --add-port={47984-48010/tcp,47998-48010/udp,5353/udp} && sudo firewall-cmd --reload   # Fedora
```

## Updating

```bash
docker compose pull && docker compose up -d
```

To stay on one version, replace `:latest` with a release tag, e.g. `:2026.09.28.3`, or
`:steamos-3.8` for the newest build of a SteamOS series.
