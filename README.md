# 帰ってきた赤木

*Akagi Returns* — a real-time mahjong AI assistant for **Mahjong Soul**,
trimmed down to one platform and one machine: macOS on Apple silicon, run from
source.

It watches your game over a controlled Chromium instance (or a MITM proxy),
mirrors the board into a live game state, and asks a bot what it would do. It
shows shanten, waits, agari/tenpai rates, per-opponent deal-in risk, and a
recommended discard — and, with autoplay enabled, performs the decision in the
client for you with timing fitted to measured human opponents
([Timing profiles](#timing-profiles)).

> **Educational use only.** Game publishers may act against accounts that use
> tools like this. Any consequences are yours.

This is a personal fork of [shinkuan/Akagi](https://github.com/shinkuan/Akagi)
(v3, the Rust + Tauri rewrite). See
[What's different from the original](#whats-different-from-the-original) below.

## Requirements

- macOS on Apple silicon (`aarch64-apple-darwin`)
- Rust toolchain (`rustup`)
- Node.js 20 (the run script looks for Homebrew's `node@20`)
- Google Chrome, or let Akagi download Chrome for Testing

## Quick start

```bash
# One time: fetch the bundled python runtime and build the frontend.
scripts/akagi setup

# Keep the Mac awake for the whole session, then run.
caffeinate -dism &
scripts/akagi run
```

`caffeinate -dism` prevents display sleep, idle sleep, and system sleep. Run it
**before** `scripts/akagi run` — a Mac that sleeps mid-hand drops the WebSocket
and the bot loses the game state. Press `Ctrl-C` on the caffeinate job (or
`kill %1`) when you're done.

## Commands

Everything goes through one script:

| Command | What it does |
| --- | --- |
| `scripts/akagi setup` | Fetch the bundled python + uv, install frontend deps, build the UI, dedupe bot venvs |
| `scripts/akagi run` | Build whatever is missing, then launch |
| `scripts/akagi clean` | Reclaim disk. Never touches `configs/` or `data/` |
| `scripts/akagi dedupe` | Hardlink identical files across bot venvs |
| `scripts/akagi doctor` | Show resolved paths, installed bots, and disk usage |
| `scripts/apply-profile.sh` | Swap the autoplay timing profile — see [Timing profiles](#timing-profiles) |

`run` builds only what's absent, so after the first launch it starts in
seconds. `clean` removes `target/`, `node_modules/`, `frontend/dist/`, logs,
and Chromium caches — all regenerable, and worth several gigabytes.

## How to use

1. **Launch.** `scripts/akagi run` opens the Akagi window and, in Chromium
   capture mode, a browser on the Mahjong Soul lobby.
2. **First run** walks you through a setup wizard: capture mode, browser, and
   which bot to install. The bundled Mortal bot is the usual choice.
3. **Pick your server** under Settings → Capture. It's a language picker —
   日本語, English, or 中文 — because each region is a separate server with
   separate accounts.
4. **Play.** Once a hand starts, the dashboard fills in: your hand, the
   discard recommendation, waits, and each opponent's deal-in risk.
5. **Autoplay** (Settings → Autoplay) plays the bot's choice for you. It needs
   Chromium capture mode, since it works by synthesising real mouse input at
   reconstructed canvas coordinates.
6. **Tune the timing** with `scripts/apply-profile.sh`, or by editing
   `configs/delay.lua` directly. It hot-reloads on save, so think time can be
   adjusted between hands. See [Timing profiles](#timing-profiles).
7. **Review afterwards** on the History page: every game is kept as mjai JSONL
   with per-game stats.

### Where your state lives

Akagi resolves its data directories relative to the executable, which for a
cargo build means `target/debug/`. Anything that must survive a rebuild
therefore lives at the repo root and is symlinked into place by `run`:

- `configs/` — `config.toml` and `delay.lua`. Tracked in git; back these up.
- `data/` — CA cert, logs, game history, and the Chromium profile (your login
  session). Git-ignored, local to this machine.

That split is what makes `target/` fully disposable.

## Timing profiles

Autoplay has to decide how long to wait before each action. That delay is the
one thing about autoplay the server can measure directly: Mahjong Soul stamps
every action with a `timeuse` field, in whole seconds, and those integers are
the only behavioural trace that leaves the machine. Mouse paths, hover, idle
jitter — none of it is transmitted. So the delay model is worth getting right,
and nothing else about the click sequence is.

`profiles/` holds three models, applied with one command:

```bash
scripts/apply-profile.sh calibrated            # the one to use
scripts/apply-profile.sh calibrated --room bronze
```

| Profile | What it is |
| --- | --- |
| `calibrated` | Fitted to opponents measured in our own gateway logs. **Use this.** |
| `factory` | Akagi's shipped model, unmodified. Runs ~19% slow. |
| `rushed` | Faster than any measured human. A negative control, not a setting. |

`calibrated` exists because the factory model double-counts: its think-time
clusters were fitted to the *marginal* distribution of higher-room players, and
then conditional bonuses were layered on top without being subtracted back out.
Measured over 1,492 opponent discards, humans discard at a 2.02 s median and
the factory model simulates 2.44 s. The correction is one number — every think
mu drops by 0.22 in ln-seconds — leaving the relative structure between cells
alone, since that came from a 21,500-decision fit and there is no reason to
doubt it.

**Only `calibrated` models the dealer's opening discard.** The other two have
no model for it, so that decision collapses onto the budget cap: 62% of
openings landing in a single whole-second bucket, against 15% for humans. This
is the single most identifiable thing either of them does, and it is why
"factory" should not be read as "safest".

`--room` adds a per-room offset. Bronze opponents are measurably slower
(+0.15 ln-seconds, 95% CI [0.11, 0.18]); silver and jade were both measured and
came out indistinguishable, so everything above bronze uses the same numbers
and the flag only matters when dropping down.

The script patches the seven timing keys in `configs/config.toml` in place and
rewrites `configs/delay.lua`. It touches nothing else — the start URL, overlay,
bot selection and CA settings survive, which an earlier whole-file version of
this script did not manage.

### Where the reasoning lives

The measurements behind these numbers — what the server actually receives, how
the model was fitted, the traps in measuring it, and what is left exposed — are
written up in **[`majsoul-wire-timing`](https://github.com/hashiryu-returns/majsoul-wire-timing)**,
not here. One copy, so there is one thing to keep correct. The profile headers
in `profiles/` cite it by document name.

### Refitting the model

That repository also carries `fit-timing.py`, which rebuilds a timing model from
whatever logs you have rather than reusing the numbers baked into
`delay-calibrated.lua`. Worth doing after a few hundred hands in a room the
current fit did not cover, or simply to keep the constants yours:

```bash
cd ../majsoul-wire-timing
python3 fit-timing.py ../akagi-returns/data/logs --out fitted.lua
cp fitted.lua ../akagi-returns/profiles/delay-fitted.lua
cd ../akagi-returns && scripts/apply-profile.sh fitted
```

`apply-profile.sh` accepts any `profiles/delay-<name>.lua`, so a regenerated
profile drops straight in. Note that it fits a simpler model than
`delay-calibrated.lua` — two log-normals and a long-thought term, taken straight
from the marginal — rather than the cluster structure inherited from upstream.
Both reproduce the measured distribution; the fitted one is not shared with
anyone else, which is the point of regenerating it.

The shared timing values in `profiles/autoplay.toml` still apply and are not
part of the fit.

## Folder structure

```
.
├── src/                    Rust backend (the Tauri app)
│   ├── capture/            Frame sources: Chromium via CDP, or the MITM proxy
│   ├── proxy/              hudsucker MITM proxy, CA generation, cert rewriting
│   ├── bridge/majsoul/     Mahjong Soul protobuf wire format ⇄ mjai events
│   ├── game_state/         Live board state on top of riichienv-core
│   ├── analysis/           Shanten, waits, agari/tenpai rates, deal-in risk
│   ├── bot/                Bot process lifecycle, uv venv management
│   ├── autoplay/           Decision → canvas clicks, with the Lua delay model
│   ├── history/            Game archive (index.jsonl + per-game mjai JSONL)
│   ├── inspector/          Frame/event capture for debugging
│   ├── ipc/                Tauri commands and events
│   └── schema/             Types shared with the frontend
├── native_bot/             Built-in libriichi-free bot (candle CNN inference)
├── frontend/               React + Vite + Tailwind UI
│   └── src/
│       ├── routes/         Overview, Game, Bots, History, Review, Logs, Settings, Setup, Overlay
│       ├── components/     UI components (shadcn/ui in components/ui)
│       ├── tiles/          Dashboard tiles (hand, risk chart, recommendation)
│       ├── stores/         Zustand state
│       └── i18n/           en, ja, zh-CN, zh-TW
├── assets/
│   ├── delay/              Bundled default delay.lua + superseded versions
│   └── icons/              App icons
├── capabilities/           Tauri permission manifests
├── configs/                Your config.toml + delay.lua  (tracked)
├── data/                   Runtime state: CA, logs, history, browser profile
├── mjai_bot/               Installed bots + their uv venvs  (managed by Akagi)
├── profiles/               Autoplay timing profiles + shared autoplay.toml
├── runtime/                Bundled python + uv binaries
├── scripts/
│   ├── akagi               setup / run / clean / dedupe / doctor
│   ├── apply-profile.sh    Writes a profile into configs/
│   └── fetch-runtime.sh    Downloads python-build-standalone + uv
├── build.rs                protobuf codegen + target triple
└── tauri.conf.json         Window, bundle, and permission config
```

## What's different from the original

Upstream Akagi is a cross-platform, multi-game, release-packaged application.
This fork is the opposite: one game, one OS, run from a source checkout. That
premise is what every change below follows from.

**Mahjong Soul only.** Tenhou and Riichi City support is gone — their protocol
bridges, autoplay paths (Tenhou drives the client's own DOM handlers; Riichi
City injects protocol frames through the proxy), platform config, and UI
pickers — about 8,300 lines. The platform selector is gone with them, and the
capture layer no longer branches per platform. Archived history records from
other platforms still deserialize, so an old game archive stays readable.

**Server picker instead of a URL field.** The Chromium start URL is a language
dropdown (日本語 / English / 中文) rather than something you retype when you
switch between regional accounts.

**Disposable build tree.** Upstream keeps runtime state under the executable's
directory, which for a cargo build means `cargo clean` takes your CA, logs,
history, and browser login with it. Here that state lives in `configs/` and
`data/` at the repo root and is symlinked into `target/debug/` at launch, so
`target/` can be deleted at any time.

**One script.** `scripts/akagi` replaces the ad-hoc dev scripts with
`setup`/`run`/`clean`/`dedupe`/`doctor`. `clean` is explicit about only
removing regenerable bytes; `dedupe` hardlinks the identical dependency trees
that separate bot venvs would otherwise each pay for (~400 MB for two Mortal
bots).

**Stripped for size.** No CI workflows, release packaging, signing, binary
test fixtures, or training scripts. The unit tests are intact — 792 on the
Rust side, 94 in the frontend. Non-macOS-arm64 `libriichi` binaries and
non-Japanese READMEs are gone. `native_bot` lost its `extract` binary and
replay module. Cargo is now a workspace, so there's a single lockfile.

**Calibrated timing.** Upstream ships one delay model. This fork adds
`profiles/` and `scripts/apply-profile.sh`, and the model it applies by default
is refitted against opponents measured in real gateway logs rather than
upstream's values — see [Timing profiles](#timing-profiles). One matching
change in `src/autoplay/delay/mod.rs` lets the dealer's opening discard draw on
the time bank, which stops the built-in model from flattening that decision
onto the budget cap.

**Renamed.** The window and product name are 帰ってきた赤木, to keep it
distinct from an upstream build.

Not changed: the analysis engine, the mjai event schema, the bot protocol, the
Lua scripting interface, and the history format all behave as upstream.

## License

Apache-2.0, inherited from [shinkuan/Akagi](https://github.com/shinkuan/Akagi).
Bundled mjai bots (Mortal) carry their own licenses — see the license files in
each `mjai_bot/<name>/` directory.
