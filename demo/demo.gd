extends Control
## Partii for Godot in one screen: who's playing, a counter kept in a cloud save, a leaderboard, the
## full-game unlock, and device motion (tilt) with its state. Set GAME and KEY to your game's id and
## its project's publishable key (`partii keys create`; publishable, not a secret). On the web the page
## address can set them too: ?game=<id>&key=<pk_...>&api=<https://api...> (the tests use this).
## Off the web it still runs: a local guest, the save in user://, and the Partii-only calls answer
## {ok: false, reason: "unavailable"}.
##
## Test hooks (web only): ?probe=1 prints one "PROBE {json}" console line every 250 ms with the state;
## ?auto=1 runs every call once after sign-in (save, load, score, board, track) and puts the results in
## the probe line. tests/web/*.mjs read these.

const GAME := "my-game"
const KEY := "pk_..."
const BOARD := "score"

@onready var who: Label = $Box/Who
@onready var count_label: Label = $Box/Count
@onready var board_label: Label = $Box/Board
@onready var motion_label: Label = $Box/Motion
@onready var unlock_button: Button = $Box/Unlock
@onready var status: Label = $Box/Status

var count := 0
var configured := false
var player := {}
var probe := false
var auto := {}
var _t := 0.0

func _ready() -> void:
	$Box/Add.pressed.connect(_on_add)
	$Box/Score.pressed.connect(_on_score)
	unlock_button.pressed.connect(_on_unlock)
	Partii.motion_changed.connect(func(_s): _show())
	var game := GAME
	var key := KEY
	var api := ""
	if OS.has_feature("web"):
		var q := str(JavaScriptBridge.eval("location.search", true))
		probe = q.contains("probe=1")
		game = _param(q, "game", game)
		key = _param(q, "key", key)
		api = _param(q, "api", "")
	if Partii.available() and key != "pk_...":
		configured = (await Partii.configure(game, key, api)).get("ok", false)
	# On the web Partii needs configure() first; off the web every call falls back on its own.
	var ready_ := configured or not Partii.available()
	if not ready_:
		who.text = "Set GAME and KEY in demo.gd"
		_show()
		return
	var me: Dictionary = await Partii.sign_in()
	player = me.get("player", {})
	who.text = "Playing as %s%s" % [player.get("name", "?"), " (guest)" if player.get("guest", true) else ""]
	var s: Dictionary = await Partii.load_slot("main")
	if s.get("ok") and s.get("data") is Dictionary:
		count = int(s.data.get("count", 0))
	_show()
	if OS.has_feature("web") and str(JavaScriptBridge.eval("location.search", true)).contains("auto=1") and configured:
		_auto()

func _param(q: String, name: String, fallback: String) -> String:
	var m := RegEx.create_from_string("[?&]" + name + "=([^&]+)").search(q)
	return m.get_string(1).uri_decode() if m else fallback

func _process(delta: float) -> void:
	# The tilt readout, and the probe line.
	var g := Partii.gravity()
	motion_label.text = "Motion: %s  gravity (%.2f, %.2f, %.2f)" % [Partii.motion_state(), g.x, g.y, g.z]
	if not probe:
		return
	_t += delta
	if _t < 0.25:
		return
	_t = 0.0
	print("PROBE ", JSON.stringify({"configured": configured, "player": player, "count": count, "motion": Partii.motion_state(), "live": Partii.motion_live(), "g": [snappedf(g.x, 0.001), snappedf(g.y, 0.001), snappedf(g.z, 0.001)], "auto": auto}))

## Every call once, results kept for the probe line (tests/web/staging.mjs).
func _auto() -> void:
	var r := {}
	count += 1
	r.save = await Partii.save_slot("main", {"count": count})
	r.load = await Partii.load_slot("main")
	r.score = await Partii.submit_score(BOARD, 42)
	r.board = await Partii.leaderboard(BOARD, "all", 5)
	Partii.track("demo_auto", {"count": count})
	r.done = true
	auto = r
	_show()

func _on_add() -> void:
	count += 1
	_show()
	var r := await Partii.save_slot("main", {"count": count})
	if not r.get("ok"):
		status.text = "Not saved: %s" % r.get("reason", "?")
		if r.get("reason") == "conflict":
			# A newer save from another device: take the bigger count, then save again.
			var theirs = r.get("theirs")
			if theirs is Dictionary and theirs.get("data") is Dictionary:
				count = max(count, int(theirs.data.get("count", 0)))
			await Partii.load_slot("main")
			await Partii.save_slot("main", {"count": count})
			_show()

func _on_score() -> void:
	# A game sends one score per run, at game over. Here the counter is the "score".
	var r := await Partii.submit_score(BOARD, count)
	if not r.get("ok"):
		board_label.text = "Score not sent (%s)" % r.get("reason", "?")
		return
	var b := await Partii.leaderboard(BOARD, "all", 3)
	var lines := []
	for e in b.get("entries", []):
		lines.append("%d. %s %d" % [int(e.rank), e.display_name, int(e.score)])
	var me = b.get("me")
	if me is Dictionary:
		lines.append("You: #%d" % int(me.rank))
	board_label.text = "  ".join(lines)

func _on_unlock() -> void:
	# From the tap itself: browsers open Partii's buy popup only from a gesture.
	var r := await Partii.unlock()
	if r.get("ok"):
		status.text = "Unlocked. Thank you!"
	elif r.get("reason") == "popup_blocked":
		OS.shell_open(str(r.get("url", "")))
	else:
		status.text = "Not bought (%s)" % r.get("reason", "?")
	_show()

func _show() -> void:
	count_label.text = "Count: %d (saved to Partii)" % count
	unlock_button.text = "Full game unlocked" if Partii.owns_full_game() else "Unlock the full game"
	unlock_button.disabled = Partii.owns_full_game()
