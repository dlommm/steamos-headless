# Usage

## Connecting with Moonlight

[Moonlight](https://moonlight-stream.org) runs on Windows, macOS, Linux, Android, iOS,
Apple TV, Android TV, Chromebooks, the Steam Deck and more.

1. **Create the Sunshine login.** Open `https://<server-ip>:47990` (Sunshine's web UI). The
   certificate is self-signed, so accept the browser's warning. If `SUNSHINE_PASS` is set,
   the login is already there.
2. **Pair.** In Moonlight, the server shows up by itself on the same network (by default as
   **SteamOS-Headless**). If it doesn't, use **Add host** with the server's IP. Select it and
   Moonlight shows a 4-digit PIN. Enter it in the web UI under **PIN**.
3. **Launch an app:**

| Moonlight app | Opens |
|---|---|
| **Steam Big Picture** | Gaming Mode: Steam's Deck interface, the same as a Steam Deck's |
| **Desktop** | Desktop Mode: SteamOS's KDE Plasma desktop with the Steam desktop client |

The first time, Steam runs its setup: pick a language, a time zone and sign in. Steam may
update itself and restart once. That's normal.

## A console that's always on

SteamOS keeps running when nobody is connected, like a console left on. Gaming Mode starts as
soon as the container starts, so Steam can update itself and download games before anyone
connects.

- **Disconnecting** Moonlight leaves everything running. A game keeps running too, and you
  continue where you left off next time, from the same or another device.
- **Quit app** in Moonlight ends the stream, not SteamOS. Close a game from Steam instead.
- Downloads, updates and cloud saves keep going while nobody is connected.

## Resolution and refresh rate

The display takes the resolution and frame rate of the Moonlight client that connects. Set
them in Moonlight's settings. A phone, a 4K TV and a 1440p/144 Hz monitor each get exactly
their own size.

- When a client with a different resolution connects to Gaming Mode, Steam restarts once so
  gamescope runs at the new size. That takes a few seconds.
- Reconnecting from the same device doesn't restart anything.
- The container remembers the last client's resolution and starts at it next time, so the
  first connection after a restart or an update doesn't restart Steam either.
- Desktop Mode is resized in place, without restarting.

## Gaming Mode and Desktop Mode

The container runs one session at a time, like a Deck.

| To | Do |
|---|---|
| Go to the desktop | Steam button → **Power** → **Switch to Desktop**, or launch **Desktop** in Moonlight |
| Go back to Gaming Mode | Double-click **Return to Gaming Mode** on the desktop, or launch **Steam Big Picture** in Moonlight |

Switching modes restarts Steam, because Gaming Mode and Desktop Mode each run their own
Steam. The same happens on a Deck.

If Steam quits, crashes or restarts itself (after an update, for example), the session comes
back by itself.

## The power menu

| Steam's power menu | In the container |
|---|---|
| **Restart** | Restarts the SteamOS session (Steam and gamescope). The container keeps running |
| **Shut Down** | Stops the session until the next Moonlight connection. The container keeps running, and launching an app in Moonlight starts SteamOS again |
| **Sleep** | Steam goes through sleep and wakes right away. Nothing is paused; the server stays on |

To really stop it, stop the container (`docker compose stop`, or from your NAS's UI).

## Controllers, keyboard and mouse

Sunshine creates virtual devices for everything Moonlight sends: gamepads (up to 16,
including motion and touchpad on DualShock/DualSense), keyboard, mouse and touch. Steam
treats them like controllers plugged into a Deck, so Steam Input, per-game layouts and the
Steam button (the guide/home button) work.

Useful Moonlight shortcuts on a PC client:

| Keys | Does |
|---|---|
| `Ctrl+Alt+Shift+Q` | Disconnect |
| `Ctrl+Alt+Shift+Z` | Release the mouse and keyboard |
| `Ctrl+Alt+Shift+S` | Show stream statistics |
| `Ctrl+Alt+Shift+X` | Toggle full screen |

On a gamepad, hold `Start+Select+L1+R1` to disconnect (the Moonlight default).

## Audio

Sound is streamed to the client. Microphones aren't forwarded by Moonlight.

## Games and storage

Steam installs games in `/home/deck` unless you mount a games drive at `/games`, which is
added to Steam automatically. See [storage](storage.md) for putting games on an HDD, several
drives and reusing a library you already have.

## Updates

- **Steam client** updates happen inside SteamOS, as on a Deck.
- **SteamOS, drivers and Sunshine** come with the image. Pull a new image to update; nothing
  in `/home/deck` or `/games` is touched:

```bash
docker compose pull && docker compose up -d
```

Steam's **Settings → System → Check for updates** always says SteamOS is up to date, because
the OS is the image. The OS version and build shown there are the image's.

## Playing away from home

Sunshine's ports shouldn't be open to the internet. Use a VPN such as
[Tailscale](https://tailscale.com) or WireGuard between the client and your network, then add
the server in Moonlight by its VPN address.
