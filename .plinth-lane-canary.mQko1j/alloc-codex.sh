BEFORE="$(git rev-parse HEAD)"; SNAP="$(mktemp)" || { echo "SNAP mktemp failed rc=$?"; exit 1; }
/private/tmp/claude-501/-Users-austin-Dev-plinth/90401f5f-00cb-479c-9330-909d2566d0eb/scratchpad/split/wtb/.plinth-lane-canary.mQko1j/mock-plinth/lane-guard.sh snapshot > "$SNAP" || { echo "SNAPSHOT FAILED rc=$?"; exit 1; }
# SPEC under project CWD so Claude Code Write can create it (system /tmp is
# outside the default project file-access scope). Path must NOT exist yet:
# Write refuses to overwrite an unread existing file.
SPEC_DIR="$(mktemp -d "${PWD}/.plinth-lane.XXXXXX")" || { echo "SPEC_DIR mktemp failed rc=$?"; exit 1; }
SPEC="$SPEC_DIR/prompt"
OUT="$(mktemp -t codex-out.XXXXXX)" || { rm -rf "$SPEC_DIR"; echo "OUT mktemp failed rc=$?"; exit 1; }
[ ! -e "$SPEC" ] || { echo "SPEC path already exists — refuse to proceed"; exit 1; }
printf 'BEFORE=%q SNAP=%q SPEC_DIR=%q SPEC=%q OUT=%q\n' "$BEFORE" "$SNAP" "$SPEC_DIR" "$SPEC" "$OUT"
