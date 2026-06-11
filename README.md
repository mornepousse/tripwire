# tripwire

Plugin Claude Code qui scaffolde un pipeline anti-régression dans n'importe quel repo.
Extrait du workflow du projet KaSe_firmware.

## L'invariant

> Un seul script (`scripts/check.sh`) définit ce que « vert » veut dire.
> Chaque garde-fou (hook git, hook Claude Code, CI) ne fait que l'appeler
> avec un mode adapté à son budget temps.

- `check.sh --fast` — boucle courte (< 30 s), lancée après chaque édition surveillée
- `check.sh --variant <name>` — fast + build d'une variante (au Stop de Claude Code)
- `check.sh` — full : fast + toutes les variantes (pre-push, CI)
- Dégradation gracieuse : env de build absent → retombe sur `--fast` au lieu de bloquer

## Installation

```bash
claude plugin marketplace add ~/Documents/GitHub/tripwire   # ou l'URL GitLab
claude plugin install tripwire@tripwire
```

## Skills

| Skill | Usage |
|---|---|
| `/tripwire:init` | Scaffolde check.sh, hooks git, hooks Claude Code, section CLAUDE.md |
| `/tripwire:gen-agents` | Génère des agents test-author / code-reviewer / debugger spécialisés au projet |
| `/tripwire:release` | Workflow de release : tag git = version, check vert obligatoire, glab/gh release |
