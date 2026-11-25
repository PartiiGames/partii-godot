// The rooms engine (partii-net compiled to wasm: the monorepo's platform/sdk/engine-web, copied into
// ./engine) as a plain script for Godot: window.__partii_engine = {initSync, WebEngine}. build.sh bundles
// it into ../partii-engine.js; the wasm ships as ../partii-engine.wasm. The addon loads both only on the
// first room call (Partii.create_room, join_room, quick_play).
import { initSync, WebEngine } from "./engine/partii_engine.js";
(globalThis as any).__partii_engine = { initSync, WebEngine };
