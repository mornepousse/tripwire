# tripwire

Plugin **multi-plateforme** (Claude Code et Mistral Vibe) qui scaffolde un pipeline anti-régression dans n'importe quel repo.
Extrait du workflow du projet KaSe_firmware.

## L'invariant

> Un seul script (`scripts/check.sh`) définit ce que « vert » veut dire.
> Chaque garde-fou (hook git, hook de plateforme, CI) ne fait que l'appeler
> avec un mode adapté à son budget temps.

- `check.sh --fast` — boucle courte (< 30 s), lancée après chaque édition surveillée
- `check.sh --variant <name>` — fast + build d'une variante (au hook Stop/onStop de la plateforme)
- `check.sh` — full : fast + toutes les variantes (pre-push, CI)
- Dégradation gracieuse : env de build absent → retombe sur `--fast` au lieu de bloquer

## Tokens & rtk (optionnel)

tripwire est déjà frugal en tokens par design : `check.sh` exécute tests et
builds en `>/dev/null` (seul le code de retour compte), et les hooks ne
renvoient à l'assistant qu'un résumé tronqué en cas de rouge. Aucune sortie
verbeuse n'entre dans le contexte via le pipeline lui-même.

Le seul moment verbeux est volontaire : quand `check.sh` est rouge, il invite
à relancer la commande pour le détail (`relance pour le détail : <cmd>`). Ce
re-run est une commande shell normale — si vous utilisez [rtk](https://github.com/rtk-ai/rtk)
(proxy qui compresse les sorties de 60-90 %) en interception globale, ce détail
est compressé automatiquement, sans que tripwire ait à s'en occuper.

Autrement dit : **aucune intégration n'est nécessaire.** tripwire reste
sans dépendance et portable ; rtk, s'il est présent, agit sur la seule étape
qui en bénéficie.

## Installation

### Pour Claude Code

```bash
# Depuis GitLab :
claude plugin marketplace add https://gitlab.com/harrael/tripwire
# Ou depuis un clone local :
claude plugin marketplace add ~/Documents/GitHub/tripwire

claude plugin install tripwire@tripwire
```

### Pour Mistral Vibe

```bash
# Depuis GitLab :
vibe plugin marketplace add https://gitlab.com/harrael/tripwire
# Ou depuis un clone local :
vibe plugin marketplace add ~/Documents/GitHub/tripwire

vibe plugin install tripwire@tripwire
```

## Skills

| Skill | Usage |
|---|---|
| `/tripwire:init` | Scaffolde check.sh, hooks git, hooks de plateforme (Claude Code ou Mistral Vibe), section config (CLAUDE.md ou VIBE.md) |
| `/tripwire:gen-agents` | Génère des agents test-author / code-reviewer / debugger spécialisés au projet |
| `/tripwire:release` | Workflow de release : tag git = version, check vert obligatoire, glab/gh release |

## Détection automatique de plateforme

Le plugin détecte automatiquement si vous utilisez **Claude Code** ou **Mistral Vibe** en vérifiant les variables d'environnement (`CLAUDE_PROJECT_DIR` ou `VIBE_PROJECT_DIR`) et adapte son comportement :
- Génération des bons hooks (PostToolUse/Stop pour Claude, onEdit/onWrite/onStop pour Vibe)
- Création du bon fichier de configuration (.claude/settings.json ou .vibe/config.json)
- Utilisation du bon fichier de documentation (CLAUDE.md ou VIBE.md)
