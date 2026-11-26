extends Node
## Headless check of the Partii autoload on the native backend (the GDExtension in addons/partii/bin):
##   PARTII_NO_KEYCHAIN=1 godot --headless --path . res://tests/native/autoload_test.tscn
## The same calls a web build makes: configure (staging), sign_in, save_slot/load_slot, create_room. A
## second engine (a raw PartiiNative) joins the room; host -> guest and guest -> host bytes arrive and
## the host's room shows 2 members. "PROBE {json}" lines; exit 0 = pass. Cap 120 s. Prints no tokens.

const GAME := "smashii"
const KEY := "pk_smashii_web_j0GFKzE395-H9XhsNeaR8t"
const API := "https://api-staging.partii.games"

var checks := {}
var guest: Object
var got_from_guest := false

func _ready() -> void:
	get_tree().create_timer(120.0, true).timeout.connect(func(): _done("cap"))
	checks["backend"] = Partii.backend()
	if Partii.backend() != "native":
		return _done("backend is %s, not native" % Partii.backend())
	checks["configure"] = (await Partii.configure(GAME, KEY, API)).get("ok", false)
	var s: Dictionary = await Partii.sign_in()
	checks["sign_in"] = s.get("ok", false)
	checks["guest"] = s.get("player", {}).get("guest", null)
	checks["player"] = s.get("player", {}).get("id", "")
	if not s.get("ok", false):
		return _done("sign_in: %s" % s.get("reason", ""))
	var v := randi() % 1000
	checks["save"] = (await Partii.save_slot("progress", {"v": v})).get("ok", false)
	var t := Time.get_ticks_msec()
	while Partii.pending_saves() > 0 and Time.get_ticks_msec() - t < 15000:
		await get_tree().process_frame
	checks["load"] = int((await Partii.load_slot("progress")).get("data", {}).get("v", -1)) == v
	checks["has_rooms"] = Partii.has("rooms")

	Partii.message.connect(func(from: int, bytes: PackedByteArray):
		if bytes.get_string_from_utf8() == "to-host":
			got_from_guest = true)
	var r: Dictionary = await Partii.create_room({"max": 4, "name": "host"})
	if not r.get("ok", false):
		return _done("create_room: %s %s" % [r.get("reason", ""), r.get("message", "")])
	var code := str(r.room.get("code", ""))
	checks["room"] = code
	checks["is_host"] = Partii.is_host()

	# The second member: its own engine, this device's guest token (the same player, a second seat).
	guest = ClassDB.instantiate("PartiiNative")
	var dir := ProjectSettings.globalize_path("user://partii-guest")
	DirAccess.make_dir_recursive_absolute(dir)
	guest.start(GAME, KEY, API, dir, "test", PackedStringArray(), "")
	t = Time.get_ticks_msec()
	while not guest.ready() and Time.get_ticks_msec() - t < 30000:
		await get_tree().process_frame
	guest.rooms_start("godot/test guest")
	guest.join_room(code, "player", "guest", "{}", JSON.stringify({"net_version": Partii._net_version()}))
	var joined := false
	var got_from_host := false
	t = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < 40000:
		await get_tree().process_frame
		for e in (JSON.parse_string(guest.rooms_poll()) as Array):
			match str(e.get("ev", "")):
				"joined":
					joined = true
				"failed":
					checks["guest_join"] = "failed: %s" % e.get("code", "")
					return _done("guest join failed")
				"message":
					if guest.message_bytes(int(e.i)).get_string_from_utf8() == "to-guest":
						got_from_host = true
		if joined:
			Partii.send(Partii.BROADCAST, "to-guest".to_utf8_buffer())
			guest.send(int(Partii.room().get("host", 0)), "to-host".to_utf8_buffer())
		if joined and got_from_host and got_from_guest and Partii.room().get("members", []).size() == 2:
			break
	checks["guest_join"] = joined
	checks["host_to_guest"] = got_from_host
	checks["guest_to_host"] = got_from_guest
	checks["members"] = Partii.room().get("members", []).size()
	var ok: bool = checks.configure and checks.sign_in and checks.save and checks.load and joined and got_from_host and got_from_guest and checks.members == 2
	_done("" if ok else "a check failed")

func _done(why: String) -> void:
	print("PROBE ", JSON.stringify({"ev": "result", "pass": why == "", "why": why, "checks": checks}))
	if guest:
		guest.leave_room()
	Partii.leave_room()
	get_tree().quit(0 if why == "" else 1)
