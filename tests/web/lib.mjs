// Shared by the tests: serve a web export from a folder, load Playwright, and follow the demo's
// "PROBE {json}" console lines (demo/demo.gd, ?probe=1).
import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { extname, join, resolve } from "node:path";
import { createRequire } from "node:module";

// PLAYWRIGHT_DIR: a node_modules folder with playwright in it (else it resolves from here).
const require = createRequire(process.env.PLAYWRIGHT_DIR ? join(process.env.PLAYWRIGHT_DIR, "x.js") : import.meta.url);
export const { chromium, devices } = require("playwright");

const types = { ".html": "text/html", ".js": "text/javascript", ".wasm": "application/wasm", ".pck": "application/octet-stream", ".png": "image/png", ".json": "application/json" };

/** Serves dir on 127.0.0.1 (a random port); resolves to its base address. */
export async function serve(dir, host = "127.0.0.1") {
  const root = resolve(dir);
  const s = createServer(async (req, res) => {
    const p = join(root, decodeURIComponent(new URL(req.url, "http://x").pathname).replace(/\/$/, "/index.html"));
    try { const b = await readFile(p); res.writeHead(200, { "content-type": types[extname(p)] ?? "application/octet-stream" }); res.end(b); }
    catch { res.writeHead(404).end(); }
  }).listen(0, host);
  await new Promise((r) => s.once("listening", r));
  return { url: `http://${host}:${s.address().port}/`, close: () => s.close() };
}

/** A run with a hard cap and a no-progress watchdog (no PROBE line for idleMs fails it). */
export function run(name, capMs, idleMs = 30_000) {
  const t0 = Date.now();
  const r = {
    lastProbe: Date.now(),
    log: (...a) => console.log(`[${((Date.now() - t0) / 1000).toFixed(1)}s]`, ...a),
    fail: (why) => { r.log(`${name} FAIL:`, why); process.exit(1); },
    pass: () => { r.log(`${name} PASS`); process.exit(0); },
  };
  setTimeout(() => r.fail(`hard cap ${capMs / 1000} s`), capMs).unref();
  setInterval(() => Date.now() - r.lastProbe > idleMs && r.fail(`no PROBE line for ${idleMs / 1000} s`), 1000).unref();
  return r;
}

/** Follows a page's probe lines and console errors. */
export function watch(page, r) {
  const w = { p: null, errors: [] };
  page.on("console", (m) => {
    const t = m.text();
    if (t.startsWith("PROBE ")) { r.lastProbe = Date.now(); w.p = JSON.parse(t.slice(6)); }
    else if (m.type() === "error" && !/^\s*at: |GDScript backtrace|\[\d+\] /.test(t)) w.errors.push(t);
  });
  page.on("pageerror", (e) => w.errors.push(String(e)));
  w.until = async (what, f, ms = 30_000) => {
    const end = Date.now() + ms;
    while (!(w.p && f(w.p))) {
      if (Date.now() > end) r.fail(`timed out: ${what} (last probe ${JSON.stringify(w.p)?.slice(0, 500)})`);
      await new Promise((ok) => setTimeout(ok, 100));
    }
    r.log("ok:", what);
    return w.p;
  };
  return w;
}

export const near = (a, b, eps = 0.02) => Math.abs(a - b) <= eps;
