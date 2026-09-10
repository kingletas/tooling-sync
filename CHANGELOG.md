# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- **Which repositories are tools is declared rather than inferred from where they sit.** `TOOLING_REPOS` names a file holding one repository path per line, and that file is the authority when it exists. Scanning a parent directory is kept as the fallback for anyone who keeps their tools in one place.
- **A listed repository that is not on disk reads `MISSING`.** Skipping it would let the list stop describing anything without saying so.
- **`TOOLING_ROOT` has no default.** It used to default to a directory on the author's machine. Set it to scan a directory; with neither a list nor `TOOLING_ROOT`, every command exits 2 and names the list it looked for.

### Added

- **A tool can be declared as installed somewhere other than the prefix.** A `.deb` or a flatpak puts the command in `/usr/bin`, and the prefix being empty is then the intended state rather than a missing install. Declare it in `TOOLING_ELSEWHERE` and it reads `elsewhere` instead of `uninstalled`, `check` stays quiet, and `install` leaves it alone rather than putting a second copy on `PATH` ahead of the real one.
- **The declaration names a path and that path is checked.** A tool declared as living somewhere it is not reads `elsewhere-gone`, because a declaration nothing verifies is a way to silence a tool that really has disappeared.
- **A copy turning up in the prefix anyway is still reported normally.** Two installs racing each other on `PATH` is what this tool exists to notice, and a declaration does not get to hide one.
- **CI runs `make check`** on every push and pull request.
- **A release workflow.** Pushing a tag such as `v1.1.0` runs `make check`, proves `make install` works, and publishes a GitHub Release whose body is that version's section of this file. A tag with no section here fails before anything is published.

### Fixed

- **`make install` works on a machine with no repository list yet.** It used to install the command and then fail its own check, because there was nothing to track. It now prints where to write the list and exits 0.

## [1.1.0]

### Added

- **`install` leaves what it installed read-only, and `lock` / `unlock` do it on demand.** The repository is the source and the prefix holds a build artefact; a `>` redirect, a `cp` and an editor now all refuse. The installers keep working because `install(1)` unlinks the target rather than opening it — there is a test for that, and if it ever fails every tool in the estate has become uninstallable. `TOOLING_LOCK=0` turns it off.
- **Declared-local files are never locked.** They are configuration, hand-edited on purpose.

### Changed

- **`adopt` reads as recovery rather than as the other half of a pair**, and `bin-ahead`, `bin-only` and `diverged` say *edited in place* rather than naming a command. A tool that offers two directions evenly teaches that either is fine.

## [1.0.0]

### Added

- **`status`, `check`, `diff`, `install`, `adopt`, `record`, `tools`.** `check` is the one a hook calls; everything else is for a person deciding what to do about what it found.
- **The installer is asked what a tool owns.** `make install PREFIX=<tmpdir>` into a scratch prefix produces the tree to compare against, so a rename on the way in needs no special case and this tool holds no list of anybody's files.
- **A baseline of the last agreeing state**, which is what makes direction answerable at all. Without it the only available fact is "these differ", and acting on that overwrites whichever side you guessed wrong about. With no baseline the state is `unknown` and it refuses to guess.
- **`bin-only`** — a file present in the prefix and in no repository. The one drift a repository-side check cannot see, and the state that found a live gate helper running from `~/bin` that existed nowhere else.
- **Declared local differences**, with a required reason that is printed, and carried around the installer by `install` so a declaration cannot become a quiet way to lose a file.
- **Bytecode and linter caches are never evidence of drift** — an installer that verifies itself leaves `__pycache__` in the scratch prefix, and real use leaves it in the real one.
- **Eighteen tests** over a throwaway estate of fake repositories and a fake prefix. Every assertion is about a state transition, because the states are the tool: a status line reading `bin-ahead` when the repository moved is the one bug that matters.
