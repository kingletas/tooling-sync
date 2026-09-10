# From nothing to a working tooling-sync

By the end of this page you'll have tooling-sync installed, tracking a small practice tool, and you'll have seen it catch an edit made to the installed copy instead of the source. It takes about ten minutes.

## Contents

- [What this is](#what-this-is)
- [What you need](#what-you-need)
- [Step 1: install it](#step-1-install-it)
- [Step 2: make a tool to track](#step-2-make-a-tool-to-track)
- [Step 3: tell tooling-sync about it](#step-3-tell-tooling-sync-about-it)
- [Step 4: install through it](#step-4-install-through-it)
- [Step 5: change the source](#step-5-change-the-source)
- [Step 6: catch an edit made in the wrong place](#step-6-catch-an-edit-made-in-the-wrong-place)
- [Where to go next](#where-to-go-next)

## What this is

Say you write your own command-line tools. Each one has a repository, where you edit it, and an installed copy in `~/bin`, which is what actually runs. Nothing tells you when those two copies stop matching, or which one changed.

tooling-sync keeps track of both. It tells you whether the installed copy is behind the source, and it fails loudly when somebody edited the installed copy directly, because that edit exists nowhere else.

## What you need

- `bash` 4.2 or newer, `make`, `git` and the usual coreutils.
- A `~/bin` directory on your `PATH`. The first step creates the directory. If `make install` prints `note: ... is not on your PATH`, add `export PATH="$HOME/bin:$PATH"` to your shell profile and open a new terminal.

Every command below was run on a clean home directory. In the output, `/home/you` stands for your own home directory.

## Step 1: install it

```bash
cd ~
git clone https://github.com/kingletas/tooling-sync && cd tooling-sync
mkdir -p ~/bin
make install
```

The clone was run from a local copy of this repository rather than from GitHub, so that one line is not verified; the rest ran as shown.

```text
installed tooling-sync -> /home/you/bin
next: list your tool repositories in /home/you/.config/tooling-sync/repos, one path per line
```

It has nothing to track yet, so it tells you where the list goes.

## Step 2: make a tool to track

tooling-sync works with any repository whose `Makefile` has an `install` target. Here's the smallest one that works, a command called `hello`:

```bash
mkdir -p ~/src/hello/bin
cd ~/src/hello
printf '#!/usr/bin/env bash\necho "hello, version 1"\n' > bin/hello
printf 'PREFIX ?= $(HOME)/bin\n\ninstall:\n\tinstall -m 755 bin/hello $(PREFIX)/hello\n' > Makefile
cat Makefile
```

```text
PREFIX ?= $(HOME)/bin

install:
	install -m 755 bin/hello $(PREFIX)/hello
```

The `PREFIX ?=` line matters. tooling-sync runs `make install PREFIX=<a scratch directory>` to learn which files the tool installs, so the Makefile has to honour `PREFIX`.

## Step 3: tell tooling-sync about it

The list is one repository path per line. `$HOME` is expanded, and lines starting with `#` are ignored.

```bash
mkdir -p ~/.config/tooling-sync
echo '$HOME/src/hello' > ~/.config/tooling-sync/repos
tooling-sync tools
```

```text
TOOL               REPOSITORY                                     BASELINE
hello              ~/src/hello                                    none

listed in: /home/you/.config/tooling-sync/repos
prefix:    ~/bin
```

`BASELINE none` means it has never seen the two copies agree. The first install records that.

## Step 4: install through it

```bash
tooling-sync install hello
hello
tooling-sync status
```

```text
hello
  make: Entering directory '/home/you/src/hello'
  install -m 755 bin/hello /home/you/bin/hello
  make: Leaving directory '/home/you/src/hello'
  locked 1 file(s) read-only
  baseline recorded
hello, version 1

hello
  in step

1 file(s) tracked, 0 out of step
```

Two things happened besides the copy. It recorded a baseline: the fingerprint of each file at the moment both copies matched. That's how it can tell later which side moved. It also made the installed copy read-only, so an editor refuses to change it.

## Step 5: change the source

Edit the repository copy, the right way round:

```bash
sed -i 's/version 1/version 2/' bin/hello
tooling-sync status
```

```text
hello
  repo-ahead   hello                                    tooling-sync install — the prefix is behind the source

1 file(s) tracked, 1 out of step
```

`repo-ahead` means the installed copy is stale. Nothing is lost, because the repository has the work. `check`, the command a pre-commit hook calls, mentions it and still passes:

```bash
tooling-sync check; echo "exit $?"
```

```text
tooling-sync: 1 file(s) are newer in their repository than on PATH.
  repo-ahead   hello/hello
Run "tooling-sync install" when you want to be running them.

exit 0
```

Install it to catch up:

```bash
tooling-sync install hello
hello
```

The last line of the output is `hello, version 2`.

## Step 6: catch an edit made in the wrong place

Try to edit the installed copy directly:

```bash
echo "echo edited in place" >> ~/bin/hello
```

```text
bash: /home/you/bin/hello: Permission denied
```

That's the read-only lock doing its job. To see what `check` does when an edit gets through anyway, unlock the file and edit it:

```bash
tooling-sync unlock hello
echo "echo edited in place" >> ~/bin/hello
tooling-sync check; echo "exit $?"
```

```text
hello              1 file(s) unlocked

These are build artefacts. Edit the repository and install; unlocking is for
reading and experimenting, not for making a change that has to last.
tooling-sync: 1 file(s) were edited in the prefix rather than in the source.
  bin-ahead    hello/hello

The repository is the source; the prefix holds a build artefact. This work
exists on the disk in one place and that place has no history.
"tooling-sync diff" shows it, "tooling-sync adopt" rescues it into the
repository -- then commit there and "tooling-sync install" back out.
exit 1
```

It exits 1, so a pre-commit hook would stop the commit. `bin-ahead` means the installed copy holds work the repository doesn't have. To rescue it, copy it back into the repository:

```bash
tooling-sync adopt hello
tail -1 bin/hello
tooling-sync check; echo "exit $?"
```

```text
  adopted hello

1 file(s) adopted into the repositories. They are now DIRTY and uncommitted —
commit them, then run "tooling-sync install" so the prefix comes back from
the source rather than being left as the thing that was edited.

Adopting is recovery. The process is: edit the repository, then install.
echo edited in place
exit 0
```

When everything is in step, `check` prints nothing and exits 0. That silence is the good result.

When you're done, remove the practice tool with `rm -rf ~/src/hello ~/bin/hello` and delete its line from `~/.config/tooling-sync/repos`.

## Where to go next

- [README](../README.md): every state it reports, declared differences, and tools installed outside `~/bin`.
- [CONTRIBUTING.md](../CONTRIBUTING.md): how to run the suite and what a change should look like.
