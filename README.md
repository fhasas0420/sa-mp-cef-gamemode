# sa-mp-cef-gamemode

Freeroam / stunt gamemode for **GTA San Andreas multiplayer** on [open.mp](https://open.mp), with an
in-game **HTML/CSS/JS interface** powered by [samp-cef](https://github.com/ZOTTCE/samp-cef).

- **Gamemode:** vehicle spawner, teleports, stunt bonuses, nitro, `/fix`, `/flip`, `/skin`, `/time`, `/weather`
- **CEF UI:** HUD, speedometer, vehicle/teleport menu (`Y`), toast notifications
- **Update server:** delivers the UI, the CEF client files and launcher updates to players

Players connect with **[sa-mp-cef-launcher](https://github.com/fhasas0420/sa-mp-cef-launcher)**, which
installs the CEF client and starts the game. Players with plain SA-MP can still join; they get classic
dialogs instead of the UI.

More documentation:
- **[docs/GAMEMODE.md](docs/GAMEMODE.md)**: what the gamemode does, a tour of `freeroam.pwn`, and recipes
  (add a teleport, a command, a menu item, a new UI event)
- **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)**: how the server, launcher and CEF fit together

---

## Full setup, step by step

The project has two parts that live on two machines:

| | Machine | Repo |
|---|---|---|
| **Server** | Linux (Ubuntu/Debian x86_64), runs 24/7 | this repo |
| **Build PC** | Windows 10/11, where you build the launcher | [sa-mp-cef-launcher](https://github.com/fhasas0420/sa-mp-cef-launcher) |

Do the steps **in this order**. Steps 1–4 happen on the server; steps 5–8 happen on the Windows PC.

### Step 1: Install the system packages (server, once)

```bash
sudo dpkg --add-architecture i386
sudo apt update
sudo apt install -y git nodejs screen libc6:i386 libstdc++6:i386
```

open.mp is a 32-bit program, so it needs the `:i386` libraries. Node.js runs the update server.

### Step 2: Download and set up the gamemode (server)

```bash
cd ~
git clone https://github.com/fhasas0420/sa-mp-cef-gamemode.git
cd sa-mp-cef-gamemode
./setup.sh --website http://YOUR_SERVER_IP:8080
```

Replace `YOUR_SERVER_IP` with the address **players** use to reach the server: your public IP, or a LAN IP
like `192.168.1.50` for a home network. `setup.sh`:
- checks the 32-bit libraries;
- generates an RCON password (it prints it, so save it) and leaves RCON disabled;
- writes the `website` address into `omp-server/config.json`;
- compiles the gamemode.

### Step 3: Open the ports (server)

| Port | Protocol | Used for |
|---|---|---|
| 7777 | UDP | the game (SA-MP connection) |
| 7779 | UDP | CEF (the in-game UI's data channel, always game port + 2) |
| 8080 | TCP | update server (UI page, CEF files, launcher downloads, server status) |

```bash
sudo ufw allow 7777/udp
sudo ufw allow 7779/udp
sudo ufw allow 8080/tcp
```

For players outside your home network, also **forward these three ports on your router** to the
server's LAN IP.

### Step 4: Start the server (server)

```bash
./server.sh start
```

Expected output:
```
game:   running
web:    running
cef:    listening on 7779
```

Check it from any browser: `http://YOUR_SERVER_IP:8080/api/status` should show `"online":true`.

At this point people can already join with plain SA-MP at `YOUR_SERVER_IP:7777` (dialogs, no UI).
Steps 5–8 add the launcher and the CEF UI.

### Step 5: Prepare the Windows build PC

Follow **[sa-mp-cef-launcher → Setup](https://github.com/fhasas0420/sa-mp-cef-launcher#setup-step-by-step)**:
install the build tools, set your server address, and choose how files get to the server: copy them
yourself (any server), or upload them automatically over SSH (optional).

### Step 6: Build the CEF client package (Windows, once)

Described in the launcher README. It builds the in-game browser (`cef.asi` + `cef/`, about 340 MB), which
must end up in **`client-files/`** here. It's **required once**, because the package is too big for git,
and again only when you change `cef-version.txt`.

### Step 7: Build and publish the launcher (Windows)

Double-click `build.bat` in the launcher repo. The installer and `latest.yml` must end up in
**`launcher-releases/`** here (`latest.yml` last).

### Step 8: Give players the download link

```
http://YOUR_SERVER_IP:8080/launcher/download
```

That's it. From now on, see **Day-to-day** below.

---

## Day-to-day

| You want to change | Edit (in this repo) | Then |
|---|---|---|
| Gamemode logic, commands | `omp-server/gamemodes/freeroam.pwn` | `./server.sh rebuild` |
| In-game UI look | `ui/index.html` | nothing; players see it when they reconnect |
| Launcher news | `update-server/news.json` | nothing; shown immediately |
| Server name, max players | `omp-server/config.json` | `./server.sh restart` |
| The launcher | the launcher repo | `build.bat` there; players update automatically |

**`server.sh` commands:**

| Command | What it does |
|---|---|
| `./server.sh start` | start the game server and update server (if not running) |
| `./server.sh stop` | stop both |
| `./server.sh restart` | stop + start |
| `./server.sh status` | show what's running |
| `./server.sh compile` | compile the gamemode only (shows errors with line numbers) |
| `./server.sh rebuild` | compile, then restart the game server if the compile succeeded |

**Console and logs:**
- `screen -r fr-game` opens the live game console; `screen -r fr-web` opens the update server's. Leave
  with **Ctrl+A, then D**. Ctrl+C would stop the server.
- Logs are in `omp-server/console.log` and `update-server/server.log`.
- The servers don't start automatically after a reboot. Run `./server.sh start` again, or add a systemd service.

## Contents of this repo

```
omp-server/                    ready-to-run open.mp 1.6.7 server (Linux x86)
  gamemodes/freeroam.pwn        the gamemode source (+ compiled freeroam.amx)
  components/cef.so             samp-cef open.mp component (built from cef-version.txt)
  qawno/pawncc, qawno/include/  Pawn compiler + includes (incl. cef.inc)
  config.json                   server config (setup.sh fills in RCON password + website)
ui/index.html                 in-game CEF interface
update-server/server.js       HTTP :8080: UI, client files, launcher releases, status, news
update-server/news.json       launcher news feed
setup.sh                      first-time setup (step 2)
server.sh                     start / stop / restart / status / compile / rebuild
build-cef-server.sh           rebuilds cef.so (only when changing cef-version.txt)
cef-version.txt               samp-cef commit (must match the launcher repo)
client-files/                 (created by setup, not in git) CEF package the launcher downloads
launcher-releases/            (created by setup, not in git) launcher installers + latest.yml
```

## Configuration

| Setting | Where |
|---|---|
| Server name, max players, RCON | `omp-server/config.json` |
| UI address | `website` in `config.json`; the gamemode loads `<website>/ui/index.html`. Set by `setup.sh --website` |
| Update server port / game port | environment variables `PORT` / `GAME_PORT` (default 8080 / 7777) |
| Address shown in the launcher | environment variable `PUBLIC_HOST` (default: whatever address the launcher used) |

Your local changes to `config.json` (password, website) are kept out of git commits automatically
(`setup.sh` runs `git update-index --skip-worktree`). To commit config changes on purpose, run
`git update-index --no-skip-worktree omp-server/config.json` first.

## Updating samp-cef (advanced)

Only when you want a newer samp-cef. Client and server **must** use the same commit.
1. Put the new commit hash into `cef-version.txt` here **and** in the launcher repo.
2. Server: `sudo apt install -y cmake ninja-build gcc-multilib g++-multilib`,
   install Rust (`curl https://sh.rustup.rs -sSf | sh`), then `./build-cef-server.sh` and `./server.sh restart`.
3. Windows: run `build-cef-client.ps1` in the launcher repo and put the result into `client-files/`.

## Troubleshooting

| Problem | Fix |
|---|---|
| `setup.sh`: "open.mp needs 32-bit libraries" | Do step 1 (`libc6:i386 libstdc++6:i386`). |
| `cef: NOT listening`, or the log says `failed to bind CEF server ... Address already in use` | An old server process is still running. Run `./server.sh restart`, which stops it properly. |
| `/api/status` doesn't load from another PC | Port 8080/tcp is blocked: check `ufw` and router forwarding (step 3). |
| In game: "CEF not detected" | The player started with plain `samp.exe` instead of the launcher, or port 7779/udp is blocked. |
| In game: "UI failed to load" | `website` in `config.json` is wrong or not reachable for players. Re-run `./setup.sh --website ...` and `./server.sh restart`. |
| Compile errors | `./server.sh compile` shows the file and line. See [docs/GAMEMODE.md](docs/GAMEMODE.md). |

## Security note

The update server uses plain HTTP. File hashes protect against broken downloads, not against someone
tampering with network traffic. For a public server, put it behind HTTPS (Caddy or nginx with Let's
Encrypt) and use `https://` in `website` and in the launcher config.

## License

[GPL-3.0](LICENSE). Uses [samp-cef](https://github.com/ZOTTCE/samp-cef) (GPL-3.0; the exact source is the
commit in `cef-version.txt`) and includes the [open.mp](https://github.com/openmultiplayer/open.mp) 1.6.7.3218
server binaries (MPL-2.0, see `omp-server/LICENSE-open.mp.md`; source at the
[v1.6.7.3218 tag](https://github.com/openmultiplayer/open.mp/tree/v1.6.7.3218)).
Not affiliated with Rockstar Games, Take-Two, SA-MP or open.mp. Contains no game files.
