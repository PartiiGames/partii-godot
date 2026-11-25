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

## Partii is reachable here (a web build with the SDK bundle).
func available() -> bool:
	return _sdk != null

## The version is the project's application/config/version (Project Settings), for analytics.
func configure(game: String, key: String, api := "") -> Dictionary:
	_cfg = {"game": game, "key": key, "api": api if api != "" else "https://api.partii.games"}
	var r := await _call("configure", [game, key, api, str(ProjectSettings.get_setting("application/config/version", ""))])
	if r.get("ok"):
		track("motion", {"state": _state})
	return r

## The Partii account when Partii can vouch for it (its app or partii.games: no tap), else this device's
## guest (whose saves move to the account when the player signs in). Off the web: a local guest.
func sign_in() -> Dictionary:
	if _sdk == null:
		return {"ok": true, "player": {"id": "", "name": "", "guest": true}, "local": true}
	var r := await _call("signIn")
	if r.get("ok"):
		await items()
	return r

## A save slot's data (anything JSON). Off the web: user://partii/<slot>.json.
func load_slot(slot: String) -> Dictionary:
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
	return _owned.has(item)

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
	if _sdk != null:
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

## "web", "native" (later: the GDExtension) or "none".
func backend() -> String:
	return "web" if _sdk != null else "none"

## What this build can do: "rooms", "saves", "shop", "scores", "motion".
func has(feature: String) -> bool:
	if _sdk == null:
		return feature == "motion" and not _web
	return feature in ["rooms", "saves", "shop", "scores", "motion", "lobbies"]

func _net_version() -> String:
	var v := str(ProjectSettings.get_setting("partii/net_version", ""))
	return v if v != "" else str(ProjectSettings.get_setting("application/config/version", "0")).replace(" ", "_")

func _start_rooms() -> Dictionary:
	if _rooms_on:
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
	return _entered(await _call("createRoom", [o]))

## Join by code. opts: {kind, name, meta, password}.
func join_room(code: String, opts := {}) -> Dictionary:
	var s := await _start_rooms()
	if not s.ok:
		return s
	var o := opts.duplicate()
	o["net_version"] = _net_version()
	return _entered(await _call("joinRoom", [code, o]))

## The best open lobby for this build → {ok, code} (code null: none open, so host one).
func quick_play(opts := {}) -> Dictionary:
	var o := opts.duplicate()
	o["net_version"] = _net_version()
	return await _call("quickPlay", [o])

## Open lobbies, nearest first. opts: {mode, region, sort, limit, has_space} → {ok, enabled, lobbies}.
func list_lobbies(opts := {}) -> Dictionary:
	var o := opts.duplicate()
	o["net_version"] = _net_version()
	return await _call("listLobbies", [o])

func leave_room() -> void:
	if _rooms_on:
		_call("leaveRoom")
	_room = {}

## Host only.
func kick(mid: int) -> void:
	_call("kick", [mid])

## Host only: room fields (meta, joinable, ...). The reliable channel for game state that must arrive.
func update_room(patch: Dictionary) -> void:
	_call("updateRoom", [patch])

## Host only: list the room in lobbies (or null to unlist).
func set_listing(listing) -> void:
	_call("setListing", [listing])

## Your own name and/or meta (null keeps it); the others get member_updated.
func update_me(name = null, meta = null) -> void:
	_call("updateMe", [name, meta])

## Play traffic: unreliable, at most 1199 bytes. to: a member's mid or Partii.BROADCAST.
func send(to: int, bytes: PackedByteArray) -> void:
	if _rooms_on and bytes.size() > 0:
		_sdk.send(to, Marshalls.raw_to_base64(bytes))

## NOT for gameplay: a rare reliable setup message (a seed, a loadout). Use room meta first.
func send_reliable_setup(to: int, bytes: PackedByteArray) -> void:
	if _rooms_on and bytes.size() > 0:
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
	var d = JSON.parse_string(str(_sdk.netStats()))
	return d if d is Dictionary else {}

func _pump_rooms() -> void:
	var evs = JSON.parse_string(str(_sdk.roomsPoll()))
	if not evs is Array:
		return
	for e in evs:
		match str(e.get("ev", "")):
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
	if _cfg.is_empty():
		return {"ok": false, "reason": "not_configured"}
	var h := HTTPRequest.new()
	h.timeout = 20.0
	add_child(h)
	var headers := PackedStringArray(["content-type: application/json", "x-partii-key: %s" % _cfg.key])
	var err := h.request(str(_cfg.api) + path, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
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
				var pl: Dictionary = p.get("player", {})
				player_changed.emit(pl)
				return {"ok": true, "player": pl, "merged": p.get("merged", false)}
			"denied":
				return {"ok": false, "reason": str(p.get("reason", "denied")), "message": str(p.get("message", ""))}
			"used", "expired":
				return {"ok": false, "reason": str(p.status)}
	return {"ok": false, "reason": "expired"}
