# Traps

These are things that broke without any error while a Godot 3 tilt game was ported to Godot 4 and put
on Partii. Each one cost a round of "it looks wrong on my phone". Check these first.

## Godot 3 → 4: properties dropped without a warning

`godot --convert-3to4` renames a lot, but Godot 4 **ignores** a property it doesn't know when it loads
a scene. You get no error, just the default value. These were all missed:

| Godot 3 (in .tscn) | Godot 4 | What you see if it's missed |
|---|---|---|
| ParticlesMaterial / CPUParticles2D `initial_velocity`, `scale` / `scale_amount`, `damping`, `angular_velocity`, `orbit_velocity`, `linear_accel`, `radial_accel`, `tangential_accel`, `angle`, `hue_variation`, `anim_speed`, `anim_offset` (each with its `*_random`) | `*_min` and `*_max` (`min = value × (1 − random)`, `max = value`) | Particles that don't move (speed 0) and are tiny (size 1): explosions become still dots |
| `emission_shape` 2 and up | **+1** (Godot 4 inserted `SPHERE_SURFACE` at 2) | A box emitter becomes a sphere outline |
| `flag_disable_z`, `flag_align_y`, `flag_rotate_y` | `particle_flag_disable_z` and so on | 2D particles fly off into z and look slow |
| Particles `local_coords` left out (Godot 3's default was **true**) | Godot 4's default is **false**: write `local_coords = true` | Particles stay behind when the emitter moves |
| AnimationPlayer `playback_speed` | `speed_scale` | Animations at 1× (an asteroid's 0.2× spin came out 5× too fast) |
| Animation `loop = true` | `loop_mode = 1` | An animation plays once and stops |
| TextureButton `expand = true` | `ignore_texture_size = true` | Buttons drawn at their texture's full size (huge on a phone) |
| TextureRect `expand = true` | `expand_mode = 1` (and `stretch_mode` values move down by 1) | Images at their full size, or stretched the wrong way |
| Label `align` / `valign` | `horizontal_alignment` / `vertical_alignment` | Text left-aligned |
| Label `autowrap = true` | `autowrap_mode = 3` | Long text runs off the screen |
| Control `rect_rotation` (degrees) | `rotation` is in **radians** | A 35° tilt hint spins wildly |

`RectangleShape2D.extents` is fine: Godot 4 converts it to `size` (×2) itself.

**Find them all in a few seconds:** for each `.tscn`, load it, then for every node compare the
property names in its `SceneState` with `ClassDB.instantiate(type).get_property_list()`. Any name
that isn't there was dropped. Skip `script`, `metadata/*` and the names a node's own script exports.
Sub-resources (materials, animations) need the same check against their class.

```gdscript
var st: SceneState = load(path).get_state()
for i in st.get_node_count():
    var obj = ClassDB.instantiate(st.get_node_type(i)) if ClassDB.can_instantiate(st.get_node_type(i)) else null
    if obj == null: continue
    var names := {}
    for p in obj.get_property_list(): names[p.name] = true
    for j in st.get_node_property_count(i):
        var n := st.get_node_property_name(i, j)
        if not names.has(n) and n != "script" and not n.contains("/"):
            print("dropped: ", path, " ", st.get_node_name(i), " ", n)
```

## Godot 4 on the web

- **Threads off.** Partii's iPhone app (a WKWebView frame) isn't cross-origin isolated, so a threaded
  export never starts there. Use a single-threaded export (Godot 4.3+).
- **No accelerometer.** `Input.get_accelerometer()` is zero on a Godot 4 web build. Use
  `Partii.gravity()`, which reads `devicemotion`.
- **iOS and Android disagree on sign.** iOS reports `accelerationIncludingGravity` in CoreMotion's
  convention, Android the opposite. `Partii.gravity()` makes both CoreMotion (in g).
- **`OS.get_name()` is "Web" on a phone too.** "Is this a phone?" is `OS.has_feature("web_ios")` or
  `OS.has_feature("web_android")` (or `Partii.is_touch_device()`), not `OS.get_name() == "iOS"`.
- **`JavaScriptObject.call()` is Godot's own `Object.call`.** Name a JS method something else
  (the addon uses `invoke`), or the call never reaches JavaScript.
- **Autoloads pause with the tree.** A heartbeat or analytics autoload needs
  `process_mode = PROCESS_MODE_ALWAYS`, or it stops whenever the game pauses.
- **`visibilitychange` fires on `document`, not `window`.** A listener on `window` never hears it.

## Device motion inside a frame (Partii, or any site that frames your game)

- **iOS refuses motion in a frame without `allow`, with no error.** Without
  `allow="accelerometer; gyroscope; magnetometer"` on the iframe,
  `DeviceMotionEvent.requestPermission()` comes back `denied` without asking the player. A game
  can't add that attribute itself. Inside Partii, the frame gets it after the player says yes in
  Partii's own "Motion sensors" question, and then the frame **reloads**.
- **So ask Partii first.** Declare `"hardware": {"motion": "<why>"}` in `partii.json`. On the first tap
  the addon asks Partii (`{partii: "jam", op: "hw", want: "motion"}`). A `reload` answer means the
  frame reloads with motion allowed, and on iOS the **next** tap asks the browser. The states are
  `needs_tap`, `asking`, `reloading`, `needs_tap` again (iOS), then `granted`. Show "Tap to turn on
  tilt" while the state is `needs_tap`.
- **iOS asks only from inside a tap's own gesture.** Call `requestPermission` in a capture-phase
  `touchend`/`click` listener, before the engine handles the event. Calling it later from GDScript,
  once the gesture has ended, fails.
- **Always have a fallback** (a touch stick) for `denied` and `unsupported`.

## Testing headless

- **Fake tilt works.** Chromium accepts
  `new DeviceMotionEvent("devicemotion", {accelerationIncludingGravity: {...}})`. Use a phone device
  profile so Godot sets `web_android` / `web_ios`.
- **A synthetic `blur` doesn't reach Godot.** To test pausing, have a test hook send
  `NOTIFICATION_APPLICATION_FOCUS_OUT` to the scene.
- **A synthetic `visibilitychange` must bubble and go to `document`:**
  `document.dispatchEvent(new Event("visibilitychange", {bubbles: true}))`, with
  `document.visibilityState` redefined to `"hidden"`.
- **Give every test a hard time cap and a "no progress" watchdog.** A web export that fails to start
  just sits there, with nothing on the console.
- **Tap game coordinates, not page coordinates.** With `stretch_mode = viewport` and `keep`, the game
  is scaled by `min(w / W, h / H)` and centred. Read a button's real position from a screenshot or
  from the scene, not from a guess at its anchors.
