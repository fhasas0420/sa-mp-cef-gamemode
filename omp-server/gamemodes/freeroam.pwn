// =====================================================================
//  Freeroam / Stunt gamemode for open.mp with samp-cef UI
//  UI:  <website>/ui/index.html, where <website> is "website" in config.json
//       (e.g. "http://203.0.113.10:8080", served by update-server)
//  Keys: Y = open menu (vehicles / teleports), CEF players
//        players without CEF get classic dialogs as fallback
//  Guide: docs/GAMEMODE.md (structure, events, how to add teleports/commands/UI)
// =====================================================================
#define MAX_PLAYERS 100
#include <open.mp>
#include <cef>

#define UI_BROWSER_ID     1
#define UI_PATH           "/ui/index.html"
#define DIALOG_VEHICLES   100
#define DIALOG_TELEPORTS  101
#define COLOR_INFO        0x4FC3F7FF
#define COLOR_ERR         0xFF6B6BFF
#define COLOR_OK          0x7CE38BFF

enum E_PLAYER {
	bool:pCef,          // has CEF plugin
	bool:pUiReady,      // browser created + page loaded
	bool:pMenuOpen,
	pVehicle,           // personal spawned vehicle id
	pLastSpeed
}
new gPlayer[MAX_PLAYERS][E_PLAYER];
new gUiUrl[160];    // built in OnGameModeInit from config.json "website"

// ---------------------------------------------------------------------
// Teleports (index must match TELEPORTS in ui/index.html)
// ---------------------------------------------------------------------
enum E_TP { tpName[32], Float:tpX, Float:tpY, Float:tpZ, Float:tpA }
new const gTeleports[][E_TP] = {
	{"LS Airport",            1961.0, -2193.0,  13.5,  90.0},
	{"SF Airport",           -1404.0,  -260.0,  14.1, 315.0},
	{"LV Airport",            1477.0,  1240.0,  10.8,   0.0},
	{"Mount Chiliad",        -2324.0, -1626.0, 483.7, 210.0},
	{"Grove Street",          2495.0, -1687.0,  13.5,   0.0},
	{"LV Strip",              2035.0,  1340.0,  10.8, 270.0},
	{"Santa Maria Beach",      370.0, -1830.0,   7.6,  90.0},
	{"Vinewood Sign",         1415.0,  -805.0,  85.0, 180.0},
	{"Aircraft Graveyard",     412.0,  2524.0,  16.5,  90.0},
	{"Sherman Dam",           -890.0,  1980.0,  60.0, 270.0},
	{"Big Ear",               -326.0,  1530.0,  75.4, 180.0},
	{"SF Downtown",          -1975.0,   600.0,  35.0,   0.0}
};

// ---------------------------------------------------------------------
// Vehicle names, model 400..611
// ---------------------------------------------------------------------
new const gVehicleNames[212][] = {
	"Landstalker","Bravura","Buffalo","Linerunner","Perenniel","Sentinel","Dumper","Firetruck","Trashmaster","Stretch",
	"Manana","Infernus","Voodoo","Pony","Mule","Cheetah","Ambulance","Leviathan","Moonbeam","Esperanto",
	"Taxi","Washington","Bobcat","Mr Whoopee","BF Injection","Hunter","Premier","Enforcer","Securicar","Banshee",
	"Predator","Bus","Rhino","Barracks","Hotknife","Trailer 1","Previon","Coach","Cabbie","Stallion",
	"Rumpo","RC Bandit","Romero","Packer","Monster","Admiral","Squalo","Seasparrow","Pizzaboy","Tram",
	"Trailer 2","Turismo","Speeder","Reefer","Tropic","Flatbed","Yankee","Caddy","Solair","Berkley's RC Van",
	"Skimmer","PCJ-600","Faggio","Freeway","RC Baron","RC Raider","Glendale","Oceanic","Sanchez","Sparrow",
	"Patriot","Quad","Coastguard","Dinghy","Hermes","Sabre","Rustler","ZR-350","Walton","Regina",
	"Comet","BMX","Burrito","Camper","Marquis","Baggage","Dozer","Maverick","News Chopper","Rancher",
	"FBI Rancher","Virgo","Greenwood","Jetmax","Hotring","Sandking","Blista Compact","Police Maverick","Boxville","Benson",
	"Mesa","RC Goblin","Hotring Racer A","Hotring Racer B","Bloodring Banger","Rancher","Super GT","Elegant","Journey","Bike",
	"Mountain Bike","Beagle","Cropdust","Stunt","Tanker","RoadTrain","Nebula","Majestic","Buccaneer","Shamal",
	"Hydra","FCR-900","NRG-500","HPV1000","Cement Truck","Tow Truck","Fortune","Cadrona","FBI Truck","Willard",
	"Forklift","Tractor","Combine","Feltzer","Remington","Slamvan","Blade","Freight","Streak","Vortex",
	"Vincent","Bullet","Clover","Sadler","Firetruck LA","Hustler","Intruder","Primo","Cargobob","Tampa",
	"Sunrise","Merit","Utility","Nevada","Yosemite","Windsor","Monster A","Monster B","Uranus","Jester",
	"Sultan","Stratum","Elegy","Raindance","RC Tiger","Flash","Tahoma","Savanna","Bandito","Freight Flat",
	"Streak Carriage","Kart","Mower","Duneride","Sweeper","Broadway","Tornado","AT-400","DFT-30","Huntley",
	"Stafford","BF-400","Newsvan","Tug","Trailer 3","Emperor","Wayfarer","Euros","Hotdog","Club",
	"Freight Carriage","Trailer 3","Andromada","Dodo","RC Cam","Launch","Police Car (LSPD)","Police Car (SFPD)","Police Car (LVPD)","Police Ranger",
	"Picador","S.W.A.T. Van","Alpha","Phoenix","Glendale","Sadler","Luggage Trailer A","Luggage Trailer B","Stair Trailer","Boxville",
	"Farm Plow","Utility Trailer"
};

// Models that cannot be spawned/driven alone (trains, trailers, RC cam)
stock bool:IsBlockedModel(model)
{
	switch (model) {
		case 435, 449, 450, 537, 538, 569, 570, 584, 590, 591, 594, 606, 607, 608, 610, 611:
			return true;
	}
	return false;
}

stock FindVehicleModel(const query[])
{
	new id = strval(query);
	if (id >= 400 && id <= 611) return id;
	for (new i = 0; i < sizeof gVehicleNames; i++) {
		if (strfind(gVehicleNames[i], query, true) != -1) return i + 400;
	}
	return -1;
}

// ---------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------
stock Notify(playerid, const text[], color = COLOR_INFO)
{
	if (gPlayer[playerid][pUiReady]) {
		cef_emit_event(playerid, "notify", CEFSTR(text));
	} else {
		SendClientMessage(playerid, color, text);
	}
	return 1;
}

stock SpawnPlayerVehicle(playerid, model)
{
	if (model < 400 || model > 611 || IsBlockedModel(model)) {
		Notify(playerid, "That vehicle cannot be spawned.", COLOR_ERR);
		return 0;
	}
	if (GetPlayerInterior(playerid) != 0) {
		Notify(playerid, "You cannot spawn vehicles inside interiors.", COLOR_ERR);
		return 0;
	}

	new Float:x, Float:y, Float:z, Float:a;
	GetPlayerPos(playerid, x, y, z);
	if (IsPlayerInAnyVehicle(playerid)) GetVehicleZAngle(GetPlayerVehicleID(playerid), a);
	else GetPlayerFacingAngle(playerid, a);

	if (gPlayer[playerid][pVehicle] != INVALID_VEHICLE_ID) {
		DestroyVehicle(gPlayer[playerid][pVehicle]);
	}

	new vid = CreateVehicle(model, x, y, z + 1.0, a, -1, -1, -1);
	if (vid == INVALID_VEHICLE_ID) {
		Notify(playerid, "Vehicle limit reached, try again later.", COLOR_ERR);
		return 0;
	}
	LinkVehicleToInterior(vid, 0);
	SetVehicleVirtualWorld(vid, GetPlayerVirtualWorld(playerid));
	PutPlayerInVehicle(playerid, vid, 0);
	gPlayer[playerid][pVehicle] = vid;

	new msg[64];
	format(msg, sizeof msg, "Spawned %s", gVehicleNames[model - 400]);
	Notify(playerid, msg, COLOR_OK);
	return 1;
}

stock TeleportPlayer(playerid, idx)
{
	if (idx < 0 || idx >= sizeof gTeleports) return 0;

	SetPlayerInterior(playerid, 0);
	if (IsPlayerInAnyVehicle(playerid) && GetPlayerState(playerid) == PLAYER_STATE_DRIVER) {
		new vid = GetPlayerVehicleID(playerid);
		LinkVehicleToInterior(vid, 0);
		SetVehiclePos(vid, gTeleports[idx][tpX], gTeleports[idx][tpY], gTeleports[idx][tpZ] + 1.0);
		SetVehicleZAngle(vid, gTeleports[idx][tpA]);
		PutPlayerInVehicle(playerid, vid, 0);
	} else {
		SetPlayerPos(playerid, gTeleports[idx][tpX], gTeleports[idx][tpY], gTeleports[idx][tpZ]);
		SetPlayerFacingAngle(playerid, gTeleports[idx][tpA]);
	}
	SetCameraBehindPlayer(playerid);

	new msg[64];
	format(msg, sizeof msg, "Teleported to %s", gTeleports[idx][tpName]);
	Notify(playerid, msg, COLOR_OK);
	return 1;
}

stock OpenMenu(playerid, const tab[] = "vehicles")
{
	if (gPlayer[playerid][pUiReady]) {
		gPlayer[playerid][pMenuOpen] = true;
		cef_emit_event(playerid, "menu:open", CEFSTR(tab));
		cef_focus_browser(playerid, UI_BROWSER_ID, true);
		return;
	}
	// Fallback for players without CEF
	if (!strcmp(tab, "teleports")) ShowTeleportDialog(playerid);
	else ShowVehicleDialog(playerid);
}

stock CloseMenu(playerid)
{
	gPlayer[playerid][pMenuOpen] = false;
	if (gPlayer[playerid][pUiReady]) {
		cef_focus_browser(playerid, UI_BROWSER_ID, false);
	}
}

stock ShowVehicleDialog(playerid)
{
	ShowPlayerDialog(playerid, DIALOG_VEHICLES, DIALOG_STYLE_INPUT, "Spawn vehicle",
		"Enter a vehicle name or model ID (400-611):", "Spawn", "Cancel");
}

stock ShowTeleportDialog(playerid)
{
	new list[512];
	for (new i = 0; i < sizeof gTeleports; i++) {
		strcat(list, gTeleports[i][tpName]);
		strcat(list, "\n");
	}
	ShowPlayerDialog(playerid, DIALOG_TELEPORTS, DIALOG_STYLE_LIST, "Teleports", list, "Go", "Cancel");
}

// ---------------------------------------------------------------------
// Gamemode lifecycle
// ---------------------------------------------------------------------
main()
{
	print("[freeroam] Freeroam / Stunt gamemode loaded");
}

public OnGameModeInit()
{
	SetGameModeText("Freeroam / Stunt");

	// UI address = config.json "website" + /ui/index.html
	GetConsoleVarAsString("website", gUiUrl, sizeof gUiUrl);
	new len = strlen(gUiUrl);
	if (len && gUiUrl[len - 1] == '/') gUiUrl[len - 1] = EOS;
	if (strfind(gUiUrl, "http", true) != 0) {
		print("[freeroam] WARNING: config.json \"website\" is not an http(s) URL - CEF UI disabled");
		gUiUrl[0] = EOS;
	} else {
		strcat(gUiUrl, UI_PATH);
		printf("[freeroam] CEF UI: %s", gUiUrl);
	}
	UsePlayerPedAnims();
	EnableStuntBonusForAll(true);
	ShowPlayerMarkers(PLAYER_MARKERS_MODE_GLOBAL);

	// A handful of skins to choose from
	new const skins[] = {0, 2, 23, 29, 46, 60, 101, 170, 188, 250, 12, 40, 55, 91, 193};
	for (new i = 0; i < sizeof skins; i++) {
		AddPlayerClass(skins[i], 1961.0, -2193.0, 13.5, 90.0, WEAPON_FIST, 0, WEAPON_FIST, 0, WEAPON_FIST, 0);
	}

	// Events coming from the CEF UI
	cef_subscribe("ui:ready",      "OnUiReady");
	cef_subscribe("menu:close",    "OnUiMenuClose");
	cef_subscribe("vehicle:spawn", "OnUiVehicleSpawn");
	cef_subscribe("tp:go",         "OnUiTeleport");

	SetTimer("UiTick", 200, true);
	return 1;
}

public OnPlayerConnect(playerid)
{
	gPlayer[playerid][pCef] = false;
	gPlayer[playerid][pUiReady] = false;
	gPlayer[playerid][pMenuOpen] = false;
	gPlayer[playerid][pVehicle] = INVALID_VEHICLE_ID;
	gPlayer[playerid][pLastSpeed] = -1;

	SendClientMessage(playerid, COLOR_INFO, "Welcome to Freeroam! Press Y for the menu, /help for commands.");
	return 1;
}

public OnPlayerDisconnect(playerid, reason)
{
	if (gPlayer[playerid][pVehicle] != INVALID_VEHICLE_ID) {
		DestroyVehicle(gPlayer[playerid][pVehicle]);
		gPlayer[playerid][pVehicle] = INVALID_VEHICLE_ID;
	}
	return 1;
}

public OnPlayerRequestClass(playerid, classid)
{
	SetPlayerPos(playerid, 1958.0, 1343.0, 15.4);
	SetPlayerFacingAngle(playerid, 270.0);
	SetPlayerCameraPos(playerid, 1963.0, 1343.0, 16.4);
	SetPlayerCameraLookAt(playerid, 1958.0, 1343.0, 15.4);
	return 1;
}

public OnPlayerSpawn(playerid)
{
	SetPlayerInterior(playerid, 0);
	GivePlayerWeapon(playerid, WEAPON_PARACHUTE, 1);
	return 1;
}

public OnPlayerDeath(playerid, killerid, WEAPON:reason)
{
	if (killerid != INVALID_PLAYER_ID) GivePlayerMoney(killerid, 500);
	return 1;
}

// ---------------------------------------------------------------------
// CEF callbacks
// ---------------------------------------------------------------------
public OnCefInitialize(player_id, success)
{
	gPlayer[player_id][pCef] = (success == 1);
	if (success == 1 && gUiUrl[0]) {
		cef_create_browser(player_id, UI_BROWSER_ID, gUiUrl, false, false);
	} else if (success == 1) {
		SendClientMessage(player_id, COLOR_ERR, "The server's UI is not configured - classic menus enabled.");
	} else {
		SendClientMessage(player_id, COLOR_ERR, "CEF not detected - use our launcher for the full UI. Classic menus enabled.");
	}
	return 1;
}

public OnCefBrowserCreated(player_id, browser_id, status_code)
{
	if (browser_id != UI_BROWSER_ID) return 1;
	if (status_code != 200) {
		printf("[freeroam] UI failed to load for %d (HTTP %d)", player_id, status_code);
		SendClientMessage(player_id, COLOR_ERR, "UI failed to load - classic menus enabled.");
		return 1;
	}
	return 1;
}

forward OnUiReady(player_id, const arguments[]);
public OnUiReady(player_id, const arguments[])
{
	gPlayer[player_id][pUiReady] = true;
	new name[MAX_PLAYER_NAME];
	GetPlayerName(player_id, name, sizeof name);
	cef_emit_event(player_id, "hud:init", CEFSTR(name), CEFINT(player_id));
	return 1;
}

forward OnUiMenuClose(player_id, const arguments[]);
public OnUiMenuClose(player_id, const arguments[])
{
	CloseMenu(player_id);
	return 1;
}

forward OnUiVehicleSpawn(player_id, const arguments[]);
public OnUiVehicleSpawn(player_id, const arguments[])
{
	if (GetPlayerState(player_id) == PLAYER_STATE_WASTED || GetPlayerState(player_id) == PLAYER_STATE_SPECTATING) return 1;
	if (SpawnPlayerVehicle(player_id, strval(arguments))) {
		CloseMenu(player_id);
		cef_emit_event(player_id, "menu:close");
	}
	return 1;
}

forward OnUiTeleport(player_id, const arguments[]);
public OnUiTeleport(player_id, const arguments[])
{
	if (GetPlayerState(player_id) == PLAYER_STATE_WASTED || GetPlayerState(player_id) == PLAYER_STATE_SPECTATING) return 1;
	if (TeleportPlayer(player_id, strval(arguments))) {
		CloseMenu(player_id);
		cef_emit_event(player_id, "menu:close");
	}
	return 1;
}

// Pushes HUD + speedometer data to every CEF player (5x / second)
forward UiTick();
public UiTick()
{
	static tick;
	tick++;
	new online = 0;
	for (new i = 0; i < MAX_PLAYERS; i++) if (IsPlayerConnected(i)) online++;

	for (new playerid = 0; playerid < MAX_PLAYERS; playerid++) {
		if (!IsPlayerConnected(playerid) || !gPlayer[playerid][pUiReady]) continue;

		new vid = GetPlayerVehicleID(playerid);
		if (vid != 0) {
			new Float:vx, Float:vy, Float:vz, Float:hp;
			GetVehicleVelocity(vid, vx, vy, vz);
			GetVehicleHealth(vid, hp);
			new speed = floatround(VectorSize(vx, vy, vz) * 180.0);
			new model = GetVehicleModel(vid);
			cef_emit_event(playerid, "speedo", CEFINT(speed), CEFINT(floatround(hp)), CEFSTR(gVehicleNames[model - 400]));
			gPlayer[playerid][pLastSpeed] = speed;
		} else if (gPlayer[playerid][pLastSpeed] != -1) {
			cef_emit_event(playerid, "speedo:hide");
			gPlayer[playerid][pLastSpeed] = -1;
		}

		if (tick % 5 == 0) {
			cef_emit_event(playerid, "hud", CEFINT(GetPlayerMoney(playerid)), CEFINT(online), CEFINT(GetPlayerScore(playerid)));
		}
	}
	return 1;
}

// ---------------------------------------------------------------------
// Input
// ---------------------------------------------------------------------
public OnPlayerKeyStateChange(playerid, KEY:newkeys, KEY:oldkeys)
{
	if ((newkeys & KEY_YES) && !(oldkeys & KEY_YES)) {
		if (gPlayer[playerid][pMenuOpen]) {
			CloseMenu(playerid);
			if (gPlayer[playerid][pUiReady]) cef_emit_event(playerid, "menu:close");
		} else {
			OpenMenu(playerid);
		}
	}
	// Hold FIRE in a car = nitro refill
	if ((newkeys & KEY_FIRE) && IsPlayerInAnyVehicle(playerid) && GetPlayerState(playerid) == PLAYER_STATE_DRIVER) {
		AddVehicleComponent(GetPlayerVehicleID(playerid), 1010);
	}
	return 1;
}

public OnDialogResponse(playerid, dialogid, response, listitem, inputtext[])
{
	if (!response) return 1;
	switch (dialogid) {
		case DIALOG_VEHICLES: {
			new model = FindVehicleModel(inputtext);
			if (model == -1) Notify(playerid, "Unknown vehicle.", COLOR_ERR);
			else SpawnPlayerVehicle(playerid, model);
			return 1;
		}
		case DIALOG_TELEPORTS: {
			TeleportPlayer(playerid, listitem);
			return 1;
		}
	}
	return 0;
}

public OnPlayerCommandText(playerid, cmdtext[])
{
	new cmd[32], params[96];
	new space = strfind(cmdtext, " ");
	if (space == -1) {
		strcat(cmd, cmdtext);
	} else {
		strmid(cmd, cmdtext, 0, space);
		strmid(params, cmdtext, space + 1, strlen(cmdtext));
	}

	if (!strcmp(cmd, "/help", true)) {
		SendClientMessage(playerid, COLOR_INFO, "Keys: Y = menu, FIRE in car = nitro");
		SendClientMessage(playerid, COLOR_INFO, "/v <name|id>  /tp  /menu  /fix  /flip  /skin <id>  /time <h>  /weather <id>  /kill");
		return 1;
	}
	if (!strcmp(cmd, "/menu", true)) { OpenMenu(playerid, "vehicles"); return 1; }
	if (!strcmp(cmd, "/tp", true))   { OpenMenu(playerid, "teleports"); return 1; }

	if (!strcmp(cmd, "/v", true) || !strcmp(cmd, "/car", true)) {
		if (!params[0]) { OpenMenu(playerid, "vehicles"); return 1; }
		new model = FindVehicleModel(params);
		if (model == -1) Notify(playerid, "Unknown vehicle.", COLOR_ERR);
		else SpawnPlayerVehicle(playerid, model);
		return 1;
	}
	if (!strcmp(cmd, "/fix", true)) {
		if (!IsPlayerInAnyVehicle(playerid)) return Notify(playerid, "You are not in a vehicle.", COLOR_ERR), 1;
		RepairVehicle(GetPlayerVehicleID(playerid));
		Notify(playerid, "Vehicle repaired.", COLOR_OK);
		return 1;
	}
	if (!strcmp(cmd, "/flip", true)) {
		if (!IsPlayerInAnyVehicle(playerid)) return Notify(playerid, "You are not in a vehicle.", COLOR_ERR), 1;
		new vid = GetPlayerVehicleID(playerid), Float:a;
		GetVehicleZAngle(vid, a);
		SetVehicleZAngle(vid, a);
		Notify(playerid, "Vehicle flipped.", COLOR_OK);
		return 1;
	}
	if (!strcmp(cmd, "/skin", true)) {
		new skin = strval(params);
		if (!params[0] || skin < 0 || skin > 311 || skin == 74) return Notify(playerid, "Usage: /skin <0-311>", COLOR_ERR), 1;
		SetPlayerSkin(playerid, skin);
		return 1;
	}
	if (!strcmp(cmd, "/time", true)) {
		new h = strval(params);
		if (!params[0] || h < 0 || h > 23) return Notify(playerid, "Usage: /time <0-23>", COLOR_ERR), 1;
		SetPlayerTime(playerid, h, 0);
		return 1;
	}
	if (!strcmp(cmd, "/weather", true)) {
		new w = strval(params);
		if (!params[0] || w < 0 || w > 45) return Notify(playerid, "Usage: /weather <0-45>", COLOR_ERR), 1;
		SetPlayerWeather(playerid, w);
		return 1;
	}
	if (!strcmp(cmd, "/kill", true)) { SetPlayerHealth(playerid, 0.0); return 1; }
	return 0;
}
