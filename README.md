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

## Gros projets

Le contrat « fast < 30 s à chaque édition, check du variant à chaque Stop »
tient aussi sur les gros repos grâce à quatre mécanismes du `check.sh` généré :

- **Skip-si-déjà-vert** : empreinte de l'état du repo (HEAD + diff + fichiers
  non trackés) mémorisée par mode dans `.git/tripwire/` ; si rien n'a bougé
  depuis le dernier vert, le check sort immédiatement. `--force` ou
  `TRIPWIRE_FORCE=1` pour outrepasser (ex. toolchain mise à jour).
- **Scoping monorepo** : table `MODULE_FAST=("glob:commande" …)` dans check.sh ;
  les hooks passent le fichier édité (`--changed`) et la phase rapide ne lance
  que les tests du module touché.
- **Verrou + debounce** : `flock` empêche deux checks concurrents (le second
  sort poliment) ; les hooks post-édition ne relancent pas de check à moins de
  `TRIPWIRE_DEBOUNCE` secondes du précédent (défaut 10).
- **Garde-budget** : si la phase rapide dérive au-delà de `TRIPWIRE_FAST_BUDGET`
  secondes (défaut 30), check.sh l'annonce — le tripwire surveille son propre
  contrat.
- **Échec lisible sans re-run** : la sortie du dernier rouge est capturée dans
  `.git/tripwire/last-fail.log` (l'assistant la lit au lieu de relancer la
  commande) ; chaque passage réel logge sa durée dans `history.tsv` —
  `/tripwire:status` en tire la tendance.

`/tripwire:init` propose aussi une **CI à étages** (fast sur MR/PR, full sur la
branche par défaut + nightly) et ajuste le timeout du hook Stop aux builds longs.

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
| `/tripwire:init` | Scaffolde check.sh (skip-si-vert, scoping monorepo, verrou, garde-budget), hooks git, hooks de plateforme (Claude Code : PostToolUse/Stop/SessionStart ; Mistral Vibe : onEdit/onWrite/onStop), CI à étages optionnelle, section config (CLAUDE.md ou VIBE.md). **Relancé sur un projet équipé** : détecte les scaffolds en retard via le tampon `# tripwire-template:` et propose une mise à jour ciblée sans écraser vos commandes |
| `/tripwire:gen-agents` | Génère jusqu'à 5 agents spécialisés au projet : test-author / code-reviewer / debugger / maintainer / security-auditor (les deux derniers avec mémoire persistante inter-sessions) |
| `/tripwire:release` | Workflow de release : tag git = version, bump semver proposé depuis les commits, check vert obligatoire, sync des manifests de version, glab/gh release |
| `/tripwire:status` | Diagnostic one-shot : scaffold à jour ? hooks actifs ? dernier vert/rouge ? dérive des durées ? angles morts de surveillance ? |
| `/tripwire:bisect` | Localise le commit qui a cassé le check : `git bisect run` avec check.sh comme oracle |

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
