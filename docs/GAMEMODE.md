# The gamemode

The gameplay lives in two files that work as a pair:

| File | Language | Runs on | Job |
|---|---|---|---|
| `omp-server/gamemodes/freeroam.pwn` | Pawn | the server | all game logic: vehicles, teleports, commands, what to show to whom |
| `ui/index.html` | HTML/CSS/JS | each player's game (CEF) | how it looks: HUD, speedometer, menu, notifications |

The **server decides**, and the **UI only displays and reports clicks**. The UI never changes the game by
itself. It sends a request (for example "spawn model 411"), and the gamemode checks it and does it.

## What players get

| Feature | How |
|---|---|
| Spawn | LS Airport, with a parachute. 15 skins in class selection |
| Menu | **Y** (or `/menu`): *Vehicles* tab (categories + search) and *Teleports* tab (12 locations) |
| Vehicles | `/v infernus` or `/v 411`. One personal vehicle per player: spawning a new one deletes the old one, and leaving the server deletes it too |
| Teleports | `/tp` opens the list. Drivers are teleported **with** their vehicle |
| Nitro | press **FIRE** while driving (re-adds nitro every time) |
| Commands | `/help` `/fix` `/flip` `/skin <0-311>` `/time <0-23>` `/weather <0-45>` `/kill` |
| HUD | money, name, ID and players online (top right). Speedometer with km/h, vehicle name and health bar while driving |
| Money | stunt bonuses (built into the game), plus $500 per kill |
| Without CEF | everything still works. The menu becomes classic SA-MP dialogs, and messages go to chat |

## Tour of `freeroam.pwn`

Read it top to bottom. It's 489 lines, in this order:

| Section | What's there |
|---|---|
| **Settings** (`#define`s) | browser ID, UI path, dialog IDs, chat colors |
| **`gPlayer[]`** | per-player state: has CEF?, UI loaded?, menu open?, their vehicle ID, last speed |
| **`gTeleports[]`** | teleport list: name, x, y, z, facing angle |
| **`gVehicleNames[]`** | names of all 212 vehicle models (400–611), used by `/v <name>` and the speedometer |
| **`IsBlockedModel`** | trains, trailers and the RC cam can't be spawned |
| **Helpers** | `Notify` (toast or chat), `SpawnPlayerVehicle`, `TeleportPlayer`, `OpenMenu`/`CloseMenu`, the fallback dialogs |
| **Lifecycle** | `OnGameModeInit` (UI address from `config.json`, skins, event subscriptions, timer), connect/disconnect/spawn/death |
| **CEF callbacks** | `OnCefInitialize` → create the browser. `OnUiReady`, `OnUiVehicleSpawn`, `OnUiTeleport`, `OnUiMenuClose` handle clicks from the UI |
| **`UiTick`** | timer, 5 times per second: sends the speedometer, and the HUD once per second |
| **Input** | Y key and FIRE nitro (`OnPlayerKeyStateChange`), dialog answers, all `/commands` |

### Life of a player

```
connect ──▶ OnPlayerConnect          reset gPlayer[], welcome message
        ──▶ OnCefInitialize(ok)      has CEF? → cef_create_browser(<website>/ui/index.html)
                                     no CEF?  → chat note, dialogs will be used
        ──▶ (page loads) "ui:ready"  → OnUiReady: mark UI ready, send hud:init (name, id)
        ──▶ UiTick every 200 ms      → "speedo" while driving, "hud" every 1 s
press Y ──▶ OpenMenu                 → "menu:open" + cef_focus_browser(true)  (mouse goes to the UI)
click   ──▶ "vehicle:spawn 411"      → OnUiVehicleSpawn → SpawnPlayerVehicle → "menu:close" + focus off
leave   ──▶ OnPlayerDisconnect       destroy their vehicle
```

## How the server and the UI talk

Through **named events**. The full list is in [ARCHITECTURE.md](ARCHITECTURE.md#3-gamemode--ui-events).

```pawn
// Pawn → UI
cef_emit_event(playerid, "notify", CEFSTR("Hello!"));
cef_emit_event(playerid, "hud", CEFINT(money), CEFINT(online), CEFINT(score));

// UI → Pawn: subscribe once in OnGameModeInit ...
cef_subscribe("tp:go", "OnUiTeleport");
// ... and handle it. All arguments arrive as ONE string, separated by spaces.
forward OnUiTeleport(player_id, const arguments[]);
public OnUiTeleport(player_id, const arguments[]) { TeleportPlayer(player_id, strval(arguments)); return 1; }
```

```js
// in ui/index.html
bridge.on("notify", text => { /* show it */ });
bridge.emit("tp:go", 3);
```

**Rule:** treat everything coming from the UI as untrusted input, like chat. Check the values in Pawn,
the way `SpawnPlayerVehicle` checks the model range and `TeleportPlayer` checks the index.

## Recipes

After editing `freeroam.pwn`, run **`./server.sh rebuild`** (compile + restart). For `ui/index.html`, players
just **reconnect**.

### Add a teleport

1. `freeroam.pwn`: add a line at the **end** of `gTeleports`:
   ```pawn
   {"Los Santos Forum",       2781.0, -1813.0,  11.8,  90.0}
   ```
   To get coordinates, stand at the spot in game and type `/save`. That's a SA-MP client command; it
   writes x, y, z and angle to `Documents\GTA San Andreas User Files\SAMP\savedpositions.txt`.
2. `ui/index.html`: add the same entry at the **same position** in `TELEPORTS`:
   ```js
   ["Los Santos Forum", "Los Santos"]
   ```
   The UI sends the **index**, so the order in both lists must match.

### Add a command

In `OnPlayerCommandText`, next to the others:
```pawn
if (!strcmp(cmd, "/heal", true)) {
    SetPlayerHealth(playerid, 100.0);
    Notify(playerid, "Healed.", COLOR_OK);
    return 1;
}
```
`cmd` is the command word and `params` is everything after it. Add it to the `/help` text too.

### Add vehicles to the menu

`ui/index.html` only: add model IDs to a category in `VEHICLES` (or make a new category), and make sure
each ID has a name in `NAMES`.
```js
"Muscle": [402, 475, 496, 517, 518, 526, 527, 542, 549, 589],
```
The menu's **search only knows the models listed in `NAMES`** (about 70 popular ones). `/v <name>` in chat
knows all 212.

### Send something new to the UI

Example: show a "Wanted" level.

```pawn
// freeroam.pwn, wherever it changes
cef_emit_event(playerid, "wanted", CEFINT(GetPlayerWantedLevel(playerid)));
```
```html
<!-- ui/index.html: element + handler -->
<div id="wanted"></div>
<script>
bridge.on("wanted", level => { $("wanted").textContent = "★".repeat(level); });
</script>
```
Only send to players whose UI is ready (`gPlayer[playerid][pUiReady]`), as `Notify` and `UiTick` do.

### Receive something new from the UI

```js
// ui/index.html, e.g. a button
bridge.emit("skin:set", 101);
```
```pawn
// freeroam.pwn, OnGameModeInit
cef_subscribe("skin:set", "OnUiSkinSet");

forward OnUiSkinSet(player_id, const arguments[]);
public OnUiSkinSet(player_id, const arguments[])
{
    new skin = strval(arguments);
    if (skin < 0 || skin > 311 || skin == 74) return 1;   // validate!
    SetPlayerSkin(player_id, skin);
    return 1;
}
```

### Change the spawn point or skins

`OnGameModeInit`: the `skins[]` list and the coordinates in `AddPlayerClass` set where players spawn.
`OnPlayerRequestClass` sets where the class-selection camera looks.

## Working on the UI without the game

Open `http://<server>:8080/ui/index.html` in a normal browser. Outside the game `window.cef` doesn't exist,
so the page uses a stub: everything the page would send is logged to the console, and you can trigger
server events by hand in DevTools:

```js
__h["menu:open"]("vehicles")
__h["speedo"](142, 800, "Infernus")
__h["hud"](25000, 3, 0)
__h["notify"]("Hello from DevTools")
```

The page background is transparent, because in game it sits on top of GTA.

## Good to know

- **One browser per player.** The whole UI is one page (browser ID `1`). That's samp-cef's recommendation
  for performance: add new screens as parts of `index.html` instead of new browsers.
- **Menu focus.** While a browser is focused it takes all mouse and keyboard input, so the game doesn't
  get Y. That's why the page itself closes the menu on Y/Esc and sends `menu:close` to the server.
- **Players without CEF** are first-class: every feature has a chat or dialog path. Keep it that way when
  adding features (`Notify` does it automatically for messages).
- **`MAX_PLAYERS` is 100** in the script. Raise it if `max_players` in `config.json` is higher.
- **Compiler:** `omp-server/qawno/pawncc` with open.mp's includes. `./server.sh compile` shows errors with
  line numbers. Includes go in `omp-server/qawno/include/`.
