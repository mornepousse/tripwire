---
name: init
description: Use when installing the tripwire anti-regression pipeline into a project — scaffolds scripts/check.sh (single source of truth), versioned git hooks (pre-push), platform-specific hooks (Claude Code: PostToolUse/Stop, Mistral Vibe: onEdit/onWrite/onStop with graceful degradation), and a config section (CLAUDE.md or VIBE.md). Trigger on "installe le tripwire", "ajoute le pipeline anti-régression", "/tripwire:init", "mets en place check.sh".
---

# tripwire:init — scaffolder le pipeline anti-régression

## Détection de plateforme (Étape -1)

**D'abord, détecter si on est sur Claude Code ou Mistral Vibe** :
- Si `CLAUDE_PROJECT_DIR` est défini → PLATEFORME = "claude"
- Sinon si `VIBE_PROJECT_DIR` est défini → PLATEFORME = "vibe"
- Sinon → demander à l'utilisateur via AskUserQuestion

Les variables suivantes sont dérivées de PLATEFORME :

| Plateforme | CONFIG_DIR | CONFIG_FILE | MD_FILE | HOOK_PREFIX | HOOK_TYPES |
|---|---|---|---|---|---|
| claude | .claude | settings.json | CLAUDE.md | cc_ | PostToolUse, Stop |
| vibe | .vibe | config.json | VIBE.md | vibe_ | onEdit/onWrite, onStop |

## L'invariant à installer

> Un seul script (`scripts/check.sh`) définit ce que « vert » veut dire.
> Chaque garde-fou (hook git, hook de plateforme, CI) ne fait que l'appeler
> avec un mode adapté à son budget temps.

Ne JAMAIS dupliquer une commande de test/build dans un hook : les hooks
appellent `check.sh` et rien d'autre.

## Étape 0 — Idempotence & mise à jour

Si `scripts/check.sh` existe déjà dans le repo cible :
- Lire son tampon `# tripwire-template: vX.Y.Z` (ligne 2 ; absent → scaffold
  pré-v0.5.0) et le comparer à la version du plugin (champ `version` de
  `.claude-plugin/plugin.json` à la racine du plugin — deux niveaux au-dessus
  du dossier de cette skill).
- Scaffold en retard → annoncer **précisément ce qui a changé** entre les deux
  versions (voir « Historique des templates ») et demander (AskUserQuestion) :
  mettre à jour ces éléments / compléter ce qui manque / annuler.
- Lors d'une mise à jour : ne JAMAIS écraser les valeurs projet (commandes
  fast/build, variantes, chemins surveillés, env setup) — les relire depuis les
  fichiers existants et les réinjecter dans les nouveaux templates. Mettre à
  jour le tampon.
- Ne jamais écraser un `check.sh` existant sans accord explicite.

### Cas particulier : dialecte divergent (scaffold ancêtre ou modifié)

Un vieux scaffold peut avoir des **noms de modes différents** (ex. KaSe :
`--host-only`/`--board` au lieu de `--fast`/`--variant`), un **fichier de
variante custom** (`.kase-board`), un **préambule projet** (export ccache…) ou
des **hooks maison** hors tripwire dans `settings.json`. Avant de proposer la
mise à jour :
1. `grep -rl` les noms de modes dans la CI, les agents (`.claude/agents/`),
   les docs et le {CONFIG_MD} du repo — mesurer ce qui casserait.
2. Proposer (AskUserQuestion) : **standard + alias** (recommandé — template
   à jour, anciens modes acceptés en alias dans le `case`, fichier de variante
   custom conservé partout où les templates lisent `.tripwire-variant`) /
   backport dans le dialecte (pas de standardisation, upgrades futurs
   manuels) / migration complète (mettre aussi à jour CI, agents et docs).
3. En standard + alias : réinjecter le préambule projet après le `cd`,
   ajouter les alias dans le `case` (`--ancien|--standard)`), documenter les
   alias dans l'en-tête, et adapter `{{VARIANT_STATE_BLOCK}}` /
   `{{SESSION_VARIANT_LINE}}` au fichier de variante custom.
4. Les hooks maison de `settings.json` et les scripts non-tripwire de
   `scripts/hooks/` ne sont JAMAIS touchés.

### Historique des templates

| Version | Changements nécessitant une mise à jour du scaffold |
|---|---|
| v0.2.0 | base : check.sh, pre-push, install-hooks, hooks post_edit/stop |
| v0.3.0 | support Mistral Vibe (rien à mettre à jour pour un scaffold Claude Code) |
| v0.5.0 | + hook SessionStart (`cc_session_start.sh` + entrée `settings.json`) ; tampon `# tripwire-template:` dans check.sh |
| v0.6.0 | check.sh : skip-si-déjà-vert (`--force`), scoping monorepo (`MODULE_FAST` + `--changed`), verrou flock, garde-budget (`TRIPWIRE_FAST_BUDGET`) ; hooks post-edit : debounce (`TRIPWIRE_DEBOUNCE`) + `--changed` ; templates CI à étages (gitlab/github) |
| v0.7.0 | check.sh : `last-fail.log` (détail du rouge sans re-run) + `history.tsv` (durées par mode) ; nouveaux skills status et bisect (rien à re-scaffolder, mais le check.sh mérite la mise à jour) |
| v0.8.0 | skills uniquement (mode flotte de status, procédure dialecte divergent d'init) — **aucun template modifié** : un tampon v0.7.0 est à jour |
| v0.9.0 | qualité des tests — check.sh : ratchet (`TEST_COUNT_CMD` + `.tripwire-testcount` committé, strict au pre-push) + avis TDD (`SRC_GREP`/`TEST_GREP`) ; hooks post-edit : garde anti-affaiblissement (`TEST_PATH_PATTERNS`/`ASSERT_PATTERN`) ; pre-push : `TRIPWIRE_RATCHET_STRICT=1` ; nouveau skill test-review |
| v0.10.0 | doctrine économie de modèles — section « Économie de modèles » dans les sections MD scaffoldées ; gen-agents : `model: sonnet` épinglé sur les agents de jugement ; check.sh **inchangé** (tampon v0.9.0 valide) — re-scaffold léger : section MD + regénérer les agents |

### Cohabitation avec l'outillage tiers (pre-commit, TDD Guard…)

- Repo avec **pre-commit/husky/lefthook** déjà en place : ne PAS s'approprier
  `core.hooksPath` — insérer un hook `pre-push` dans LEUR config qui appelle
  `./scripts/check.sh` (l'invariant survit : tout appelle check.sh). Le
  signaler dans le récap.
- Proposer (optionnel, question) **TDD Guard** pour la discipline TDD
  par-édition — il cohabite avec les hooks tripwire (le merge préserve les
  entrées étrangères). **Règle sécurité avant tout greffon tiers** : passe de
  vetting (lire le script du hook, identifier ce qui quitte la machine —
  TDD Guard envoie le code à une API de validation —, scripts postinstall),
  **version épinglée exacte**, **jamais d'auto-update** : toute montée de
  version = review du diff. Ne jamais installer un greffon tiers sans l'accord
  explicite de l'utilisateur après lui avoir présenté cette surface.

## Étape 1 — Détection de stack

Chercher les marqueurs à la racine et proposer des défauts :

| Marqueur | Stack | fast (défaut) | full (défaut) |
|---|---|---|---|
| `Cargo.toml` | Rust | `cargo test` | `cargo clippy --all-targets -- -D warnings && cargo build --release` |
| `idf_component.yml` / `sdkconfig*` | ESP-IDF | tests host CMake (`cmake -S test -B test/build && cmake --build test/build && ./test/build/test_runner`) | `idf.py build` par variante (`-B build_$v -DSDKCONFIG=build_$v/sdkconfig`) |
| `CMakeLists.txt` (sans IDF) | C/C++ | `ctest --test-dir build` | `cmake --build build` |
| `package.json` | Node | `npm test` | `npm run lint && npm run build` |
| `pyproject.toml` | Python | `pytest -q` | `ruff check . && pytest` |
| `go.mod` | Go | `go test ./...` | `go vet ./... && go build ./...` |

Aucun marqueur → demander les commandes sans proposer de défaut.

## Étape 2 — Questions (AskUserQuestion, une à la fois)

1. **Commande fast** — boucle courte, cible < 30 s. Proposer le défaut détecté.
   Contraintes : la commande doit être relançable telle quelle depuis la racine
   du repo, ne pas contenir de substitution `$(...)` (elle est ré-affichée
   dans les messages d'échec), et **pas de guillemets doubles internes** — le
   template l'affecte à `FAST_RUN_CMD="…"`, des `"` imbriqués la tronqueraient
   silencieusement (bash concatène). Utiliser des quotes simples :
   `nix-shell shell.nix --run 'cargo test'`, pas `--run "cargo test"`.
   Les `cd` internes sont OK (exécution en subshell).
2. **Variantes** — liste de cibles de build (équivalent boards/features/targets),
   ou « aucune » (mono-cible). Si variantes : demander la commande de build
   paramétrée par `$v` et la variante par défaut (pour `.tripwire-variant`).
   Si aucune variante : demander/confirmer quand même la commande de build complet — elle alimente `{{VARIANT_BUILD_CMD}}` (le mode full mono-cible = fast + ce build). Même contrainte que la commande fast : pas de substitution `$(...)`.
3. **Chemins surveillés** — répertoires dont l'édition déclenche le hook
   {HOOK_TYPES} (ex. `src/`, `tests/`). Convertir en patterns `case` :
   `src/` → `*"src/"*`.
4. **Setup d'environnement** — commande à sourcer avant un build
   (ex. `source ~/esp/esp-idf/export.sh`), ou « aucun ».
   Si un setup existe, demander aussi comment tester que l'env est chargé (ex. variable exportée : `[ -n "${IDF_PATH:-}" ]`) — c'est la valeur de `{{ENV_AVAILABLE_TEST}}`. Sans setup : `true`.
5. **Modules (monorepo, optionnel)** — ne poser la question que si le repo a
   l'air d'un monorepo (plusieurs sous-projets avec leurs propres manifests) :
   liste de couples `glob → commande de test du module` pour router la phase
   rapide sur le module touché. Sinon : table vide (`{{MODULE_FAST_ENTRIES}}`
   remplacé par rien).
6. **CI (optionnel)** — proposer de générer la CI à étages (fast sur MR/PR,
   full sur la branche par défaut + nightly). Forge déduite de
   `git remote get-url origin` (gitlab/github ; pas de remote → sauter).
   GitLab : demander l'image docker (`{{CI_IMAGE}}`, défaut `debian:stable-slim`
   avec l'avertissement d'y mettre la toolchain du projet).
   **Ne jamais écraser** un `.gitlab-ci.yml`/workflow existant — proposer le
   contenu à intégrer à la main.
7. **Timeout du hook Stop** — défaut 600 s dans `settings.json`. Si le build
   d'une variante dépasse ~8 min, demander la valeur et remplacer `600` dans le
   fichier généré (sed après copie ; le template reste du JSON valide).
8. **Ratchet de tests (optionnel)** — commande une-ligne qui imprime le nombre
   de tests (`{{TEST_COUNT_CMD}}`), ou « aucun » (ratchet inerte). Défauts :

   | Stack | TEST_COUNT_CMD | ASSERT_PATTERN |
   |---|---|---|
   | C host (harnais type KaSe) | `grep -rho 'TEST_ASSERT' test/ \| wc -l` | `TEST_ASSERT` |
   | Rust | `grep -rho '#\[test\]' src/ \| wc -l` | `assert!\|assert_eq!\|assert_ne!` |
   | Python | `grep -rho 'def test_' tests/ \| wc -l` | `assert` |
   | Node / Go / autre | demander | demander |

   Mêmes contraintes que la commande fast (pas de `$(...)`, pas de `"`), et **pas de `$` non échappé** — `TEST_COUNT_CMD`, `SRC_GREP` et `TEST_GREP` sont assignés en double quotes dans le template, un `$2` d'awk y serait expansé (`set -u` → crash). Pas de quote simple dans `ASSERT_PATTERN` (injecté entre quotes simples dans les hooks).
   Si activé : `.tripwire-testcount` est créé au premier check vert et doit
   être **committé** (comme `.tripwire-variant`) — baisser le ratchet = diff
   visible en review.
9. **Chemins de test** — dérivés de la question 3 ou demandés : patterns
   `case` (`{{TEST_PATH_PATTERNS}}`, ex. `*"/test/"*`), forme grep
   (`{{TEST_GREP}}`, ex. `^test/`) et forme grep des sources
   (`{{SRC_GREP}}`, ex. `^src/|^main/`). Vérifier que les chemins de test
   sont AUSSI dans `{{WATCHED_PATH_PATTERNS}}` (sinon la garde
   anti-affaiblissement ne voit jamais les fichiers de test).

## Étape 3 — Génération

Templates dans `templates/` de cette skill. Remplacer les placeholders puis
écrire dans le repo cible :

| Template | Destination cible | chmod | Plateforme |
|---|---|---|---|
| `check.sh.tmpl` | `scripts/check.sh` | `+x` | les deux |
| `pre-push.tmpl` | `scripts/hooks/pre-push` | `+x` | les deux |
| `install-hooks.sh.tmpl` | `scripts/install-hooks.sh` | `+x` | les deux |
| `{HOOK_PREFIX}post_edit.sh.tmpl` | `scripts/hooks/{HOOK_PREFIX}post_edit.sh` | `+x` | {PLATEFORME} |
| `{HOOK_PREFIX}stop.sh.tmpl` | `scripts/hooks/{HOOK_PREFIX}stop.sh` | `+x` | {PLATEFORME} |
| `cc_session_start.sh.tmpl` | `scripts/hooks/cc_session_start.sh` | `+x` | claude uniquement (Vibe n'a pas d'événement session-start) |
| `gitlab-ci.yml.tmpl` | `.gitlab-ci.yml` (si CI acceptée, forge gitlab, fichier absent) | — | les deux |
| `github-actions.yml.tmpl` | `.github/workflows/tripwire.yml` (si CI acceptée, forge github, fichier absent) | — | les deux |
| `{PLATEFORME}-config.json.tmpl` | `{CONFIG_DIR}/{CONFIG_FILE}` (**merge**, voir plus bas) | — | {PLATEFORME} |
| `{PLATEFORME}-md-section.md.tmpl` | section ajoutée au `{MD_FILE}` | — | {PLATEFORME} |

### Placeholders

| Placeholder | Valeur |
|---|---|
| `{{PROJECT_NAME}}` | nom du repo cible |
| `{{TRIPWIRE_VERSION}}` | version du plugin au moment du scaffold (`vX.Y.Z`, depuis le `version` de `.claude-plugin/plugin.json` du plugin) — sert à l'Étape 0 pour détecter les scaffolds en retard |
| `{{FAST_CMD}}` | commande fast (une ligne) |
| `{{FAST_DESC}}` | description humaine de la phase fast |
| `{{VARIANTS_SPACE_SEPARATED}}` | `v1 v2 …` ; **vide** si mono-cible |
| `{{VARIANT_BUILD_CMD}}` | commande de build, peut utiliser `$v` |
| `{{VARIANT_LIST_DESC}}` | ex. « les 3 variantes » / « le build complet » |
| `{{DEFAULT_VARIANT}}` | variante par défaut (multi uniquement) (consommé dans la construction de `{{VARIANT_STATE_BLOCK}}`, n'apparaît littéralement dans aucun template) |
| `{{ENV_SETUP_BLOCK}}` | bloc shell de setup d'env ; **supprimer la ligne** si aucun |
| `{{ENV_AVAILABLE_TEST}}` | test shell de dispo de l'env ; `true` si aucun |
| `{{VARIANT_STATE_BLOCK}}` | deux lignes : `VARIANT="$(cat .tripwire-variant 2>/dev/null \|\| true)"` puis `VARIANT="${VARIANT:-<défaut>}"` (robuste au fichier vide) ; **supprimer la ligne** si mono |
| `{{STOP_CHECK_ARGS}}` | `--variant "$VARIANT"` (multi) ; vide (mono) |
| `{{STOP_CHECK_DESC}}` | `variant $VARIANT` (multi) ; `complet` (mono) |
| `{{WATCHED_PATH_PATTERNS}}` | patterns `case` séparés par `\|` |
| `{{TDD_SCOPE}}` | types de logique pure du projet |
| `{{SESSION_VARIANT_LINE}}` | multi : `V="$(cat .tripwire-variant 2>/dev/null \|\| true)"; [ -n "$V" ] && CTX="$CTX tripwire: variante courante: $V."` ; **supprimer la ligne** si mono |
| `{{MODULE_FAST_ENTRIES}}` | monorepo : entrées `"<glob>:<commande>"` séparées par des espaces ; **vide** sinon |
| `{{CI_IMAGE}}` | image docker CI GitLab (défaut `debian:stable-slim`, à adapter à la toolchain) |
| `{{DEFAULT_BRANCH}}` | branche par défaut du repo cible (`git symbolic-ref refs/remotes/origin/HEAD`, repli `main`) |
| `{{TEST_COUNT_CMD}}` | commande de comptage des tests (question 8) ; **vide** si aucun |
| `{{ASSERT_PATTERN}}` | regex grep -E des assertions de la stack (question 8) ; `assert` par défaut si ratchet actif sans mieux |
| `{{TEST_PATH_PATTERNS}}` | patterns `case` des fichiers de test (question 9) ; `*"/__jamais__/"*` si aucun |
| `{{TEST_GREP}}` | forme grep -E des chemins de test ; **vide** si aucun |
| `{{SRC_GREP}}` | forme grep -E des chemins source surveillés ; **vide** si aucun |

### Adaptations mono-cible
- `ALL_VARIANTS=()` vide ; le mode `--variant` reste dans check.sh (inerte, ne pas le retirer).
- Dans la section {MD_FILE} : supprimer la ligne `--variant`, supprimer la mention `.tripwire-variant`, et reformuler la puce {HOOK_TYPES} en "check complet".
- Pas de fichier `.tripwire-variant` ; supprimer la ligne `{{SESSION_VARIANT_LINE}}` de `cc_session_start.sh`.

### Multi-variantes
- Créer `.tripwire-variant` contenant la variante par défaut.
- Ajouter `.tripwire-variant` au `.gitignore` ? NON — le committer (comme
  `.kase-board` chez KaSe) pour qu'un clone frais ait un défaut sain.

### Merge de `{CONFIG_DIR}/{CONFIG_FILE}`
- Fichier absent → écrire le template tel quel.
- Fichier présent → lire le JSON existant, ajouter les entrées {HOOK_TYPES}
  du template aux tableaux existants (créer les clés si absentes).
  Ne JAMAIS supprimer ou modifier les hooks existants. Vérifier le résultat
  avec `jq .` avant d'écrire.
- Idempotence du merge : si une entrée `command` pointant sur `scripts/hooks/{HOOK_PREFIX}*` existe déjà, ne pas la dupliquer.

### Section {MD_FILE}
- `{MD_FILE}` absent → le créer avec un titre `# <projet> — {PLATEFORME} instructions` puis la section.
- Présent → ajouter la section à la fin (ou remplacer une section
  « Workflow anti-régression » existante si mise à jour).

## Étape 4 — Validation (OBLIGATOIRE avant de conclure)

```bash
command -v python3   # requis par les hooks (parsing JSON) — avertir si absent
bash -n scripts/check.sh scripts/hooks/*.sh scripts/hooks/pre-push scripts/install-hooks.sh
# Aucun placeholder résiduel ne doit rester :
grep -rn '{{' scripts/ {CONFIG_DIR}/{CONFIG_FILE} {MD_FILE} && echo "PLACEHOLDERS RESTANTS — corriger avant de conclure" || true
./scripts/install-hooks.sh
test -x scripts/hooks/pre-push
git config --get core.hooksPath    # doit afficher scripts/hooks
./scripts/check.sh --fast          # doit être VERT
# Hook {HOOK_TYPES} : un chemin surveillé (doit durer ~ la commande fast) puis un non surveillé (retour immédiat)
echo '{"file_path":"'$PWD'/<chemin surveillé>/x"}' | scripts/hooks/{HOOK_PREFIX}post_edit.sh; echo "rc=$?"   # rc=0
echo '{"file_path":"'$PWD'/UNWATCHED.md"}' | scripts/hooks/{HOOK_PREFIX}post_edit.sh; echo "rc=$?"          # rc=0, immédiat
# SessionStart (claude uniquement) : rc=0 toujours ; installe core.hooksPath s'il manque
echo '{}' | scripts/hooks/cc_session_start.sh; echo "rc=$?"   # rc=0
```

Si `check.sh --fast` est rouge : diagnostiquer avec l'utilisateur (commande
fast incorrecte ?) avant de conclure. Ne jamais livrer un tripwire rouge.

## Étape 5 — Récap final

Lister les fichiers créés/modifiés, rappeler :
- `./scripts/install-hooks.sh` à lancer sur chaque nouveau clone ;
- `echo <variante> > .tripwire-variant` pour changer la variante courante ;
- les hooks {PLATEFORME} s'activent à la prochaine session.
