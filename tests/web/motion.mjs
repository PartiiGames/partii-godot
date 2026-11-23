// Device motion in a plain page (no Partii frame), headless: the same tilt read on an Android phone
// and on an iPhone must give the same Partii.gravity() (CoreMotion axes, in g), though the two
// browsers report opposite signs. Android: no permission, readings flow at once. iPhone: the state is
// needs_tap until a tap, which calls DeviceMotionEvent.requestPermission (stubbed here and counted).
// Hard cap 120 s; a watchdog when no PROBE line comes for 30 s.
//   node tests/web/motion.mjs build/web
import { chromium, devices, serve, run, watch, near } from "./lib.mjs";

const r = run("MOTION", 120_000);
const game = await serve(process.argv[2] ?? "build/web");
const browser = await chromium.launch({ headless: true });
// The phone tilted 30° to the left (its left edge down), screen up: in CoreMotion axes, (-0.5, 0, -0.866) g.
const want = [-0.5, 0, -0.866];
const G = 9.80665;

async function phone(name, device, reading, ios) {
  const ctx = await browser.newContext({ ...devices[device] });
  await ctx.addInitScript(({ reading, ios }) => {
    if (ios) { window.__perms = 0; DeviceMotionEvent.requestPermission = () => { window.__perms++; return Promise.resolve("granted"); }; }
    setInterval(() => window.dispatchEvent(new DeviceMotionEvent("devicemotion", { accelerationIncludingGravity: reading, interval: 16 })), 16);
  }, { reading, ios });
  const page = await ctx.newPage();
  const w = watch(page, r);
  await page.goto(game.url + "index.html?probe=1", { timeout: 60_000 });
  if (ios) {
    await w.until(`${name}: needs a tap`, (p) => p.motion === "needs_tap");
    const vp = page.viewportSize();
    await page.touchscreen.tap(vp.width / 2, 40);
  }
  const p = await w.until(`${name}: tilt live`, (p) => p.motion === "granted" && p.live === true);
  r.log(name, "gravity", JSON.stringify(p.g));
  if (!p.g.every((v, i) => near(v, want[i]))) r.fail(`${name}: gravity ${JSON.stringify(p.g)}, want ${JSON.stringify(want)}`);
  if (ios) { const n = await page.evaluate(() => window.__perms); if (n !== 1) r.fail(`${name}: iOS asked ${n} times (want 1)`); }
  if (w.errors.length) r.fail(`${name}: console errors: ${w.errors.slice(0, 3).join(" | ")}`);
  await ctx.close();
}

// Android reports gravity with the opposite sign to iOS (m/s² either way).
await phone("Android (Pixel 7)", "Pixel 7", { x: 0.5 * G, y: 0, z: 0.866 * G }, false);
await phone("iPhone 13", "iPhone 13", { x: -0.5 * G, y: 0, z: -0.866 * G }, true);
await browser.close();
game.close();
r.pass();
