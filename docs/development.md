# Development

## Building the image

```bash
git clone https://github.com/dlommm/steamos-headless.git
cd steamos-headless
cp .env.example .env
docker compose build            # STEAMOS_VERSION / SUNSHINE_VERSION from .env
docker compose up -d
```

Or with plain Docker:

```bash
docker build -t steamos-headless \
  --build-arg STEAMOS_VERSION=latest \
  --build-arg SUNSHINE_VERSION=latest .
```

| Build argument | Default | |
|---|---|---|
| `STEAMOS_VERSION` | `latest` | SteamOS release whose repositories are used, e.g. `3.8`. `latest` is the highest numbered one, which can be a preview |
| `SUNSHINE_VERSION` | `latest` | Sunshine release, without the `v`, e.g. `2026.914.233613` |
| `IMAGE_VERSION` | `dev` | Version string written into the image (CI sets it to the release tag) |

Docker caches build steps, so a rebuild reuses old package downloads. Use
`docker compose build --pull --no-cache` to pick up new SteamOS and Sunshine releases. A full
build downloads several GB and takes a while.

## Repository layout

| Path | What it is |
|---|---|
| [`Dockerfile`](../Dockerfile) | Installs SteamOS from Valve's repositories, rebuilds gamescope with a fix, adds Sunshine and `rootfs/` |
| [`rootfs/`](../rootfs) | Files copied into the image as-is |
| [`rootfs/usr/local/bin/entrypoint`](../rootfs/usr/local/bin/entrypoint) | Container start-up: GPU, services, display, session, Sunshine |
| `rootfs/usr/local/bin/steamos-session*` | The session manager and the scripts Sunshine and SteamOS use to control it |
| `rootfs/usr/local/bin/` (others) | Container stand-ins for SteamOS services: `systemctl`, `steamosctl`, `atomupd-manager`, `login1-shim`, `reboot`... |
| [`rootfs/usr/bin/holo-polkit-helpers/`](../rootfs/usr/bin/holo-polkit-helpers) | Overrides for SteamOS helpers that would act on the host's disks or hardware |
| [`rootfs/etc/steamos-headless/`](../rootfs/etc/steamos-headless) | Default Sunshine apps, sway and Avahi configuration |
| [`deploy/`](../deploy) | Ready-to-use templates per platform |
| [`docs/`](.) | Documentation |
| [`host/`](../host) | Files for the host (the udev rule) |
| [`.github/workflows/build.yml`](../.github/workflows/build.yml) | CI: build, push to Docker Hub, GitHub Release |

[How it works](how-it-works.md) explains how these fit together.

## Guidelines

- **Mirror SteamOS.** Use Valve's own packages and scripts wherever they exist. Before writing
  a `steamos-*`, `holo-*` or `jupiter-*` stand-in, check which Valve package ships the real
  one (`pacman -F <file>` in the image) and install that instead.
- **Only stand in for OS services.** Where Valve's scripts expect systemd, logind, polkit, SDDM
  or the A/B updater, provide the same interface in container terms. Override a Valve script
  only where running it would act on the host (formatting, trimming, factory reset, hardware
  writes).
- **Keep user data in `/home/deck`.** Anything that must survive an image update goes there.
  The container's own state lives in `~/.config/steamos-headless`.
- **Think beyond host networking and one GPU.** Test with a container that has its own network
  namespace (macvlan) and on hosts with more than one GPU where possible.
- Scripts are Bash with `set -uo pipefail` (or `-euo`). Check them with `bash -n` and
  [ShellCheck](https://www.shellcheck.net).

## Debugging a running container

```bash
docker exec -it steamos bash                          # root shell
docker exec -it -u deck steamos bash                  # as the deck user
docker exec steamos tail -f /home/deck/.local/state/steamos-session.log
```

With `SSH_AUTHORIZED_KEYS` set, `ssh -p 2222 deck@<server>` works too. The
[troubleshooting guide](troubleshooting.md) lists every log file.

## CI and releases

[GitHub Actions](../.github/workflows/build.yml) builds the image whenever `Dockerfile`,
`rootfs/` or the workflow changes, every Monday, and when started by hand (**Actions → build →
Run workflow**). Builds never use the layer cache, so every build gets the newest SteamOS and
Sunshine.

| Branch | Pushes to Docker Hub | GitHub Release |
|---|---|---|
| `main` | `latest`, `<date>.<run>` and `steamos-<x.y>` | Yes, listing the component versions |
| any other | `branch-<name>` only | No |

To test a change on a real server without touching `latest`, push it to a branch and run
`dendlomm/steamos-headless:branch-<name>` there.

The workflow needs two repository secrets: `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` (a
Docker Hub access token with read and write access).
