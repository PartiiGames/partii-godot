extends Node
## Rooms check for `partii test room` (tests/web/rooms.sh): the host page (?partii_room=new) creates a
## room; each guest (?partii_room=CODE) joins it. Guests send inputs (PartiiNet.Inputs) 20 times a
## second; the host runs a tiny world (each guest's newest input count) and broadcasts snapshots
## (PartiiNet.Snapshots). window.__partiiTestReport says: synced = the host sees every guest's inputs
## arriving, and a guest sees its own input echoed back in the host's snapshots.
## Also prints "PROBE {json}" lines for the farm logs.

var _q := {}
var _role := ""
var _inputs := PartiiNet.Inputs.new()
var _snaps := PartiiNet.Snapshots.new()
var _world := {}       # host: guest mid → newest input count
var _echo := 0         # guest: my own count as the host last reported it
var _count := 0
var _tick := 0.0
var _seen_snap_ms := 0
var _error := ""

func _ready() -> void:
	if not OS.has_feature("web"):
		print("PROBE ", JSON.stringify({"ev": "skip", "why": "web only"}))
		return
	var qs := str(JavaScriptBridge.eval("location.search", true)).trim_prefix("?")
	for kv in qs.split("&", false):
		var p := kv.split("=", true, 1)
		_q[p[0].uri_decode()] = p[1].uri_decode() if p.size() > 1 else ""
	JavaScriptBridge.eval("window.__partii_rooms_test = {synced: false}; window.__partiiTestReport = () => window.__partii_rooms_test;", true)
	Partii.message.connect(_on_message)
	Partii.member_left.connect(func(mid, _r): _world.erase(mid); _inputs.forget(mid))
	Partii.room_left.connect(func(r): _probe({"ev": "room_left", "reason": r}))
	await Partii.configure(str(_q.get("partii_game", "smashii")), str(_q.get("partii_key", "")), str(_q.get("partii_api", "")))
	var me := await Partii.sign_in()
	_probe({"ev": "signed_in", "ok": me.get("ok", false), "reason": me.get("reason", "")})
	var code := str(_q.get("partii_room", "new"))
	var r: Dictionary
	if code == "new":
		_role = "host"
		r = await Partii.create_room({"max": 8, "kind": "player", "name": "host", "meta": {"test": true}})
	else:
		_role = "guest"
		r = await Partii.join_room(code, {"kind": "player", "name": str(_q.get("partii_test", "guest"))})
	_probe({"ev": "room", "role": _role, "ok": r.get("ok", false), "reason": r.get("reason", ""), "message": r.get("message", ""), "code": Partii.room().get("code", ""), "mid": Partii.my_mid()})
	if not r.get("ok", false):
		_error = "%s: %s" % [r.get("reason", ""), r.get("message", "")]
		_report()

func _process(delta: float) -> void:
	if not Partii.in_room():
		return
	_tick += delta
	if _tick < 0.05:
		return
	_tick = 0.0
	if _role == "guest":
		_count += 1
		var b := PackedByteArray()
		b.resize(4)
		b.encode_u32(0, _count)
		Partii.send(int(Partii.room().get("host", 0)), _inputs.pack(b))
	else:
		# The world: [n u8]([mid u16][count u32])*
		var b := PackedByteArray()
		b.resize(1 + 6 * _world.size())
		b[0] = _world.size()
		var i := 1
		for mid in _world:
			b.encode_u16(i, mid)
			b.encode_u32(i + 2, _world[mid])
			i += 6
		Partii.send(Partii.BROADCAST, _snaps.pack(b))
	_report()

func _on_message(from: int, bytes: PackedByteArray) -> void:
	match PartiiNet.kind(bytes):
		PartiiNet.KIND_INPUTS:
			for b in _inputs.unpack(from, bytes):
				_world[from] = b.decode_u32(0)
		PartiiNet.KIND_SNAPSHOT:
			var w := _snaps.unpack(from, bytes)
			if w.is_empty():
				return
			_seen_snap_ms = Time.get_ticks_msec()
			for k in w[0]:
				if w.decode_u16(1 + 6 * k) == Partii.my_mid():
					_echo = w.decode_u32(1 + 6 * k + 2)

func _report() -> void:
	var guests := 0
	for m in Partii.room().get("members", []):
		if int(m.get("mid", -1)) != Partii.my_mid():
			guests += 1
	var synced := false
	var rep := {"role": _role, "code": Partii.room().get("code", ""), "mid": Partii.my_mid(), "error": _error}
	if _role == "host":
		var want := int(_q.get("partii_guests", "0"))
		rep["members"] = guests
		rep["world"] = _world.duplicate()
		synced = _error == "" and _world.size() >= maxi(want, 1) and guests >= maxi(want, 1)
	else:
		rep["sent"] = _count
		rep["echo"] = _echo
		rep["snap_age_ms"] = Time.get_ticks_msec() - _seen_snap_ms if _seen_snap_ms else -1
		synced = _error == "" and _echo > 0 and _count - _echo < 40 and Time.get_ticks_msec() - _seen_snap_ms < 1000
	rep["synced"] = synced
	JavaScriptBridge.eval("window.__partii_rooms_test = %s;" % JSON.stringify(rep), true)
	if Engine.get_process_frames() % 60 == 0 or _error != "":
		_probe(rep)

func _probe(d: Dictionary) -> void:
	print("PROBE ", JSON.stringify(d))
