#!/usr/bin/env bash
# Apply a timing profile (shared profiles/autoplay.toml + one delay.lua).
#
#   scripts/apply-profile.sh calibrated   # matches measured opponents (use this)
#   scripts/apply-profile.sh factory      # Akagi's factory model; slowest
#   scripts/apply-profile.sh rushed       # faster than any human; control only
#
# Only `calibrated` models the dealer's opening discard. The other two collapse
# it onto the budget cap — see majsoul-wire-timing docs/03-fitting-a-delay-model.md.
#
# Bronze opponents are measurably slower, so the profile takes a room as well.
# Defaults to `jade`, the calibration target; silver, gold and throne all use
# the same numbers, so only bronze changes anything:
#
#   scripts/apply-profile.sh calibrated --room bronze
#
# Writes into <repo>/configs/, which `scripts/akagi run` symlinks into
# target/debug/ at launch, so the result survives a rebuild. Point it at a
# different config directory with:
#
#   AKAGI_CONFIG=/path/to/configs scripts/apply-profile.sh rushed
#
# delay.lua hot-reloads, so a profile can be swapped between hands.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$REPO"
AKAGI_CONFIG="${AKAGI_CONFIG:-${REPO}/configs}"

die() { echo "apply-profile: $*" >&2; exit 1; }

[[ -d "$AKAGI_CONFIG" ]] || die "config dir not found: $AKAGI_CONFIG
run scripts/akagi run once to create it, or set AKAGI_CONFIG."

# Patch only the keys autoplay.toml declares. Replacing the whole config.toml
# (as this script used to) also reset start_url, the overlay, and any tuning
# done in the Settings UI, so the timing profile quietly undid unrelated work.
patch_shared_config() {
  python3 - "$ROOT/profiles/autoplay.toml" "$AKAGI_CONFIG/config.toml" <<'PY'
import re, sys
from pathlib import Path

frag_path, target_path = Path(sys.argv[1]), Path(sys.argv[2])

# Both files are Akagi-generated TOML: one `key = value` per line, no inline
# tables or multi-line values in the tables we touch. A line-level patch keeps
# comments and key order in the target intact, which a load/dump would not.
def parse(text):
    tables, table = {}, None
    for line in text.splitlines():
        s = line.split('#', 1)[0].strip()
        if s.startswith('[') and s.endswith(']'):
            table = s[1:-1]
        elif '=' in s and table is not None:
            k, v = s.split('=', 1)
            tables.setdefault(table, {})[k.strip()] = v.strip()
    return tables

wanted = parse(frag_path.read_text())
lines = target_path.read_text().splitlines(keepends=True)

applied, table = [], None
for i, line in enumerate(lines):
    s = line.split('#', 1)[0].strip()
    if s.startswith('[') and s.endswith(']'):
        table = s[1:-1]
        continue
    if table not in wanted or '=' not in s:
        continue
    key = s.split('=', 1)[0].strip()
    if key in wanted[table]:
        new = wanted[table].pop(key)
        lines[i] = re.sub(r'=.*$', f'= {new}', line.rstrip('\n')) + '\n'
        applied.append(f'{table}.{key} = {new}')

missing = [f'{t}.{k}' for t, keys in wanted.items() for k in keys]
if missing:
    sys.exit('apply-profile: keys absent from config.toml: ' + ', '.join(missing) +
             '\nAkagi\'s schema changed — update profiles/autoplay.toml.')

target_path.write_text(''.join(lines))
for a in applied:
    print(f'    {a}')
PY
}

# ln-second offset added to every THINK mu, per room. Derived from the
# opponent think times in Akagi's own gateway logs with disconnect windows
# excluded; see majsoul-wire-timing docs/03-fitting-a-delay-model.md for the sample sizes and the
# bootstrap intervals. `jade` is the calibration target, hence 0.
#
# Only bronze needs a shift. Silver and jade were both measured and came out
# indistinguishable from each other; gold and throne are absent from the logs
# and inherit 0 by extrapolation from that flatness.
room_shift() {
  case "$1" in
    jade|silver)   echo "0.00" ;;   # measured: indistinguishable
    gold|throne)   echo "0.00" ;;   # no data; extrapolated from silver = jade
    bronze)        echo "0.15" ;;   # measured: 95% CI [0.11, 0.18]
    *) return 1 ;;
  esac
}

apply_profile() {
  local name="$1" room="$2" shift_val
  [[ -f "$ROOT/profiles/delay-${name}.lua" ]] || die "missing profiles/delay-${name}.lua"
  shift_val="$(room_shift "$room")" || die "unknown room: ${room}
known rooms: jade, silver, gold, throne, bronze"

  echo "==> patching shared timing into ${AKAGI_CONFIG}/config.toml"
  patch_shared_config

  # Rewrite the one constant rather than templating the file, so the
  # profile in profiles/ stays a readable, runnable script.
  python3 - "$ROOT/profiles/delay-${name}.lua" "$AKAGI_CONFIG/delay.lua" \
            "$shift_val" "$room" "$room_explicit" <<'PY'
import re, sys
from pathlib import Path

src, dst, shift, room, explicit = (Path(sys.argv[1]), Path(sys.argv[2]),
                                   sys.argv[3], sys.argv[4], sys.argv[5] == '1')
text = src.read_text()
pat = re.compile(r'^(local ROOM_MU_SHIFT\s*=\s*)[-+0-9.]+(.*)$', re.M)

# A profile refitted from your own logs has no room hook: the room difference
# is already inside the fitted level, so there is nothing to shift. Only the
# profiles derived from the upstream model carry the constant.
if not pat.search(text):
    if explicit:
        sys.exit(f'apply-profile: {src.name} has no ROOM_MU_SHIFT, so --room '
                 f'{room} cannot be applied.\nRefit against logs from that room '
                 'instead — the difference lands in the fitted level.')
    dst.write_text(text)
    print('    no ROOM_MU_SHIFT (fitted profile; room is already in the fit)')
    raise SystemExit(0)

text, n = pat.subn(rf'\g<1>{shift}  -- room: {room}', text)
if n != 1:
    sys.exit(f'apply-profile: {n} ROOM_MU_SHIFT lines in {src.name}, expected 1.')
dst.write_text(text)
print(f'    ROOM_MU_SHIFT = {shift}  ({room})')
PY

  echo "==> delay.lua <- profiles/delay-${name}.lua"
  echo "applied ${name} / ${room} -> ${AKAGI_CONFIG}"
}

profile=""
room="jade"
room_explicit=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    factory|baseline|default)  profile=factory; shift ;;
    calibrated|moderate|mid)   profile=calibrated; shift ;;
    rushed|fast|quick)         profile=rushed; shift ;;
    --room)           room="${2:-}"; [[ -n "$room" ]] || die "--room needs a value"; room_explicit=1; shift 2 ;;
    --room=*)         room="${1#--room=}"; room_explicit=1; shift ;;
    # Any other name that names a real file, so a profile refitted with
    # majsoul-wire-timing's fit-timing.py can be dropped into profiles/ and
    # applied without editing this script.
    -*)               profile=""; break ;;
    *)
      if [[ -f "$REPO/profiles/delay-${1}.lua" ]]; then profile="$1"; shift
      else profile=""; break; fi ;;
  esac
done

if [[ -z "$profile" ]]; then
  cat >&2 <<EOF
Usage: scripts/apply-profile.sh {calibrated|factory|rushed|NAME} [--room ROOM]

  calibrated matches measured opponents; use this     (aliases: moderate, mid)
  factory    Akagi's shipped model; runs ~19% slow    (aliases: baseline, default)
  rushed     faster than any human; negative control  (aliases: fast, quick)
  NAME       any profiles/delay-NAME.lua, e.g. one refitted from your own logs
             with majsoul-wire-timing's fit-timing.py

ROOM (default: jade)
  jade | silver          +0.00  measured, and indistinguishable from each other
  gold | throne          +0.00  no data; extrapolated from silver = jade
  bronze                 +0.15  measured, 95% CI [+0.11, +0.18]

Target: ${AKAGI_CONFIG}
EOF
  exit 1
fi

apply_profile "$profile" "$room"
