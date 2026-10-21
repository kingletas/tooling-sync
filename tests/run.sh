#!/usr/bin/env bash
#
# The end-to-end suite. Builds a throwaway estate -- fake tool repositories and
# a fake prefix -- so nothing here can touch the real ~/bin. Every assertion is
# about a state transition, because the states ARE the tool: a status line that
# says `bin-ahead` when the repository moved is the one bug that matters.

set -uo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
SYNC="$HERE/bin/tooling-sync"

pass=0; fail=0
ok()   { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad()  { fail=$((fail + 1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
check(){ if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1" "expected [$3], got [$2]"; fi; }

ROOT="$(mktemp -d "${TMPDIR:-/tmp}/tooling-sync-test.XXXXXX")"
trap 'rm -rf "$ROOT"' EXIT
# TOOLING_REPOS is pointed at a path that does not exist so the scan fallback
# is what runs here. Left at its default it would read this machine's real
# ~/.config/tooling-sync/repos, and the suite would be asserting against the
# estate rather than against its own fixtures.
export TOOLING_ROOT="$ROOT/repos" PREFIX="$ROOT/prefix" TOOLING_REPOS="$ROOT/no-such-list"
export TOOLING_STATE="$ROOT/state" TOOLING_LOCAL="$ROOT/local.tsv"
mkdir -p "$TOOLING_ROOT" "$PREFIX"

# A minimal tool with the interface the estate requires: a Makefile with an
# install target that delegates. Two files, one of them in a payload directory,
# because a payload directory is where the real ones keep their configuration.
make_tool() {
  local name="$1" d="$TOOLING_ROOT/$1"
  mkdir -p "$d/bin/$name.d" "$d/scripts"
  printf '#!/usr/bin/env bash\necho %s v1\n' "$name" > "$d/bin/$name"
  printf 'setting = 1\n' > "$d/bin/$name.d/config.tsv"
  chmod 755 "$d/bin/$name"
  cat > "$d/scripts/install" <<INSTALL
#!/usr/bin/env bash
set -euo pipefail
here="\$(cd -- "\$(dirname -- "\${BASH_SOURCE[0]}")/.." && pwd -P)"
prefix="\${1:-\$HOME/bin}"
install -m 755 "\$here/bin/$name" "\$prefix/$name"
install -d -m 755 "\$prefix/$name.d"
install -m 644 "\$here"/bin/$name.d/* "\$prefix/$name.d/"
INSTALL
  chmod 755 "$d/scripts/install"
  # shellcheck disable=SC2016  # $(PREFIX) is make's variable, not the shell's
  printf 'install:\n\t@scripts/install "$(PREFIX)"\n' > "$d/Makefile"
}

# Editing the prefix is what this tool exists to catch, so the tests have to do
# it on purpose -- and `install` now leaves those files read-only, so they have
# to unlock first. The chmod is not test scaffolding to look past: it is the
# feature. A test that could write without it would mean the lock was not there.
edit_prefix() {  # path, content
  chmod u+w "$1"
  printf '%s\n' "$2" > "$1"
}

state_for() {  # tool, file -> the bare state word
  "$SYNC" status "$1" 2>&1 | awk -v f="$2" '$2 == f {print $1}'
}

echo
echo "tooling-sync"
echo

# --- discovery ---------------------------------------------------------------

make_tool alpha
make_tool beta
mkdir -p "$TOOLING_ROOT/not-a-tool"          # no Makefile at all
printf 'help:\n\t@true\n' > "$TOOLING_ROOT/not-a-tool/Makefile"   # ... and no install target

listed="$("$SYNC" tools | awk 'NR>1 && NF {print $1}' | grep -vE '^(prefix:|listed)$' | tr '\n' ' ')"
check "tracks a repository whose Makefile installs" "$listed" "alpha beta "

# --- the list is the authority when there is one ----------------------------
#
# The scan above is the fallback. When TOOLING_REPOS names a file, membership
# is declared: a repository joins by being listed, not by sitting somewhere.

REPOS="$ROOT/repos.list"
printf '%s\n' "$TOOLING_ROOT/alpha" > "$REPOS"
listed="$(TOOLING_REPOS="$REPOS" "$SYNC" tools | awk 'NR>1 && NF {print $1}' | grep -vE '^(prefix:|listed)$' | tr '\n' ' ')"
check "the list wins over the scan"                "$listed" "alpha "

printf '%s\n' "$TOOLING_ROOT/not-a-tool" >> "$REPOS"
listed="$(TOOLING_REPOS="$REPOS" "$SYNC" tools | awk 'NR>1 && NF {print $1}' | grep -vE '^(prefix:|listed)$' | tr '\n' ' ')"
check "a listed repository is tracked without an install target" "$listed" "alpha not-a-tool "

# A path in the list that is not on disk must be REPORTED. Skipping it is how a
# list quietly stops describing anything: move every repository and a tool that
# skips reports them all as fine by never mentioning them.
printf '%s\n' "$TOOLING_ROOT/moved-away" > "$REPOS"
out="$(TOOLING_REPOS="$REPOS" "$SYNC" tools 2>&1)"
check "a listed repository that is gone reads MISSING" \
  "$(printf '%s' "$out" | grep -c 'MISSING')" "1"
check "and it is still named"                        \
  "$(printf '%s' "$out" | grep -c 'moved-away')" "1"

# Comments and blank lines are skipped, and $HOME is expanded, so the file
# can be written by hand.
printf '# a comment\n\n%s\n' "$TOOLING_ROOT/alpha" > "$REPOS"
listed="$(TOOLING_REPOS="$REPOS" "$SYNC" tools | awk 'NR>1 && NF {print $1}' | grep -vE '^(prefix:|listed)$' | tr '\n' ' ')"
check "comments and blank lines are skipped"       "$listed" "alpha "

# With no list and no TOOLING_ROOT there is nothing to track, and it says so.
out="$(TOOLING_ROOT='' "$SYNC" tools 2>&1)"; status=$?
check "no list and no scan directory is a usage error" "$status" "2"
check "and it names the list it looked for" \
  "$(printf '%s' "$out" | grep -c 'no-such-list')" "1"

# --- install, and the baseline it writes -------------------------------------

"$SYNC" install alpha >/dev/null 2>&1
check "install puts the command in the prefix" "$([[ -x "$PREFIX/alpha" ]] && echo yes)" "yes"
check "install writes a baseline"              "$([[ -s "$TOOLING_STATE/alpha.tsv" ]] && echo yes)" "yes"
check "a fresh install is in step"             "$(state_for alpha alpha)" ""
"$SYNC" check alpha >/dev/null 2>&1
check "check passes when in step"              "$?" "0"

# --- the three directions ----------------------------------------------------

printf '#!/usr/bin/env bash\necho alpha v2\n' > "$TOOLING_ROOT/alpha/bin/alpha"
check "repository edited alone reads repo-ahead" "$(state_for alpha alpha)" "repo-ahead"

# repo-ahead is stale, not lost -- the repository has the work. Blocking a
# commit on it would mean the only way to commit a tool change is to install it
# first, putting unreviewed code on PATH.
"$SYNC" check alpha >/dev/null 2>&1
check "check does not block on repo-ahead"       "$?" "0"
out="$("$SYNC" check alpha 2>&1)"
case "$out" in *repo-ahead*) ok "but does say the copy on PATH is stale" ;;
               *) bad "but does say the copy on PATH is stale" "$out" ;; esac

"$SYNC" install alpha >/dev/null 2>&1           # back in step, baseline moves with it
edit_prefix "$PREFIX/alpha" '#!/usr/bin/env bash
echo alpha v3'
check "prefix edited alone reads bin-ahead"      "$(state_for alpha alpha)" "bin-ahead"

# The other direction is loss: this file is on the disk in one place, and it is
# the place with no history. That is what the gate is for.
"$SYNC" check alpha >/dev/null 2>&1
check "check fails when the prefix holds work git does not" "$?" "1"

printf '#!/usr/bin/env bash\necho alpha v4\n' > "$TOOLING_ROOT/alpha/bin/alpha"
check "both sides edited reads diverged"         "$(state_for alpha alpha)" "diverged"

# Direction is unanswerable without a baseline, and the tool must say so rather
# than pick one. This is the state every file was in before this tool existed.
rm -f "$TOOLING_STATE/alpha.tsv"
check "no baseline reads unknown"                "$(state_for alpha alpha)" "unknown"

# --- adopt -------------------------------------------------------------------

"$SYNC" install alpha >/dev/null 2>&1
edit_prefix "$PREFIX/alpha.d/config.tsv" 'setting = 99'
"$SYNC" adopt -y alpha >/dev/null 2>&1
check "adopt copies the prefix copy into the repository" \
  "$(cat "$TOOLING_ROOT/alpha/bin/alpha.d/config.tsv")" "setting = 99"

# --- a file that exists only in the prefix -----------------------------------

# The one drift no repository-side check can see: a helper written straight into
# the payload directory, present in no repository, running on every invocation.
"$SYNC" install alpha >/dev/null 2>&1
printf 'orphan\n' > "$PREFIX/alpha.d/orphan.tsv"
check "a prefix-only file reads bin-only" "$(state_for alpha alpha.d/orphan.tsv)" "bin-only"
"$SYNC" adopt -y alpha >/dev/null 2>&1
check "adopt rescues a prefix-only file"  \
  "$([[ -f "$TOOLING_ROOT/alpha/bin/alpha.d/orphan.tsv" ]] && echo yes)" "yes"

# --- declared local differences ----------------------------------------------

"$SYNC" install beta >/dev/null 2>&1
edit_prefix "$PREFIX/beta.d/config.tsv" 'setting = local'
check "an undeclared difference is drift" "$(state_for beta beta.d/config.tsv)" "bin-ahead"
printf 'beta\tbeta.d/config.tsv\tthis estate configures it\n' > "$TOOLING_LOCAL"
check "a declared difference reads local" "$(state_for beta beta.d/config.tsv)" "local"
"$SYNC" check beta >/dev/null 2>&1
check "check passes over a declared difference" "$?" "0"

# --- the installed copy is read-only -----------------------------------------

# The point is timing. The gate catches an in-place edit at the next commit; the
# lock catches it at the keystroke, before there is anything to rescue.
"$SYNC" install alpha >/dev/null 2>&1
if ( printf 'hand edit\n' > "$PREFIX/alpha" ) 2>/dev/null; then
  bad "a plain redirect cannot overwrite an installed copy" "the write succeeded"
else
  ok "a plain redirect cannot overwrite an installed copy"
fi

# The installers themselves must keep working, and they do because install(1)
# unlinks the target rather than opening it. If this ever fails, every tool in
# the estate has become uninstallable.
printf '#!/usr/bin/env bash\necho alpha v9\n' > "$TOOLING_ROOT/alpha/bin/alpha"
"$SYNC" install alpha >/dev/null 2>&1
check "but the installer still can"        "$(state_for alpha alpha)" ""

"$SYNC" unlock alpha >/dev/null 2>&1
if ( printf 'hand edit\n' > "$PREFIX/alpha" ) 2>/dev/null; then
  ok "unlock restores the ability to edit"
else
  bad "unlock restores the ability to edit" "still read-only"
fi
"$SYNC" install alpha >/dev/null 2>&1

# --- a copy left writable is unlocked, and check fails until it is locked ----

# A plain `make install` copies without locking, and the copy still matches the
# repository, so by content alone it reads as in step. The lock is what makes
# an in-place edit fail at the keystroke, so a copy without it is reported.
make -C "$TOOLING_ROOT/alpha" install PREFIX="$PREFIX" >/dev/null 2>&1
check "a direct make install reads unlocked"      "$(state_for alpha alpha)" "unlocked"
out="$("$SYNC" check alpha 2>&1)"; status=$?
check "and check fails on it"                      "$status" "1"
case "$out" in *'tooling-sync lock'*) ok "and says to lock it" ;;
               *) bad "and says to lock it" "$out" ;; esac
check "diff has nothing to show for it" "$("$SYNC" diff alpha 2>&1 | grep -c unlocked)" "0"
"$SYNC" lock alpha >/dev/null 2>&1
check "lock puts it back in step"                  "$(state_for alpha alpha)" ""
"$SYNC" check alpha >/dev/null 2>&1
check "and check passes again"                     "$?" "0"
"$SYNC" unlock alpha >/dev/null 2>&1
check "unlock for an experiment reads unlocked too" "$(state_for alpha alpha)" "unlocked"
TOOLING_LOCK=0 "$SYNC" check alpha >/dev/null 2>&1
check "with TOOLING_LOCK=0 a writable copy is not reported" "$?" "0"
"$SYNC" install alpha >/dev/null 2>&1
check "install locks it again"                     "$(state_for alpha alpha)" ""

# Declared-local files are hand-edited on purpose and must not be locked.
"$SYNC" install beta >/dev/null 2>&1
if ( printf 'setting = edited\n' > "$PREFIX/beta.d/config.tsv" ) 2>/dev/null; then
  ok "a declared-local file is left writable"
else
  bad "a declared-local file is left writable" "it was locked"
fi
check "and a writable declared-local file reads local, not unlocked" \
  "$(state_for beta beta.d/config.tsv)" "local"
printf 'setting = local\n' > "$PREFIX/beta.d/config.tsv"

# --- a declared difference survives its own installer ------------------------

# The feature the whole `local` idea rests on. Without it, declaring a file
# local makes `status` quiet and the next `install` overwrites it anyway --
# which is worse than not declaring it, because now nothing reports the loss.
"$SYNC" install beta >/dev/null 2>&1
check "install does not clobber a declared-local file" \
  "$(cat "$PREFIX/beta.d/config.tsv")" "setting = local"

# --- dry runs write nothing --------------------------------------------------

before="$(cat "$PREFIX/beta.d/config.tsv")"
printf 'setting = 2\n' > "$TOOLING_ROOT/beta/bin/beta.d/config.tsv"
"$SYNC" -n install beta >/dev/null 2>&1
check "a dry-run install copies nothing" "$(cat "$PREFIX/beta.d/config.tsv")" "$before"

# --- a tool installed somewhere other than the prefix -------------------------
#
# A .deb or a flatpak puts the command outside PREFIX, and the prefix being
# empty is then the intended state rather than a missing install.

export TOOLING_ELSEWHERE="$ROOT/elsewhere.tsv"
real="$ROOT/opt/alpha"
mkdir -p "$(dirname "$real")"; printf '#!/bin/sh\n' > "$real"; chmod +x "$real"

rm -f "$PREFIX/alpha"
check "with nothing declared, an absent command reads uninstalled" \
  "$(state_for alpha alpha)" "uninstalled"

printf 'alpha\t%s\tinstalled from a package\n' "$real" > "$TOOLING_ELSEWHERE"
check "declared and present reads elsewhere" "$(state_for alpha alpha)" "elsewhere"

"$SYNC" check >/dev/null 2>&1
check "check does not block on a tool that lives elsewhere" "$?" "0"

"$SYNC" install alpha >/dev/null 2>&1
check "install leaves the prefix alone for it" \
  "$([[ -e "$PREFIX/alpha" ]] && echo present || echo absent)" "absent"

# The declaration is checked rather than believed: otherwise it is a way to
# silence a tool that really has gone.
rm -f "$real"
check "declared and NOT there reads elsewhere-gone" "$(state_for alpha alpha)" "elsewhere-gone"

# And a copy turning up in the prefix anyway is still reported, because two
# installs racing each other on PATH is the thing this tool exists to notice.
printf '#!/bin/sh\n' > "$real"; chmod +x "$real"
printf 'stray\n' > "$PREFIX/alpha"; chmod +x "$PREFIX/alpha"
check "a stray copy in the prefix is still reported" \
  "$([[ "$(state_for alpha alpha)" == "elsewhere" ]] && echo hidden || echo reported)" "reported"

# And it fails a check rather than being noted: the prefix comes first on PATH,
# so this copy is the one that runs. It hides best when it matches the source,
# which hashes equal and would otherwise read `synced`.
check "a shadowing copy reads shadowing" "$(state_for alpha alpha)" "shadowing"
"$SYNC" check alpha >/dev/null 2>&1
check "and it blocks, unlike a tool that is merely stale" "$?" "1"

# Payload is not an entry point and cannot shadow anything on PATH.
mkdir -p "$PREFIX/alpha.d"; printf 'x\n' > "$PREFIX/alpha.d/data.tsv"
check "a payload file under an elsewhere tool is not called shadowing" \
  "$([[ "$(state_for alpha alpha.d/data.tsv)" == "shadowing" ]] && echo wrong || echo right)" "right"
rm -rf "$PREFIX/alpha.d"

rm -f "$TOOLING_ELSEWHERE" "$PREFIX/alpha"

# --- a name that is no tool, and a tool named by where you stand -------------

# A name nobody tracks ends the command. It used to be said and then passed:
# the refusal was raised inside a process substitution, which ended only that
# child, and the command went on with an empty list and exit 0. A gate that
# calls `check NAME` with the wrong name was a gate that never looked.
make_tool gamma
"$SYNC" install gamma >/dev/null 2>&1
for verb in status check install adopt lock unlock record; do
  out="$("$SYNC" -y "$verb" no-such-tool 2>&1)"; code=$?
  check "$verb with a name nobody tracks exits 2" "$code" "2"
  check "and says which name" "$(grep -c 'no such tool repository: no-such-tool' <<< "$out")" "1"
done
"$SYNC" diff no-such-tool >/dev/null 2>&1
check "diff with a name nobody tracks exits 2" "$?" "2"
"$SYNC" check "" >/dev/null 2>&1
check "an empty name is no tool either" "$?" "2"

# One bad name stops the whole command, so nothing is done for the good one.
printf '#!/usr/bin/env bash\necho gamma v2\n' > "$TOOLING_ROOT/gamma/bin/gamma"
check "the source moved, so gamma is waiting to be installed" "$(state_for gamma gamma)" "repo-ahead"
"$SYNC" -y install gamma no-such-tool >/dev/null 2>&1
check "install with one good name and one bad exits 2" "$?" "2"
check "and installs nothing for the good one" "$(state_for gamma gamma)" "repo-ahead"
"$SYNC" -y install gamma >/dev/null 2>&1

# A directory names the tool whose repository it is inside. A gate runs in
# whichever checkout the commit is made from, and a worktree's folder is not
# named after the tool.
git -C "$TOOLING_ROOT/gamma" init -q
git -C "$TOOLING_ROOT/gamma" -c user.name=Test -c user.email=t@example.com add -A
git -C "$TOOLING_ROOT/gamma" -c user.name=Test -c user.email=t@example.com commit -qm fixture
git -C "$TOOLING_ROOT/gamma" worktree add -q "$ROOT/elsewhere-worktree" -b side
"$SYNC" check "$TOOLING_ROOT/gamma" >/dev/null 2>&1
check "a clean tool named by its repository's path passes" "$?" "0"
(cd "$ROOT/elsewhere-worktree" && "$SYNC" check . >/dev/null 2>&1)
check "and named as . from a worktree of it" "$?" "0"
edit_prefix "$PREFIX/gamma" "edited where it runs"
out="$(cd "$ROOT/elsewhere-worktree" && "$SYNC" check . 2>&1)"; code=$?
check "from a worktree, . runs the check: an edit in the prefix fails it" "$code" "1"
check "and it is gamma the check names" "$(grep -c 'bin-ahead *gamma/gamma' <<< "$out")" "1"
(cd "$TOOLING_ROOT/gamma/bin" && "$SYNC" check . >/dev/null 2>&1)
check "a folder inside the repository names it too" "$?" "1"
check "status takes a directory as well" "$(cd "$ROOT/elsewhere-worktree" && "$SYNC" status . 2>&1 | awk '$2 == "gamma" {print $1}')" "bin-ahead"

mkdir -p "$ROOT/not-a-repository"
out="$("$SYNC" check "$ROOT/not-a-repository" 2>&1)"; code=$?
check "a directory in no repository exits 2" "$code" "2"
check "and says it is not inside a tracked tool" "$(grep -c 'not inside a tracked tool repository' <<< "$out")" "1"
git -C "$ROOT/not-a-repository" init -q
"$SYNC" check "$ROOT/not-a-repository" >/dev/null 2>&1
check "a repository nobody tracks exits 2" "$?" "2"
"$SYNC" check "$ROOT/no/such/path" >/dev/null 2>&1
check "a path that does not exist exits 2" "$?" "2"

echo
printf '  %d passed, %d failed\n\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
