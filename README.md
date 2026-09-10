<h1 align="center">🔁 tooling-sync</h1>

<p align="center">
  Tell an installed command apart from the repository it came from — <em>and know which one moved.</em>
</p>

<p align="center">
  <img alt="Bash" src="https://img.shields.io/badge/bash-4.2%2B-4eaa25">
  <img alt="Dependencies" src="https://img.shields.io/badge/dependencies-make%20%7C%20coreutils-brightgreen">
  <a href="https://github.com/kingletas/tooling-sync/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/kingletas/tooling-sync/actions/workflows/ci.yml/badge.svg"></a>
  <img alt="License" src="https://img.shields.io/badge/license-MIT-green">
</p>

---

```bash
make install                 # put it on your PATH
tooling-sync status          # what moved, and which way
tooling-sync install         # repository -> prefix
tooling-sync adopt           # prefix -> repository
```

New to it? [`docs/from-nothing.md`](docs/from-nothing.md) walks through tracking a first tool, step by step.

## Why

A tool that lives in a repository and *runs* from `~/bin` has two working copies, and nothing in git relates them. Both are editable, both look authoritative, and an edit to either one is invisible from the other. There is no `git status` that spans them, no CI that sees both, and no moment at which anything says they have parted.

The failure is not that somebody forgot to run `make install`. It is that **"in step" had no definition**, so there was nothing for a check to check.

It got worse in the specific way this tool was written for. Extracting five commands into publishable repositories *generalised* them: the repository copy discovers its vault, the installed copy had one hardcoded; the repository ships a starter lane table, the installed one names eleven real repositories. So the two copies were different **on purpose**, byte-equality could never be the test, and no other test existed.

Three of the five would have broken if the repository copy had simply been installed over the top, because the configuration the generalised version reads had not been written yet. Everyone involved could see that installing was wrong, and nobody could say what right looked like. A week later, edits had landed on both sides.

## The direction is not symmetric

**The repository is the source. The prefix holds a build artefact, and the copy runs one way:** edit the repository, then install. Everything below exists to notice when that did not happen.

So **`adopt` is a recovery path, not the other half of a pair.** It exists because an edit already made in the prefix has to go somewhere and deleting it is worse than importing it — not because editing the prefix is a thing to do. A tool that offers two directions evenly teaches that either is fine.

**`install` leaves what it installed read-only**, which is where this stops being advice. A `>` redirect, a `cp` and an editor all refuse; the installers keep working, because `install(1)` unlinks the target rather than opening it. The point is timing — the gate catches an in-place edit at the next commit, and the lock catches it at the keystroke, before there is anything to rescue. `tooling-sync unlock` is one command for a deliberate experiment, and `TOOLING_LOCK=0` turns it off.

Declared-local files are never locked. They are your own configuration, and hand-editing them is the one thing you're supposed to do here.

## The two ideas

**The installer is the authority on what a tool owns.** `make install PREFIX=<tmpdir>` into a scratch directory produces the exact tree the tool believes it installs, and that tree is what gets compared against the real prefix. A tool that renames a file on the way in — say `bin/scanner.py` becoming `mytool.d/scanner.py` — needs no special case here, and cannot acquire one by drifting. It also means this tool has no list of what each tool installs, which is one fewer thing to keep in step.

**A baseline, so "which side moved" is answerable.** Two copies that differ tell you nothing about direction. Recording the hashes at the moment they last agreed turns one useless comparison into a three-way one:

| Installed | Repository | State | What to do |
|---|---|---|---|
| = baseline | moved | `repo-ahead` | `tooling-sync install` |
| moved | = baseline | `bin-ahead` | `tooling-sync adopt` |
| moved | moved | `diverged` | `tooling-sync diff`, by hand |
| — | present | `uninstalled` | `tooling-sync install` |
| present | — | `bin-only` | `tooling-sync adopt` |
| moved | moved, no baseline | `unknown` | `tooling-sync diff` |

With no baseline the honest answer is `unknown`, and it says that rather than guessing. **A wrong guess about direction overwrites work**, which is worse than the drift it was trying to fix.

**`check` fails on four of those states, not six.** What it guards against is *loss* — `bin-ahead`, `bin-only`, `diverged` and `unknown` all mean there is a file on the disk in exactly one place, and it is the place with no history. `repo-ahead` and `uninstalled` are stale, not lost: the repository already has the work, and only the copy being run is behind. It says so and exits 0.

Blocking on those would mean the only way to commit a tool change is to install it first, which puts unreviewed code on `PATH` — this gate refused exactly that commit before the distinction was drawn.

`bin-only` is the state no repository-side check can reach: a helper written straight into the payload directory, present in no repository, running on every invocation. One of those had been live for a day when this tool first ran.

## Declared differences

Some differences are correct and permanent — an installed config file naming your own paths, against the generic starter the repository ships. Declare them:

```
# tool <TAB> path relative to the prefix <TAB> why
mytool	mytool.d/config.tsv	this machine's own settings; the repository ships a starter
```

in `~/.config/tooling-sync/local.tsv`. They report as `local` and `check` passes over them.

Two things make the declaration honest rather than a mute button. **The reason column is required and is printed** — an undocumented exception is indistinguishable from the drift this catches. And **`install` carries a declared file around the installer** rather than letting it be overwritten, because a declaration that quiets `status` while the next install clobbers the file anyway is worse than no declaration at all.

Keep the list short. A file listed there has no gate on it.

## What it tracks

Whatever `TOOLING_REPOS` lists — one repository path per line, `$HOME` expanded, `#` comments and blank lines ignored. The tool's name is the basename. **A listed path that is not on disk reads `MISSING` rather than being skipped**, because a list that quietly stops describing anything is worse than no list.

With no such file, set `TOOLING_ROOT` to a directory and it scans that for directories whose `Makefile` has an `install` target. That works well if you keep your tools in one place. There is no default: with neither a list nor `TOOLING_ROOT`, it stops and names the list it looked for.

**Prefer the list once you have more than a couple.** Membership by location means a project acquires this tool's behaviour by being filed somewhere, and that is a real cost: two GTK applications had to be moved out of the scanned directory because being staged like a command breaks a desktop launcher.

## Commands

| | |
|---|---|
| `status [TOOL...]` | one line per file that is not in step, and what to do about it |
| `check [TOOL...]` | the same, exit 1 on drift — what a pre-commit hook calls |
| `diff TOOL [FILE]` | the actual difference, repository on the left |
| `install [TOOL...]` | repository → prefix, through the repository's own `make install` |
| `adopt [TOOL...]` | prefix → repository — **recovery**, for an edit made in the wrong place |
| `record [TOOL...]` | accept the current state as the baseline |
| `lock` / `unlock` | make the installed copies read-only, or stop |
| `tools` | what is tracked, and whether each has a baseline |

`-n` for a dry run, `-y` to skip the prompt `adopt` raises before overwriting a repository copy that also moved.

## Environment

| | |
|---|---|
| `TOOLING_REPOS` | the list of repositories, one path per line (default `~/.config/tooling-sync/repos`) |
| `TOOLING_ROOT` | a directory to scan when there is no list (no default) |
| `PREFIX` | where they install (default `~/bin`) |
| `TOOLING_STATE` | baselines (default `$XDG_STATE_HOME/tooling-sync`) |
| `TOOLING_LOCAL` | the declared-difference table |
| `TOOLING_LOCK` | `0` to stop `install` locking what it installed |

## As a gate

The point is not to have a report. It is to make a commit fail. If your pre-commit hook maps a directory to the command that guards it, the two rows look like this, with `~/src/tools` standing in for wherever your tool repositories live:

```
tooling	$HOME/src/tools	*	tooling-sync,make	tooling-sync check "$(basename "$PWD")" && make check
tooling-bin	$HOME/bin	*	tooling-sync	tooling-sync check
```

A full check across six tools costs under a second, because an install is a handful of file copies.

## License

MIT.
