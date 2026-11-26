//! Partii for Godot, native backend (v0 skeleton). The `Partii` autoload (addons/partii/partii.gd) uses
//! `PartiiNative` when the GDExtension is loaded: the same GDScript calls as the web backend.
//! Everything here polls; partii-sdk does its network work on background threads.
use godot::prelude::*;
use partii::account::{Account, AccountConfig};
use partii::net::{Config as NetConfig, Engine};

struct PartiiExtension;

#[gdextension]
unsafe impl ExtensionLibrary for PartiiExtension {}

#[derive(GodotClass)]
#[class(base = RefCounted, init)]
pub struct PartiiNative {
    acct: Option<Account>,
    net: Option<Engine>,
    edge: String,
    key: String,
    base: Base<RefCounted>,
}

#[godot_api]
impl PartiiNative {
    /// Start the account (guest sign-in on this device). data_dir: a user:// folder, globalized.
    #[func]
    fn start(&mut self, game: GString, key: GString, edge: GString, data_dir: GString, version: GString) -> bool {
        self.edge = edge.to_string();
        self.key = key.to_string();
        self.acct = Some(Account::start(AccountConfig {
            edge: self.edge.clone(),
            key: Some(self.key.clone()),
            game: game.to_string(),
            data_dir: data_dir.to_string().into(),
            version: version.to_string(),
            platform: std::env::consts::OS.into(),
            analytics: true,
            ..AccountConfig::default()
        }));
        true
    }
    #[func]
    fn ready(&self) -> bool {
        self.acct.as_ref().is_some_and(|a| a.ready())
    }
    #[func]
    fn player_id(&self) -> GString {
        self.acct.as_ref().and_then(|a| a.player_id()).unwrap_or_default().pipe_gs()
    }
    #[func]
    fn is_guest(&self) -> bool {
        self.acct.as_ref().and_then(|a| a.is_guest()).unwrap_or(true)
    }
    #[func]
    fn error(&self) -> GString {
        self.acct.as_ref().and_then(|a| a.error()).unwrap_or_default().pipe_gs()
    }
    /// The slot's JSON ("" before the first save).
    #[func]
    fn read_save(&self, slot: GString) -> GString {
        self.acct.as_ref().and_then(|a| a.read_save(&slot.to_string())).unwrap_or_default().pipe_gs()
    }
    #[func]
    fn write_save(&self, slot: GString, json: GString) -> bool {
        self.acct.as_ref().is_some_and(|a| a.write_save(&slot.to_string(), &json.to_string()))
    }
    #[func]
    fn owns(&self, sku: GString) -> i32 {
        match self.acct.as_ref().and_then(|a| a.owns(&sku.to_string())) {
            Some(true) => 1,
            Some(false) => 0,
            None => -1,
        }
    }
    #[func]
    fn track(&self, name: GString, props_json: GString) {
        if let Some(a) = &self.acct {
            a.track(&name.to_string(), serde_json::from_str(&props_json.to_string()).unwrap_or_default());
        }
    }
    #[func]
    fn unlock_achievement(&self, id: GString) {
        if let Some(a) = &self.acct {
            a.unlock_achievement(&id.to_string());
        }
    }
    #[func]
    fn end_session(&self) {
        if let Some(a) = &self.acct {
            a.end_session(std::time::Duration::from_secs(2));
        }
    }

    // --- Rooms: partii-net's native engine, the same events as the web backend's roomsPoll ---

    #[func]
    fn rooms_start(&mut self, client: GString) -> bool {
        if self.net.is_none() {
            self.net = Some(Engine::start(NetConfig {
                edge: self.edge.clone(),
                key: self.key.clone(),
                conn: Engine::new_conn_id(),
                client: client.to_string(),
                player_token: self.acct.as_ref().and_then(|a| a.player_token()),
                away: true,
                ..NetConfig::default()
            }));
        }
        true
    }
    /// Events since the last call, as a JSON array (messages as {ev: "message", from, bytes: [..]}).
    #[func]
    fn rooms_poll(&self) -> GString {
        self.net.as_ref().map(|e| serde_json::to_string(&e.poll()).unwrap_or_else(|_| "[]".into())).unwrap_or_else(|| "[]".into()).pipe_gs()
    }
    #[func]
    fn create_room(&self, game: GString, kind: GString, name: GString, meta_json: GString, settings_json: GString) -> i64 {
        self.net.as_ref().map_or(-1, |e| {
            e.create_with(&game.to_string(), &kind.to_string(), &name.to_string(), json(&meta_json), json(&settings_json)) as i64
        })
    }
    #[func]
    fn join_room(&self, code: GString, kind: GString, name: GString, meta_json: GString, settings_json: GString) -> i64 {
        self.net.as_ref().map_or(-1, |e| {
            e.join_with(&code.to_string(), &kind.to_string(), &name.to_string(), json(&meta_json), json(&settings_json)) as i64
        })
    }
    #[func]
    fn leave_room(&self) {
        if let Some(e) = &self.net {
            e.leave();
        }
    }
    #[func]
    fn update_room(&self, patch_json: GString) {
        if let Some(e) = &self.net {
            e.update(json(&patch_json));
        }
    }
    #[func]
    fn kick(&self, mid: i64) {
        if let Some(e) = &self.net {
            e.kick(mid as u16);
        }
    }
    /// Play traffic: unreliable only.
    #[func]
    fn send(&self, to: i64, bytes: PackedByteArray) {
        if let Some(e) = &self.net {
            e.send(to as u16, false, bytes.to_vec());
        }
    }
    /// Not for gameplay: a rare reliable setup message.
    #[func]
    fn send_reliable_setup(&self, to: i64, bytes: PackedByteArray) {
        if let Some(e) = &self.net {
            e.send(to as u16, true, bytes.to_vec());
        }
    }
    #[func]
    fn net_stats(&self) -> GString {
        self.net.as_ref().map(|e| e.stats().to_string()).unwrap_or_else(|| "{}".into()).pipe_gs()
    }

    /// Keep this game's player token in the OS store. false: no store here (then keep nothing).
    #[func]
    fn token_store(&self, game: GString, token: GString) -> bool {
        keystore::set(&game.to_string(), &token.to_string())
    }
    /// The stored token, or "".
    #[func]
    fn token_load(&self, game: GString) -> GString {
        keystore::get(&game.to_string()).unwrap_or_default().pipe_gs()
    }
    #[func]
    fn token_clear(&self, game: GString) -> bool {
        keystore::clear(&game.to_string())
    }
}

// --- The sign-in token in the OS credential store ---

#[cfg(any(target_os = "macos", target_os = "windows", target_os = "linux"))]
mod keystore {
    fn entry(game: &str) -> Option<keyring::Entry> {
        keyring::Entry::new("games.partii.player", game).ok()
    }
    pub fn set(game: &str, token: &str) -> bool {
        entry(game).is_some_and(|e| e.set_password(token).is_ok())
    }
    pub fn get(game: &str) -> Option<String> {
        entry(game)?.get_password().ok()
    }
    pub fn clear(game: &str) -> bool {
        entry(game).is_some_and(|e| matches!(e.delete_credential(), Ok(()) | Err(keyring::Error::NoEntry)))
    }
}

#[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "linux")))]
mod keystore {
    pub fn set(_: &str, _: &str) -> bool {
        false
    }
    pub fn get(_: &str) -> Option<String> {
        None
    }
    pub fn clear(_: &str) -> bool {
        false
    }
}

fn json(s: &GString) -> serde_json::Value {
    serde_json::from_str(&s.to_string()).unwrap_or(serde_json::Value::Null)
}

trait PipeGs {
    fn pipe_gs(self) -> GString;
}
impl PipeGs for String {
    fn pipe_gs(self) -> GString {
        GString::from(self.as_str())
    }
}
