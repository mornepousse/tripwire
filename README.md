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
| `/tripwire:init` | Scaffolde check.sh, hooks git, hooks de plateforme (Claude Code : PostToolUse/Stop/SessionStart ; Mistral Vibe : onEdit/onWrite/onStop), section config (CLAUDE.md ou VIBE.md). **Relancé sur un projet équipé** : détecte les scaffolds en retard via le tampon `# tripwire-template:` et propose une mise à jour ciblée sans écraser vos commandes |
| `/tripwire:gen-agents` | Génère jusqu'à 5 agents spécialisés au projet : test-author / code-reviewer / debugger / maintainer / security-auditor (les deux derniers avec mémoire persistante inter-sessions) |
| `/tripwire:release` | Workflow de release : tag git = version, bump semver proposé depuis les commits, check vert obligatoire, sync des manifests de version, glab/gh release |

## Mettre à jour un projet équipé

Chaque `check.sh` généré porte un tampon `# tripwire-template: vX.Y.Z`. Après un
`claude plugin update tripwire@tripwire`, relancez `/tripwire:init` dans le
projet : le skill compare le tampon à la version du plugin, annonce ce qui a
changé et met à jour les fichiers scaffoldés en préservant vos commandes
fast/build, variantes et chemins surveillés.

Le hook `SessionStart` installe par ailleurs les hooks git automatiquement à
chaque nouveau clone — plus besoin de penser à `./scripts/install-hooks.sh`.

## Équipes (Claude for Teams / Enterprise)

Pour déployer le pipeline à toute une organisation, deux mécanismes Claude Code
se combinent avec tripwire (Admin Settings → Claude Code → Managed settings) :

- **Marketplace contrôlé** : `strictKnownMarketplaces` dans les managed settings
  limite les marketplaces autorisés — ajoutez-y l'URL de ce repo pour distribuer
  tripwire officiellement (`claude plugin marketplace add <url>` chez chaque dev).
- **Hooks managés** : les managed settings acceptent une clé `hooks` identique à
  celle que `/tripwire:init` écrit dans `.claude/settings.json`. Un admin peut
  donc pousser les hooks `PostToolUse`/`Stop`/`SessionStart` org-wide. Pour que
  les repos non-tripwire restent silencieux, garder les commandes derrière un
  test d'existence :
  ```json
  { "type": "command",
    "command": "H=\"$CLAUDE_PROJECT_DIR/scripts/hooks/cc_stop.sh\"; [ -x \"$H\" ] && exec \"$H\"; exit 0" }
  ```

L'invariant reste inchangé : les hooks managés n'appellent que `scripts/check.sh`
du repo courant ; chaque projet garde la définition de son « vert ».

## Détection automatique de plateforme

Le plugin détecte automatiquement si vous utilisez **Claude Code** ou **Mistral Vibe** en vérifiant les variables d'environnement (`CLAUDE_PROJECT_DIR` ou `VIBE_PROJECT_DIR`) et adapte son comportement :
- Génération des bons hooks (PostToolUse/Stop pour Claude, onEdit/onWrite/onStop pour Vibe)
- Création du bon fichier de configuration (.claude/settings.json ou .vibe/config.json)
- Utilisation du bon fichier de documentation (CLAUDE.md ou VIBE.md)
