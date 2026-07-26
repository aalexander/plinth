set -euo pipefail
cap() { shift; "$@"; }
LANE_RULES=canary-isolation
BEFORE=eeb96ef033e68f53bab47055cf8a733ff4285e24 SNAP=/var/folders/_x/cfgcf6z559dftdh5ggxr9tgw0000gn/T/tmp.Hifj33tsBp SPEC_DIR=/private/tmp/claude-501/-Users-austin-Dev-plinth/90401f5f-00cb-479c-9330-909d2566d0eb/scratchpad/split/wtb/.plinth-lane.4Lfljp SPEC=/private/tmp/claude-501/-Users-austin-Dev-plinth/90401f5f-00cb-479c-9330-909d2566d0eb/scratchpad/split/wtb/.plinth-lane.4Lfljp/prompt OUT=/var/folders/_x/cfgcf6z559dftdh5ggxr9tgw0000gn/T/grok-out.XXXXXX.WSGiCYH9Ve
OUT=/private/tmp/claude-501/-Users-austin-Dev-plinth/90401f5f-00cb-479c-9330-909d2566d0eb/scratchpad/split/wtb/.plinth-lane-canary.mQko1j/out-grok
RECEIVED=/private/tmp/claude-501/-Users-austin-Dev-plinth/90401f5f-00cb-479c-9330-909d2566d0eb/scratchpad/split/wtb/.plinth-lane-canary.mQko1j/received-grok; export RECEIVED
PATH=/private/tmp/claude-501/-Users-austin-Dev-plinth/90401f5f-00cb-479c-9330-909d2566d0eb/scratchpad/split/wtb/.plinth-lane-canary.mQko1j/bin:"$PATH"; export PATH
RC=0; cap 600 grok --prompt-file "$SPEC" --rules "$LANE_RULES" \
--permission-mode bypassPermissions --sandbox workspace --max-turns 20 \
--output-format plain --cwd "$(pwd)" \
> "$OUT" 2>&1 || RC=$?
# Prompt was consumed path-based; remove the project-local SPEC_DIR (and the
# prompt file) on every path — success, timeout, or CLI failure — so specs
# do not accumulate as hidden residue under the repo. SPEC_DIR comes from the
# pasted step-0 handoff (not re-derived), so cleanup uses the same directory
# Write created.
[ -n "$SPEC_DIR" ] && [ "$SPEC" = "$SPEC_DIR/prompt" ] || {
echo "SPEC_DIR handoff missing or mismatched SPEC"; exit 1; }
rm -rf "$SPEC_DIR"
echo "RUN_RC=$RC BEFORE=$BEFORE SNAP=$SNAP OUT=$OUT"   # paste these literals into steps 3-4
