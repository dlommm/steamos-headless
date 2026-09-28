# Storage: updates, NVMe + HDD, extra drives

## Updates never wipe your data

The image only contains the OS (SteamOS, Sunshine, drivers). Everything that belongs to you
lives in folders mounted from the host:

| Container path | Holds | Suggested disk |
|---|---|---|
| `/home/deck` | Steam client, Steam login, settings, Sunshine pairings, and games unless you add `/games` | NVMe / SSD |
| `/games` (optional) | Game library | HDD (or any big disk) |
| `/var/cache/nvidia` | Cached NVIDIA driver installer | anywhere |

Updating replaces only the image and reattaches the same folders:

```bash
docker compose pull && docker compose up -d
```

Steam, your login, installed games and Moonlight pairings are all still there afterwards. The
same is true on TrueNAS (Update / Pull image), Unraid (Apply update), and Portainer (Re-pull
and redeploy).

Data is only lost if you delete it yourself:

- `docker compose down -v` (the `-v` deletes **named volumes**; plain `down` is safe), or
- deleting the host folders or datasets.

Using host folders (bind mounts, like the `deploy/` templates) instead of named volumes means
the data is visible on the host and easy to back up. `docker volume prune` can't remove it
either.

## Games on an HDD, OS on NVMe

Mount the HDD folder at `/games`:

```yaml
    volumes:
      - /mnt/nvme/steamos/home:/home/deck   # Steam + config on NVMe
      - /mnt/hdd/games:/games               # games on the HDD
```

At every start the container registers `/games` as a Steam library, so it appears in
**Steam → Settings → Storage** with no clicking around. Nothing inside it is changed; the
container only creates `steamapps/` and a small `libraryfolder.vdf` marker if they're missing.

In Steam → Settings → Storage, select the `/games` drive and choose **Make default** so new
installs go there. Existing games can be moved with **Move** in the same screen.

Proton prefixes (save data for some games) and shader caches live next to each game, so they
end up on the HDD too. Load times follow the disk: for a few games where loading matters,
keep them in the NVMe library and put the rest on the HDD.

## More than one games drive

Mount each drive and list them all in `STEAM_LIBRARIES` (colon-separated):

```yaml
    environment:
      STEAM_LIBRARIES: /games:/games2:/games-ssd
    volumes:
      - /mnt/hdd1/games:/games
      - /mnt/hdd2/games:/games2
      - /mnt/sata-ssd/games:/games-ssd
```

Paths that aren't mounted are skipped, so the default `/games` does nothing if you don't
mount it.

## Reusing a games folder you already have

Point `/games` at an existing Steam library folder (the one that contains `steamapps/`), for
example from a previous steam-headless install or a desktop PC. Steam finds the installed games
on the next start; if some show as "not installed", choose Install and Steam detects the files
instead of downloading them again.

## Permissions

The container runs Steam as `deck` (uid 1000). At start it makes the top of each library
folder writable by `deck`, and never changes existing files recursively. If an existing library
was written by a different user, give it to uid 1000 once on the host:

```bash
sudo chown -R 1000:1000 /mnt/hdd/games
```

## Per-platform paths

| Platform | Steam home (fast) | Games (big) |
|---|---|---|
| Linux | `/mnt/nvme/steamos/home` | `/mnt/hdd/games` |
| TrueNAS | dataset on the SSD pool, e.g. `/mnt/ssd/apps/steamos/home` | dataset on the HDD pool, e.g. `/mnt/tank/games` |
| Unraid | `/mnt/cache/appdata/steamos` (cache pool) | `/mnt/user/games` (array share) |
| Proxmox VM | VM disk on NVMe storage | a second virtual disk on HDD storage, or an NFS/SMB share mounted in the VM |

On Unraid, set the `games` share's primary storage to the **Array** so games go straight to
the HDDs (a cache in front of it would fill up with game downloads).
