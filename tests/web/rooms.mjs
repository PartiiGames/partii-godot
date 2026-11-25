// Rooms over Partii staging, headless: a host and GUESTS guests (default 2), each its own browser
// context, the export served under the game's staging address (a secure context, as on the real site).
// The host creates a room (demo/rooms_test.gd), guests join by its code, guests send inputs and the
// host broadcasts snapshots; pass when every page's window.__partiiTestReport says synced for HOLD s.
//   node tests/web/rooms.mjs <build/web> [--game smashii --site https://smashii-staging.partii.games/
//        --key pk_... --api https://api-staging.partii.games]
// Env: GUESTS, HOLD (seconds, default 8), PLAYWRIGHT_DIR. Hard cap 150 s; no probe line for 40 s fails.
import { readFile } from "node:fs/promises";
import { extname, join, resolve } from "node:path";
import { chromium, run } from "./lib.mjs";

const a = process.argv.slice(2);
const arg = (n, d) => (a.includes(n) ? a[a.indexOf(n) + 1] : d);
const dir = resolve(a[0] ?? "build/web");
const GAME = arg("--game", "smashii");
const SITE = arg("--site", "https://smashii-staging.partii.games/");
const KEY = arg("--key", "pk_smashii_web_j0GFKzE395-H9XhsNeaR8t");
const API = arg("--api", "https://api-staging.partii.games");
if (!/staging/.test(SITE) || !/staging/.test(API)) { console.error("rooms.mjs runs against staging only"); process.exit(2); }
const GUESTS = Number(process.env.GUESTS ?? 2);
const HOLD = Number(process.env.HOLD ?? 8);
const r = run("rooms", 150_000, 40_000);
const types = { ".html": "text/html", ".js": "text/javascript", ".wasm": "application/wasm", ".pck": "application/octet-stream", ".png": "image/png", ".json": "application/json" };

const browser = await chromium.launch({ args: ["--use-gl=angle", "--use-angle=swiftshader", "--mute-audio"] });
const pages = [];
async function open(i, room) {
  const ctx = await browser.newContext({ viewport: { width: 360, height: 640 } });
  // The export, served as the game's own staging site; everything else goes to the network.
  await ctx.route((u) => u.href.startsWith(SITE), async (route) => {
    const p = join(dir, new URL(route.request().url()).pathname.replace(/\/$/, "/index.html"));
    try { await route.fulfill({ status: 200, contentType: types[extname(p)] ?? "application/octet-stream", body: await readFile(p) }); }
    catch { await route.fulfill({ status: 404, body: "" }); }
  });
  const page = await ctx.newPage();
  const w = { i, p: null, errors: [] };
  page.on("console", (m) => {
    const t = m.text();
    if (t.startsWith("PROBE ")) { r.lastProbe = Date.now(); w.p = JSON.parse(t.slice(6)); if (w.p.ev || w.p.error) r.log(i ? `guest${i}` : "host", t.slice(6, 300)); }
    else if (m.type() === "error" && !/^\s*at: |GDScript backtrace|\[\d+\] /.test(t)) { w.errors.push(t); r.log(i ? `guest${i}` : "host", "console error:", t.slice(0, 300)); }
  });
  page.on("pageerror", (e) => { w.errors.push(String(e)); r.log(i ? `guest${i}` : "host", "pageerror:", String(e).slice(0, 300)); });
  const q = new URLSearchParams({ partii_game: GAME, partii_key: KEY, partii_api: API, partii_room: room, partii_test: i ? `guest${i}` : "host", partii_guests: String(GUESTS) });
  await page.goto(`${SITE}index.html?${q}`);
  w.page = page;
  w.report = () => page.evaluate(() => (typeof window.__partiiTestReport === "function" ? window.__partiiTestReport() : null)).catch(() => null);
  pages.push(w);
  return w;
}

const until = async (what, f, ms) => {
  const end = Date.now() + ms;
  for (;;) { const v = await f(); if (v) { r.log("ok:", what); return v; } if (Date.now() > end) r.fail(`timed out: ${what}`); await new Promise((ok) => setTimeout(ok, 250)); }
};

const host = await open(0, "new");
const code = await until("host made a room", async () => { const p = await host.report(); if (p?.error) r.fail(`host: ${p.error}`); return p?.code || null; }, 60_000);
r.log("room", code);
for (let i = 1; i <= GUESTS; i++) await open(i, code);
let since = 0;
let last = [];
await until(`all ${GUESTS + 1} pages synced for ${HOLD} s`, async () => {
  last = await Promise.all(pages.map((w) => w.report()));
  const bad = last.map((p, i) => (p?.synced ? null : `${i ? `guest${i}` : "host"}: ${JSON.stringify(p)?.slice(0, 200)}`)).filter(Boolean);
  for (const p of last) if (p?.error) r.fail(p.error);
  if (bad.length) { since = 0; return false; }
  if (!since) since = Date.now();
  return Date.now() - since >= HOLD * 1000;
}, 80_000);
for (const [i, p] of last.entries()) r.log(i ? `guest${i}` : "host", JSON.stringify(p));
const errs = pages.flatMap((w) => w.errors);
if (errs.length) r.fail(`${errs.length} console errors`);
await browser.close();
r.pass();
