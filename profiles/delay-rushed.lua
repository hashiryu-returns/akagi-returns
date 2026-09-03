-- Profile: rushed — deliberately faster than any human. NOT for normal use.
--
-- Kept as a negative control, not as an option. It is quicker than measured
-- opponents in every room and wrong on both tails at once: 13.1% of discards
-- under one second against a measured 9-11%, and only 3.1% at 6 s or longer
-- against a measured 6-8%. That combination describes a player who never
-- stops to think, which no real player does.
--
-- Its purpose is verification. Because it misses the human distribution in a
-- known direction, applying it should visibly move the whole-second histogram
-- the server records. If it does not, the profile is not reaching Akagi and
-- the measurement pipeline is broken — worth knowing before trusting any
-- result from `calibrated`.
--
-- Its left tail only became observable when min_delay_ms dropped to 600; at
-- the old floor the sub-second mass was clamped away before it reached the
-- server. Grinding volume with this is a bad trade twice over, since play
-- volume is itself a higher detection risk than timing.
--
-- Like factory, it has no model for the dealer's opening discard, so that
-- decision collapses onto the budget cap. Only delay-calibrated.lua fixes it.
-- Use `calibrated`. See majsoul-wire-timing docs/03-fitting-a-delay-model.md.

local ROUTINE = {
  tedashi   = { honor = 0.25, terminal = 0.10, middle = 0.10 },
  tsumogiri = { honor = 0.30, terminal = 0.20, middle = 0.15 },
}

local THINK = {
  tedashi   = { honor = { 0.60, 0.50 }, terminal = { 0.65, 0.50 },
                middle = { 0.85, 0.55 }, default = { 0.70, 0.55 } },
  tsumogiri = { honor = { 0.40, 0.45 }, terminal = { 0.45, 0.45 },
                middle = { 0.50, 0.48 }, default = { 0.45, 0.47 } },
}

local OTHER = {
  reach           = { 0.90, 0.55 },
  claim           = { 0.15, 0.57 },
  post_call_dahai = { 0.40, 0.42 },
  hora            = { 0.10, 0.50 },
  in_riichi       = { 0.25, 0.30 },
}

local function routine_probability(ctx, giri)
  local p = (ROUTINE[giri] or {})[ctx.tile_class or "middle"] or 0.10
  if ctx.opponent_riichi then p = p * 0.4 end
  if p > 0.6 then p = 0.6 end
  return p
end

local function discard_think(ctx)
  local giri = ctx.tsumogiri and "tsumogiri" or "tedashi"
  if ctx.rng() < routine_probability(ctx, giri) then
    return ctx.lognormal(0.0, 0.18)
  end
  local params = THINK[giri][ctx.tile_class or "default"]
                 or THINK[giri].default
  local think = ctx.lognormal(params[1], params[2])
  if giri == "tedashi" and ctx.junme ~= nil and ctx.junme > 0 then
    think = think * (1.0 + 0.012 * math.min(ctx.junme, 15))
  end
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
    think = ctx.lognormal(THINK.tedashi.middle[1], THINK.tedashi.middle[2])
  else
    think = ctx.lognormal(OTHER.claim[1], OTHER.claim[2])
  end

  if ctx.first_action then
    think = think + 0.2 + 0.4 * ctx.rng()
  end

  if ctx.can_riichi and ctx.action == "dahai" then
    think = think + 0.2 + 0.4 * ctx.rng()
  end

  if ctx.rng() < 0.01 then
    think = think + 1.0 + ctx.lognormal(0.6, 0.4)
    allow_bank = true
  end

  if ctx.budget ~= nil then
    local free_s = math.max(ctx.budget.fixed_ms / 1000 - 1.0, 0)
    local bank_s = ctx.budget.add_ms / 1000
    if think > free_s then
      if bank_s >= 3.0 then
        allow_bank = true
      else
        think = free_s
      end
    end
  end

  return { delay_ms = think * 1000, allow_bank = allow_bank }
end
