extends Node
## Headless native check of Partii.sign_in_with_browser() against staging:
##   godot --headless --path . res://tests/native/browser_login_test.tscn
## Prints "PROBE {json}": the code to approve (approve it at the printed url), then the result.
## Hard cap: 540 s (the poll window is 600 s).

func _ready() -> void:
	get_tree().create_timer(540.0, true).timeout.connect(func():
		print("PROBE ", JSON.stringify({"ev": "cap"}))
		get_tree().quit(3))
	Partii.browser_login_code.connect(func(code, url): print("PROBE ", JSON.stringify({"ev": "code", "code": code, "verify_url": url})))
	await Partii.configure("smashii", "pk_smashii_web_j0GFKzE395-H9XhsNeaR8t", "https://api-staging.partii.games")
	var r := await Partii.sign_in_with_browser()
	print("PROBE ", JSON.stringify({"ev": "result", "ok": r.get("ok", false), "reason": r.get("reason", ""), "player_id": r.get("player", {}).get("id", ""), "merged": r.get("merged", false), "has_token": Partii._player_token != ""}))
	get_tree().quit(0 if r.get("ok", false) else 1)

func _process(_d: float) -> void:
	if Engine.get_process_frames() % 600 == 0:
		print("PROBE ", JSON.stringify({"ev": "tick", "secs": Time.get_ticks_msec() / 1000}))
