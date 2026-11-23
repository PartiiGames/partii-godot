// The browser half of Partii for Godot: the Partii web SDK (sdk/ts: createClient, autoSignIn, buy)
// behind one entry the addon's GDScript calls through JavaScriptBridge:
//   window.__partii_godot_sdk.invoke(name, argsJson, id, callback)  (not "call": in GDScript that is Object.call)  →  callback(id, resultJson)
// Every result is {ok: true, ...} or {ok: false, reason, message?}. Built into ../partii-sdk.js by build.sh.
import { createClient, PartiiError, type PartiiClient } from "@partii/sdk/client";
import { autoSignIn } from "@partii/sdk/autosignin";
import { buy } from "@partii/sdk/buy";

/** The full game's unlock: the one item with this id (edge pops.ts FULL_GAME). */
const FULL_GAME = "full_game";

type Cfg = { game: string; key: string; api?: string };
let cfg: Cfg | null = null;
let client: PartiiClient | null = null;
let player: { id: string; name: string; guest: boolean } | null = null;
let token: string | null = null;

const DEVICE = () => `partii_godot:${cfg?.game}:device`;
const store = {
  get: (k: string) => { try { return localStorage.getItem(k); } catch { return null; } },
  set: (k: string, v: string) => { try { localStorage.setItem(k, v); } catch { /* private mode */ } },
};
const apiBase = () => cfg?.api ?? (/(^|\.)staging\.partii\.games$|-staging\.partii\.games$/.test(location.hostname) ? "https://api-staging.partii.games" : "https://api.partii.games");
const fail = (e: unknown) => (e instanceof PartiiError ? { ok: false, reason: e.code, message: e.message, status: e.status } : { ok: false, reason: "failed", message: String(e) });
const who = (p: any, guest: boolean) => (player = { id: String(p?.id ?? ""), name: String(p?.display_name ?? p?.name ?? ""), guest });
const need = () => { if (!client || !cfg) throw new PartiiError("not_configured", "Partii.configure(game, key) first", "", 0, null); return client; };

// The playing heartbeat (playerPlaying, docs/GUIDE.md): only while the player is really playing (not
// paused, on a menu or idle), every 60 s with how many real inputs came since the last one; the page
// hidden counts as not playing. stopped when play ends.
let playing = false;
let inputs = 0;
let beat: ReturnType<typeof setInterval> | null = null;
for (const t of ["keydown", "pointerdown", "touchstart", "gamepadconnected"]) addEventListener(t, () => { inputs++; }, { capture: true, passive: true });
const send = (state: "playing" | "stopped") => {
  if (!client || !cfg || !player) return;
  const input = inputs;
  inputs = 0;
  client.playerPlaying({ game: cfg.game, state, ...(state === "playing" ? { input } : {}) }).catch(() => {});
};
const setBeat = () => {
  const on = playing && document.visibilityState === "visible";
  if (on && !beat) { send("playing"); beat = setInterval(() => send("playing"), 60_000); }
  else if (!on && beat) { clearInterval(beat); beat = null; send("stopped"); }
};
document.addEventListener("visibilitychange", setBeat);
addEventListener("pagehide", () => { if (beat) { clearInterval(beat); beat = null; send("stopped"); } });

// Analytics (analyticsIngest, errorsIngest: the game's numbers in `partii analytics summary`/`events`
// and grouped errors in `partii errors`). One session per page load; session_start at configure and
// session_end {secs} whenever the page is hidden or left (secs counts from launch; the largest wins).
// Errors: uncaught JS errors, rejected promises, and the engine's own error lines on the console
// (Godot's SCRIPT ERROR, ERROR, USER ERROR with their "at:" line); a WebAssembly abort is a panic.
// Each distinct message once a session, at most 20. Events and errors before configure wait for it.
const UA = navigator.userAgent || "";
const OS_ = /iPad|iPhone|iPod/.test(UA) || (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1) ? "ios" : /Android/.test(UA) ? "android" : "desktop";
const FRAMED = (() => { try { return window.top !== window; } catch { return true; } })();
const SESSION = (typeof crypto.randomUUID === "function" ? crypto.randomUUID() : `${Date.now()}${Math.random()}`).replace(/[^A-Za-z0-9_-]/g, "").slice(0, 64);
const T0 = Date.now();
let version = "";
const events: { name: string; at: number; session: string; props: Record<string, unknown> }[] = [];
const errors: { kind: string; message: string; backtrace: string; context: Record<string, unknown>; session: string; at: number }[] = [];
const seen = new Set<string>();
const post = (path: string, body: unknown, keepalive: boolean) => {
  if (!cfg) return;
  const headers: Record<string, string> = { "content-type": "application/json", "x-partii-key": cfg.key };
  if (token) headers.authorization = `Bearer ${token}`;
  fetch(`${apiBase()}/v1/games/${encodeURIComponent(cfg.game)}${path}`, { method: "POST", headers, body: JSON.stringify(body), keepalive }).catch(() => {});
};
const device = () => {
  let d = store.get(DEVICE());
  if (!d) { d = `godot-${crypto.randomUUID()}`; store.set(DEVICE(), d); }
  return d;
};
const batch = () => ({ device: device(), platform: "web", version, build: OS_ });
const flush = (keepalive = false) => {
  if (!cfg) return;
  while (events.length) post("/events", { ...batch(), events: events.splice(0, 100) }, keepalive);
  while (errors.length) post("/errors", { ...batch(), errors: errors.splice(0, 20) }, keepalive);
};
const track = (name: string, props: Record<string, unknown> = {}) => {
  events.push({ name, at: Date.now(), session: SESSION, props: { os: OS_, framed: FRAMED, ...props } });
  // Hidden already (a pause that follows the page going away): send now, it may not come back.
  if (events.length >= 50 || document.visibilityState === "hidden") flush(document.visibilityState === "hidden");
};
let lastErr: (typeof errors)[number] | null = null;
const report = (kind: "panic" | "error", message: string, backtrace = "") => {
  message = message.trim().slice(0, 2000);
  if (!message || seen.has(message) || seen.size >= 20) return;
  seen.add(message);
  lastErr = { kind, message, backtrace, context: { os: OS_, framed: FRAMED, secs: Math.round((Date.now() - T0) / 1000) }, session: SESSION, at: Date.now() };
  errors.push(lastErr);
  setTimeout(() => flush(), 1500); // after the "at:" line that follows an engine error
};
const PANIC = /Aborted\(|RuntimeError|unreachable|out of memory/i;
addEventListener("error", (e) => report(PANIC.test(String(e.message)) ? "panic" : "error", String(e.message || e.error || "error"), `${e.filename ?? ""}:${e.lineno ?? 0}:${e.colno ?? 0}\n${e.error?.stack ?? ""}`));
addEventListener("unhandledrejection", (e) => { const r: any = e.reason; report(PANIC.test(String(r)) ? "panic" : "error", `unhandled rejection: ${r?.message ?? r}`, String(r?.stack ?? "")); });
const ENGINE = /^(USER )?(SCRIPT )?ERROR: /;
const consoleError = console.error.bind(console);
console.error = (...a: unknown[]) => {
  consoleError(...a);
  const m = a.map((x) => (typeof x === "string" ? x : x instanceof Error ? x.message : String(x))).join(" ");
  if (/^\s*at: /.test(m) && lastErr && errors.includes(lastErr)) { lastErr.backtrace += m.trim() + "\n"; return; }
  if (ENGINE.test(m)) { const [head, ...rest] = m.split("\n"); report("error", head, rest.join("\n")); }
  else if (PANIC.test(m)) report("panic", m);
};
setInterval(() => flush(), 15_000);
const end = () => { track("session_end", { secs: Math.round((Date.now() - T0) / 1000) }); flush(true); };
document.addEventListener("visibilitychange", () => { if (document.visibilityState === "hidden") end(); });
addEventListener("pagehide", end);

const calls: Record<string, (...a: any[]) => Promise<unknown>> = {
  async configure(game: string, key: string, api?: string, ver?: string) {
    const first = !cfg;
    cfg = { game, key, ...(api ? { api } : {}) };
    version = String(ver ?? "").slice(0, 64);
    client = createClient({ base: apiBase(), key });
    if (first) { events.unshift({ name: "session_start", at: T0, session: SESSION, props: { os: OS_, framed: FRAMED } }); flush(); }
    return { ok: true, session: SESSION };
  },
  // Signed in as the Partii account when Partii can vouch (its app or partii.games, no tap), else a
  // guest on this device (its saves merge into the account when the player signs in later).
  async signIn() {
    const c = need();
    // Tests on Partii staging only: a test account's player token set in sessionStorage (partii_godot:test_player_token).
    const test = /-staging\.partii\.games$/.test(location.hostname) ? (() => { try { return sessionStorage.getItem("partii_godot:test_player_token"); } catch { return null; } })() : null;
    if (test) {
      c.setPlayerToken(test);
      token = test;
      const me: any = await c.playersMe();
      return { ok: true, player: who(me.player ?? me, false), test: true };
    }
    // This device's guest first (asking again with the same id renews it), so a sign-in merges it.
    const g: any = await c.playersGuest({ device_id: device() });
    c.setPlayerToken(g.player_token);
    token = g.player_token;
    // A guest has no sign-in but this device (edge players.ts view: providers).
    const guest = !((g.player?.providers ?? []) as unknown[]).some((p) => (typeof p === "string" ? p : (p as any)?.provider) !== "device");
    who(g.player, guest);
    if (guest) {
      try {
        const a = await autoSignIn(c);
        if (a && "player_token" in a) { token = (a as any).player_token; return { ok: true, player: who(a.player, false), merged: a.merged }; }
      } catch { /* stay the guest */ }
    }
    return { ok: true, player };
  },
  async player() { return { ok: true, player }; },
  async track(name: string, props?: Record<string, unknown>) { track(String(name), props && typeof props === "object" ? props : {}); return { ok: true }; },
  async setPlaying(on: boolean) { playing = !!on; setBeat(); return { ok: true, playing }; },
  async load(slot: string) {
    try { const r: any = await need().savesGet(cfg!.game, slot); return { ok: true, data: r.save?.data ?? null, rev: r.save?.rev ?? 0 }; }
    catch (e) { if (e instanceof PartiiError && e.status === 404) return { ok: true, data: null, rev: 0 }; throw e; }
  },
  async save(slot: string, data: unknown, rev: number) {
    try { const r: any = await need().savesPut(cfg!.game, slot, { data, rev }); return { ok: true, rev: r.save?.rev ?? r.rev ?? rev + 1 }; }
    catch (e) {
      // A newer save from another device: hand both to the game to merge.
      if (e instanceof PartiiError && e.status === 409) return { ok: false, reason: "conflict", theirs: (e.body as any)?.error?.theirs ?? (e.body as any)?.theirs ?? null };
      throw e;
    }
  },
  async items() { const r: any = await need().playersItems({ game: cfg!.game }); return { ok: true, items: r.items ?? [] }; },
  // Partii shows the buy sheet (over the game in Partii, else a popup), never the game. Call it from a tap.
  // Unlock the full game (the item full_game: sdk/ts buy.ts unlock, branch tips-and-unlock): owned already, ok at once.
  async unlock() {
    const c = need();
    const r: any = await c.playersItems({ game: cfg!.game }).catch(() => null);
    if ((r?.items ?? []).some((h: any) => h.game === cfg!.game && h.item === FULL_GAME && h.count > 0)) return { ok: true, item: FULL_GAME, owned: true };
    return await buy(c, { game: cfg!.game, item: FULL_GAME });
  },
  async buy(item: string, quantity?: number) { return await buy(need(), { game: cfg!.game, item, ...(quantity ? { quantity } : {}) }); },
  // Leaderboards (edge api/leaderboards.ts): one submit per run, as the signed-in player or this device's
  // guest; each board keeps the player's best for today, this week and all time.
  async submitScore(board: string, score: number, meta?: Record<string, unknown>) {
    if (!token) return { ok: false, reason: "not_signed_in" };
    const r: any = await need().leaderboardSubmit(cfg!.game, board, { score: Number(score), ...(meta && typeof meta === "object" && Object.keys(meta).length ? { meta } : {}) });
    return { ok: true, ...r };
  },
  // The top players (period daily, weekly or all; limit 1-100) and, signed in, me: this player's best and rank.
  async leaderboard(board: string, period?: string, limit?: number) {
    const r: any = await need().leaderboardGet(cfg!.game, board, { period: period || "all", limit: limit || 10 });
    return { ok: true, ...r };
  },
};

(window as any).__partii_godot_sdk = {
  session: SESSION,
  invoke(name: string, argsJson: string, id: number, cb: (id: number, json: string) => void) {
    const f = calls[name];
    const args = (() => { try { return JSON.parse(argsJson || "[]"); } catch { return []; } })();
    (f ? f(...args) : Promise.resolve({ ok: false, reason: "unknown_call", message: name }))
      .catch(fail)
      .then((r) => cb(id, JSON.stringify(r ?? { ok: true })));
  },
};
