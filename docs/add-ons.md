# Add-ons

Popular Steam Deck add-ons can be installed when the container starts, each with its own
official installer, the way a Deck user would install them. **Nothing is installed unless you
list it.**

- Each add-on is installed once, then updates itself: Decky and its plugins from Decky's
  menu, Flatpak apps through Discover in Desktop Mode.
- Removing a name from the list later doesn't uninstall anything. Uninstall it the usual
  way (Discover, or Decky's settings).
- Everything is installed into `/home/deck`, so it survives image updates.

```yaml
environment:
  PRELOAD_APPS: decky,heroic,protonup,xcloud          # names from the table below
  PRELOAD_FLATPAKS: com.spotify.Client                # any other Flathub app ID
  DECKY_PLUGINS: CSS Loader,SteamGridDB,ProtonDB Badges
  ADD_TO_STEAM: default,discord                       # which apps show up in Gaming Mode
```

## `PRELOAD_APPS`

Comma-separated. **In Steam** means it's added to Steam's library as a non-Steam game by
default, so it can be launched from Gaming Mode (see [`ADD_TO_STEAM`](#add_to_steam)).

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
| `xcloud` | Xbox Cloud Gaming via Microsoft Edge (Flathub) | yes | Set up as in Microsoft's [Steam Deck guide](https://support.microsoft.com/en-us/topic/xbox-cloud-gaming-in-microsoft-edge-with-steam-deck-43dd011b-0ce8-4810-8302-965be6d53296): Edge may read controllers, and **Xbox Cloud Gaming** opens xbox.com/play full screen. In Steam, set its controller layout to *Gamepad with Mouse Trackpad* |
| `firefox` | [Firefox](https://www.mozilla.org/firefox/) (Flathub) | | The browser SteamOS offers on its desktop |
| `chrome` | [Google Chrome](https://www.google.com/chrome/) (Flathub) | | |
| `discord` | [Discord](https://discord.com) (Flathub) | | |
| `flatseal` | [Flatseal](https://github.com/tchx84/Flatseal) (Flathub) | | Flatpak permissions, e.g. letting Heroic, Lutris or Bottles see a `/games` drive |

Flatpak apps are installed for the `deck` user. Large apps take a few minutes after the first
start, and Steam starts in the meantime. Progress goes to `/var/log/preload-flatpak.log`
(`docker exec steamos tail -f /var/log/preload-flatpak.log`).

## `PRELOAD_FLATPAKS`

Any other [Flathub](https://flathub.org) apps, by app ID (the last part of the app's Flathub
URL), comma-separated, e.g. `com.spotify.Client,org.videolan.VLC,tv.kodi.Kodi`. They're
installed like the ones above, and not added to Steam unless listed in `ADD_TO_STEAM`.

## `DECKY_PLUGINS`

Plugins from Decky's store, by the name shown in the store, comma-separated, e.g.
`CSS Loader,SteamGridDB,ProtonDB Badges,HLTB for Deck,TabMaster,Audio Loader`. Listing any
installs Decky too.

They're installed the way Decky's store installs them (checked against the store's checksum)
before Decky starts, and update from Decky's menu afterwards. Plugins that tune Deck hardware
(PowerTools, CPU/GPU or fan control) can't do anything in a container. Decky's install log is
`/var/log/decky-install.log`.

## `ADD_TO_STEAM`

Which of the installed apps get added to Steam's library as non-Steam games, so they can be
launched from Gaming Mode. Valve's own **Add to Steam** helper (the same one as the desktop's
right-click menu) does it once Steam is running with an account signed in. It happens the
first time only: remove a shortcut in Steam and it stays removed.

| Value | Adds |
|---|---|
| empty (default) | The game launchers: those marked **In Steam** above that you installed |
| `none` | Nothing |
| `heroic,discord` | Exactly these (names from `PRELOAD_APPS`, or app IDs from `PRELOAD_FLATPAKS`) |
| `default,discord` | The launchers, plus these |

## Installing things yourself

Everything a Deck user does by hand works too:

- **Discover** (Desktop Mode) installs Flatpak apps from Flathub.
- **Add to Steam** from an app's right-click menu in Desktop Mode puts it in Gaming Mode.

Don't install apps with `pacman`. As on a Deck, the system belongs to the OS image, so
packages installed that way are gone after the next image update. Use Flatpak instead.
