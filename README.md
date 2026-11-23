# Partii for Godot

A small Godot 4 addon that lets a game exported to the **web** use [Partii](https://partii.games):
the player (signed in automatically inside Partii, else a guest on this device), cloud saves,
purchases (Pops items and unlocking the full game), leaderboards, device motion (tilt) inside
Partii's frame, a "really playing" heartbeat, and analytics and error reports. Off the web every call
falls back cleanly (a local guest, saves in `user://`, `unavailable` for Partii-only calls), so one
code path fits desktop, native and web.

It came out of porting a Godot 3 tilt-to-steer arcade game to Godot 4 and Partii. The things that
cost the most time on that port are in [TRAPS.md](TRAPS.md).

MIT licensed ([LICENSE](LICENSE)), by Partii Games. This repo is the source of truth; [partii-examples](https://github.com/PartiiGames/partii-examples) example 13 points here. Godot 4.3 or newer (tested on 4.6.1), Compatibility renderer.

## What's here

| Path | What |
|---|---|
| `addons/partii/` | The addon: copy this folder into your game. Its [README](addons/partii/README.md) is the full guide. |
| `addons/partii/partii.gd` | The `Partii` autoload (GDScript), the calls below. |
| `addons/partii/partii-sdk.js` | The browser half: the Partii web SDK bundled with `web/partii-godot.ts`. Shipped inside the export. |
| `addons/partii/web/` | Its source and `build.sh`, to rebuild `partii-sdk.js`. |
| `demo/` | One screen that uses every call: player, a cloud-saved counter, a leaderboard, the unlock, tilt. |
| `web/partii.json` | An example manifest, copied next to `index.html` in your export. |
| `tests/web/` | Headless browser tests (Playwright) against the demo's web export. |
| `icon.png`, `tools/` | The Asset Library icon (`tools/make-icon.py` draws it) and `tools/check-plugin-cfg.sh` (plugin.cfg name, author, version; the library zip holds only `addons/`). |

## Install

1. Get `addons/partii/` into your project: from Godot's **AssetLib** tab (search "Partii"), or copy the folder from this repo. The Asset Library zip holds only `addons/` (`.gitattributes`).
2. **Project → Project Settings → Plugins:** enable **Partii**. This adds the `Partii` autoload.
3. **Export → Web:**
   - turn **Thread Support off** (Partii's iPhone app frame isn't cross-origin isolated);
   - under Resources, add `addons/partii/partii-sdk.js` to **Filters to export non-resource files**.
4. Put a `partii.json` next to the exported `index.html` that declares the hardware you use, with the
   reason players will see (see `web/partii.json`):
   ```json
   { "hardware": { "motion": "Tilt your phone to steer" } }
   ```
5. In your first scene: `await Partii.configure("<your game id>", "<publishable key pk_...>")`, then
   `await Partii.sign_in()`. The publishable key comes from `partii keys create <game>` and is not a
   secret; never put a developer token in a game.
6. `partii web deploy <game> build/web`.

## The calls

Every call that talks to Partii is awaited and returns a Dictionary: `{ok: true, ...}` or
`{ok: false, reason, message?}`.

| Call | What |
|---|---|
| `Partii.available()` | `true` on a web build with the SDK; `false` on desktop/native (the fallbacks run). |
| `await Partii.configure(game, key, api := "")` | Once, at start. `api` only to point at another Partii API (staging). |
| `await Partii.sign_in()` | `{ok, player: {id, name, guest}}`. Inside Partii (its app or partii.games): the account, no tap. Elsewhere: this device's guest, whose saves, items and scores move to the account on sign-in. |
| `await Partii.load_slot(slot)` | `{ok, data, rev}`; `data` is `null` before the first save. Off the web: `user://partii/<slot>.json`. |
| `await Partii.save_slot(slot, data)` | Any JSON. A newer save from another device: `{ok: false, reason: "conflict", theirs}`, so merge, `load_slot`, save again. |
| `await Partii.items()` | `{ok, items}`, the player's items for this game. `sign_in` and `buy` refresh it. |
| `Partii.owns(item)` / `Partii.owns_full_game()` | From the last `items()`. |
| `await Partii.buy(item, quantity := 0)` | From a tap. Partii shows its own buy sheet. Reasons: `cancelled`, `popup_blocked` (with `url`), `timeout`, `not_signed_in`, `unavailable`, `failed`. |
| `await Partii.unlock()` | Buys `full_game` (a free intro, then the full game), or ok at once when it's owned. |
| `await Partii.submit_score(board, score, meta := {})` | Once per run. The board appears on the first submit (higher is better). Returns the player's best and rank for today, this week and all time. |
| `await Partii.leaderboard(board, period := "all", limit := 10)` | `{entries: [{rank, display_name, score}], me: {rank, score}}`; `period` is `daily`, `weekly` or `all`. |
| `Partii.set_playing(on)` / `Partii.is_playing()` | Really playing (not paused, a menu, game over): Partii's "playing now" and playtime. |
| `Partii.track(event, props := {})` | An analytics event. Sessions, motion changes and errors are reported on their own. |
| `Partii.gravity()` | `Vector3` in g, CoreMotion axes (x right, y up, z out of the screen; flat face up is `(0, 0, -1)`), the same on iOS and Android browsers and on native builds. |
| `Partii.motion_state()` | `native`, `unsupported`, `needs_tap`, `asking`, `reloading`, `waiting`, `granted`, `denied`. |
| `Partii.motion_live()` | Readings in the last second: tilt can steer now. |
| `Partii.is_touch_device()` | A phone or tablet (native, or a browser on one). |
| signal `motion_changed(state)` | Each motion state change. |
| signal `visibility_changed(visible)` | The page was hidden or shown (the app sent to the background, another tab). |

More detail, with code, is in [addons/partii/README.md](addons/partii/README.md).

## The demo

`demo/demo.tscn` is the main scene. Set `GAME` and `KEY` in `demo/demo.gd` (or, on the web, add
`?game=<id>&key=<pk_...>` to the page address), export for Web, and serve `build/web`. It shows who's
playing, a counter in a cloud save, "send the count as a score" with the board, the unlock button,
and the motion state with the gravity reading.

## Tests

Export the demo first (headless):

```sh
godot --headless --path . --export-release Web build/web/index.html
```

Then, with [Playwright](https://playwright.dev) installed (`npm i playwright`, or point
`PLAYWRIGHT_DIR` at a `node_modules` that has it):

| Test | Needs | Checks |
|---|---|---|
| `node tests/web/motion.mjs build/web` | nothing | An Android phone and an iPhone tilted the same way give the same `gravity()`; iOS asks for permission once, from a tap. |
| `node tests/web/frame-motion.mjs build/web` | nothing | Inside a stand-in for Partii's frame (another origin, Partii's messages): Partii is asked first, its yes reloads the frame, then iOS is asked on the next tap and tilt goes live. |
| `node tests/web/staging.mjs build/web` | a **staging** game: `PARTII_GAME`, `PARTII_KEY`, `PARTII_API` | Guest sign-in, save and load, a score and the board, analytics accepted. Skipped without them. |

Each has a hard time cap and fails if the page stops reporting for 30 s. The demo's `?probe=1` prints
one `PROBE {json}` console line every 250 ms with its state; the tests read those lines.

## Rebuilding partii-sdk.js

```sh
PARTII_SDK=<the Partii web SDK source, sdk/ts/src> ESBUILD=esbuild addons/partii/web/build.sh
```
