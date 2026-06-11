# Plugin `tripwire` — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Plugin Claude Code `tripwire` qui scaffolde le pipeline anti-régression extrait de KaSe_firmware (check.sh + hooks git + hooks Claude Code + section CLAUDE.md + agents + release) dans n'importe quel repo.

**Architecture:** Plugin pur markdown/templates — 3 skills (`init`, `gen-agents`, `release`) dont les SKILL.md guident Claude pour instancier des templates bash/json/md avec des placeholders `{{NOM}}`. Le repo est sa propre marketplace (`.claude-plugin/marketplace.json`, `source: "./"`). Aucun code exécuté par le plugin lui-même : tout ce qui s'exécute est généré dans le repo cible.

**Tech Stack:** Bash (templates), JSON (manifests), Markdown (skills/agents). Vérification : `bash -n`, `jq`, agent `plugin-dev:plugin-validator`, test E2E d'instanciation sur repo jetable.

**Spec:** `docs/superpowers/specs/2026-06-11-tripwire-plugin-design.md`

**Répertoire de travail :** `~/Documents/GitHub/tripwire` (toutes les commandes ci-dessous s'exécutent depuis cette racine).

**Note testing :** Le livrable est constitué de templates et de prose — pas de logique pure compilable. Le « TDD » du plan = chaque fichier est vérifié immédiatement après création (`bash -n` pour les templates shell, `jq .` pour le JSON), et la Task 9 est un test E2E qui instancie les templates sur un projet jouet et vérifie le comportement vert/rouge AVANT la validation finale du plugin.

---

### Task 1: Scaffold du repo — manifests + README

**Files:**
- Create: `.claude-plugin/plugin.json`
- Create: `.claude-plugin/marketplace.json`
- Create: `README.md`

- [ ] **Step 1: Créer `.claude-plugin/plugin.json`**

```json
{
  "name": "tripwire",
  "version": "0.1.0",
  "description": "Scaffolde un pipeline anti-régression : check.sh source unique de vérité + hooks git + hooks Claude Code + section CLAUDE.md. Extrait du workflow KaSe_firmware.",
  "author": {
    "name": "Mae PUGIN"
  },
  "repository": "https://gitlab.com/harrael/tripwire",
  "license": "MIT",
  "keywords": ["ci", "hooks", "tdd", "anti-regression", "scaffolding"]
}
```

- [ ] **Step 2: Créer `.claude-plugin/marketplace.json`** (self-marketplace)

```json
{
  "name": "tripwire",
  "owner": {
    "name": "Mae PUGIN"
  },
  "plugins": [
    {
      "name": "tripwire",
      "description": "Pipeline anti-régression réutilisable : check.sh + hooks git + hooks Claude Code + section CLAUDE.md + agents + release.",
      "source": "./"
    }
  ]
}
```

- [ ] **Step 3: Vérifier le JSON**

Run: `jq . .claude-plugin/plugin.json && jq . .claude-plugin/marketplace.json`
Expected: les deux JSON s'affichent sans erreur.

- [ ] **Step 4: Créer `README.md`**

```markdown
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
```

- [ ] **Step 5: Commit**

```bash
git add .claude-plugin README.md
git commit -m "feat: manifests plugin + marketplace + README"
```

---

### Task 2: Template `check.sh.tmpl`

**Files:**
- Create: `skills/init/templates/check.sh.tmpl`

Conventions placeholders (documentées dans le SKILL.md en Task 6) :
- `{{PROJECT_NAME}}` — nom du projet cible
- `{{FAST_CMD}}` — commande de la phase rapide (une ligne shell)
- `{{VARIANTS_SPACE_SEPARATED}}` — liste de variantes, ex. `v1 v2 dongle` ; vide si mono-cible
- `{{VARIANT_BUILD_CMD}}` — commande de build ; peut utiliser `$v` (nom de variante) ; en mono-cible `$v` est vide

- [ ] **Step 1: Créer le template**

```bash
#!/usr/bin/env bash
# Tripwire anti-régression {{PROJECT_NAME}} — source unique de vérité du "quoi vérifier".
# Généré par /tripwire:init. Adapter ICI ; les hooks ne font qu'appeler ce script.
# Modes:
#   check.sh                  -> full: phase rapide + toutes les variantes
#   check.sh --fast           -> phase rapide uniquement (~secondes)
#   check.sh --variant <name> -> phase rapide + une seule variante
# Sortie non-zéro si au moins un rouge (toutes les variantes sont tentées en mode full).
# Conçu pour hooks git/Claude Code + CI.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

# Variantes de build. Laisser vide pour un projet mono-cible.
ALL_VARIANTS=({{VARIANTS_SPACE_SEPARATED}})

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YEL=$'\033[1;33m'; NC=$'\033[0m'
fail() { echo "${RED}✗ $*${NC}" >&2; }
ok()   { echo "${GREEN}✓ $*${NC}"; }
info() { echo "${YEL}» $*${NC}"; }

MODE="full"
SINGLE_VARIANT=""
case "${1:-}" in
  --fast)    MODE="fast" ;;
  --variant) MODE="single"; SINGLE_VARIANT="${2:-}";
             [ -z "$SINGLE_VARIANT" ] && { fail "--variant requires a name"; exit 2; } ;;
  "" )       MODE="full" ;;
  *)         fail "unknown arg: $1"; exit 2 ;;
esac

# ---- Phase rapide (boucle courte, cible < 30 s) ----
run_fast() {
  info "Phase rapide…"
  if {{FAST_CMD}} >/dev/null 2>&1; then
    ok "Phase rapide OK"
    return 0
  else
    fail "Phase rapide: échec (relance pour le détail: {{FAST_CMD}})"
    return 1
  fi
}

# ---- Phase complète ----
# Multi-variantes: appelée une fois par variante ($v = nom).
# Mono-cible: appelée une fois avec $v vide.
build_variant() {
  local v="$1"
  info "Build ${v:-complet}…"
  if {{VARIANT_BUILD_CMD}} >/dev/null 2>&1; then
    ok "Build ${v:-complet} OK"
    return 0
  else
    fail "Build ${v:-complet}: échec (relance pour le détail: {{VARIANT_BUILD_CMD}})"
    return 1
  fi
}

rc=0
run_fast || rc=1

if [ "$MODE" = "single" ]; then
  build_variant "$SINGLE_VARIANT" || rc=1
elif [ "$MODE" = "full" ]; then
  if [ "${#ALL_VARIANTS[@]}" -eq 0 ]; then
    build_variant "" || rc=1
  else
    for v in "${ALL_VARIANTS[@]}"; do
      build_variant "$v" || rc=1
    done
  fi
fi

echo "========================================"
if [ "$rc" -eq 0 ]; then ok "check.sh: tout vert"; else fail "check.sh: ROUGE"; fi
echo "========================================"
exit "$rc"
```

- [ ] **Step 2: Vérifier la syntaxe** (les placeholders `{{X}}` sont des mots bash valides, `bash -n` passe sur le template brut)

Run: `bash -n skills/init/templates/check.sh.tmpl`
Expected: aucune sortie, exit 0.

- [ ] **Step 3: Commit**

```bash
git add skills/init/templates/check.sh.tmpl
git commit -m "feat(init): template check.sh générique (fast/variant/full)"
```

---

### Task 3: Templates hooks git — `pre-push.tmpl` + `install-hooks.sh.tmpl`

**Files:**
- Create: `skills/init/templates/pre-push.tmpl`
- Create: `skills/init/templates/install-hooks.sh.tmpl`

Placeholder additionnel : `{{ENV_SETUP_BLOCK}}` — bloc shell qui source l'environnement de build si nécessaire (ex. KaSe : `if [ -z "${IDF_PATH:-}" ] && [ -f "$HOME/esp/esp-idf/export.sh" ]; then source "$HOME/esp/esp-idf/export.sh" >/dev/null 2>&1 || true; fi`). Si le projet n'a pas de setup d'env, le SKILL.md instruit de **supprimer la ligne**.

- [ ] **Step 1: Créer `pre-push.tmpl`**

```bash
#!/usr/bin/env bash
# Hook git pre-push {{PROJECT_NAME}} — bloque le push si le tripwire est rouge.
# Activation: ./scripts/install-hooks.sh  (git config core.hooksPath scripts/hooks)
# Échappatoire WIP: git push --no-verify
set -uo pipefail
REPO="$(git rev-parse --show-toplevel)"
echo "[pre-push] check.sh complet…"
{{ENV_SETUP_BLOCK}}
"$REPO/scripts/check.sh"
rc=$?
if [ "$rc" -ne 0 ]; then
  echo "[pre-push] ROUGE — push bloqué. (git push --no-verify pour forcer un WIP)" >&2
fi
exit "$rc"
```

- [ ] **Step 2: Créer `install-hooks.sh.tmpl`**

```bash
#!/usr/bin/env bash
# Active les hooks git versionnés du repo (pre-push -> scripts/check.sh).
# À lancer une fois par clone : ./scripts/install-hooks.sh
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"
git config core.hooksPath scripts/hooks
echo "✓ core.hooksPath = $(git config --get core.hooksPath)"
echo "  pre-push lancera scripts/check.sh (full). WIP: git push --no-verify"
```

- [ ] **Step 3: Vérifier la syntaxe**

Run: `bash -n skills/init/templates/pre-push.tmpl && bash -n skills/init/templates/install-hooks.sh.tmpl`
Expected: aucune sortie, exit 0.

- [ ] **Step 4: Commit**

```bash
git add skills/init/templates/pre-push.tmpl skills/init/templates/install-hooks.sh.tmpl
git commit -m "feat(init): templates hooks git versionnés (pre-push + install)"
```

---

### Task 4: Templates hooks Claude Code — `cc_post_edit.sh.tmpl`, `cc_stop.sh.tmpl`, `settings.json.tmpl`

**Files:**
- Create: `skills/init/templates/cc_post_edit.sh.tmpl`
- Create: `skills/init/templates/cc_stop.sh.tmpl`
- Create: `skills/init/templates/settings.json.tmpl`

Placeholders additionnels :
- `{{WATCHED_PATH_PATTERNS}}` — patterns `case` séparés par `|`, ex. `*"/src/"*.rs|*"/tests/"*.rs`
- `{{ENV_AVAILABLE_TEST}}` — test shell « l'env de build est dispo », ex. `[ -n "${IDF_PATH:-}" ]` ; littéral `true` si pas de setup d'env
- `{{VARIANT_STATE_BLOCK}}` — multi-variantes : `VARIANT="$(cat .tripwire-variant 2>/dev/null || echo {{DEFAULT_VARIANT}})"` ; mono-cible : ligne supprimée
- `{{STOP_CHECK_ARGS}}` — multi : `--variant "$VARIANT"` ; mono : vide (check full, qui = fast + build unique)
- `{{STOP_CHECK_DESC}}` — multi : `variant $VARIANT` ; mono : `complet`

- [ ] **Step 1: Créer `cc_post_edit.sh.tmpl`**

```bash
#!/usr/bin/env bash
# Hook Claude Code PostToolUse — tests rapides après édition d'un fichier surveillé.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO"
FP="$(python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("file_path",""))' 2>/dev/null)"
case "$FP" in
  {{WATCHED_PATH_PATTERNS}}) ;;
  *) exit 0 ;;  # fichier non surveillé → rien
esac
OUT="$("$REPO/scripts/check.sh" --fast 2>&1)"
rc=$?
if [ "$rc" -ne 0 ]; then
  echo "Régression phase rapide après édition de $FP :" >&2
  echo "$OUT" | tail -8 >&2
  exit 2   # remonte à Claude
fi
exit 0
```

- [ ] **Step 2: Créer `cc_stop.sh.tmpl`**

```bash
#!/usr/bin/env bash
# Hook Claude Code Stop — check du variant courant avant de conclure.
# Dégradation: env de build absent -> --fast au lieu de bloquer chaque Stop.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO"
{{VARIANT_STATE_BLOCK}}
{{ENV_SETUP_BLOCK}}
if {{ENV_AVAILABLE_TEST}}; then
  OUT="$("$REPO/scripts/check.sh" {{STOP_CHECK_ARGS}} 2>&1)"
  rc=$?
  MSG="check.sh ({{STOP_CHECK_DESC}}) est ROUGE avant de conclure :"
else
  OUT="$("$REPO/scripts/check.sh" --fast 2>&1)"
  rc=$?
  MSG="check.sh --fast est ROUGE avant de conclure (env de build absent, phase complète sautée) :"
fi
if [ "$rc" -ne 0 ]; then
  echo "$MSG" >&2
  echo "$OUT" | tail -10 >&2
  exit 2
fi
exit 0
```

- [ ] **Step 3: Créer `settings.json.tmpl`** (hooks à merger dans le `.claude/settings.json` du projet cible)

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write|MultiEdit",
        "hooks": [
          { "type": "command", "command": "$CLAUDE_PROJECT_DIR/scripts/hooks/cc_post_edit.sh" }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          { "type": "command", "command": "$CLAUDE_PROJECT_DIR/scripts/hooks/cc_stop.sh" }
        ]
      }
    ]
  }
}
```

- [ ] **Step 4: Vérifier syntaxe + JSON**

Run: `bash -n skills/init/templates/cc_post_edit.sh.tmpl && bash -n skills/init/templates/cc_stop.sh.tmpl && jq . skills/init/templates/settings.json.tmpl`
Expected: le JSON s'affiche, aucune erreur bash.

- [ ] **Step 5: Commit**

```bash
git add skills/init/templates/cc_post_edit.sh.tmpl skills/init/templates/cc_stop.sh.tmpl skills/init/templates/settings.json.tmpl
git commit -m "feat(init): templates hooks Claude Code (PostToolUse + Stop avec dégradation)"
```

---

### Task 5: Template section CLAUDE.md

**Files:**
- Create: `skills/init/templates/claude-md-section.md.tmpl`

Placeholders additionnels : `{{FAST_DESC}}` (description humaine de la phase rapide, ex. « tests host »), `{{VARIANT_LIST_DESC}}` (ex. « les 6 boards » ; mono-cible : « le build complet »), `{{TDD_SCOPE}}` (types de logique pure du projet, ex. « parsing, encodage, machines à états »).

- [ ] **Step 1: Créer le template**

```markdown
## Workflow anti-régression (OBLIGATOIRE)

Source unique de vérité : `scripts/check.sh`.
- `./scripts/check.sh --fast` — {{FAST_DESC}} (~secondes)
- `./scripts/check.sh --variant <name>` — fast + build d'une variante
- `./scripts/check.sh` — fast + {{VARIANT_LIST_DESC}}

**Activation des hooks git (une fois par clone)** :
```bash
./scripts/install-hooks.sh   # ou: git config core.hooksPath scripts/hooks
```
`pre-push` lance le check complet et bloque le push si rouge. WIP : `git push --no-verify`.

**Hooks Claude Code** (`.claude/settings.json`, automatiques) :
- `PostToolUse` sur édition d'un fichier surveillé → `check.sh --fast`.
- `Stop` → check du variant courant (lu dans `.tripwire-variant`). Si l'env de
  build n'est pas disponible, dégrade en `--fast` seul.

### Norme TDD — nouvelle logique pure
Toute nouvelle fonction de logique pure ({{TDD_SCOPE}}) : test écrit **d'abord**,
ajouté à la suite de tests de la phase rapide. Le test doit être rouge avant
l'implémentation, vert après, et parallel-safe (pas d'état global muté).
```

Note : en mono-cible, le SKILL.md instruit de supprimer la ligne `--variant` et la mention `.tripwire-variant`.

- [ ] **Step 2: Commit**

```bash
git add skills/init/templates/claude-md-section.md.tmpl
git commit -m "feat(init): template section CLAUDE.md (workflow anti-régression + norme TDD)"
```

---

### Task 6: SKILL.md de `/tripwire:init`

**Files:**
- Create: `skills/init/SKILL.md`

- [ ] **Step 1: Créer le SKILL.md**

````markdown
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
3. **Chemins surveillés** — répertoires dont l'édition déclenche le hook
   PostToolUse (ex. `src/`, `tests/`). Convertir en patterns `case` :
   `src/` → `*"/src/"*`.
4. **Setup d'environnement** — commande à sourcer avant un build
   (ex. `source ~/esp/esp-idf/export.sh`), ou « aucun ».

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
| `{{DEFAULT_VARIANT}}` | variante par défaut (multi uniquement) |
| `{{ENV_SETUP_BLOCK}}` | bloc shell de setup d'env ; **supprimer la ligne** si aucun |
| `{{ENV_AVAILABLE_TEST}}` | test shell de dispo de l'env ; `true` si aucun |
| `{{VARIANT_STATE_BLOCK}}` | deux lignes : `VARIANT="$(cat .tripwire-variant 2>/dev/null \|\| true)"` puis `VARIANT="${VARIANT:-<défaut>}"` (robuste au fichier vide) ; **supprimer la ligne** si mono |
| `{{STOP_CHECK_ARGS}}` | `--variant "$VARIANT"` (multi) ; vide (mono) |
| `{{STOP_CHECK_DESC}}` | `variant $VARIANT` (multi) ; `complet` (mono) |
| `{{WATCHED_PATH_PATTERNS}}` | patterns `case` séparés par `\|` |
| `{{TDD_SCOPE}}` | types de logique pure du projet |

### Adaptations mono-cible
- `ALL_VARIANTS=()` vide ; le mode `--variant` reste dans check.sh (inerte, ne pas le retirer).
- Dans la section CLAUDE.md : supprimer la ligne `--variant` et la mention `.tripwire-variant`.
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

### Section CLAUDE.md
- `CLAUDE.md` absent → le créer avec un titre `# <projet> — Claude Code
  instructions` puis la section.
- Présent → ajouter la section à la fin (ou remplacer une section
  « Workflow anti-régression » existante si mise à jour).

## Étape 4 — Validation (OBLIGATOIRE avant de conclure)

```bash
command -v python3   # requis par les hooks Claude Code (parsing JSON) — avertir si absent
bash -n scripts/check.sh scripts/hooks/*.sh scripts/hooks/pre-push scripts/install-hooks.sh
./scripts/install-hooks.sh
git config --get core.hooksPath    # doit afficher scripts/hooks
./scripts/check.sh --fast          # doit être VERT
echo '{"tool_input":{"file_path":"'$PWD'/<un chemin surveillé>/x"}}' | scripts/hooks/cc_post_edit.sh; echo "rc=$?"   # rc=0 attendu (vert)
```

Si `check.sh --fast` est rouge : diagnostiquer avec l'utilisateur (commande
fast incorrecte ?) avant de conclure. Ne jamais livrer un tripwire rouge.

## Étape 5 — Récap final

Lister les fichiers créés/modifiés, rappeler :
- `./scripts/install-hooks.sh` à lancer sur chaque nouveau clone ;
- `echo <variante> > .tripwire-variant` pour changer la variante courante ;
- les hooks Claude Code s'activent à la prochaine session.
````

- [ ] **Step 2: Vérifier le frontmatter** (parse YAML basique)

Run: `python3 -c "import re; t=open('skills/init/SKILL.md').read(); m=re.match(r'^---\n(.*?)\n---', t, re.S); assert m and 'name:' in m.group(1) and 'description:' in m.group(1); print('frontmatter OK')"`
Expected: `frontmatter OK`

- [ ] **Step 3: Commit**

```bash
git add skills/init/SKILL.md
git commit -m "feat(init): SKILL.md — workflow guidé de scaffolding"
```

---

### Task 7: Skill `/tripwire:gen-agents` — SKILL.md + 3 templates d'agents

**Files:**
- Create: `skills/gen-agents/SKILL.md`
- Create: `skills/gen-agents/templates/test-author.md.tmpl`
- Create: `skills/gen-agents/templates/code-reviewer.md.tmpl`
- Create: `skills/gen-agents/templates/debugger.md.tmpl`

Placeholders agents : `{{PROJ}}` (slug court du projet, ex. `kase`), `{{PROJECT_NAME}}`, `{{PROJECT_CONTEXT}}` (3-6 lignes : stack, structure, conventions — extrait du CLAUDE.md cible), `{{TEST_CONVENTIONS}}`, `{{REVIEW_CHECKLIST}}` (liste des conventions à vérifier), `{{BUILD_DEBUG_CMDS}}` (commandes de build/diagnostic).

- [ ] **Step 1: Créer `test-author.md.tmpl`**

```markdown
---
name: {{PROJ}}-test-author
description: Use this agent to write or restructure tests in {{PROJECT_NAME}}. Tests must be written BEFORE new pure-logic implementation (TDD norm), be parallel-safe, and not depend on external state. Examples:\n\n- User: "ajoute des tests pour le nouveau parser"\n  Assistant: "Je lance {{PROJ}}-test-author pour écrire les tests d'abord."\n\n- User: "ce test est flaky"\n  Assistant: "Je lance {{PROJ}}-test-author pour identifier la dépendance d'état."
---

Tu es l'auteur de tests du projet {{PROJECT_NAME}}.

## Contexte projet
{{PROJECT_CONTEXT}}

## Conventions de test
{{TEST_CONVENTIONS}}

## Règles
1. TDD : pour toute logique pure nouvelle, écrire le test AVANT l'implémentation.
   Vérifier qu'il est rouge avant, vert après.
2. Parallel-safe : pas d'état global muté, pas de chemins temp partagés,
   pas de dépendance à l'ordre d'exécution.
3. Chaque test vérifie UN comportement, nommé d'après ce comportement.
4. Lancer la suite via `./scripts/check.sh --fast` et confirmer le vert
   avant de conclure.
```

- [ ] **Step 2: Créer `code-reviewer.md.tmpl`**

```markdown
---
name: {{PROJ}}-code-reviewer
description: Use this agent to review recently written or modified code in {{PROJECT_NAME}} against the project conventions. Run before any merge to main or release. Examples:\n\n- User: "review avant merge"\n  Assistant: "Je lance {{PROJ}}-code-reviewer sur le diff vs main."\n\n- After writing non-trivial code proactively:\n  Assistant: "Je lance {{PROJ}}-code-reviewer pour vérifier les conventions."
---

Tu es le reviewer du projet {{PROJECT_NAME}}.

## Contexte projet
{{PROJECT_CONTEXT}}

## Checklist de review
{{REVIEW_CHECKLIST}}

## Méthode
1. Examiner le diff (`git diff main...HEAD` ou les fichiers indiqués).
2. Vérifier chaque point de la checklist ; citer fichier:ligne pour chaque écart.
3. Vérifier que la norme TDD a été suivie (tests présents pour la logique pure nouvelle).
4. Lancer `./scripts/check.sh --fast` ; un review ne peut pas conclure « OK » sur un tripwire rouge.
5. Classer les findings : bloquant / important / cosmétique.
```

- [ ] **Step 3: Créer `debugger.md.tmpl`**

```markdown
---
name: {{PROJ}}-debugger
description: Use this agent to debug failures in {{PROJECT_NAME}} — failing tests, broken builds, runtime errors. It reproduces, isolates the root cause, and proposes a minimal fix. Examples:\n\n- User: "le build casse" + logs\n  Assistant: "Je lance {{PROJ}}-debugger pour isoler la cause."\n\n- User: "ce test échoue depuis hier"\n  Assistant: "Je lance {{PROJ}}-debugger pour bisecter la régression."
---

Tu es le debugger du projet {{PROJECT_NAME}}.

## Contexte projet
{{PROJECT_CONTEXT}}

## Commandes de diagnostic
{{BUILD_DEBUG_CMDS}}

## Méthode
1. Reproduire d'abord : relancer la commande qui échoue, capturer la sortie exacte.
2. Isoler : réduire au plus petit cas qui échoue (un test, un fichier, un commit
   — `git bisect` si régression temporelle).
3. Cause racine AVANT fix : ne jamais proposer de patch sans expliquer pourquoi
   ça casse.
4. Fix minimal, puis `./scripts/check.sh --fast` (et `--variant`/full si le fix
   touche au build) pour confirmer.
```

- [ ] **Step 4: Créer `skills/gen-agents/SKILL.md`**

```markdown
---
name: gen-agents
description: Use when generating project-specialized subagents (test-author, code-reviewer, debugger) into a target repo's .claude/agents/. Reads the target CLAUDE.md and repo structure to fill in project context. Trigger on "/tripwire:gen-agents", "génère les agents du projet", "ajoute un agent de review spécialisé".
---

# tripwire:gen-agents — agents spécialisés au projet

Génère dans `.claude/agents/` du repo cible jusqu'à 3 agents à partir des
templates de `templates/` : `test-author`, `code-reviewer`, `debugger`.

## Workflow

1. **Demander** (AskUserQuestion, multiSelect) lesquels générer (défaut : les 3).
2. **Collecter le contexte** — lire le `CLAUDE.md` cible et la structure du
   repo pour remplir :
   - `{{PROJ}}` : slug court (ex. `kase`, demander si ambigu) ;
   - `{{PROJECT_CONTEXT}}` : 3-6 lignes — stack, structure des dossiers,
     conventions clés ;
   - `{{TEST_CONVENTIONS}}` : où vivent les tests, comment les lancer,
     contraintes (parallel-safe, mocks…) ;
   - `{{REVIEW_CHECKLIST}}` : extraire les conventions du CLAUDE.md en liste
     vérifiable (ex. « pas de malloc dans les hot paths ») ;
   - `{{BUILD_DEBUG_CMDS}}` : commandes de build/log/diagnostic du projet.
   Si le CLAUDE.md cible est pauvre, poser 1-2 questions ciblées plutôt
   qu'inventer.
3. **Générer** `.claude/agents/<proj>-<role>.md` pour chaque agent choisi.
   Ne pas écraser un agent existant sans accord explicite.
4. **Vérifier** : frontmatter présent (`name`, `description` avec exemples),
   placeholders tous remplis (`grep -n '{{' .claude/agents/<proj>-*.md` ne
   doit rien retourner).
5. **Rappeler** : les agents sont disponibles à la prochaine session, et la
   section « Quand invoquer les agents » peut être ajoutée au CLAUDE.md cible.
```

- [ ] **Step 5: Vérifier**

Run: `python3 -c "
import re
for f in ['skills/gen-agents/SKILL.md','skills/gen-agents/templates/test-author.md.tmpl','skills/gen-agents/templates/code-reviewer.md.tmpl','skills/gen-agents/templates/debugger.md.tmpl']:
    t=open(f).read()
    assert re.match(r'^---\n.*?name:.*?\n.*?---', t, re.S), f
print('frontmatters OK')"`
Expected: `frontmatters OK`

- [ ] **Step 6: Commit**

```bash
git add skills/gen-agents
git commit -m "feat(gen-agents): skill + templates test-author/code-reviewer/debugger"
```

---

### Task 8: Skill `/tripwire:release`

**Files:**
- Create: `skills/release/SKILL.md`

- [ ] **Step 1: Créer le SKILL.md**

````markdown
---
name: release
description: Use when cutting a release in a tripwire-enabled project — git tag vX.Y.Z as single version source, full check.sh must be green, build artifacts, create GitLab/GitHub release. Trigger on "/tripwire:release", "prépare une release", "cut une release", "publie vX.Y.Z".
---

# tripwire:release — workflow de release générique

## Principes (non négociables)

1. **Tag git `vX.Y.Z` = source de vérité de la version.** Jamais de fichier
   VERSION. Entre releases, la version dérive de `git describe --tags`.
2. **`./scripts/check.sh` complet VERT obligatoire avant de tagger.**
   Pas d'exception, pas de `--no-verify` sur une release.
3. Working tree propre (`git status` clean) avant de tagger.

## Première utilisation sur un projet

Si le CLAUDE.md cible n'a pas de section « Release », demander :
- commande(s) de build des artefacts (et leurs chemins de sortie) ;
- artefacts à attacher à la release (globs).
Puis **persister** ces réponses dans une section `## Release` du CLAUDE.md
cible pour les runs suivants.

## Workflow

1. **Déterminer la version** : lire `git describe --tags` ; proposer le bump
   (patch/minor/major) via AskUserQuestion si l'utilisateur n'a pas donné de
   version explicite.
2. **Pré-flight** :
   ```bash
   git status --porcelain        # doit être vide
   ./scripts/check.sh            # doit être VERT (full)
   ```
   Rouge → STOP, diagnostiquer, ne pas tagger.
3. **Tag + push** :
   ```bash
   git tag vX.Y.Z
   git push && git push --tags
   ```
4. **Build des artefacts** : commandes de la section Release du CLAUDE.md
   cible. Vérifier que chaque artefact attendu existe.
5. **Créer la release** — détecter le forge via `git remote get-url origin` :
   - contient `gitlab` → `glab release create vX.Y.Z <artefacts...>`
   - contient `github` → `gh release create vX.Y.Z <artefacts...>`
   - autre → donner les fichiers et laisser l'utilisateur publier.
6. **Récap** : version, artefacts, URL de la release.

## Notes de release

Générer les notes depuis `git log <tag précédent>..HEAD --oneline`, groupées
par type (feat/fix/docs/…). Les proposer à l'utilisateur avant publication.
````

- [ ] **Step 2: Commit**

```bash
git add skills/release/SKILL.md
git commit -m "feat(release): skill workflow de release générique (tag = version, check vert)"
```

---

### Task 9: Test E2E — instancier les templates sur un projet jouet

But : prouver que les templates, une fois les placeholders substitués, produisent un pipeline fonctionnel (vert quand tout va bien, rouge + exit code non-zéro quand un test casse, hook PostToolUse qui filtre et remonte).

**Files:**
- Create: `tests/e2e.sh` (test du plugin lui-même, committé dans le repo tripwire)

- [ ] **Step 1: Écrire `tests/e2e.sh`**

```bash
#!/usr/bin/env bash
# E2E tripwire : instancie les templates (cas mono-cible, sans env setup)
# sur un repo jouet et vérifie vert/rouge/hooks. Exit 0 si tout passe.
set -uo pipefail
PLUGIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"
git init -q -b main

mkdir -p scripts/hooks src
printf '#!/usr/bin/env bash\nexit 0\n' > fast.sh && chmod +x fast.sh
printf '#!/usr/bin/env bash\nexit 0\n' > build.sh && chmod +x build.sh

# --- Instanciation (sed) : mono-cible, pas d'env setup ---
sed -e 's|{{PROJECT_NAME}}|toy|g' \
    -e 's|{{VARIANTS_SPACE_SEPARATED}}||g' \
    -e 's|{{FAST_CMD}}|./fast.sh|g' \
    -e 's|{{VARIANT_BUILD_CMD}}|./build.sh|g' \
    "$PLUGIN/skills/init/templates/check.sh.tmpl" > scripts/check.sh
sed -e 's|{{PROJECT_NAME}}|toy|g' -e '/{{ENV_SETUP_BLOCK}}/d' \
    "$PLUGIN/skills/init/templates/pre-push.tmpl" > scripts/hooks/pre-push
cp "$PLUGIN/skills/init/templates/install-hooks.sh.tmpl" scripts/install-hooks.sh
sed -e 's|{{WATCHED_PATH_PATTERNS}}|*"/src/"*|g' \
    "$PLUGIN/skills/init/templates/cc_post_edit.sh.tmpl" > scripts/hooks/cc_post_edit.sh
sed -e '/{{VARIANT_STATE_BLOCK}}/d' -e '/{{ENV_SETUP_BLOCK}}/d' \
    -e 's|{{ENV_AVAILABLE_TEST}}|true|g' \
    -e 's|{{STOP_CHECK_ARGS}}||g' -e 's|{{STOP_CHECK_DESC}}|complet|g' \
    "$PLUGIN/skills/init/templates/cc_stop.sh.tmpl" > scripts/hooks/cc_stop.sh
chmod +x scripts/check.sh scripts/hooks/* scripts/install-hooks.sh

fails=0
chk() { local desc="$1" want="$2" got="$3"
  if [ "$got" = "$want" ]; then echo "✓ $desc"; else echo "✗ $desc (want $want, got $got)"; fails=1; fi }

# Aucun placeholder résiduel
if grep -rn '{{' scripts/ >/dev/null; then echo "✗ placeholders résiduels"; fails=1; else echo "✓ pas de placeholder résiduel"; fi

# Vert : fast, full, stop hook, post-edit (fichier surveillé + non surveillé)
./scripts/check.sh --fast >/dev/null 2>&1;             chk "fast vert" 0 $?
./scripts/check.sh >/dev/null 2>&1;                    chk "full vert" 0 $?
scripts/hooks/cc_stop.sh </dev/null >/dev/null 2>&1;   chk "stop hook vert" 0 $?
echo '{"tool_input":{"file_path":"'"$TMP"'/src/a.c"}}' | scripts/hooks/cc_post_edit.sh >/dev/null 2>&1
chk "post-edit surveillé vert" 0 $?
echo '{"tool_input":{"file_path":"'"$TMP"'/README.md"}}' | scripts/hooks/cc_post_edit.sh >/dev/null 2>&1
chk "post-edit non surveillé ignoré" 0 $?

# install-hooks
./scripts/install-hooks.sh >/dev/null 2>&1
chk "core.hooksPath" "scripts/hooks" "$(git config --get core.hooksPath)"

# Rouge : casser fast
printf '#!/usr/bin/env bash\nexit 1\n' > fast.sh
./scripts/check.sh --fast >/dev/null 2>&1;             chk "fast rouge -> rc 1" 1 $?
scripts/hooks/pre-push </dev/null >/dev/null 2>&1;     chk "pre-push bloque" 1 $?
echo '{"tool_input":{"file_path":"'"$TMP"'/src/a.c"}}' | scripts/hooks/cc_post_edit.sh >/dev/null 2>&1
chk "post-edit rouge -> rc 2" 2 $?
scripts/hooks/cc_stop.sh </dev/null >/dev/null 2>&1;   chk "stop rouge -> rc 2" 2 $?

# Rouge : fast vert mais build cassé -> full rouge, fast vert
printf '#!/usr/bin/env bash\nexit 0\n' > fast.sh
printf '#!/usr/bin/env bash\nexit 1\n' > build.sh
./scripts/check.sh --fast >/dev/null 2>&1;             chk "fast vert (build cassé)" 0 $?
./scripts/check.sh >/dev/null 2>&1;                    chk "full rouge (build cassé)" 1 $?

echo "----------------------------------------"
if [ "$fails" -eq 0 ]; then echo "E2E: tout vert"; else echo "E2E: ROUGE"; fi
exit "$fails"
```

- [ ] **Step 2: Vérifier la syntaxe puis lancer**

Run: `bash -n tests/e2e.sh && bash tests/e2e.sh`
Expected: chaque ligne préfixée `✓`, dernière ligne `E2E: tout vert`, exit 0.
Si un `✗` apparaît : corriger le **template** concerné (pas le repo jouet), relancer.

- [ ] **Step 3: Commit**

```bash
git add tests/e2e.sh
git commit -m "test: E2E instanciation des templates sur projet jouet (vert/rouge/hooks)"
```

---

### Task 10: Validation plugin + installation locale

**Files:**
- Modify: aucun (validation) ; corrections éventuelles selon findings.

- [ ] **Step 1: Lancer l'agent `plugin-dev:plugin-validator`** sur `~/Documents/GitHub/tripwire`

Via le tool Agent, `subagent_type: plugin-dev:plugin-validator`, prompt :
« Validate the plugin at /home/mae/Documents/GitHub/tripwire : manifest, marketplace.json, skills structure (init, gen-agents, release), frontmatters. »
Expected: pas d'erreur bloquante. Corriger + committer si findings.

- [ ] **Step 2: Installer la marketplace locale + le plugin**

```bash
claude plugin marketplace add ~/Documents/GitHub/tripwire
claude plugin install tripwire@tripwire
```
Expected: installation sans erreur ; `claude plugin list` (ou équivalent) montre `tripwire`.

- [ ] **Step 3: Smoke test d'invocation**

Dans une nouvelle session Claude Code sur un repo jetable : taper `/tripwire:init` et vérifier que la skill se charge (le workflow démarre par la détection de stack). Pas besoin de dérouler tout l'init — l'E2E de la Task 9 couvre le comportement des templates.

- [ ] **Step 4: Commit final éventuel + récap**

```bash
git status   # doit être propre
git log --oneline
```

---

### Task 11: Push vers GitLab (action externe — confirmer avec Mae avant)

- [ ] **Step 1: Créer le repo distant et pousser** (⚠️ outward-facing : demander confirmation explicite avant d'exécuter)

```bash
cd ~/Documents/GitHub/tripwire
glab repo create harrael/tripwire --private --defaultBranch main
git remote add origin git@gitlab.com:harrael/tripwire.git
git push -u origin main
```
Expected: repo visible sur gitlab.com/harrael/tripwire.

- [ ] **Step 2: Mettre à jour le README** si l'URL d'install distante diffère, committer, pousser.
