# Architecture

Three parts, two machines, two repos: **sa-mp-cef-gamemode** (server) and **sa-mp-cef-launcher** (Windows).

```
 PLAYER PC (Windows)                                  SERVER (Linux)
┌────────────────────────────────┐               ┌──────────────────────────────────────┐
│ Freeroam Launcher (Electron)   │── HTTP 8080 ─▶│ update-server (Node, no deps)        │
│  • status / news               │               │  /api/status   → UDP query to open.mp │
│  • syncs CEF runtime           │               │  /api/news     → news.json            │
│  • self-update                 │               │  /client/...   → client-files/ + hash │
│  • PLAY → fr-inject.exe        │               │  /launcher/... → launcher-releases/   │
└───────────────┬────────────────┘               │  /ui/...       → ui/                  │
                │ CreateProcess (suspended)      │                                      │
                │ + LoadLibrary ×2               │ omp-server (open.mp, 32-bit)          │
                ▼                                │  • gamemodes/freeroam.amx             │
┌────────────────────────────────┐── UDP 7777 ──▶│  • components/cef.so (samp-cef)       │
│ gta_sa.exe                     │  SA-MP net    │                                      │
│  + samp.dll   (player's SA-MP) │               │                                      │
│  + cef.asi → cef-client.dll    │── UDP 7779 ──▶│  cef.so ⇄ gamemode  (Pawn natives)    │
│      Chromium renders UI ◀─────┼── HTTP 8080 ──│                                      │
└────────────────────────────────┘   ui/index.html└──────────────────────────────────────┘
```

## 1. Starting the game

What happens when a player presses **PLAY** (`src/main.js` (sa-mp-cef-launcher)):

1. **Sync the CEF runtime.** The launcher downloads `/client/manifest.json`, a list of `{path, size, sha256}`
   that the update server builds from `client-files/` at startup and whenever that folder changes.
   Each file in `%APPDATA%\Freeroam Launcher\runtime\` is compared with the list. Missing or changed files
   are downloaded, hash-checked, written as `*.part` and renamed into place.
   Paths are checked so a manifest can't write outside `runtime\`.
2. **Start the game.** The launcher runs `bin\fr-inject.exe` (`injector/src/main.rs` (sa-mp-cef-launcher)):
   ```
   fr-inject --gta <GTA dir> --dll <GTA>\samp.dll --dll <runtime>\cef.asi --
             -c -n <nick> -h <host> -p <port> --lp <runtime>
   ```
   - It calls `CreateProcessW(gta_sa.exe, CREATE_SUSPENDED)`. The arguments after `--` go to the game;
     `-c -n -h -p` are the standard SA-MP connect arguments that `samp.dll` reads.
   - For each DLL: it writes the path into the game process (`VirtualAllocEx` + `WriteProcessMemory`), then
     runs `CreateRemoteThread(LoadLibraryW)` and waits. A `NULL` module handle counts as a failure.
   - Then `ResumeThread`, and it prints `PID n`. If anything fails, the game process is terminated and the
     launcher shows the error.
   - It has to be **32-bit** because `gta_sa.exe` is 32-bit and the `LoadLibraryW` address must come from
     the 32-bit `kernel32`. It's built with a static CRT so players don't need the VC++ Redistributable.
3. **CEF loads.** `cef.asi` is samp-cef's loader (a normal DLL). It reads `--lp <dir>` from the game's
   command line and loads `<dir>\cef\cef-client.dll`. Without `--lp` it would look next to `gta_sa.exe`;
   this is what keeps the GTA folder untouched.

This replaces two things players normally need: `samp.exe`, which does the same suspended-start trick for
`samp.dll` only, and an ASI loader, which would otherwise load `cef.asi`.

## 2. Server and client handshake

1. SA-MP connects to **7777/udp**. The `OnPlayerConnect` hook in `cef.inc` calls `cef_on_player_connect`.
2. `cef-client` connects to the CEF component on **7779/udp** (game port + `cef.port_offset`, default 2).
3. The gamemode receives `OnCefInitialize(playerid, success)`:
   - **success:** `cef_create_browser(playerid, 1, "<website>/ui/index.html", hidden=false, focused=false)`
   - **no CEF** (player used plain `samp.exe`): classic dialogs are used everywhere instead.
4. The browser loads the page over HTTP → `OnCefBrowserCreated(playerid, 1, 200)`.
5. The page emits `ui:ready`, and the gamemode marks the player's UI as ready and sends `hud:init`.

`<website>` is the `website` field of `omp-server/config.json` (set by `setup.sh --website`).
The gamemode reads it once in `OnGameModeInit`.

## 3. Gamemode ⇄ UI events

All communication goes through named events, one browser per player (id `1`), one page for everything.

| Direction | Event | Arguments | Purpose |
|---|---|---|---|
| server → UI | `hud:init` | name, playerid | once, after `ui:ready` |
| server → UI | `hud` | money, online, score | every 1 s |
| server → UI | `speedo` | km/h, vehicle health, vehicle name | every 200 ms while in a vehicle |
| server → UI | `speedo:hide` | – | after leaving a vehicle |
| server → UI | `notify` | text | toast message |
| server → UI | `menu:open` / `menu:close` | tab (`vehicles`/`teleports`) | Y key, `/menu`, `/tp`, `/v` |
| UI → server | `ui:ready` | – | page loaded and listening |
| UI → server | `vehicle:spawn` | model id | menu click |
| UI → server | `tp:go` | teleport index | menu click |
| UI → server | `menu:close` | – | Esc / Y / × in the menu |

- **Pawn:** `cef_emit_event(playerid, "name", CEFINT(x), CEFSTR(s), CEFFLOAT(f))` and
  `cef_subscribe("name", "Callback")`. The callback is `Callback(playerid, const arguments[])`, where all
  arguments arrive as **one space-separated string**.
- **JS:** `cef.emit("name", ...)`, `cef.on("name", fn)`. Outside the game `window.cef` doesn't exist and
  `index.html` falls back to a stub, so the page can be developed in a normal browser.
- **Focus:** while the menu is open, the gamemode calls `cef_focus_browser(..., true)` so the page gets
  mouse and keyboard input. On close it's set back to `false`.
- The teleport list exists twice: `gTeleports` in `freeroam.pwn` and `TELEPORTS` in `index.html`.
  **The order must match**, because the UI sends an index.

## 4. Updates

There are three independent update paths, each matching how often that part changes:

| What | Trigger | Mechanism |
|---|---|---|
| In-game UI | edit `ui/` | Loaded over HTTP on every connect, so players only need to reconnect |
| CEF runtime | new files in `client-files/` | Manifest + SHA-256 diff on every PLAY (only changed files are downloaded) |
| Launcher | `build.bat` (sa-mp-cef-launcher) | `electron-updater` (generic provider) reads `/launcher/latest.yml` at startup and every 30 min, downloads the new NSIS installer in the background, then shows "Restart & update" or installs when the app quits |

The installer must be uploaded **before** `latest.yml` (`build.bat` does this when uploading over SSH,
and prints the order for manual uploads), so a launcher never sees a version whose file
isn't there yet. It keeps the 3 newest installers on the server.

## 5. Building samp-cef

samp-cef has no current binary releases, so both halves are built from source.
**Client and server must come from the same commit**, because they share a network protocol.
That commit is pinned in `cef-version.txt`.

| Half | Script | Output |
|---|---|---|
| Server: open.mp component, i686 Linux | `build-cef-server.sh` | `omp-server/components/cef.so` |
| Client: Windows x86 | `build-cef-client.ps1` (sa-mp-cef-launcher) | `cef-client/` → `client-files/` |

- The server build compiles samp-cef's Rust core for `i686-unknown-linux-gnu` and its C++ open.mp wrapper
  with `-m32`, against the open.mp SDK of the same version as the server. Sources go to a temp dir that is
  deleted afterwards. The result is installed by rename, so it's safe to run while the server is up.
- The client build downloads the pinned official CEF distribution (checksum-verified by samp-cef's own
  script), builds `cef-client`, `cef-renderer` and `cef-loader` for `i686-pc-windows-msvc`, and packages
  them with all CEF runtime files.

## 6. Server processes

`server.sh` runs two `screen` sessions:

- `fr-game`: `omp-server`, logging to `omp-server/console.log`
- `fr-web`: `node update-server/server.js`, logging to `update-server/server.log`

`stop` sends SIGTERM, waits up to 10 s, then SIGKILL. Without this, an old `omp-server` can survive and keep
port 7779 bound, so the new server's CEF component fails with "Address already in use".
Neither process starts on boot. Add systemd units if you need that.

## 7. Files players end up with

```
%LOCALAPPDATA%\Programs\freeroam-launcher\     installed launcher (+ resources\bin\fr-inject.exe)
%APPDATA%\Freeroam Launcher\settings.json      nickname, GTA path
%APPDATA%\Freeroam Launcher\runtime\           cef.asi, cef\ (CEF runtime), cef_client.log
%APPDATA%\Freeroam Launcher\runtime\cef\user_data\   browser cache/cookies
%LOCALAPPDATA%\freeroam-launcher-updater\      downloaded launcher updates
```

Nothing is written to the GTA folder. If a player still has an old `cef.asi` there (and an ASI loader),
CEF would load twice, so the launcher warns about it.
