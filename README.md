# tripwire

*[Version française](README.fr.md)*

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
large repos too, thanks to five mechanisms in the generated `check.sh`:

- **Skip-if-already-green**: a fingerprint of the repo state (HEAD + diff +
  untracked files) is stored per mode in `.git/tripwire/`; if nothing moved
  since the last green run, the check exits immediately. `--force` or
  `TRIPWIRE_FORCE=1` to override (e.g. after a toolchain update).
- **Monorepo scoping**: a `MODULE_FAST=("glob:command" …)` table in check.sh;
  hooks pass the edited file (`--changed`) and the fast phase only runs the
  touched module's tests.
- **Lock + debounce**: `flock` prevents concurrent checks (the second one
  exits politely); post-edit hooks won't re-check within `TRIPWIRE_DEBOUNCE`
  seconds of the previous run (default 10).
- **Budget guard**: if the fast phase drifts past `TRIPWIRE_FAST_BUDGET`
  seconds (default 30), check.sh says so — the tripwire watches its own
  contract.
- **Readable failure without re-running**: the last red run's output is
  captured in `.git/tripwire/last-fail.log` (the assistant reads it instead
  of re-running the command); every real run logs its duration to
  `history.tsv` — `/tripwire:status` derives the trend.

`/tripwire:init` can also generate a **staged CI** (fast on MR/PR, full on the
default branch + nightly) and tunes the Stop hook timeout for long builds.

## Test quality

Green does not mean protected — three guards take care of that:

- **Test ratchet**: the number of tests (counted by `TEST_COUNT_CMD`) never
  silently decreases. The reference lives in `.tripwire-testcount`,
  **committed**: lowering the ratchet requires a visible diff line in review.
  A decrease → warning locally, **red at pre-push**.
- **Anti-weakening guard**: an edit that removes assertions from a test file
  (vs HEAD) injects a warning into the agent's context — legitimate refactor
  or cheating, it has to take a stance.
- **TDD advisory**: watched source modified without any test modified → one
  advisory line with the check's verdict.

And for what mechanics cannot see: `/tripwire:test-review` audits semantic
quality (hollow assertions, happy-path-only, mock-testing, coupling, lying
names) with proposed patches.

## Leaning on tripwire (cohabitation)

tripwire's bricks — `check.sh` (a 0/1 oracle), the hook slots (the
`settings.json` merge preserves foreign hooks), the fast phase, the staged
CI — are anchor points for third-party tooling:

| Tool | Anchor point | Integration |
|---|---|---|
| [TDD Guard](https://github.com/nizos/tdd-guard) | hook slot (PreToolUse) | Per-edit TDD discipline upstream; tripwire stays the downstream oracle (Stop/pre-push) + ratchet. Install alongside — the init merge preserves it. ⚠ sends edited code to a validation model API |
| pre-commit / lefthook | the oracle | Their config calls `./scripts/check.sh --fast` — the invariant survives. One owner for hook routing: if the repo already uses pre-commit, tripwire inserts itself as an entry instead of owning `core.hooksPath` |
| [Betterer](https://phenomnomnominal.github.io/betterer/) (JS) | the fast phase | `betterer ci` inside `FAST_CMD` = a committed multi-metric ratchet; its red becomes the check's red |
| Mutation testing (cargo-mutants, mutmut, Stryker) | staged CI (nightly slot) | The "bite proof" systematized, outside the local loop |

### Third-party add-on security (NON-NEGOTIABLE)

A third-party hook runs **with your permissions, in your session, on every
edit** — it is a dependency with shell access, not a gadget. Before leaning
anything onto tripwire:

1. **Vetting pass**: read the hook script itself (not the README); identify
   what **leaves the machine** (e.g. TDD Guard sends code to a validation
   API); check npm `postinstall` scripts and transitive dependencies;
   maintainer, activity, license.
2. **Pin the exact version**: exact npm version (no `^`/`~`), `rev:` as a SHA
   for pre-commit, pinned commit for marketplace plugins. Commit the lockfile.
3. **Never auto-update**: every version bump goes through a **diff review**
   (the classic malware vector is the compromised update of a healthy
   package — the version you audited is not the one the update will
   install). Same discipline as the ratchet: a version change is an owned
   diff line in review.
4. In an organization: `strictKnownMarketplaces` (see the Teams section) to
   bound installable sources.

## Model economy (haiku without hallucinations)

tripwire's mechanical oracle (check.sh, ratchet, bite proof) makes economical
models **safe where an error gets caught**, and only there:

| Task | Model | Why it's safe (or not) |
|---|---|---|
| Transcribing specified code, mechanical refactors | haiku | the check/compilation catches any drift |
| Extraction/reading (large-scope audits) | haiku | mandatory `file:line` citations = verifiable; targeted greps (compressed by rtk) |
| Review, audit, debug, **writing assertions** | sonnet minimum | a tautology or a hallucinated verdict passes the oracle green — nothing catches it |
| Final review before release | strongest available | it catches what everything else missed |

This doctrine is encoded in the plugin: the "Model economy" section of the
scaffolded CLAUDE.md, `model: sonnet` pinned on gen-agents' judgment agents,
the extractors/judge protocol of `/tripwire:test-review`.

## Tokens & rtk (optional)

tripwire is token-frugal by design: `check.sh` runs tests and builds with
output discarded (only the exit code matters), and hooks only relay a
truncated summary to the assistant when red. No verbose output enters the
context through the pipeline itself.

The only verbose moment is deliberate: when red, the failure details are in
`last-fail.log`. If you use [rtk](https://github.com/rtk-ai/rtk) (a proxy
that compresses command output by 60-90%) globally, any manual re-run gets
compressed automatically — no integration needed. tripwire stays
dependency-free and portable.

## Installation

### For Claude Code

```bash
# From GitHub:
claude plugin marketplace add https://github.com/mornepousse/tripwire
# Or from GitLab:
claude plugin marketplace add https://gitlab.com/harrael/tripwire

claude plugin install tripwire@tripwire
```

### For Mistral Vibe

```bash
vibe plugin marketplace add https://github.com/mornepousse/tripwire
vibe plugin install tripwire@tripwire
```

## Skills

| Skill | Usage |
|---|---|
| `/tripwire:init` | Scaffolds check.sh (skip-if-green, monorepo scoping, lock, budget guard, test ratchet), git hooks, platform hooks (Claude Code: PostToolUse/Stop/SessionStart; Mistral Vibe: onEdit/onWrite/onStop), optional staged CI, config section (CLAUDE.md or VIBE.md). **Re-run on an equipped project**: detects outdated scaffolds via the `# tripwire-template:` stamp and proposes a targeted update without touching your commands |
| `/tripwire:gen-agents` | Generates up to 5 project-specialized agents: test-author / code-reviewer / debugger / maintainer / security-auditor (the last two with persistent cross-session memory; judgment agents pinned to `model: sonnet`) |
| `/tripwire:release` | Release workflow: git tag = version, semver bump proposed from commits, green check mandatory, version-manifest sync, glab/gh release |
| `/tripwire:status` | One-shot diagnosis: scaffold up to date? hooks active? last green/red? duration drift? watched-path blind spots? `--fleet` mode: a table of all equipped repos |
| `/tripwire:bisect` | Finds the commit that broke the check: `git bisect run` with check.sh as the oracle |
| `/tripwire:test-review` | Semantic test audit: hollow assertions, happy-path-only, mock-testing, coupling, parallel-safety, lying names — findings + patches. Large-scope protocol: economical extractors (cited) + one strong judge |

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

## License

[MIT](LICENSE). Additionally, **the files that `/tripwire:init` and
`/tripwire:gen-agents` generate into your projects are yours** — no
attribution or license notice required on scaffolded output.
