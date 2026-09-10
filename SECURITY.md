# Security policy

## Supported versions

The `main` branch is supported, and tagged releases get fixes for the current minor version.

## What it trusts

`tooling-sync install` runs `make install` inside every repository it tracks. That runs whatever that repository's Makefile says, as you. **Only list repositories whose code you'd run anyway.**

`adopt` copies files from your prefix into a repository. It asks before overwriting a repository file that also changed, unless you pass `-y`.

## Reporting a vulnerability

**Don't open a public issue.**

Report privately through GitHub's [private vulnerability reporting](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability) on this repository, which opens a draft advisory only the maintainers can see. Or email **code@kingletas.com**.

Tell us what it does wrong, how to reach it, and what an attacker gets. A failing test is the clearest report there is.

You'll get an acknowledgement, a triage verdict, and for anything confirmed, a fix with a regression test and a sweep for the rest of that defect's class.
