# Contributing

Thanks for looking.

## What you need

`bash` 4.2 or newer, `make` and coreutils. Install `shellcheck` too if you're changing any shell. Without it, `make lint` says it skipped the check rather than failing.

## The gate

```bash
make check
```

That's everything a commit has to pass, and it's what CI runs. The suite builds fake repositories and a fake prefix in a temporary directory, so it never writes to your real prefix.

## What a change should look like

- One concern per pull request, with the reasoning in the description.
- `make check` green.
- A test that fails before your change and passes after it. **One direction isn't a test**: something that fires isn't evidence it can be quiet, and something quiet isn't evidence it can fire.
- An entry in `CHANGELOG.md` under `## [Unreleased]`, saying what changed for somebody using this rather than what the diff did.
- Comments say what the code does or what it guards against, in a sentence or two. History belongs in the commit message and the changelog.

## Security

Don't open a public issue for a vulnerability. [SECURITY.md](SECURITY.md) has the reporting route.
