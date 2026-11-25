/* tslint:disable */
/* eslint-disable */

/**
 * The engine for web pages (JavaScript). One per page.
 */
export class WebEngine {
    free(): void;
    [Symbol.dispose](): void;
    /**
     * Sign in on this live connection without reconnecting: a player token
     * (`"pt_…"`), or `null`/`undefined` to sign out. Returns the request id;
     * the reply is an `authed` event (`{req, signed_in, player_id, changed}`)
     * or `auth_failed` (`{req, code: "bad_token" | "player_mismatch" |
     * "rate_limited" | "offline" | …, message, retry_after_ms}`). Once
     * accepted, reconnects send this token in their hello.
     */
    auth(token?: string | null): number;
    /**
     * The page is going to the background (`visibilitychange` to hidden,
     * `pagehide`): hold this seat for the room's `away_grace_ms`. The reply
     * is an `away_held` event (`{req, reason, until, grace_ms}`) or `failed`
     * (`not_enabled` without `"away": true` in the config).
     */
    away(): number;
    /**
     * Back in the foreground (visible again, `pageshow`) on a socket that
     * survived; a reconnect is back on its own. A no-op when not away.
     */
    back(): number;
    create(game: string, max_members: number, kind: string, name: string, meta: string): number;
    /**
     * `create` with room settings as JSON, e.g. `{"max_members":32,"kinds":{"game":{"joinable":false}},"away_grace_ms":60000}`.
     * Rooms are a star (members link to the host only) unless the settings say `"topology":"mesh"`.
     */
    createWith(game: string, kind: string, name: string, meta: string, settings: string): number;
    join(code: string, kind: string, name: string, meta: string): number;
    /**
     * `join` with extra fields as JSON, e.g. `{"net_version":"a1b2c3d4e5f6"}`.
     */
    joinWith(code: string, kind: string, name: string, meta: string, settings: string): number;
    /**
     * Host only.
     */
    kick(mid: number): void;
    leave(): void;
    /**
     * Change your own name and/or meta (JSON `{"name":..,"meta":..}`); the others get `member_updated`.
     */
    memberUpdate(patch: string): number;
    /**
     * `config`: `{edge, key, conn?, client?, player_token?, no_webrtc?, away?, no_net_stats?}` (JSON).
     * `"away": true` opts in to the away grace (off by default). `"no_net_stats": true`
     * stops the room network stats reports (on by default; PROTOCOL.md "Network stats").
     */
    constructor(config: string);
    online(): boolean;
    static pathName(id: number): string;
    /**
     * Events since the last call, as a JSON array.
     */
    poll(): string;
    /**
     * Send bytes to a member (0xFFFF = everyone).
     */
    send(to: number, reliable: boolean, bytes: Uint8Array): void;
    /**
     * Link state per member, as JSON.
     */
    stats(): string;
    /**
     * Host only: change the room (`{"joinable":false}`, `{"kinds":{...}}`, `{"meta":...}`, `{"away_grace_ms":60000}`).
     */
    update(patch: string): void;
}

export type InitInput = RequestInfo | URL | Response | BufferSource | WebAssembly.Module;

export interface InitOutput {
    readonly memory: WebAssembly.Memory;
    readonly __wbg_webengine_free: (a: number, b: number) => void;
    readonly webengine_auth: (a: number, b: number, c: number) => number;
    readonly webengine_away: (a: number) => number;
    readonly webengine_back: (a: number) => number;
    readonly webengine_create: (a: number, b: number, c: number, d: number, e: number, f: number, g: number, h: number, i: number, j: number) => number;
    readonly webengine_createWith: (a: number, b: number, c: number, d: number, e: number, f: number, g: number, h: number, i: number, j: number, k: number) => number;
    readonly webengine_join: (a: number, b: number, c: number, d: number, e: number, f: number, g: number, h: number, i: number) => number;
    readonly webengine_joinWith: (a: number, b: number, c: number, d: number, e: number, f: number, g: number, h: number, i: number, j: number, k: number) => number;
    readonly webengine_kick: (a: number, b: number) => void;
    readonly webengine_leave: (a: number) => void;
    readonly webengine_memberUpdate: (a: number, b: number, c: number) => number;
    readonly webengine_new: (a: number, b: number) => [number, number, number];
    readonly webengine_online: (a: number) => number;
    readonly webengine_pathName: (a: number) => [number, number];
    readonly webengine_poll: (a: number) => [number, number];
    readonly webengine_send: (a: number, b: number, c: number, d: number, e: number) => void;
    readonly webengine_stats: (a: number) => [number, number];
    readonly webengine_update: (a: number, b: number, c: number) => void;
    readonly wasm_bindgen_a6c3b4c49f53a609___convert__closures_____invoke___wasm_bindgen_a6c3b4c49f53a609___JsValue__core_d941ad8722425d2e___result__Result_____wasm_bindgen_a6c3b4c49f53a609___JsError___true_: (a: number, b: number, c: any) => [number, number];
    readonly wasm_bindgen_a6c3b4c49f53a609___convert__closures_____invoke___js_sys_ed21aba2a8e84718___Function_fn_wasm_bindgen_a6c3b4c49f53a609___JsValue_____wasm_bindgen_a6c3b4c49f53a609___sys__Undefined___js_sys_ed21aba2a8e84718___Function_fn_wasm_bindgen_a6c3b4c49f53a609___JsValue_____wasm_bindgen_a6c3b4c49f53a609___sys__Undefined_______true_: (a: number, b: number, c: any, d: any) => void;
    readonly wasm_bindgen_a6c3b4c49f53a609___convert__closures_____invoke___web_sys_652ef47ad5c9cd95___features__gen_MessageEvent__MessageEvent______true_: (a: number, b: number, c: any) => void;
    readonly wasm_bindgen_a6c3b4c49f53a609___convert__closures_____invoke___web_sys_652ef47ad5c9cd95___features__gen_MessageEvent__MessageEvent______true__2: (a: number, b: number, c: any) => void;
    readonly wasm_bindgen_a6c3b4c49f53a609___convert__closures_____invoke___web_sys_652ef47ad5c9cd95___features__gen_MessageEvent__MessageEvent______true__3: (a: number, b: number, c: any) => void;
    readonly wasm_bindgen_a6c3b4c49f53a609___convert__closures_____invoke_______true_: (a: number, b: number) => void;
    readonly __wbindgen_malloc: (a: number, b: number) => number;
    readonly __wbindgen_realloc: (a: number, b: number, c: number, d: number) => number;
    readonly __externref_table_alloc: () => number;
    readonly __wbindgen_externrefs: WebAssembly.Table;
    readonly __wbindgen_exn_store: (a: number) => void;
    readonly __wbindgen_destroy_closure: (a: number, b: number) => void;
    readonly __externref_table_dealloc: (a: number) => void;
    readonly __wbindgen_free: (a: number, b: number, c: number) => void;
    readonly __wbindgen_start: () => void;
}

export type SyncInitInput = BufferSource | WebAssembly.Module;

/**
 * Instantiates the given `module`, which can either be bytes or
 * a precompiled `WebAssembly.Module`.
 *
 * @param {{ module: SyncInitInput }} module - Passing `SyncInitInput` directly is deprecated.
 *
 * @returns {InitOutput}
 */
export function initSync(module: { module: SyncInitInput } | SyncInitInput): InitOutput;

/**
 * If `module_or_path` is {RequestInfo} or {URL}, makes a request and
 * for everything else, calls `WebAssembly.instantiate` directly.
 *
 * @param {{ module_or_path: InitInput | Promise<InitInput> }} module_or_path - Passing `InitInput` directly is deprecated.
 *
 * @returns {Promise<InitOutput>}
 */
export default function __wbg_init (module_or_path?: { module_or_path: InitInput | Promise<InitInput> } | InitInput | Promise<InitInput>): Promise<InitOutput>;
