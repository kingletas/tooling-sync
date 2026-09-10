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
# reads the same as contract-gate.d/repos.
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

# Declared-local files are hand-edited on purpose and must not be locked.
"$SYNC" install beta >/dev/null 2>&1
if ( printf 'setting = edited\n' > "$PREFIX/beta.d/config.tsv" ) 2>/dev/null; then
  ok "a declared-local file is left writable"
else
  bad "a declared-local file is left writable" "it was locked"
fi
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

echo
printf '  %d passed, %d failed\n\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
