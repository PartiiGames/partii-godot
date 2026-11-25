extends Node
## Headless check of the native backend (the GDExtension, addons/partii/bin):
##   godot --headless --path . res://tests/native/gdext_test.tscn
## The class loads; guest sign-in through partii-sdk (staging); a save round-trips; a room is created
## with partii-net's native engine; the OS token store answers. "PROBE {json}" lines; exit 0 = pass. Cap 120 s.

var n: Object
var checks := {}

func _ready() -> void:
	get_tree().create_timer(120.0, true).timeout.connect(func(): _done("cap"))
	checks["class"] = ClassDB.class_exists("PartiiNative")
	if not checks["class"]:
		return _done("PartiiNative isn't registered")
	n = ClassDB.instantiate("PartiiNative")
	var dir := ProjectSettings.globalize_path("user://partii")
	DirAccess.make_dir_recursive_absolute(dir)
	n.start("smashii", "pk_smashii_web_j0GFKzE395-H9XhsNeaR8t", "https://api-staging.partii.games", dir, "test")
	var t := Time.get_ticks_msec()
	while not n.ready() and Time.get_ticks_msec() - t < 30000:
		await get_tree().process_frame
	checks["ready"] = n.ready()
	checks["player"] = n.player_id()
	checks["guest"] = n.is_guest()
	checks["error"] = n.error()
	n.write_save("progress", JSON.stringify({"n": 7}))
	checks["save"] = n.read_save("progress")
	checks["token_store"] = PartiiNative.token_store("smashii-test", "x")
	PartiiNative.token_clear("smashii-test")
	n.rooms_start("godot/test linux")
	var req: int = n.create_room("smashii", "player", "native", "{}", JSON.stringify({"max_members": 4}))
	t = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < 30000 and not checks.has("room"):
		await get_tree().process_frame
		var evs = JSON.parse_string(n.rooms_poll())
		for e in (evs if evs is Array else []):
			if e.get("ev") in ["created", "failed"] and int(e.get("req", -1)) == req:
				checks["room"] = e.get("room", {}).get("code", "") if e.ev == "created" else "failed: %s" % e.get("code", "")
			elif e.get("ev") == "online":
				checks["online"] = true
	var ok: bool = checks["ready"] and str(checks["player"]) != "" and str(checks["save"]).contains("7") and str(checks.get("room", "")).length() >= 4 and not str(checks.get("room", "")).begins_with("failed")
	_done("" if ok else "a check failed")

func _done(why: String) -> void:
	print("PROBE ", JSON.stringify({"ev": "result", "pass": why == "", "why": why, "checks": checks}))
	if n:
		n.leave_room()
	get_tree().quit(0 if why == "" else 1)
