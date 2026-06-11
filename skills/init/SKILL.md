---
name: init
description: Use when installing the tripwire anti-regression pipeline into a project — scaffolds scripts/check.sh (single source of truth), versioned git hooks (pre-push), Claude Code hooks (PostToolUse/Stop with graceful degradation), and a CLAUDE.md section. Trigger on "installe le tripwire", "ajoute le pipeline anti-régression", "/tripwire:init", "mets en place check.sh".
---

# tripwire:init — scaffolder le pipeline anti-régression

## L'invariant à installer

> Un seul script (`scripts/check.sh`) définit ce que « vert » veut dire.
> Chaque garde-fou (hook git, hook Claude Code, CI) ne fait que l'appeler
> avec un mode adapté à son budget temps.

Ne JAMAIS dupliquer une commande de test/build dans un hook : les hooks
appellent `check.sh` et rien d'autre.

## Étape 0 — Idempotence

Si `scripts/check.sh` existe déjà dans le repo cible :
- Le lire, annoncer ce qui est déjà en place, et demander à l'utilisateur
  (AskUserQuestion) : mettre à jour / compléter ce qui manque / annuler.
- Ne jamais écraser un `check.sh` existant sans accord explicite.

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
   Contrainte : la commande doit être relançable telle quelle depuis la racine
   du repo et ne pas contenir de substitution `$(...)` (elle est ré-affichée
   dans les messages d'échec). Les `cd` internes sont OK (exécution en subshell).
2. **Variantes** — liste de cibles de build (équivalent boards/features/targets),
   ou « aucune » (mono-cible). Si variantes : demander la commande de build
   paramétrée par `$v` et la variante par défaut (pour `.tripwire-variant`).
   Si aucune variante : demander/confirmer quand même la commande de build complet — elle alimente `{{VARIANT_BUILD_CMD}}` (le mode full mono-cible = fast + ce build). Même contrainte que la commande fast : pas de substitution `$(...)`.
3. **Chemins surveillés** — répertoires dont l'édition déclenche le hook
   PostToolUse (ex. `src/`, `tests/`). Convertir en patterns `case` :
   `src/` → `*"/src/"*`.
4. **Setup d'environnement** — commande à sourcer avant un build
   (ex. `source ~/esp/esp-idf/export.sh`), ou « aucun ».
   Si un setup existe, demander aussi comment tester que l'env est chargé (ex. variable exportée : `[ -n "${IDF_PATH:-}" ]`) — c'est la valeur de `{{ENV_AVAILABLE_TEST}}`. Sans setup : `true`.

## Étape 3 — Génération

Templates dans `templates/` de cette skill. Remplacer les placeholders puis
écrire dans le repo cible :

| Template | Destination cible | chmod |
|---|---|---|
| `check.sh.tmpl` | `scripts/check.sh` | `+x` |
| `pre-push.tmpl` | `scripts/hooks/pre-push` | `+x` |
| `install-hooks.sh.tmpl` | `scripts/install-hooks.sh` | `+x` |
| `cc_post_edit.sh.tmpl` | `scripts/hooks/cc_post_edit.sh` | `+x` |
| `cc_stop.sh.tmpl` | `scripts/hooks/cc_stop.sh` | `+x` |
| `settings.json.tmpl` | `.claude/settings.json` (**merge**, voir plus bas) | — |
| `claude-md-section.md.tmpl` | section ajoutée au `CLAUDE.md` | — |

### Placeholders

| Placeholder | Valeur |
|---|---|
| `{{PROJECT_NAME}}` | nom du repo cible |
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

### Adaptations mono-cible
- `ALL_VARIANTS=()` vide ; le mode `--variant` reste dans check.sh (inerte, ne pas le retirer).
- Dans la section CLAUDE.md : supprimer la ligne `--variant`, supprimer la mention `.tripwire-variant`, et reformuler la puce Stop en "check complet".
- Pas de fichier `.tripwire-variant`.

### Multi-variantes
- Créer `.tripwire-variant` contenant la variante par défaut.
- Ajouter `.tripwire-variant` au `.gitignore` ? NON — le committer (comme
  `.kase-board` chez KaSe) pour qu'un clone frais ait un défaut sain.

### Merge de `.claude/settings.json`
- Fichier absent → écrire le template tel quel.
- Fichier présent → lire le JSON existant, ajouter les entrées `PostToolUse`
  et `Stop` du template aux tableaux existants (créer les clés si absentes).
  Ne JAMAIS supprimer ou modifier les hooks existants. Vérifier le résultat
  avec `jq .` avant d'écrire.
- Idempotence du merge : si une entrée `command` pointant sur `scripts/hooks/cc_post_edit.sh` ou `cc_stop.sh` existe déjà, ne pas la dupliquer.

### Section CLAUDE.md
- `CLAUDE.md` absent → le créer avec un titre `# <projet> — Claude Code
  instructions` puis la section.
- Présent → ajouter la section à la fin (ou remplacer une section
  « Workflow anti-régression » existante si mise à jour).

## Étape 4 — Validation (OBLIGATOIRE avant de conclure)

```bash
command -v python3   # requis par les hooks Claude Code (parsing JSON) — avertir si absent
bash -n scripts/check.sh scripts/hooks/*.sh scripts/hooks/pre-push scripts/install-hooks.sh
# Aucun placeholder résiduel ne doit rester :
grep -rn '{{' scripts/ .claude/settings.json CLAUDE.md && echo "PLACEHOLDERS RESTANTS — corriger avant de conclure" || true
./scripts/install-hooks.sh
test -x scripts/hooks/pre-push
git config --get core.hooksPath    # doit afficher scripts/hooks
./scripts/check.sh --fast          # doit être VERT
# Hook PostToolUse : un chemin surveillé (doit durer ~ la commande fast) puis un non surveillé (retour immédiat)
echo '{"tool_input":{"file_path":"'$PWD'/<chemin surveillé>/x"}}' | scripts/hooks/cc_post_edit.sh; echo "rc=$?"   # rc=0
echo '{"tool_input":{"file_path":"'$PWD'/UNWATCHED.md"}}' | scripts/hooks/cc_post_edit.sh; echo "rc=$?"          # rc=0, immédiat
```

Si `check.sh --fast` est rouge : diagnostiquer avec l'utilisateur (commande
fast incorrecte ?) avant de conclure. Ne jamais livrer un tripwire rouge.

## Étape 5 — Récap final

Lister les fichiers créés/modifiés, rappeler :
- `./scripts/install-hooks.sh` à lancer sur chaque nouveau clone ;
- `echo <variante> > .tripwire-variant` pour changer la variante courante ;
- les hooks Claude Code s'activent à la prochaine session.
