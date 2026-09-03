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
# There used to be a --room flag adding a per-room offset. Bronze opponents
# really are slower (+0.15 ln-seconds), but the shift only applied for the
# dozen games it takes a new account to leave Bronze, and leaving it on
# afterwards means playing every higher room ~16% slow — the factory model's
# failure, reintroduced by hand. A Bronze seat seated at the human median
# just looks like an experienced player on a new account, which it is.
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

apply_profile() {
  local name="$1"
  [[ -f "$ROOT/profiles/delay-${name}.lua" ]] || die "missing profiles/delay-${name}.lua"

  echo "==> patching shared timing into ${AKAGI_CONFIG}/config.toml"
  patch_shared_config

  # A straight copy: the profile in profiles/ is the whole model, readable
  # and runnable as-is.
  cp "$ROOT/profiles/delay-${name}.lua" "$AKAGI_CONFIG/delay.lua"

  echo "==> delay.lua <- profiles/delay-${name}.lua"
  echo "applied ${name} -> ${AKAGI_CONFIG}"
}

profile=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    factory|baseline|default)  profile=factory; shift ;;
    calibrated|moderate|mid)   profile=calibrated; shift ;;
    rushed|fast|quick)         profile=rushed; shift ;;
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
Usage: scripts/apply-profile.sh {calibrated|factory|rushed|NAME}

  calibrated matches measured opponents; use this     (aliases: moderate, mid)
  factory    Akagi's shipped model; runs ~19% slow    (aliases: baseline, default)
  rushed     faster than any human; negative control  (aliases: fast, quick)
  NAME       any profiles/delay-NAME.lua, e.g. one refitted from your own logs
             with majsoul-wire-timing's fit-timing.py

Target: ${AKAGI_CONFIG}
EOF
  exit 1
fi

apply_profile "$profile"
