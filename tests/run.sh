#!/usr/bin/env bash
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO" || exit 2

specs=(roster_spec config_spec launch_spec name_spec resume_spec sessions_spec board_spec board_render_spec switch_spec lifecycle_spec actions_spec autoname_spec state_spec ui_spec ui_keys_spec backends_spec backends_claude_spec board_type_spec generic_resume_spec mixed_fleet_spec)
total_pass=0
total_fail=0

for spec in "${specs[@]}"; do
  TMP=$(mktemp -d)
  OUT=$(mktemp)
  echo "== ${spec} =="
  AGENT_FLEET_TEST_OUT="$OUT" XDG_DATA_HOME="$TMP" \
    nvim --headless -l "tests/${spec}.lua" 2>/dev/null
  if [ ! -s "$OUT" ]; then
    echo "FAIL ${spec} produced no output"
    total_fail=$((total_fail + 1))
  else
    cat "$OUT"
    p=$(grep -c '^PASS ' "$OUT" || true)
    f=$(grep -c '^FAIL ' "$OUT" || true)
    total_pass=$((total_pass + p))
    total_fail=$((total_fail + f))
  fi
  rm -rf "$TMP" "$OUT"
  echo
done

echo "${total_pass} passed, ${total_fail} failed"
[ "$total_fail" -eq 0 ]
