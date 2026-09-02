//! Autoplay: perform the bot's decisions in the real client, via CDP.
//!
//! Data flow: bot decision (an `MjaiEvent`) joins the latest
//! `GameStateSnapshot` and `legal_actions` from the `riichienv-core` game
//! state, and the platform impl plans a sequence of `Step`s. Action
//! availability is sourced from the riichi engine, not from the platform
//! protocol parser.
//!
//! Mahjong Soul renders to a canvas and exposes nothing to script, so the
//! only way in is synthesised mouse input at reconstructed coordinates.
//! Everything expensive here exists because of that: coordinate tables,
//! candidate-row index arithmetic, click verification and retry.
//!
//! Reach is two inputs — declare, then discard — both taking the tile from
//! the bot's own `Reach { pai }` and performed in one plan; the client does
//! not act on the declaration alone but holds its reach popup open.
//!
//! Every response arriving here is a decision the riichi engine asked for —
//! `bot::manager` does not flush to the bot otherwise — so an `MjaiEvent::None`
//! means *decline*, and never "the bot had nothing to say".
//!
//! Module layout:
//! - [`context`] — shared state between the chromium capture backend
//!   and this manager (page handle + canvas rect cache).
//! - [`platform`] — `PlatformAutoplay` trait + the `Step` types
//!   (`Click` / `Sleep` / `AwaitReady`).
//! - [`majsoul`] — the production Majsoul implementation: 16:9
//!   coordinate tables (ported from the Python autoplay in
//!   <https://github.com/shinkuan/Akagi>) + plan dispatch covering all mjai
//!   action types.
//! - [`cdp_input`] — chromiumoxide wrappers (`dispatch_click`,
//!   `evaluate_canvas_rect`).
//! - [`manager`] — the long-lived `AutoplayManager` task that owns
//!   per-game state and drives the plan.
//! - [`verify`] — did the click land? Counts the client's own uplink
//!   input commands (bumped by the Majsoul bridge) so the manager can
//!   tell a click that registered from one the UI swallowed, and retry.
//!
//! Entry point: [`manager::run_autoplay_manager`].

pub mod budget;
pub mod cdp_input;
pub mod context;
pub mod delay;
pub mod majsoul;
pub mod manager;
pub mod platform;
pub mod verify;

pub use budget::{BudgetSource, SharedTimeBudget, TimeBudget};
pub use context::{AutoplayContext, CanvasRect};
pub use manager::run_autoplay_manager;
pub use platform::{ActionContext, PlanResult, PlatformAutoplay, Step};
pub use verify::{InputKind, InputWatch, SharedInputWatch};
