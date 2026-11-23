// Device motion inside Partii's frame, as an iPhone, headless. A stand-in for Partii's page (another
// origin, the same messages as Partii's host: hw-hello, hw asks with phase "open" and a result, a
// "reload" answer) frames the build. Partii's question must come first: the first tap asks Partii,
// whose yes reloads the frame with motion allowed; then the next tap asks iOS
// (DeviceMotionEvent.requestPermission, stubbed and counted) and tilt goes live.
// Hard cap 120 s; a watchdog when no PROBE line comes for 30 s.
//   node tests/web/frame-motion.mjs build/web
import { createServer } from "node:http";
import { chromium, devices, serve, run, watch } from "./lib.mjs";

const r = run("FRAME MOTION", 120_000);
const game = await serve(process.argv[2] ?? "build/web");
const gameUrl = game.url + "index.html?probe=1";
// Partii's page: frames the game with motion only once allowed; answers hw-hello and hw asks.
const hostHtml = `<!doctype html><meta name=viewport content="width=device-width"><style>html,body{margin:0;height:100%;background:#000}iframe{border:0;width:100%;height:100%}</style>
<iframe id=f allow="gamepad; fullscreen; autoplay" src="${gameUrl}"></iframe>
<script>
const f = document.getElementById("f");
window.t = { hellos: 0, asks: 0, perms: 0, allowed: false };
const post = (m) => f.contentWindow.postMessage({ partii: "ui", ...m }, "*");
addEventListener("message", (e) => {
  if (e.source !== f.contentWindow || !e.data) return;
  const d = e.data;
  if (d.test === "perm") return void t.perms++;
  if (d.partii !== "jam") return;
  if (d.op === "hw-hello") { t.hellos++; return post({ op: "hw", granted: t.allowed ? ["motion"] : [] }); }
  if (d.op === "hw" && d.want === "motion") {
    t.asks++;
    post({ op: "hw", id: d.id, phase: "open" });
    // The player taps Allow in Partii's modal: the frame gets motion on its next load.
    setTimeout(() => { t.allowed = true; f.setAttribute("allow", "gamepad; fullscreen; autoplay; accelerometer; gyroscope; magnetometer"); post({ op: "hw", id: d.id, result: { ok: false, reason: "reload" } }); }, 300);
  }
});
</script>`;
// "localhost" vs the game's 127.0.0.1: another origin, as Partii's page is to a game.
const host = createServer((req, res) => { res.writeHead(200, { "content-type": "text/html" }); res.end(hostHtml); }).listen(0, "localhost");
await new Promise((ok) => host.once("listening", ok));

const browser = await chromium.launch({ headless: true });
const ctx = await browser.newContext({ ...devices["iPhone 13"], viewport: { width: 390, height: 844 } });
// In the game's frame: iOS's requestPermission (counted, granted), and an upright phone's readings.
await ctx.addInitScript(() => {
  if (window.parent === window) return;
  DeviceMotionEvent.requestPermission = () => { parent.postMessage({ test: "perm" }, "*"); return Promise.resolve("granted"); };
  setInterval(() => window.dispatchEvent(new DeviceMotionEvent("devicemotion", { accelerationIncludingGravity: { x: 0, y: -6.93, z: -6.93 }, interval: 16 })), 16);
});
const page = await ctx.newPage();
const w = watch(page, r);
await page.goto(`http://localhost:${host.address().port}/`, { timeout: 60_000 });
const counts = () => page.evaluate(() => ({ ...window.t }));
await w.until("in the frame, tilt needs a tap", (p) => p.motion === "needs_tap");
r.log("tap 1 (asks Partii)");
await page.touchscreen.tap(195, 40);
{
  const end = Date.now() + 20_000;
  while ((await counts()).hellos < 2) { if (Date.now() > end) r.fail(`the frame didn't reload after Partii's yes (host ${JSON.stringify(await counts())})`); await new Promise((ok) => setTimeout(ok, 100)); }
  w.p = null;
}
await w.until("Partii allowed it: the frame reloaded, and iOS needs a tap", (p) => p.motion === "needs_tap", 20_000);
let c = await counts();
r.log("host:", JSON.stringify(c));
if (c.asks !== 1) r.fail(`Partii was asked ${c.asks} times (want 1)`);
if (c.perms !== 0) r.fail("iOS was asked before Partii allowed the frame");
r.log("tap 2 (asks iOS)");
await page.touchscreen.tap(195, 40);
await w.until("tilt live", (p) => p.motion === "granted" && p.live === true);
c = await counts();
r.log("host:", JSON.stringify(c));
if (c.perms !== 1) r.fail(`iOS was asked ${c.perms} times (want 1)`);
if (c.asks !== 1) r.fail(`Partii was asked again (${c.asks})`);
if (w.errors.length) r.fail("console errors: " + w.errors.slice(0, 5).join(" | "));
await browser.close();
game.close(); host.close();
r.pass();
