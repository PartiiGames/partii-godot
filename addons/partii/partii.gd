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
