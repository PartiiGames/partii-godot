// The Partii calls against a real Partii API (use a STAGING game, never production), headless: the
// demo's ?auto=1 signs in as this browser's guest, saves and loads a counter, submits a score of 42,
// reads the board and sends an analytics event. Every result must be ok, the board must list the
// score, and every analytics POST must be accepted. Needs your own game:
//   PARTII_GAME=<game id> PARTII_KEY=<its publishable key, pk_...> PARTII_API=https://api-staging.partii.games \
//     node tests/web/staging.mjs build/web
// Without them it says so and exits 0 (skipped). Hard cap 90 s; a watchdog when no PROBE line comes for 30 s.
import { chromium, devices, serve, run, watch } from "./lib.mjs";

const { PARTII_GAME: game, PARTII_KEY: key, PARTII_API: api } = process.env;
if (!game || !key || !api) { console.log("STAGING SKIPPED: set PARTII_GAME, PARTII_KEY and PARTII_API (a staging game)"); process.exit(0); }
if (!/staging/.test(api)) { console.log("STAGING REFUSED: PARTII_API should be a staging API"); process.exit(1); }
const r = run("STAGING", 90_000);
const web = await serve(process.argv[2] ?? "build/web");
const browser = await chromium.launch({ headless: true });
const ctx = await browser.newContext({ ...devices["Pixel 7"] });
const page = await ctx.newPage();
const w = watch(page, r);
const posts = [];
const refused = [];
page.on("response", (res) => {
  const u = new URL(res.url());
  const m = res.request().method();
  if (m === "POST" && /\/(events|errors)$/.test(u.pathname)) posts.push(`${u.pathname.split("/").pop()} ${res.status()}`);
  // A new player has no save yet: Partii answers GET /v1/saves/<game>/<slot> with 404 (load_slot gives data null).
  // The browser logs that as "Failed to load resource"; any other refused request fails the test.
  if (res.status() >= 400 && !(m === "GET" && res.status() === 404 && /\/v1\/saves\/[^/]+\/[^/]+$/.test(u.pathname))) refused.push(`${m} ${u.pathname} ${res.status()}`);
});
const q = new URLSearchParams({ probe: "1", auto: "1", game, key, api });
await page.goto(`${web.url}index.html?${q}`, { timeout: 60_000 });
const p = await w.until("every call ran", (p) => p.auto && p.auto.done, 45_000);
const a = p.auto;
r.log("player:", JSON.stringify(p.player));
r.log("results:", JSON.stringify({ save: a.save.ok, load: a.load.data, score: a.score.best?.all, board: (a.board.entries ?? []).map((e) => e.score) }));
if (!p.player?.id) r.fail("no player (sign-in failed)");
for (const k of ["save", "load", "score", "board"]) if (!a[k]?.ok) r.fail(`${k}: ${JSON.stringify(a[k])}`);
if (a.load.data?.count !== p.count) r.fail(`load gave ${JSON.stringify(a.load.data)}, saved count ${p.count}`);
if (!(a.board.entries ?? []).some((e) => e.score === 42) && a.board.me?.score !== 42) r.fail("the board doesn't list the score 42");
// Analytics go out every 15 s or when the page is hidden: hide it.
await page.evaluate(() => { Object.defineProperty(document, "visibilityState", { value: "hidden", configurable: true }); document.dispatchEvent(new Event("visibilitychange", { bubbles: true })); });
await new Promise((ok) => setTimeout(ok, 3000));
r.log("analytics posts:", posts.join(", "));
if (!posts.some((x) => x === "events 200")) r.fail("no analytics batch was accepted");
if (posts.some((x) => !x.endsWith(" 200"))) r.fail("a POST was refused: " + posts.join(", "));
if (refused.length) r.fail("refused requests: " + refused.join(", "));
const errors = w.errors.filter((e) => !/^Failed to load resource: the server responded with a status of 404/.test(e));
if (errors.length) r.fail("console errors: " + errors.slice(0, 5).join(" | "));
await browser.close();
web.close();
r.pass();
