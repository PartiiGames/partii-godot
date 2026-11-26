extends Node
## Partii for Godot (v0): the player, cloud saves and purchases (Pops items) through the Partii web SDK,
## and device motion on the web. Elsewhere (desktop, native) it falls back cleanly (README.md).
##
##   await Partii.configure("my-game", "pk_...")   # once, at start (the project's publishable key)
##   var me = await Partii.sign_in()               # {ok, player: {id, name, guest}}
##   var s = await Partii.load_slot("main")           # {ok, data, rev}; data null: no save yet
##   await Partii.save_slot("main", data)             # {ok, rev} | {ok: false, reason: "conflict", theirs}
##   await Partii.items()                          # {ok, items: [{item, count, ...}]}
##   Partii.owns("full_game")                      # from the last items() (after sign_in, refreshed by buy)
##   await Partii.buy("item_id")                   # from a tap: Partii shows the sheet, never the game
##   Partii.owns_full_game() / await Partii.unlock()  # the full game after a free intro (item full_game)
##   Partii.set_playing(true / false)              # really playing (not paused, menus, game over): counts the player
##   Partii.visibility_changed                     # signal(visible): the page was hidden or shown
##   Partii.track("level_done", {"level": 3})      # an analytics event (flat props); sessions, motion
##                                                 # changes and errors are reported on their own
##
##   Partii.motion_state()   # "native" | "unsupported" | "needs_tap" | "asking" | "reloading" | "waiting"
##                           # | "granted" | "denied"  (asking: Partii's own modal is up)
##   Partii.gravity()        # Vector3 in g, CoreMotion axes (x right, y up, z out of the screen;
##                           # flat and face up is (0, 0, -1)), the same on iOS and Android browsers
##   Partii.motion_live()    # readings in the last second: tilt can steer now
##   Partii.motion_changed   # signal(state)
##
## On iOS the browser asks for motion only from a tap: the first tap anywhere in the game asks.
## Inside Partii's frame, Partii asks first ("Motion sensors" modal, on the first tap); its yes reloads
## the game with motion allowed, and on iOS the next tap brings the browser's own question.
## On native builds gravity() is Input.get_accelerometer() in g, so one code path fits both.

signal motion_changed(state: String)
signal visibility_changed(visible: bool)

const _JS := """
(() => {
  if (window.__partii_godot) return;
  const ua = navigator.userAgent || "";
  const ios = /iPad|iPhone|iPod/.test(ua) || (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1);
  const s = window.__partii_godot = { x: 0, y: 0, z: 0, at: 0, state: "unsupported", ios, visible: document.visibilityState !== "hidden" };
  document.addEventListener("visibilitychange", () => { s.visible = document.visibilityState !== "hidden"; });
  if (typeof DeviceMotionEvent === "undefined") return;
  const G = 9.80665;
  const on = (e) => {
    const a = e.accelerationIncludingGravity;
    if (!a || a.x === null) return;
    // To CoreMotion's convention (what Godot's iOS build reported): iOS Safari already reports it
    // that way (in m/s²); Android browsers report the opposite sign.
    const k = ios ? 1 / G : -1 / G;
    s.x = a.x * k; s.y = a.y * k; s.z = (a.z ?? 0) * k; s.at = performance.now();
    if (s.state !== "granted") s.state = "granted";
  };
  const listen = () => window.addEventListener("devicemotion", on);
  // Inside Partii's frame (store jam-ui/hardware.tsx; edge jam/hardware-client.ts is Partii's own runtime
  // side): the frame has motion only once the player allowed it in Partii's modal. Say hello, hear what
  // this frame load has, and ask Partii first; its yes reloads the frame with motion allowed.
  const framed = window.parent !== window;
  let host = null; // Partii's answer to the hello: the kinds this frame has (null: none yet, or no Partii)
  let noHost = !framed;
  const asks = new Map();
  let seq = 0;
  if (framed) {
    addEventListener("message", (e) => {
      if (e.source !== window.parent || !e.data || e.data.partii !== "ui") return;
      const d = e.data;
      if (d.op === "hw" && Array.isArray(d.granted)) {
        host = new Set(d.granted.map(String));
        if (!host.has("motion") && s.state !== "granted" && s.state !== "denied") s.state = "needs_tap";
        return;
      }
      if (d.op === "hw") {
        const a = asks.get(d.id);
        if (!a) return;
        if (d.phase === "open") return a.open();
        asks.delete(d.id);
        a.done(d.result && typeof d.result === "object" ? d.result : { ok: false, reason: "error" });
      } else if (d.op === "hw-reload") location.reload();
      else if (d.op === "hw-off" && d.what === "motion") { window.removeEventListener("devicemotion", on); s.state = "denied"; }
    });
    try { window.parent.postMessage({ partii: "jam", op: "hw-hello" }, "*"); } catch (_) { noHost = true; }
  }
  const askPartii = () => new Promise((resolve) => {
    const id = "motion_" + (++seq).toString(36) + Date.now().toString(36);
    let opened = false;
    const t = setTimeout(() => { if (!opened) { asks.delete(id); resolve({ ok: false, reason: "no_host" }); } }, 1500);
    asks.set(id, { open: () => { opened = true; clearTimeout(t); }, done: (r) => { clearTimeout(t); resolve(r); } });
    try { window.parent.postMessage({ partii: "jam", op: "hw", id, want: "motion" }, "*"); } catch (_) { clearTimeout(t); resolve({ ok: false, reason: "no_host" }); }
  });
  // Partii has motion for this frame already, or there's no Partii around: the browser's own question.
  const frameHas = () => noHost || (host !== null && host.has("motion"));
  const viaPartii = () => {
    s.state = "asking";
    askPartii().then((r) => {
      if (r.reason === "reload") { s.state = "reloading"; location.reload(); return; }
      if (r.reason === "no_host") noHost = true;
      if (r.ok || r.reason === "no_host") {
        // Allowed: on iOS the browser's question needs a tap of its own; elsewhere readings just start.
        if (typeof DeviceMotionEvent.requestPermission === "function") s.state = "needs_tap";
        else { if (host) host.add("motion"); s.state = s.at ? "granted" : "waiting"; }
        return;
      }
      s.state = "denied"; // the player said no in Partii (Settings can change it)
    });
  };
  if (typeof DeviceMotionEvent.requestPermission === "function") {
    s.state = "needs_tap";
    const ask = () => {
      if (s.state !== "needs_tap") return;
      if (!frameHas()) return viaPartii();
      s.state = "waiting";
      DeviceMotionEvent.requestPermission().then(
        (r) => { if (r === "granted") { s.state = "granted"; listen(); } else s.state = "denied"; },
        () => { s.state = "needs_tap"; } // not from a gesture: the next tap asks again
      );
    };
    // Capture phase, so the ask runs inside the tap's own gesture, before the engine sees it.
    for (const t of ["touchend", "click"]) window.addEventListener(t, ask, { capture: true });
  } else {
    s.state = "waiting"; // no prompt: granted once the first reading arrives
    listen();
    // Inside Partii without motion yet (the hello says so): the first tap asks Partii.
    for (const t of ["touchend", "click"]) window.addEventListener(t, () => { if (s.state === "needs_tap") viaPartii(); }, { capture: true });
  }
})();
"""

var _web := false
var _visible := true
var _sdk: JavaScriptObject = null
## The GDExtension (native desktop builds with addons/partii/bin/), else null.
var _nat: RefCounted = null
var _cb: JavaScriptObject = null
var _next_id := 0
var _owned := {}
var _rev := {}

## One answer from the browser half (web/partii-godot.ts), by call id.
signal _reply(id: int, result: Dictionary)

var _s: JavaScriptObject = null
var _state := "native"
var _last_at := -1.0
var _last_change_ms := -100000

func _ready() -> void:
	# Motion, visibility and analytics keep going while the game is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_web = OS.has_feature("web")
	if _web:
		JavaScriptBridge.eval(_JS, true)
		_s = JavaScriptBridge.get_interface("__partii_godot")
		_state = str(_s.state) if _s else "unsupported"
		var f := FileAccess.open("res://addons/partii/partii-sdk.js", FileAccess.READ)
		if f:
			JavaScriptBridge.eval(f.get_as_text(), true)
			_sdk = JavaScriptBridge.get_interface("__partii_godot_sdk")
			_cb = JavaScriptBridge.create_callback(_on_reply)
		else:
			push_warning("Partii: partii-sdk.js isn't in the export (add addons/partii/partii-sdk.js to include_filter)")
	elif ClassDB.class_exists("PartiiNative"):
		_nat = ClassDB.instantiate("PartiiNative")

func _notification(what: int) -> void:
	if _nat == null or not _rooms_on:
		return
	if what == NOTIFICATION_APPLICATION_PAUSED:
		_nat.away()
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		_nat.back()

func _process(_delta: float) -> void:
	if _rooms_on:
		_pump_rooms()
	if _s == null:
		return
	var v := bool(_s.visible)
	if v != _visible:
		_visible = v
		visibility_changed.emit(v)
	var at := float(_s.at)
	if at != _last_at:
		_last_at = at
		_last_change_ms = Time.get_ticks_msec()
	var now := str(_s.state)
	if now != _state:
		_state = now
		motion_changed.emit(_state)
		track("motion", {"state": _state})

## Where motion stands (see the class comment).
func motion_state() -> String:
	return _state

## Readings are arriving (one in the last second): tilt can steer. Native mobile builds: always.
func motion_live() -> bool:
	if _s == null:
		return not _web
	return _state == "granted" and Time.get_ticks_msec() - _last_change_ms < 1000

## Gravity plus the device's own acceleration, in g, CoreMotion axes.
func gravity() -> Vector3:
	if _s != null:
		return Vector3(float(_s.x), float(_s.y), float(_s.z))
	if _web:
		return Vector3.ZERO
	var a := Input.get_accelerometer()
	# Godot's Android build reports m/s², its iOS build g.
	return a / 9.80665 if OS.get_name() == "Android" else a

## True on a phone or tablet browser (or a native mobile build): where tilt is the control.
func is_touch_device() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("web_ios") or OS.has_feature("web_android")


# --- Player, saves, purchases ---

func _on_reply(args: Array) -> void:
	var r = JSON.parse_string(str(args[1]))
	_reply.emit(int(args[0]), r if r is Dictionary else {"ok": false, "reason": "bad_reply"})

func _call(name: String, args: Array = []) -> Dictionary:
	if _sdk == null:
		return {"ok": false, "reason": "unavailable"}
	_next_id += 1
	var id := _next_id
	# invoke, not call: on a JavaScriptObject, call() is Godot's own Object.call.
	_sdk.invoke(name, JSON.stringify(args), id, _cb)
	while true:
		var got: Array = await _reply
		if got[0] == id:
			return got[1]
	return {}

## Partii is reachable here (a web build with the SDK bundle, or a native build with the GDExtension).
func available() -> bool:
	return _sdk != null or _nat != null

## The OS credential store keeps a signed-in player's token (Keychain, Credential Manager, Secret
## Service). PARTII_NO_KEYCHAIN=1 turns it off (tests).
func _keychain() -> bool:
	return OS.get_environment("PARTII_NO_KEYCHAIN") != "1"

func _version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", ""))

## Native: (re)start the account, as the stored or given player, else this device's guest.
func _start_native(token: String) -> void:
	DirAccess.make_dir_recursive_absolute("user://partii")
	var slots := PackedStringArray(ProjectSettings.get_setting("partii/save_slots", ["progress"]))
	_nat.start(_cfg.game, _cfg.key, _cfg.api, ProjectSettings.globalize_path("user://partii"), _version(), slots, token)

## The version is the project's application/config/version (Project Settings), for analytics.
func configure(game: String, key: String, api := "") -> Dictionary:
	_cfg = {"game": game, "key": key, "api": api if api != "" else "https://api.partii.games"}
	if _nat != null:
		_start_native(str(_nat.token_load(game)) if _keychain() else "")
		return {"ok": true}
	var r := await _call("configure", [game, key, api, _version()])
	if r.get("ok"):
		track("motion", {"state": _state})
	return r

## The Partii account when Partii can vouch for it (its app or partii.games: no tap), else this device's
## guest (whose saves move to the account when the player signs in). Off the web: a local guest.
func sign_in() -> Dictionary:
	if _nat != null:
		var until := Time.get_ticks_msec() + 20000
		while not _nat.ready():
			if Time.get_ticks_msec() > until:
				return {"ok": false, "reason": "offline", "message": str(_nat.error())}
			await get_tree().process_frame
		_player_token = str(_nat.player_token())
		return {"ok": true, "player": _native_player()}
	if _sdk == null:
		return {"ok": true, "player": {"id": "", "name": "", "guest": true}, "local": true}
	var r := await _call("signIn")
	if r.get("ok"):
		await items()
	return r

## Native: forget the signed-in player (and its stored token); carry on as this device's guest.
func sign_out() -> Dictionary:
	if _nat == null:
		return {"ok": false, "reason": "unavailable"}
	_nat.token_clear(str(_cfg.get("game", "")))
	_player_token = ""
	_start_native("")
	var r := await sign_in()
	if r.get("ok"):
		player_changed.emit(r.player)
		if _rooms_on:
			_nat.rooms_auth(_player_token)
	return r

func _native_player() -> Dictionary:
	return {"id": str(_nat.player_id()), "name": "", "guest": bool(_nat.is_guest())}

## A save slot's data (anything JSON). Native: list slots in the project setting partii/save_slots
## (default ["progress"]) so they're fetched at sign-in. No Partii here: user://partii/<slot>.json.
func load_slot(slot: String) -> Dictionary:
	if _nat != null:
		var s := str(_nat.read_save(slot))
		return {"ok": true, "data": JSON.parse_string(s) if s != "" else null}
	if _sdk == null:
		var f := FileAccess.open("user://partii/%s.json" % slot, FileAccess.READ)
		return {"ok": true, "data": JSON.parse_string(f.get_as_text()) if f else null, "rev": 0, "local": true}
	var r := await _call("load", [slot])
	if r.get("ok"):
		_rev[slot] = int(r.get("rev", 0))
	return r

## Writes a save slot. A newer save from another device: {ok: false, reason: "conflict", theirs}; merge
## and save again (load_slot() first takes their rev).
func save_slot(slot: String, data) -> Dictionary:
	if _nat != null:
		# Native saves queue and retry offline; partii-sdk merges a newer save from another device.
		return {"ok": bool(_nat.write_save(slot, JSON.stringify(data)))}
	if _sdk == null:
		DirAccess.make_dir_recursive_absolute("user://partii")
		var f := FileAccess.open("user://partii/%s.json" % slot, FileAccess.WRITE)
		if f == null:
			return {"ok": false, "reason": "write_failed"}
		f.store_string(JSON.stringify(data))
		return {"ok": true, "local": true}
	var r := await _call("save", [slot, data, int(_rev.get(slot, 0))])
	if r.get("ok"):
		_rev[slot] = int(r.get("rev", 0))
	return r

## The player's items for this game (bought with Pops); owns() answers from it.
func items() -> Dictionary:
	if _sdk == null:
		return {"ok": true, "items": [], "local": true}
	var r := await _call("items")
	if r.get("ok"):
		_owned.clear()
		for it in r.get("items", []):
			if it is Dictionary and int(it.get("count", 0)) > 0 and not it.get("retired", false):
				_owned[str(it.get("item", ""))] = int(it.get("count", 0))
	return r

## The full game's unlock: Partii has no demos, so a game's intro is free and this item unlocks the rest.
const FULL_GAME := "full_game"

func owns_full_game() -> bool:
	return owns(FULL_GAME)

## Buy the full game (from a tap). Owned already: {ok: true, owned: true} with no sheet.
func unlock() -> Dictionary:
	if _sdk == null:
		return {"ok": false, "reason": "unavailable"}
	var r := await _call("unlock")
	if r.get("ok"):
		await items()
	return r

func owns(item: String) -> bool:
	if _nat != null:
		return int(_nat.owns(item)) == 1
	return _owned.has(item)

## Writes Partii hasn't stored yet (native; wait for 0 before quitting when a save must not be lost).
func pending_saves() -> int:
	return int(_nat.pending_writes()) if _nat != null else 0

## Buy an item (call it from a tap: browsers allow the popup only then). Partii shows its own buy sheet.
## {ok: true} once bought, or {ok: false, reason}: cancelled, popup_blocked (with url), not_signed_in,
## unavailable (not on the web) ...
func buy(item: String, quantity := 0) -> Dictionary:
	if _sdk == null:
		return {"ok": false, "reason": "unavailable"}
	var r := await _call("buy", [item] + ([quantity] if quantity > 0 else []))
	if r.get("ok"):
		await items()
	return r

# --- Leaderboards ---

## Submit a run's score to a board (once per run, e.g. at game over). Boards appear on the first submit,
## higher-is-better (a developer flips a board to lowest-wins with `partii leaderboards config`). meta is
## flat (short strings, numbers, bools; 1 KB) and is kept with the best. Returns {ok, board, score,
## best: {daily, weekly, all: {score, rank, improved}}}. Off the web: {ok: false, reason: "unavailable"}.
func submit_score(board: String, score: float, meta := {}) -> Dictionary:
	if _sdk == null:
		return {"ok": false, "reason": "unavailable"}
	return await _call("submitScore", [board, score, meta])

## A board's top players: {ok, entries: [{rank, display_name, score, ...}], players, me: {score, rank} or
## null, resets_at}. period is "daily", "weekly" or "all"; limit 1-100.
func leaderboard(board: String, period := "all", limit := 10) -> Dictionary:
	if _sdk == null:
		return {"ok": false, "reason": "unavailable"}
	return await _call("leaderboard", [board, period, limit])


## Say whether the player is really playing (not paused, on a menu, at game over, idle). Partii counts
## them in "playing now" and for playtime while it's true and the page is visible. Off the web: nothing.
func set_playing(on: bool) -> void:
	_playing = on
	if _sdk != null:
		_call("setPlaying", [on])

var _playing := false

## What set_playing() last said.
func is_playing() -> bool:
	return _playing

## An analytics event: a name (lowercase letters, digits, _ and .) and flat props (strings, numbers,
## bools; about 1 KB). Sent in batches with the session, the device and the version. Off the web: nothing.
func track(event: String, props := {}) -> void:
	if _nat != null:
		_nat.track(event, JSON.stringify(props))
	elif _sdk != null:
		_call("track", [event, props])


# --- Rooms, lobbies, Quick Play (web: partii-net's engine, loaded on the first room call) ---
# The netcode rule: the host runs the world; play traffic is unreliable and byte-packed, and the newest
# state wins (PartiiSnapshots / PartiiInputs in net.gd do the ring buffers). send() is unreliable only;
# send_reliable_setup() is for rare setup messages, never gameplay. Reliable state goes in room meta
# (update_room, host) and member meta (update_me). Players just join: `kind` is the game's own field.

## A send() to everyone in the room.
const BROADCAST := 65535

signal room_joined(room: Dictionary)
## reason: ended, host_left, host_lost, kicked, version_mismatch, expired, timeout
signal room_left(reason: String)
signal room_updated(room: Dictionary)
signal member_joined(member: Dictionary)
signal member_updated(member: Dictionary)
signal member_left(mid: int, reason: String)
## The member's app went to the background or its socket dropped; it keeps its seat until `until` (ms).
signal member_away(mid: int, until: int)
signal member_back(mid: int)
signal message(from: int, bytes: PackedByteArray)
signal online_changed(online: bool)
signal peer_connected(mid: int, path: String)

var _room := {}
var _rooms_on := false
var _online := false

## "web", "native" (the GDExtension) or "none".
func backend() -> String:
	return "web" if _sdk != null else ("native" if _nat != null else "none")

## What this build can do: "rooms", "saves", "shop", "scores", "motion".
func has(feature: String) -> bool:
	if _nat != null:
		return feature in ["rooms", "saves", "motion", "lobbies"]
	if _sdk == null:
		return feature == "motion" and not _web
	return feature in ["rooms", "saves", "shop", "scores", "motion", "lobbies"]

func _net_version() -> String:
	var v := str(ProjectSettings.get_setting("partii/net_version", ""))
	return v if v != "" else str(ProjectSettings.get_setting("application/config/version", "0")).replace(" ", "_")

func _start_rooms() -> Dictionary:
	if _rooms_on:
		return {"ok": true}
	if _nat != null:
		_nat.rooms_start("godot")
		_rooms_on = true
		return {"ok": true}
	if _sdk == null:
		return {"ok": false, "reason": "unavailable"}
	if not bool(_sdk.roomsReady()):
		var js := FileAccess.open("res://addons/partii/partii-engine.js", FileAccess.READ)
		var wasm := FileAccess.get_file_as_bytes("res://addons/partii/partii-engine.wasm")
		if js == null or wasm.is_empty():
			push_warning("Partii: rooms need addons/partii/partii-engine.js and .wasm in the export (include_filter)")
			return {"ok": false, "reason": "unavailable", "message": "partii-engine files aren't in the export"}
		JavaScriptBridge.eval(js.get_as_text(), true)
		var r := await _call("roomsStart", [Marshalls.raw_to_base64(wasm)])
		if not r.get("ok", false):
			return r
	_rooms_on = true
	return {"ok": true}

func _entered(r: Dictionary) -> Dictionary:
	if r.get("ok", false):
		_room = r.get("room", {})
	return r

## Host a room. opts: {max, kind, name, meta, listing: {name, mode, map, visibility, tags} (null: by code only)}.
## → {ok, room: {code, host, you, members, meta}} | {ok: false, reason} (family_blocked for a kid's account).
func create_room(opts := {}) -> Dictionary:
	var s := await _start_rooms()
	if not s.ok:
		return s
	var o := opts.duplicate()
	o["net_version"] = _net_version()
	if _nat != null:
		var meta: Dictionary = (o.get("meta", {}) as Dictionary).duplicate()
		if o.get("listing") is Dictionary:
			meta["listing"] = _listing(o.listing)
		var settings := {"max_members": int(o.get("max", 8)), "net_version": o.net_version}
		settings.merge(o.get("settings", {}), true)
		return _entered(await _answer(_nat.create_room(_cfg.game, str(o.get("kind", "player")), str(o.get("name", "")), JSON.stringify(meta), JSON.stringify(settings))))
	return _entered(await _call("createRoom", [o]))

## Join by code. opts: {kind, name, meta, password}.
func join_room(code: String, opts := {}) -> Dictionary:
	var s := await _start_rooms()
	if not s.ok:
		return s
	var o := opts.duplicate()
	o["net_version"] = _net_version()
	if _nat != null:
		var settings := {"net_version": o.net_version}
		if o.has("password"):
			settings["password"] = o.password
		return _entered(await _answer(_nat.join_room(code.to_upper(), str(o.get("kind", "player")), str(o.get("name", "")), JSON.stringify(o.get("meta", {})), JSON.stringify(settings))))
	return _entered(await _call("joinRoom", [code, o]))

## The best open lobby for this build → {ok, code} (code null: none open, so host one).
func quick_play(opts := {}) -> Dictionary:
	var o := opts.duplicate()
	o["net_version"] = _net_version()
	if _nat != null:
		var r := await _api("POST", "/v1/games/%s/lobbies/quick-join" % _cfg.get("game", "").uri_encode(), o)
		if not r.ok and r.get("reason") == "no_lobby":
			return {"ok": true, "code": null}
		return r
	return await _call("quickPlay", [o])

## Open lobbies, nearest first. opts: {mode, region, sort, limit, has_space} → {ok, enabled, lobbies}.
func list_lobbies(opts := {}) -> Dictionary:
	var o := opts.duplicate()
	o["net_version"] = _net_version()
	if _nat != null:
		var q := PackedStringArray()
		for k in o:
			if o[k] != null and str(o[k]) != "":
				q.append("%s=%s" % [str(k).uri_encode(), str(o[k]).uri_encode()])
		return await _api("GET", "/v1/games/%s/lobbies?%s" % [_cfg.get("game", "").uri_encode(), "&".join(q)], null)
	return await _call("listLobbies", [o])

func leave_room() -> void:
	if _rooms_on:
		if _nat != null:
			_nat.leave_room()
		else:
			_call("leaveRoom")
	_room = {}

## Host only.
func kick(mid: int) -> void:
	if _nat != null:
		_nat.kick(mid)
	else:
		_call("kick", [mid])

## Host only: room fields (meta, joinable, ...). The reliable channel for game state that must arrive.
func update_room(patch: Dictionary) -> void:
	if _nat != null:
		_nat.update_room(JSON.stringify(patch))
	else:
		_call("updateRoom", [patch])

func _listing(l) -> Variant:
	if not l is Dictionary:
		return null
	var d := {"visibility": "public"}
	d.merge(l, true)
	return d

## Host only: list the room in lobbies (or null to unlist).
func set_listing(listing) -> void:
	if _nat != null:
		var meta: Dictionary = (_room.get("meta", {}) as Dictionary).duplicate() if _room.get("meta") is Dictionary else {}
		meta["listing"] = _listing(listing)
		_nat.update_room(JSON.stringify({"meta": meta}))
	else:
		_call("setListing", [listing])

## Your own name and/or meta (null keeps it); the others get member_updated.
func update_me(name = null, meta = null) -> void:
	if _nat != null:
		var p := {}
		if name != null:
			p["name"] = name
		if meta != null:
			p["meta"] = meta
		_nat.update_me(JSON.stringify(p))
	else:
		_call("updateMe", [name, meta])

## Play traffic: unreliable, at most 1199 bytes. to: a member's mid or Partii.BROADCAST.
func send(to: int, bytes: PackedByteArray) -> void:
	if _rooms_on and bytes.size() > 0:
		if _nat != null:
			_nat.send(to, bytes)
		else:
			_sdk.send(to, Marshalls.raw_to_base64(bytes))

## NOT for gameplay: a rare reliable setup message (a seed, a loadout). Use room meta first.
func send_reliable_setup(to: int, bytes: PackedByteArray) -> void:
	if _rooms_on and bytes.size() > 0:
		if _nat != null:
			_nat.send_reliable_setup(to, bytes)
		else:
			_sdk.sendSetup(to, Marshalls.raw_to_base64(bytes))

func room() -> Dictionary:
	return _room

func in_room() -> bool:
	return not _room.is_empty()

func my_mid() -> int:
	return int(_room.get("you", -1))

func is_host() -> bool:
	return in_room() and int(_room.get("host", -2)) == my_mid()

func online() -> bool:
	return _online

func net_stats() -> Dictionary:
	if not _rooms_on:
		return {}
	var d = JSON.parse_string(str(_nat.net_stats() if _nat != null else _sdk.netStats()))
	return d if d is Dictionary else {}

## Native: create/join answers by request id, filled by _pump_rooms.
var _answers := {}

func _answer(req: int) -> Dictionary:
	if req < 0:
		return {"ok": false, "reason": "unavailable"}
	var until := Time.get_ticks_msec() + 20000
	while not _answers.has(req):
		if Time.get_ticks_msec() > until:
			return {"ok": false, "reason": "timeout"}
		await get_tree().process_frame
	var r: Dictionary = _answers[req]
	_answers.erase(req)
	return r

## Native: the engine sends room changes as events; keep the room here (the web engine keeps its own).
func _native_member(m: Dictionary, gone := false) -> void:
	var ms: Array = _room.get("members", [])
	for i in ms.size():
		if int(ms[i].get("mid", -1)) == int(m.get("mid", -2)):
			if gone:
				ms.remove_at(i)
			else:
				ms[i] = m
			return
	if not gone:
		ms.append(m)
	_room["members"] = ms

func _native_status(mid: int, status: String) -> void:
	for m in _room.get("members", []):
		if int(m.get("mid", -1)) == mid:
			m["status"] = status

func _pump_rooms() -> void:
	var evs = JSON.parse_string(str(_nat.rooms_poll() if _nat != null else _sdk.roomsPoll()))
	if not evs is Array:
		return
	for e in evs:
		var ev := str(e.get("ev", ""))
		if _nat != null:
			match ev:
				"created", "joined":
					_answers[int(e.get("req", -1))] = {"ok": true, "room": e.get("room", {})}
				"failed":
					_answers[int(e.get("req", -1))] = {"ok": false, "reason": str(e.get("code", "")), "message": str(e.get("message", ""))}
					continue
				"member_joined", "member_updated":
					_native_member(e.get("member", {}))
				"member_left":
					_native_member({"mid": e.get("mid", -1)}, true)
				"member_away", "member_suspended":
					_native_status(int(e.get("mid", -1)), "suspended")
				"member_back", "member_resumed":
					_native_status(int(e.get("mid", -1)), "active")
				"message":
					message.emit(int(e.get("from", -1)), _nat.message_bytes(int(e.get("i", -1))))
					continue
		match ev:
			"online":
				_online = true
				online_changed.emit(true)
			"offline":
				_online = false
				online_changed.emit(false)
			"created", "joined", "resumed":
				_room = e.get("room", _room)
				room_joined.emit(_room)
			"room_updated":
				_room = e.get("room", _room)
				room_updated.emit(_room)
			"member_joined":
				_sync_room()
				member_joined.emit(e.get("member", {}))
			"member_updated":
				_sync_room()
				member_updated.emit(e.get("member", {}))
			"member_left":
				_sync_room()
				member_left.emit(int(e.get("mid", -1)), str(e.get("reason", "")))
			"member_away", "member_suspended":
				_sync_room()
				member_away.emit(int(e.get("mid", -1)), int(e.get("until", 0)))
			"member_back", "member_resumed":
				_sync_room()
				member_back.emit(int(e.get("mid", -1)))
			"room_closed":
				_room = {}
				room_left.emit(str(e.get("reason", "")))
			"message":
				message.emit(int(e.get("from", -1)), Marshalls.base64_to_raw(str(e.get("data", ""))))
			"peer_connected":
				peer_connected.emit(int(e.get("mid", -1)), str(e.get("path", "")))
			"error":
				push_warning("Partii rooms: %s" % e.get("message", ""))

func _sync_room() -> void:
	if _nat != null:
		return
	var r = JSON.parse_string(str(_sdk.room()))
	if r is Dictionary:
		_room = r


# --- Browser sign-in (native: desktop, phones, consoles) ---
# POST /v1/players/browser-login/start, then poll until the player approves in their browser (or on
# another device with the code). Phones pass a return_url (the game's registered deep link); desktop
# and consoles show code_display and verify_url. The guest's progress merges into the account.

var _cfg := {}
var _player_token := ""

## The browser opened (or show these on a TV): code like "BCDF-2345" and the page to enter it on.
signal browser_login_code(code: String, verify_url: String)
signal player_changed(player: Dictionary)

func _api_post(path: String, body: Dictionary) -> Dictionary:
	return await _api("POST", path, body, false)

## An HTTP call to the Partii API with the game's key (and the player's token when `player`).
func _api(method: String, path: String, body, player := true) -> Dictionary:
	if _cfg.is_empty():
		return {"ok": false, "reason": "not_configured"}
	var h := HTTPRequest.new()
	h.timeout = 20.0
	add_child(h)
	var headers := PackedStringArray(["content-type: application/json", "x-partii-key: %s" % _cfg.key])
	if player and _player_token != "":
		headers.append("authorization: Bearer %s" % _player_token)
	var m := HTTPClient.METHOD_GET if method == "GET" else HTTPClient.METHOD_POST
	var err := h.request(str(_cfg.api) + path, headers, m, JSON.stringify(body) if body != null else "")
	if err != OK:
		h.queue_free()
		return {"ok": false, "reason": "offline", "message": error_string(err)}
	var res: Array = await h.request_completed
	h.queue_free()
	if res[0] != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "reason": "offline", "status": 0}
	var d = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	d = d if d is Dictionary else {}
	d["status_code"] = res[1]
	if int(res[1]) >= 400:
		var e = d.get("error", d)
		return {"ok": false, "reason": str(e.get("code", "failed")) if e is Dictionary else "failed", "message": str(e.get("message", "")) if e is Dictionary else "", "status_code": res[1], "interval_s": d.get("interval_s", 0)}
	d["ok"] = true
	return d

## Sign in to a Partii account through the browser (native builds). return_url: phones only, a deep link
## registered for the game. → {ok, player, merged} | {ok: false, reason: denied | kid_account | expired | ...}
func sign_in_with_browser(return_url := "") -> Dictionary:
	var platform := "desktop"
	if OS.has_feature("ios"):
		platform = "ios"
	elif OS.has_feature("android"):
		platform = "android"
	var body := {"game": _cfg.get("game", ""), "platform": platform}
	if return_url != "":
		body["return_url"] = return_url
	if _player_token != "":
		body["guest_token"] = _player_token
	var st := await _api_post("/v1/players/browser-login/start", body)
	if not st.ok:
		return st
	browser_login_code.emit(str(st.get("code_display", st.get("code", ""))), str(st.get("verify_url", "")))
	OS.shell_open(str(st.get("url", st.get("verify_url", ""))))
	var interval := float(st.get("interval_s", 5))
	var until := Time.get_ticks_msec() + int(float(st.get("expires_in", 600)) * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().create_timer(interval, true).timeout
		var p := await _api_post("/v1/players/browser-login/poll", {"poll_token": st.poll_token})
		if not p.ok:
			if p.get("reason") == "slow_down":
				interval = minf(maxf(float(p.get("interval_s", 0)), interval + 5.0), 60.0)
				continue
			if p.get("reason") == "offline":
				continue
			return p
		match str(p.get("status", "")):
			"pending":
				interval = float(p.get("interval_s", interval))
			"approved":
				_player_token = str(p.get("player_token", ""))
				if _nat != null:
					# The account (and a live rooms connection) carry on as the signed-in player.
					if _keychain():
						_nat.token_store(str(_cfg.game), _player_token)
					_start_native(_player_token)
					if _rooms_on:
						_nat.rooms_auth(_player_token)
				var pl: Dictionary = p.get("player", {})
				player_changed.emit(pl)
				return {"ok": true, "player": pl, "merged": p.get("merged", false)}
			"denied":
				return {"ok": false, "reason": str(p.get("reason", "denied")), "message": str(p.get("message", ""))}
			"used", "expired":
				return {"ok": false, "reason": str(p.status)}
	return {"ok": false, "reason": "expired"}
