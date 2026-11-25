# Partii for Godot (v0.3)

A small addon so a Godot 4 game exported to the web can use what Partii gives it: **the player**
(signed in automatically inside Partii, else a guest), **cloud saves**, **purchases** (Pops items,
unlocking the full game, ownership checks) and **device motion** (tilt). Off the web every call falls
back cleanly, so one code path fits desktop, native and web. It also reports when the player is
really playing, and tells the game when the page is hidden, and reports analytics and errors.

## Install

1. Copy `addons/partii/` into your project.
2. Project → Project Settings → Plugins → enable **Partii**. This adds the `Partii` autoload.
3. Export for **Web**. Use no threads: Partii's iPhone app frame isn't cross-origin isolated, so
   turn off Thread Support in the Web preset.
4. Put a `partii.json` next to `index.html` that declares what you use:
   ```json
   { "hardware": { "motion": "Tilt your phone to steer" } }
   ```
   Partii shows the player its own "Motion sensors" question with your reason. Only a declared kind
   reaches your game's frame (the `allow` attribute), and review sees it.
5. In the Web preset's Resources tab, add `addons/partii/partii-sdk.js` to **Filters to export
   non-resource files** (`include_filter`). That file is the Partii web SDK the addon talks to.
   For multiplayer rooms add `addons/partii/partii-engine.js, addons/partii/partii-engine.wasm` too
   (the rooms engine, 640 KB, loaded only on the first room call).
6. `partii web deploy <game> build/web`

## Multiplayer rooms

**The netcode rule:** the host runs the world. Clients send their inputs, the host sends snapshots,
every packet is unreliable and byte-packed, and the newest state wins. A lost packet is never resent;
the next one carries what it had. `PartiiNet` does this for you, so start there:

```gdscript
var inputs := PartiiNet.Inputs.new()        # clients → host: each packet repeats the last 4 inputs
var snaps := PartiiNet.Snapshots.new()      # host → clients: older snapshots are dropped

func _ready():
    Partii.message.connect(_on_message)
    var q = await Partii.quick_play()       # the best open lobby for this build, or code null
    var r: Dictionary
    if q.ok and q.code:
        r = await Partii.join_room(q.code)
    else:
        r = await Partii.create_room({"max": 8, "listing": {"name": "Fun room", "mode": "arcade"}})
    if not r.ok:
        show_reason(r.reason)               # e.g. family_blocked: show it, never work around it

func _physics_process(_d):
    if Partii.is_host():
        step_world()
        Partii.send(Partii.BROADCAST, snaps.pack(world_bytes()))
    elif Partii.in_room():
        Partii.send(Partii.room().host, inputs.pack(my_input_bytes()))

func _on_message(from: int, bytes: PackedByteArray):
    match PartiiNet.kind(bytes):
        PartiiNet.KIND_INPUTS:              # host
            for b in inputs.unpack(from, bytes): apply_input(from, b)
        PartiiNet.KIND_SNAPSHOT:            # client
            var w := snaps.unpack(from, bytes)
            if not w.is_empty(): show_world(w)
```

| Call | |
|---|---|
| `create_room({max, kind, name, meta, listing})` | Host a room. `listing` (`{name, mode, map, visibility, tags}`) lists it in lobbies; leave it out for join-by-code only. |
| `join_room(code, {kind, name, meta, password})` | Join by code. |
| `quick_play({mode, region})` | `{ok, code}`: the best open lobby, or `code` null (then host one). |
| `list_lobbies({mode, region, sort, limit})` | `{ok, enabled, lobbies: [{code, name, mode, map, players, max, region, ...}]}` for a server browser. |
| `send(to, bytes)` | **Unreliable only**, at most 1199 bytes. `to` is a member's `mid` or `Partii.BROADCAST`. |
| `update_room(patch)`, `set_listing(l)` | Host only. Room `meta` is the reliable channel: state that must arrive (the map, the round, scores between rounds). |
| `update_me(name, meta)` | Your own member meta, also reliable (ready, team, skin). |
| `send_reliable_setup(to, bytes)` | **Not for gameplay.** A rare one-off (a seed, a loadout) when meta doesn't fit. |
| `leave_room()`, `kick(mid)`, `room()`, `in_room()`, `my_mid()`, `is_host()`, `online()`, `net_stats()` | |

Signals: `room_joined(room)`, `room_left(reason)`, `room_updated(room)`, `member_joined(m)`,
`member_updated(m)`, `member_left(mid, reason)`, `member_away(mid, until)`, `member_back(mid)`,
`message(from, bytes)`, `online_changed(online)`, `peer_connected(mid, path)`.

- **The host never moves.** If the host leaves, the room ends (`room_left("host_left")`).
- **Away is not gone.** A phone sent to the background keeps its seat for 30 s (`member_away`, then
  `member_back` or `member_left`). Show "away"; don't free the seat.
- **A joiner can miss the first broadcast.** Have a new member say hello and answer it with the full
  state.
- **Builds must match.** Rooms and Quick Play use the project's `partii/net_version` setting (or
  `application/config/version`), so players on different builds never meet.
- **Players just join.** There's no role picker; `kind` is your own field and your game decides roles.
- **Family rules.** A kid's account joins only rooms a parent approved; calls answer
  `family_blocked` and kids' lobby lists show only allowed rooms. Show the reason.

Test it headless: `node tests/web/rooms.mjs build/web` (a host and 2 guests on Partii staging).

## Player, saves, purchases

A working screen with all of it is the demo project's `demo/demo.tscn`: set its `GAME` and `KEY`,
and run it.

```gdscript
func _ready():
    await Partii.configure("my-game", "pk_...")   # your project's publishable key (not a secret)
    var me = await Partii.sign_in()               # {ok, player: {id, name, guest}}
    var s = await Partii.load_slot("main")        # {ok, data, rev}; data is null before the first save
    if s.ok and s.data != null:
        apply(s.data)

func on_level_done():
    var r = await Partii.save_slot("main", {"level": level, "coins": coins})
    if not r.ok and r.reason == "conflict":       # a newer save from another device: merge, save again
        await Partii.load_slot("main")
        ...

func on_unlock_pressed():                         # from a tap: browsers allow the popup only then
    var r = await Partii.unlock()                 # buy("full_game"), or ok at once when it's owned
    if r.ok or Partii.owns_full_game():
        unlock()
    elif r.reason == "popup_blocked":
        OS.shell_open(r.url)
```

- Every call returns a Dictionary: `{ok: true, ...}` or `{ok: false, reason, message?}`.
- **Sign-in:** inside the Partii app or on partii.games the player is signed in to their account
  with no tap. Anywhere else they play as this device's guest, and the guest's saves and items move
  to the account when they sign in later.
- **Saves** are JSON (Dictionary, Array, numbers, strings), per slot. `save_slot` sends the rev the
  last `load_slot` read, so a save from another device is never overwritten silently.
- **Never buy for a player.** The player always confirms in Partii's own UI; `buy()` only opens it and
  answers what they chose. There is no silent buy. A game that buys for a player without their
  permission is removed from the store and its developer banned. A kid's account answers `age_restricted`.
- **Purchases:** Partii shows its own buy sheet (an overlay inside Partii, a popup elsewhere), never
  your game. `buy()` reasons: `cancelled`, `popup_blocked` (with `url`), `timeout`,
  `not_signed_in`, `unavailable` (not on the web), `failed`. Items are set up on Partii
  (`partii items put`); `owns(item)` answers from the last `items()`, which `sign_in` and a
  successful `buy` refresh.
- **Unlocking the full game:** Partii has no demos. A game is free, its intro plays free, and the
  item with id `full_game` (kind `permanent`; `partii items put <game> full_game --field kind=permanent`)
  unlocks the rest, owned for good on every device the player signs in on. The store then shows the
  game as Free with "In-app purchases". People on your team (test players too) can't buy your own
  items: test with a separate account on staging.
- Off the web: `sign_in` gives a local guest, saves go to `user://partii/<slot>.json`, `items` is
  empty and `buy` is `unavailable`. `Partii.available()` says which you have.

## Leaderboards

```gdscript
func on_game_over(score: int):
    var r = await Partii.submit_score("score", score)   # once per run; the board appears on first submit
    if r.get("ok"):
        print("world rank ", r.best.all.rank, " (new best: ", r.best.all.improved, ")")

func show_board():
    var b = await Partii.leaderboard("score", "all", 10) # "daily", "weekly" or "all"
    for e in b.get("entries", []):
        print(e.rank, ". ", e.display_name, "  ", e.score)
    if b.get("me"):
        print("you: #", b.me.rank, "  ", b.me.score)
```

- Boards are higher-is-better; for times (lowest wins) set the board with `partii leaderboards config`
  (higher_is_better false) before anyone submits.
- A guest's scores move to the account when the player signs in. Scores also show on the player's
  Partii profile ("High scores").
- Off the web both return `{ok: false, reason: "unavailable"}`: keep your local high scores too.

## Playing, pausing

```gdscript
func on_play_resumed():  Partii.set_playing(true)    # really playing
func on_paused():        Partii.set_playing(false)   # pause, menus, cutscenes, game over
```

- `set_playing` drives Partii's "playing now" heartbeat (`playerPlaying`): every 60 s while it's
  true and the page is visible, with how many real inputs came since (Partii Plus playtime counts
  only stretches with input), and `stopped` when it turns false or the page goes away.
- Partii's own menu over your game takes focus from its frame, so Godot sends
  `NOTIFICATION_APPLICATION_FOCUS_OUT`: pause there (and on `NOTIFICATION_WM_GO_BACK_REQUEST`).
  `Partii.visibility_changed(visible)` also fires when the page is hidden (the app sent to the
  background, another tab).

### Rebuilding partii-sdk.js

`web/partii-godot.ts` is the browser half: the Partii web SDK (`sdk/ts`: `createClient`,
`autoSignIn`, `buy`) behind the one entry the GDScript calls through JavaScriptBridge. To rebuild:

```sh
PARTII_SDK=<partii>/platform/sdk/ts/src ESBUILD=esbuild addons/partii/web/build.sh
```

## Analytics and errors

Once `configure()` has run, the addon reports on its own, with no code from you:

- `session_start` at configure, and `session_end {secs}` whenever the page is hidden or left. Partii's `partii analytics summary <game>` counts players, sessions and session length from these.
- `motion {state}` each time motion changes (`needs_tap`, `waiting`, `granted`, `denied`, `unsupported`).
- **Errors**, sent to `partii errors`: uncaught JS errors, rejected promises, and the engine's own error lines (`SCRIPT ERROR`, `ERROR`, `USER ERROR`, with their `at:` line). A WebAssembly abort is reported as a `panic`. Each distinct message is sent once per session, at most 20.

Your own events: `Partii.track("level_done", {"level": 3})`. Names use lowercase letters, digits, `_` and `.`; props are flat strings, numbers and bools (about 1 KB). Every event carries `os` (ios, android or desktop) and `framed` (inside Partii's frame). The version is the project's `application/config/version`, so set it in Project Settings. Events are batched every 15 s, and sent at once when the page is hidden.

Read them with `partii analytics summary <game>`, `partii analytics events <game> [--name control --by mode]` and `partii errors list <game>`. For example, a tilt game can send `control {mode: "tilt"|"stick"}` once a control mode has held for a while, and `play {secs}` each time play stops.

## Motion

```gdscript
func _process(delta):
    var g: Vector3 = Partii.gravity()   # in g; flat and face up is (0, 0, -1)
    var tilt := Vector2(g.x - base.x, base.y - g.y)
```

- `Partii.gravity()` uses one convention everywhere: CoreMotion's (x right, y up, z out of the
  screen, in g). It's the same on iOS Safari/WKWebView and Android browsers, which report opposite
  signs, and on native builds (`Input.get_accelerometer()` scaled to g). Godot 4's web build has no
  `Input.get_accelerometer()`, which is why this exists.
- `Partii.motion_state()`:
  - `native`: a native build, so use it.
  - `unsupported`: no sensor (a desktop browser).
  - `needs_tap`: waiting for the player's tap. On iOS the browser asks only from a tap; inside
    Partii's frame Partii asks first. The addon asks from inside that tap's own gesture, so show
    something tappable ("Tap to turn on tilt").
  - `asking`: Partii's own "Motion sensors" question is up.
  - `reloading`: the player said yes in Partii; the game's frame reloads with motion allowed, and on
    iOS the next tap brings the browser's question.
  - `waiting`: asked, with no reading yet.
  - `granted`: readings are coming in. `Partii.motion_live()`: readings in the last second.
  - `denied`: the player said no. Offer touch controls.
- `Partii.motion_changed(state)` fires on every change.
- Calibrate against a base reading taken when play starts (players hold phones at many angles), and
  offer a "recalibrate" button.

## Testing headless

Chromium accepts synthetic events, so a test can tilt the phone:

```js
window.dispatchEvent(new DeviceMotionEvent("devicemotion",
  { accelerationIncludingGravity: { x: -4.9, y: 6, z: 6 }, interval: 16 }));
```

Use an Android device profile (Playwright `devices["Pixel 7"]`) so Godot's `web_android` feature
tag is set. The demo project's `tests/web/motion.mjs` and `frame-motion.mjs` are worked examples.
