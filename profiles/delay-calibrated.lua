-- Profile: calibrated — matched to measured human discard timing.
--
-- This is the one to use. Of the three profiles it is the only one whose
-- output distribution reproduces what real opponents were measured doing;
-- the other two miss in opposite directions (see
-- majsoul-wire-timing docs/03-fitting-a-delay-model.md).
--
-- Why this is not merely "the factory model, a bit quicker":
--
-- Akagi's factory model fits its THINK clusters to the MARGINAL distribution
-- of higher-room think times, then layers conditional bonuses on top —
-- the junme multiplier, the opponent-riichi multiplier, the first-action
-- survey, the declarable-riichi bonus. Those bonuses were never subtracted
-- back out of the base clusters, so the model lands about 19% slower than
-- the humans it was calibrated against. Measured on 4 Jade halves
-- (1,492 opponent discards, disconnect windows excluded): humans discard at
-- a 2.02 s median, the factory model simulates 2.44 s. Its own comments
-- claim tedashi fast-fractions of 21/10/4% — it produces 13/5/4% once the
-- bonuses are active.
--
-- The fix is a single level correction: every THINK mu is the factory value
-- minus 0.22 (ln-seconds). The relative structure between cells is left
-- alone — that came from a 21,500-decision fit and there is no reason to
-- doubt it. Only the global level was wrong.
--
-- The long-thought rate moved too: 2% could not reproduce the measured
-- 7.0% of discards at 6 s or longer. 7% does, and it independently agrees
-- with the "higher-room players dip into the time bank on ~7% of draws"
-- observation the factory model already documented.
--
-- One thing outside this file had to change with it. The corrected model
-- puts 10.9% of discards under a second, against a measured 10.0%, but at
-- a min_delay_ms of 1000 none of that reaches the server: Akagi floors
-- the SLEEP, then adds the click overhead on top, so the observed minimum
-- is about 1.34 s and every sub-second decision arrives as `timeuse: 1`.
-- The floor is now 600 in profiles/autoplay.toml, which is what makes the
-- sub-second mass in this model observable at all. That trades away part of
-- the tile-render margin, so see majsoul-wire-timing docs/04-click-reliability.md before
-- lowering it further.
--
-- Not corrected: the OTHER table (riichi declaration, call windows, ron,
-- skip-while-in-riichi). Opponent timing for those is not recoverable from
-- the logs, so they keep the factory values rather than invented ones.
--
-- Akagi autoplay delay model.
--
-- Akagi generated this file next to your config.toml. Edit it freely —
-- it hot-reloads every time you save. Delete it to get a fresh copy of
-- the default on the next start. If the script ever errors, Akagi keeps
-- playing with its built-in model and logs the reason once.
--
-- decide_delay(ctx) returns { delay_ms = <number>, allow_bank = <bool> }.
--
-- delay_ms is the target TOTAL thinking time for the decision window —
-- the time the SERVER observes between offering the decision and
-- receiving the action. It is NOT a sleep length: Akagi subtracts
-- whatever networking and bot inference already consumed.
--
-- Akagi always enforces on top of whatever this script returns:
--   * a minimum delay (config `min_delay_ms`; the higher
--     `min_button_delay_ms` for chi/pon/kan/ron/skip/riichi buttons,
--     which render later than hand tiles) — clicks issued before the
--     UI exists are silently lost
--   * the dealing-animation wait on the dealer's opening discard
--   * the server time budget — autoplay can never run into an
--     auto-discard; the extra time bank is only spent when this script
--     returns allow_bank = true
--
-- Context passed to decide_delay:
--   ctx.action          "dahai" | "reach" | "chi" | "pon" | "daiminkan"
--                       | "ankan" | "kakan" | "hora" | "ryukyoku" | "kita"
--                       | "none"  (declining a call window)
--   ctx.tsumogiri       the discard is the just-drawn tile
--   ctx.post_call       discard following our own chi/pon
--   ctx.tile_class      "honor" | "terminal" | "middle" for a discard
--   ctx.first_action    first action of the kyoku
--   ctx.dealer_opening  dealer's 14-tile opening discard
--   ctx.can_riichi      riichi is declarable this turn
--   ctx.is_kan          the action is a kan declaration
--   ctx.in_riichi       we are in accepted riichi
--   ctx.opponent_riichi an opponent has declared riichi
--   ctx.junme           our discard number this kyoku (1 = first)
--   ctx.legal_count     number of legal actions
--   ctx.top_prob        bot's top candidate probability (0..1), or nil
--   ctx.second_prob     second candidate probability, or nil
--   ctx.margin          top_prob - second_prob, or nil
--   ctx.budget          { fixed_ms, add_ms, elapsed_ms } or nil
--   ctx.rng()           uniform random in [0, 1)
--   ctx.lognormal(mu, sigma)  log-normal sample in SECONDS
--
-- There is no room field in ctx, so the room adjustment cannot be a
-- runtime branch — apply-profile.sh rewrites the constant below instead.
-- Keep the line's shape (`local ROOM_MU_SHIFT = <number>`) or the patch
-- will not find it.
--
-- 0.00 targets Jade, and Silver measures the same. Bronze is slower;
-- see majsoul-wire-timing docs/03-fitting-a-delay-model.md for the per-room values and their
-- confidence intervals.
local ROOM_MU_SHIFT = 0.00

-- Probability that a discard is routine (no real thought) — a MIXTURE
-- WEIGHT, not a measured fast-fraction. Factory values, unchanged: the
-- level correction below already brings the fast mass onto target.
local ROUTINE = {
  tedashi   = { honor = 0.12, terminal = 0.00, middle = 0.00 },
  tsumogiri = { honor = 0.15, terminal = 0.10, middle = 0.04 },
}

-- Log-normal { mu, sigma } (ln-seconds) of the *genuine-think* cluster.
-- Every mu is the factory value minus 0.22 — see the header.
local THINK = {
  tedashi   = { honor = { 0.55, 0.50 }, terminal = { 0.61, 0.50 },
                middle = { 0.79, 0.55 }, default = { 0.65, 0.55 } },
  tsumogiri = { honor = { 0.32, 0.45 }, terminal = { 0.35, 0.45 },
                middle = { 0.41, 0.48 }, default = { 0.35, 0.47 } },
}

-- Non-discard decisions. Factory values — not measurable from the logs.
local OTHER = {
  reach           = { 1.10, 0.55 }, -- riichi declaration   (median ~3.0s)
  claim           = { 0.26, 0.57 }, -- call window incl pass (median ~1.3s)
  post_call_dahai = { 0.52, 0.42 }, -- discard after own call (median ~1.7s)
  hora            = { 0.15, 0.50 }, -- ron / tsumo           (median ~1.2s)
  in_riichi       = { 0.35, 0.30 }, -- skip while in riichi  (median ~1.4s)
}

-- NOTE: this model deliberately ignores the bot's reported probabilities
-- (ctx.top_prob / ctx.second_prob / ctx.margin). Measured bot policies
-- can be nearly flat (top ~0.11 on most decisions), which turned every
-- confidence-based rule into a permanent bias instead of a signal.
local function routine_probability(ctx, giri)
  local p = (ROUTINE[giri] or {})[ctx.tile_class or "middle"] or 0.04
  -- A riichi on the table means every discard gets a safety read.
  if ctx.opponent_riichi then p = p * 0.4 end
  if p > 0.6 then p = 0.6 end
  return p
end

local function discard_think(ctx)
  local giri = ctx.tsumogiri and "tsumogiri" or "tedashi"
  if ctx.rng() < routine_probability(ctx, giri) then
    -- Routine flick: tight cluster around one second. Deliberately not
    -- shifted by room — a reflex discard is a reflex at every rank.
    return ctx.lognormal(0.0, 0.18)
  end
  local params = THINK[giri][ctx.tile_class or "default"]
                 or THINK[giri].default
  local think = ctx.lognormal(params[1] + ROOM_MU_SHIFT, params[2])
  -- Deeper hands are read longer — but only tedashi shows this
  -- (measured tsumogiri medians are junme-flat).
  if giri == "tedashi" and ctx.junme ~= nil and ctx.junme > 0 then
    think = think * (1.0 + 0.012 * math.min(ctx.junme, 15))
  end
  -- Defence reads against a live riichi: +16% tedashi, +25% tsumogiri,
  -- with a fatter tail.
  if ctx.opponent_riichi then
    think = think * (giri == "tedashi" and 1.16 or 1.25)
    if ctx.rng() < 0.06 then think = think + ctx.lognormal(0.9, 0.5) end
  end
  return think
end

function decide_delay(ctx)
  local think
  local allow_bank = false

  if ctx.in_riichi then
    -- Only claim windows reach this point in riichi (Majsoul auto-
    -- discards our draws). Measured: still ~1.4s — humans do glance.
    think = ctx.lognormal(OTHER.in_riichi[1], OTHER.in_riichi[2])
    return { delay_ms = think * 1000 }
  end

  if ctx.action == "dahai" then
    if ctx.post_call then
      think = ctx.lognormal(OTHER.post_call_dahai[1], OTHER.post_call_dahai[2])
    else
      think = discard_think(ctx)
    end
  elseif ctx.action == "reach" then
    think = ctx.lognormal(OTHER.reach[1], OTHER.reach[2])
  elseif ctx.action == "hora" then
    think = ctx.lognormal(OTHER.hora[1], OTHER.hora[2])
  elseif ctx.action == "ankan" or ctx.action == "kakan" then
    -- Own-turn kan declaration thinks like a middle-tile tedashi.
    think = ctx.lognormal(THINK.tedashi.middle[1], THINK.tedashi.middle[2])
  else
    -- Claim-window responses: chi/pon/daiminkan/skip/kyuushu.
    think = ctx.lognormal(OTHER.claim[1], OTHER.claim[2])
  end

  -- The dealer's opening discard is its own regime, not a discard with a
  -- survey bonus bolted on. Measured opponent dealers, 229 openings with
  -- disconnect-affected seats excluded: median 5.6 s, p10 3.6, p90 9.6,
  -- and 15% at nine seconds or longer. Everything below is slower and
  -- far wider than a normal first discard, because the dealer is sorting
  -- fourteen unseen tiles rather than reacting to a draw.
  --
  -- Modelling it as "normal discard + 0.9 s" produced a median of 3.0 s,
  -- under the free window, so the budget shaping below never unlocked the
  -- bank and the 3670 ms soft cap flattened the whole thing onto itself —
  -- 84% of openings in a single whole-second bucket against a human 15%.
  -- The 3000 ms animation floor did not cause that, but it hid it, by
  -- lifting the median to something that looked reasonable.
  -- See majsoul-wire-timing docs/03-fitting-a-delay-model.md.
  --
  -- Exceeding the free window here is deliberate: the measured human
  -- median is above the 5 s allowance, so real dealers routinely spend
  -- bank time on the opening discard. The budget shaping below unlocks
  -- it, and Akagi bounds how much is actually spent.
  --
  -- Do not try to buy back the 1-2 s buckets humans occupy here by
  -- lowering dealer_first_discard_extra_delay_ms. That floor is
  -- mechanical: the hand-sort animation eats presses for ~2.9 s, and an
  -- opening press that gets eaten costs the turn, not the tile. It has to
  -- stay at 3000. The lost buckets are the price.
  if ctx.dealer_opening then
    think = ctx.lognormal(1.72, 0.38)
  elseif ctx.first_action then
    -- Non-dealer first action of a kyoku: the fresh hand gets surveyed.
    think = think + 0.5 + 0.8 * ctx.rng()
  end

  -- Neither bonus below applies to the dealer opening: the distribution
  -- above was fitted to the MARGINAL of measured openings, so it already
  -- contains whatever deliberating and double-riichi weighing those
  -- dealers did. Adding more here would repeat the double-counting
  -- mistake this profile exists to correct.
  if not ctx.dealer_opening then
    -- A declarable riichi makes this discard a real decision even when
    -- the bot ends up not declaring.
    if ctx.can_riichi and ctx.action == "dahai" then
      think = think + 0.4 + 0.8 * ctx.rng()
    end

    -- Occasional genuine tank — recounting discards, weighing a fold.
    -- 7%, not the factory 2%: measured humans spend 7.0% of discards at
    -- 6 s or longer, and 2% cannot reach that no matter how the clusters
    -- are shaped.
    if ctx.rng() < 0.07 then
      think = think + 2.0 + ctx.lognormal(0.8, 0.6)
      allow_bank = true
    end
  end

  -- Budget shaping. The server grants fixed_ms per decision plus a
  -- bank (add_ms) that REFILLS EVERY KYOKU — measured Throne players
  -- dip into it on ~7% of draws, so exceeding the free window is
  -- normal play, not an emergency. But when the bank is nearly dry,
  -- humans wrap up instead of risking the auto-discard timer.
  if ctx.budget ~= nil then
    -- Floored at 0: a sub-second fixed_ms must degrade to "answer at
    -- the enforced minimum", not to a negative delay_ms that Akagi
    -- would reject (which would silently disable this script for the
    -- whole room).
    local free_s = math.max(ctx.budget.fixed_ms / 1000 - 1.0, 0)
    local bank_s = ctx.budget.add_ms / 1000
    if think > free_s then
      if bank_s >= 3.0 then
        allow_bank = true -- natural dip; Akagi bounds how much is spent
      else
        think = free_s    -- nearly broke: finish the thought quickly
      end
    end
  end

  return { delay_ms = think * 1000, allow_bank = allow_bank }
end
