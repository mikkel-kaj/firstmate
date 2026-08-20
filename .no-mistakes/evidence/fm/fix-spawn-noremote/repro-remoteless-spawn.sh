#!/usr/bin/env bash
# Manual end-user repro: spawn a scout for a REGISTERED LOCAL-ONLY project that
# has no git remote at all, using the real bin/fm-spawn.sh, a real treehouse-style
# pooled worktree, and a fake tmux/treehouse so no terminal is actually created.
set -u
SPAWN=$1          # path to the fm-spawn.sh under test
ROOTDIR=$2        # scratch dir for this run
LABEL=$3

rm -rf "$ROOTDIR"; mkdir -p "$ROOTDIR"
home="$ROOTDIR/home"; project="$ROOTDIR/project"; pool="$ROOTDIR/pool"; fake="$ROOTDIR/fakebin"
id='ship-remoteless-demo-a1'

mkdir -p "$fake"
cat > "$fake/tmux" <<'SH'
#!/usr/bin/env bash
set -u
case "$*" in *"#{pane_current_path}"*) printf '%s\n' "${FM_FAKE_PANE_PATH:?}"; exit 0 ;; esac
case "${1:-}" in display-message) printf 'firstmate\n'; exit 0 ;; esac
exit 0
SH
printf '#!/usr/bin/env bash\nexit 0\n' > "$fake/treehouse"
chmod +x "$fake/tmux" "$fake/treehouse"

mkdir -p "$home/data/$id" "$home/projects" "$home/state" "$home/config"
printf 'codex\n' > "$home/config/crew-harness"
printf 'brief for %s\n' "$id" > "$home/data/$id/brief.md"
touch "$home/state/.last-watcher-beat"

# local-only project: git init, NO remote ever added
git init --quiet -b main "$project"
printf 'base\n' > "$project/README.md"
git -C "$project" add README.md
git -C "$project" -c user.name=Captain -c user.email=c@example.invalid commit -qm initial
base=$(git -C "$project" rev-parse HEAD)
git -C "$project" worktree add --quiet --detach "$pool" "$base"   # treehouse-style pooled worktree
# local main advances after the pool worktree was handed out (the stale-base shape)
printf 'newest local work\n' > "$project/newest.txt"
git -C "$project" add newest.txt
git -C "$project" -c user.name=Captain -c user.email=c@example.invalid commit -qm advance-local-main
tip=$(git -C "$project" rev-parse refs/heads/main)

echo "=== $LABEL ==="
echo "\$ git -C project remote -v      # local-only project, no remote configured"
git -C "$project" remote -v
echo "\$ git -C project log --oneline -1 main"
git -C "$project" log --oneline -1 main
echo "\$ git -C pool log --oneline -1 HEAD    # pooled worktree still on the stale base"
git -C "$pool" log --oneline -1 HEAD
echo
echo "\$ fm-spawn.sh $id <project> ${SPAWN_ARGS:---scout}"
FM_ROOT_OVERRIDE='' FM_HOME="$home" \
  FM_STATE_OVERRIDE="$home/state" FM_DATA_OVERRIDE="$home/data" \
  FM_PROJECTS_OVERRIDE="$home/projects" FM_CONFIG_OVERRIDE="$home/config" \
  FM_GATE_REFUSE_BYPASS=1 FM_SPAWN_NO_GUARD=1 TMUX="fake,1,0" FM_FAKE_PANE_PATH="$pool" \
  PATH="$fake:$PATH" \
  "$SPAWN" "$id" "$project" ${SPAWN_ARGS:---scout} 2>&1 | tail -n 3
rc=${PIPESTATUS[0]}
echo "exit status: $rc"
echo
echo "\$ git -C pool log --oneline -1 HEAD    # base the scout actually launches from"
git -C "$pool" log --oneline -1 HEAD
if [ "$(git -C "$pool" rev-parse HEAD)" = "$tip" ]; then
  echo "pool HEAD == local main tip ($tip)  -> launched from the freshest local base"
else
  echo "pool HEAD ($(git -C "$pool" rev-parse HEAD)) != local main tip ($tip)  -> NOT refreshed"
fi
echo "\$ ls pool/newest.txt"
ls "$pool/newest.txt" 2>&1
echo
