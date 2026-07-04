# tripwire

*[Version française](README.md)*

**Multi-platform** plugin (Claude Code and Mistral Vibe) that scaffolds an anti-regression pipeline into any repo.
Extracted from the KaSe_firmware project's workflow.

## The invariant

> A single script (`scripts/check.sh`) defines what "green" means.
> Every guard (git hook, platform hook, CI) merely calls it
> with a mode that fits its time budget.

- `check.sh --fast` — short loop (< 30 s), runs after every watched edit
- `check.sh --variant <name>` — fast + one variant build (at the platform's Stop/onStop hook)
- `check.sh` — full: fast + all variants (pre-push, CI)
- Graceful degradation: build env missing → falls back to `--fast` instead of blocking

## Large projects

The "fast < 30 s on every edit, variant check on every Stop" contract holds on
large repos too, thanks to four mechanisms in the generated `check.sh`:

- **Skip-if-already-green**: a fingerprint of the repo state (HEAD + diff +
  untracked files) is stored per mode in `.git/tripwire/`; if nothing moved
  since the last green run, the check exits immediately. `--force` or
  `TRIPWIRE_FORCE=1` to override (e.g. after a toolchain update).
- **Monorepo scoping**: a `MODULE_FAST=("glob:command" …)` table in check.sh;
  hooks pass the edited file (`--changed`) and the fast phase only runs the
  touched module's tests.
- **Lock + debounce**: `flock` prevents concurrent checks (the second one exits
  politely); post-edit hooks won't re-check within `TRIPWIRE_DEBOUNCE` seconds
  of the previous run (default 10).
- **Budget guard**: if the fast phase drifts past `TRIPWIRE_FAST_BUDGET`
  seconds (default 30), check.sh says so — the tripwire watches its own
  contract.
- **Readable failure without re-running**: the last red run's output is
  captured in `.git/tripwire/last-fail.log` (the assistant reads it instead of
  re-running the command); every real run logs its duration to `history.tsv` —
  `/tripwire:status` derives the trend.

`/tripwire:init` can also generate a **staged CI** (fast on MR/PR, full on the
default branch + nightly) and tunes the Stop hook timeout for long builds.

## Tokens & rtk (optional)

tripwire is token-frugal by design: `check.sh` runs tests and builds with
output discarded (only the exit code matters), and hooks only relay a
truncated summary to the assistant when red. No verbose output enters the
context through the pipeline itself.

The only verbose moment is deliberate: when red, the failure details are in
`last-fail.log`. If you use [rtk](https://github.com/rtk-ai/rtk) (a proxy that
compresses command output by 60-90%) globally, any manual re-run gets
compressed automatically — no integration needed. tripwire stays
dependency-free and portable.

## Installation

### For Claude Code

```bash
# From GitLab:
claude plugin marketplace add https://gitlab.com/harrael/tripwire
# Or from a local clone:
claude plugin marketplace add ~/Documents/GitHub/tripwire

claude plugin install tripwire@tripwire
```

### For Mistral Vibe

```bash
vibe plugin marketplace add https://gitlab.com/harrael/tripwire
vibe plugin install tripwire@tripwire
```

## Skills

| Skill | Usage |
|---|---|
| `/tripwire:init` | Scaffolds check.sh (skip-if-green, monorepo scoping, lock, budget guard), git hooks, platform hooks (Claude Code: PostToolUse/Stop/SessionStart; Mistral Vibe: onEdit/onWrite/onStop), optional staged CI, config section (CLAUDE.md or VIBE.md). **Re-run on an equipped project**: detects outdated scaffolds via the `# tripwire-template:` stamp and proposes a targeted update without touching your commands |
| `/tripwire:gen-agents` | Generates up to 5 project-specialized agents: test-author / code-reviewer / debugger / maintainer / security-auditor (the last two with persistent cross-session memory) |
| `/tripwire:release` | Release workflow: git tag = version, semver bump proposed from commits, green check mandatory, version-manifest sync, glab/gh release |
| `/tripwire:status` | One-shot diagnosis: scaffold up to date? hooks active? last green/red? duration drift? watched-path blind spots? `--fleet` mode: a table of all equipped repos |
| `/tripwire:bisect` | Finds the commit that broke the check: `git bisect run` with check.sh as the oracle |

## Updating an equipped project

Every generated `check.sh` carries a `# tripwire-template: vX.Y.Z` stamp.
After `claude plugin update tripwire@tripwire`, re-run `/tripwire:init` in the
project: the skill compares the stamp to the plugin version, announces what
changed, and updates the scaffolded files while preserving your fast/build
commands, variants and watched paths.

The `SessionStart` hook also installs the git hooks automatically on every
fresh clone — no need to remember `./scripts/install-hooks.sh`.

## Teams (Claude for Teams / Enterprise)

Two Claude Code mechanisms combine with tripwire for org-wide deployment
(Admin Settings → Claude Code → Managed settings):

- **Controlled marketplace**: `strictKnownMarketplaces` restricts allowed
  marketplaces — add this repo's URL to distribute tripwire officially.
- **Managed hooks**: managed settings accept the same `hooks` key that
  `/tripwire:init` writes to `.claude/settings.json`. To keep non-tripwire
  repos silent, guard the commands behind an existence test:
  ```json
  { "type": "command",
    "command": "H=\"$CLAUDE_PROJECT_DIR/scripts/hooks/cc_stop.sh\"; [ -x \"$H\" ] && exec \"$H\"; exit 0" }
  ```

The invariant is unchanged: managed hooks only call the current repo's
`scripts/check.sh`; each project keeps its own definition of "green".

## Automatic platform detection

The plugin detects whether you're on **Claude Code** or **Mistral Vibe** via
environment variables (`CLAUDE_PROJECT_DIR` / `VIBE_PROJECT_DIR`) and adapts:
generated hooks, config file (.claude/settings.json or .vibe/config.json),
documentation file (CLAUDE.md or VIBE.md).
