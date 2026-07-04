# Qualité des tests — plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Le pipeline détecte les tests supprimés (ratchet committé, rouge au push), les assertions affaiblies (contexte injecté à l'agent) et le code sans test (avis) ; un skill `/tripwire:test-review` audite sémantiquement les tests creux.

**Architecture:** Pièces 1 et 3 dans `check.sh.tmpl` (valeurs projet + blocs non bloquants sauf ratchet strict), pièce 2 dans les hooks post-edit (cc JSON additionalContext / vibe stderr), pièce 4 en skill d'instructions. Tout le mécanique est couvert TDD dans `tests/e2e.sh` sur le repo jouet.

**Tech Stack:** bash (templates), git plumbing, skills markdown.

## Global Constraints

- Spec : `docs/superpowers/specs/2026-07-04-qualite-tests-design.md`.
- TDD obligatoire : assertions e2e rouges AVANT l'implémentation des templates.
- `TEST_COUNT_CMD` vide ou en échec → ratchet totalement inerte, jamais d'erreur.
- Rien de bloquant hors `TRIPWIRE_RATCHET_STRICT=1` (posé uniquement par pre-push).
- `.tripwire-testcount` est committé (baisser le ratchet = ligne de diff visible).
- Contrainte quotes : les valeurs injectées ne contiennent pas de `"` (quotes simples internes OK).
- Chaque instanciation de template dans e2e doit substituer TOUS les nouveaux placeholders (le check « placeholders résiduels » échoue sinon).
- Signature git désactivée localement ; commits Conventional Commits.
- Après chaque tâche : `bash tests/e2e.sh` → `E2E: tout vert`, puis `./scripts/check.sh --fast --force` vert.

---

### Task 1: Ratchet de tests (check.sh.tmpl + pre-push.tmpl)

**Files:**
- Modify: `tests/e2e.sh`
- Modify: `skills/init/templates/check.sh.tmpl`
- Modify: `skills/init/templates/pre-push.tmpl`

**Interfaces:**
- Produces: variable `TEST_COUNT_CMD="{{TEST_COUNT_CMD}}"` dans check.sh ; fichier `.tripwire-testcount` (entier + newline, racine du repo cible) ; env `TRIPWIRE_RATCHET_STRICT=1` → baisse du compte = rc 1. Messages contenant le mot `ratchet`.

- [ ] **Step 1: e2e — substitutions des nouveaux placeholders (3 instanciations existantes)**

Dans `tests/e2e.sh`, ajouter aux sed de **mono** (`> scripts/check.sh`, section « Instanciation »), de **check_mod** (`> scripts/check_mod.sh`) et de **multi** (`> scripts/check.sh` du bloc multi) :

```bash
    -e 's|{{SRC_GREP}}||g' \
    -e 's|{{TEST_GREP}}||g' \
```

et pour mono uniquement :

```bash
    -e 's|{{TEST_COUNT_CMD}}|cat ntests.txt|g' \
```

pour check_mod et multi :

```bash
    -e 's|{{TEST_COUNT_CMD}}||g' \
```

(mono garde `SRC_GREP`/`TEST_GREP` vides ici — la Task 3 les remplira.)

- [ ] **Step 2: e2e — assertions ratchet (rouges)**

Insérer ce bloc juste APRÈS le bloc bisect (après `chk "bisect: commit fautif localisé" …`) et AVANT `# Rouge : casser fast` :

```bash
# ===== Ratchet de tests =====
printf '#!/usr/bin/env bash\nexit 0\n' > fast.sh   # le bloc bisect laisse fast.sh cassé
echo 5 > ntests.txt
./scripts/check.sh --fast --force >/dev/null 2>&1
chk "ratchet: bootstrap crée la référence" "5" "$(cat .tripwire-testcount 2>/dev/null)"
echo 7 > ntests.txt
./scripts/check.sh --fast --force >/dev/null 2>&1
chk "ratchet: auto-bump à la hausse" "7" "$(cat .tripwire-testcount 2>/dev/null)"
echo 6 > ntests.txt
OUT="$(./scripts/check.sh --fast --force 2>&1)"; rc=$?
chk "ratchet: baisse -> avertissement, rc 0" 0 $rc
echo "$OUT" | grep -q "ratchet"; chk "ratchet: message d'avertissement" 0 $?
chk "ratchet: la référence ne baisse pas seule" "7" "$(cat .tripwire-testcount 2>/dev/null)"
OUT="$(TRIPWIRE_RATCHET_STRICT=1 ./scripts/check.sh --fast --force 2>&1)"; rc=$?
chk "ratchet: baisse + STRICT -> rouge" 1 $rc
scripts/hooks/pre-push </dev/null >/dev/null 2>&1
chk "ratchet: pre-push bloque sur baisse" 1 $?
echo 7 > ntests.txt   # remettre compte == référence (sections suivantes propres)
```

- [ ] **Step 3: vérifier le rouge**

Run: `bash tests/e2e.sh 2>&1 | grep -E 'ratchet|E2E'`
Expected: échecs `✗ ratchet: …` (le placeholder n'existe pas encore → sed inertes, fichier jamais créé), `E2E: ROUGE`.

- [ ] **Step 4: implémentation check.sh.tmpl**

Après le bloc `MODULE_FAST=({{MODULE_FAST_ENTRIES}})`, ajouter :

```bash

# Ratchet de tests (optionnel) : commande une-ligne qui imprime le nombre de
# tests. Vide -> ratchet inerte. Référence committée : .tripwire-testcount
# (la baisser = diff visible en review). Rouge au pre-push si le compte chute
# (TRIPWIRE_RATCHET_STRICT=1, posé par le hook pre-push).
TEST_COUNT_CMD="{{TEST_COUNT_CMD}}"
```

Après la boucle des variantes (après le `fi` qui ferme `elif [ "$MODE" = "full" ]`) et AVANT `echo "========================================"`, ajouter :

```bash

# ---- Ratchet de tests : le nombre de tests ne baisse jamais en silence ----
if [ -n "$TEST_COUNT_CMD" ]; then
  TC="$( (eval "$TEST_COUNT_CMD") 2>/dev/null | tr -d '[:space:]' )"
  case "$TC" in ''|*[!0-9]*) TC="" ;; esac
  REF="$(tr -d '[:space:]' < .tripwire-testcount 2>/dev/null)"
  case "$REF" in ''|*[!0-9]*) REF="" ;; esac
  if [ -n "$TC" ]; then
    if [ -z "$REF" ]; then
      printf '%s\n' "$TC" > .tripwire-testcount 2>/dev/null \
        && info "ratchet: référence initialisée à $TC tests (.tripwire-testcount — à committer)"
    elif [ "$TC" -gt "$REF" ]; then
      printf '%s\n' "$TC" > .tripwire-testcount 2>/dev/null \
        && info "ratchet: $REF -> $TC tests (.tripwire-testcount mis à jour — à committer)"
    elif [ "$TC" -lt "$REF" ]; then
      if [ "${TRIPWIRE_RATCHET_STRICT:-0}" = "1" ]; then
        fail "ratchet: $TC tests, référence $REF — des tests ont disparu (baisse assumée ? mettre à jour .tripwire-testcount dans un commit)"
        rc=1
      else
        info "⚠ ratchet: $TC tests vs $REF attendus — des tests ont disparu ?"
      fi
    fi
  fi
fi
```

- [ ] **Step 5: implémentation pre-push.tmpl**

Après la ligne `echo "[pre-push] check.sh complet…"`, ajouter :

```bash
export TRIPWIRE_RATCHET_STRICT=1   # au push, une baisse du nombre de tests bloque
```

- [ ] **Step 6: vérifier le vert**

Run: `bash tests/e2e.sh 2>&1 | tail -1` → `E2E: tout vert`.
Run: `./scripts/check.sh --fast --force 2>&1 | tail -1` → vert (le check.sh dogfood n'a pas encore le placeholder — normal, régénéré en Task 6 ; lint valide le template).

- [ ] **Step 7: commit**

```bash
git add tests/e2e.sh skills/init/templates/check.sh.tmpl skills/init/templates/pre-push.tmpl
git commit -m "feat(check): ratchet de tests — référence committée, rouge au pre-push si baisse"
```

---

### Task 2: Garde anti-affaiblissement (hooks post-edit)

**Files:**
- Modify: `tests/e2e.sh`
- Modify: `skills/init/templates/cc_post_edit.sh.tmpl`
- Modify: `skills/init/templates/vibe_post_edit.sh.tmpl`

**Interfaces:**
- Consumes: hooks existants (watch → debounce → check fast).
- Produces: placeholders `{{TEST_PATH_PATTERNS}}` (patterns `case`) et `{{ASSERT_PATTERN}}` (regex grep -E) ; sur perte nette d'assertions vs HEAD dans un fichier de test : cc → stdout JSON `hookSpecificOutput.PostToolUse.additionalContext` contenant `assertion(s) en moins`, vibe → même texte sur stderr ; rc 0 dans tous les cas.

- [ ] **Step 1: e2e — substitutions + watch élargi**

Dans les DEUX instanciations de hooks post-edit du bloc mono (cc et vibe), remplacer la valeur de `{{WATCHED_PATH_PATTERNS}}` :

`*"/src/"*` devient `*"/src/"*\|*"/test/"*`

et ajouter à chacune :

```bash
    -e 's|{{TEST_PATH_PATTERNS}}|*"/test/"*|g' \
    -e 's|{{ASSERT_PATTERN}}|assert|g' \
```

- [ ] **Step 2: e2e — assertions garde (rouges)**

Insérer APRÈS le bloc ratchet de la Task 1, AVANT `# Rouge : casser fast` :

```bash
# ===== Garde anti-affaiblissement des tests =====
mkdir -p test
printf 'assert(a);\nassert(b);\nassert(c);\n' > test/t.c
git add -A >/dev/null 2>&1 && GITC commit -qm "c6 tests baseline"
printf 'assert(a);\n' > test/t.c            # 3 -> 1 : perte nette de 2
OUT="$(echo '{"tool_input":{"file_path":"'"$TMP"'/test/t.c"}}' | scripts/hooks/cc_post_edit.sh 2>/dev/null)"; rc=$?
chk "garde assertions: rc 0 (non bloquant)" 0 $rc
echo "$OUT" | grep -q "assertion(s) en moins"; chk "garde assertions: contexte émis" 0 $?
OUT="$(echo '{"file_path":"'"$TMP"'/test/t.c"}' | scripts/hooks/vibe_post_edit.sh 2>&1 >/dev/null)"
echo "$OUT" | grep -q "assertion(s) en moins"; chk "garde assertions: parité vibe (stderr)" 0 $?
printf 'assert(a);\nassert(b);\nassert(c);\nassert(d);\n' > test/t.c   # 3 -> 4 : gain
OUT="$(echo '{"tool_input":{"file_path":"'"$TMP"'/test/t.c"}}' | scripts/hooks/cc_post_edit.sh 2>/dev/null)"
echo "$OUT" | grep -q "assertion"; chk "garde assertions: gain -> silencieux" 1 $?
git checkout -q -- test/t.c
```

Note : `GITC` est défini par le bloc bisect plus haut dans le fichier.

- [ ] **Step 3: vérifier le rouge**

Run: `bash tests/e2e.sh 2>&1 | grep -E 'garde assertions|E2E'`
Expected: `✗ garde assertions: contexte émis`, `✗ … parité vibe`, `E2E: ROUGE`.

- [ ] **Step 4: implémentation cc_post_edit.sh.tmpl**

Remplacer la fin du fichier :

```bash
if [ "$rc" -ne 0 ]; then
  echo "Régression phase rapide après édition de $FP :" >&2
  echo "$OUT" | tail -8 >&2
  exit 2   # remonte à Claude
fi
exit 0
```

par :

```bash
if [ "$rc" -ne 0 ]; then
  echo "Régression phase rapide après édition de $FP :" >&2
  echo "$OUT" | tail -8 >&2
  exit 2   # remonte à Claude
fi
# Garde anti-affaiblissement : perte nette d'assertions vs HEAD dans un test ?
case "$FP" in
  {{TEST_PATH_PATTERNS}})
    REL="${FP#"$REPO"/}"
    NOLD="$(git show "HEAD:$REL" 2>/dev/null | grep -cE '{{ASSERT_PATTERN}}')"
    NNEW="$(grep -cE '{{ASSERT_PATTERN}}' "$FP" 2>/dev/null)"
    if git cat-file -e "HEAD:$REL" 2>/dev/null && [ "$NOLD" -gt "$NNEW" ] 2>/dev/null; then
      python3 -c 'import json,sys; print(json.dumps({"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":sys.argv[1]}}, ensure_ascii=False))' \
        "tripwire: $((NOLD-NNEW)) assertion(s) en moins dans $REL vs HEAD — refactor légitime ou affaiblissement ? Rétablir ou justifier."
    fi
    ;;
esac
exit 0
```

- [ ] **Step 5: implémentation vibe_post_edit.sh.tmpl**

Même remplacement de la fin de fichier, mais le message final devient :

```bash
      echo "tripwire: $((NOLD-NNEW)) assertion(s) en moins dans $REL vs HEAD — refactor légitime ou affaiblissement ? Rétablir ou justifier." >&2
```

(à la place de l'appel python3 ; tout le reste identique, y compris le `case`/`git cat-file`.)

- [ ] **Step 6: vérifier le vert**

Run: `bash tests/e2e.sh 2>&1 | tail -1` → `E2E: tout vert`.

- [ ] **Step 7: commit**

```bash
git add tests/e2e.sh skills/init/templates/cc_post_edit.sh.tmpl skills/init/templates/vibe_post_edit.sh.tmpl
git commit -m "feat(hooks): garde anti-affaiblissement — perte d'assertions signalée à l'agent"
```

---

### Task 3: Avis « logique sans test » (check.sh.tmpl)

**Files:**
- Modify: `tests/e2e.sh`
- Modify: `skills/init/templates/check.sh.tmpl`

**Interfaces:**
- Consumes: placeholders `{{SRC_GREP}}`/`{{TEST_GREP}}` déjà substitués partout (Task 1).
- Produces: variables `SRC_GREP`/`TEST_GREP` dans check.sh ; sur run réel avec du source modifié (`git diff --name-only HEAD`) matchant SRC_GREP et zéro fichier matchant TEST_GREP : ligne d'avis contenant `TDD:`. Jamais bloquant.

- [ ] **Step 1: e2e — activer les valeurs mono**

Dans l'instanciation mono de `scripts/check.sh`, remplacer les substitutions vides de la Task 1 :

```bash
    -e 's|{{SRC_GREP}}|^src/|g' \
    -e 's|{{TEST_GREP}}|^test/|g' \
```

- [ ] **Step 2: e2e — assertions (rouges)**

Insérer APRÈS le bloc garde-assertions (Task 2), AVANT `# Rouge : casser fast` :

```bash
# ===== Avis TDD : source modifié sans test modifié =====
echo mod >> src/f2                                    # source tracké modifié
OUT="$(./scripts/check.sh --fast --force 2>&1)"
echo "$OUT" | grep -q "TDD:"; chk "avis TDD: source sans test -> avis" 0 $?
echo t >> test/t.c                                    # un test modifié aussi
OUT="$(./scripts/check.sh --fast --force 2>&1)"
echo "$OUT" | grep -q "TDD:"; chk "avis TDD: test modifié -> silencieux" 1 $?
git checkout -q -- src/f2 test/t.c
```

- [ ] **Step 3: vérifier le rouge**

Run: `bash tests/e2e.sh 2>&1 | grep -E 'avis TDD|E2E'` → `✗ avis TDD: source sans test -> avis`, `E2E: ROUGE`.

- [ ] **Step 4: implémentation check.sh.tmpl**

Sous la ligne `TEST_COUNT_CMD="{{TEST_COUNT_CMD}}"`, ajouter :

```bash
# Avis TDD (optionnel) : formes grep -E des chemins source et test. Vides -> inerte.
SRC_GREP="{{SRC_GREP}}"
TEST_GREP="{{TEST_GREP}}"
```

Après le bloc historique des durées (`} 2>/dev/null || true`) et AVANT le dernier `echo "========================================"`, ajouter :

```bash
# Avis TDD : du source modifié sans test modifié ? (informatif, jamais bloquant)
if [ -n "$SRC_GREP" ] && [ -n "$TEST_GREP" ]; then
  CH="$(git diff --name-only HEAD 2>/dev/null)"
  if [ -n "$CH" ]; then
    NSRC="$(printf '%s\n' "$CH" | grep -cE "$SRC_GREP")"
    NTST="$(printf '%s\n' "$CH" | grep -cE "$TEST_GREP")"
    if [ "$NSRC" -gt 0 ] 2>/dev/null && [ "$NTST" -eq 0 ] 2>/dev/null; then
      info "⚠ TDD: $NSRC fichier(s) source modifié(s) sans test modifié — test d'abord ?"
    fi
  fi
fi
```

- [ ] **Step 5: vérifier le vert**

Run: `bash tests/e2e.sh 2>&1 | tail -1` → `E2E: tout vert`.

- [ ] **Step 6: commit**

```bash
git add tests/e2e.sh skills/init/templates/check.sh.tmpl
git commit -m "feat(check): avis TDD — source modifié sans test modifié signalé"
```

---

### Task 4: Skill /tripwire:test-review

**Files:**
- Create: `skills/test-review/SKILL.md`
- Modify: `skills/gen-agents/templates/test-author.md.tmpl` (une ligne en fin de fichier)

**Interfaces:**
- Produces: skill invocable `/tripwire:test-review` ; grille en 6 points référencée par test-author.

- [ ] **Step 1: créer skills/test-review/SKILL.md avec exactement ce contenu**

```markdown
---
name: test-review
description: Use when auditing the QUALITY of tests (not whether they pass) — hollow assertions, happy-path-only coverage, mock-testing, implementation coupling, parallel-safety, lying names. Scope is a diff, a module/directory, or a file. Trigger on "/tripwire:test-review", "audite les tests", "ces tests valent quoi ?", "review qualité des tests".
---

# tripwire:test-review — audit sémantique des tests

Le pipeline vérifie que les tests passent ; ce skill juge s'ils **protègent**.
Lecture seule : les patchs sont proposés, jamais appliqués sans accord.

## Scope (demander si ambigu)

1. **Diff courant** (défaut) : `git diff HEAD --name-only` + `git diff --cached
   --name-only` → fichiers de test touchés ET code sous test touché.
2. **Module/dossier** : tous les tests du dossier donné + le code qu'ils couvrent.
3. **Fichier** : un fichier de test + son code sous test.

Toujours lire le **code sous test**, pas seulement le test : les points 2 et 4
de la grille sont invérifiables autrement.

## Grille d'audit (chaque finding : fichier:ligne + preuve + patch proposé)

1. **Assertions creuses** — toujours-vraies (`assert(true)`, comparaison d'une
   constante à elle-même), assertions absentes (le test appelle mais ne
   vérifie rien), assertion sur une valeur non influencée par le code testé.
2. **Happy-path only** — au regard de la logique du code sous test : bornes
   (0, -1, max, vide), chemins d'erreur, débordements, entrées malformées.
   Lister les cas limites RÉELS du code, pas une checklist générique.
3. **Tests de mocks** — le test vérifie que le mock/stub retourne ce qu'on lui
   a dit de retourner ; le comportement réel n'est jamais exercé.
4. **Couplage à l'implémentation** — le test casserait sur un refactor sans
   changement de comportement (ordre d'appels internes, détails privés).
5. **Parallel-safety / état global** — état partagé muté sans isolation
   (norme TDD du CLAUDE.md/VIBE.md cible si elle existe : la citer).
6. **Nommage menteur** — le nom du test promet plus que ce qu'il vérifie
   (`test_handles_all_errors` qui teste un seul code d'erreur).

## Sortie

Tableau des findings par sévérité :
- **Confiance** : le test donne une fausse assurance (creux, mock-testing) —
  à corriger avant de s'appuyer dessus.
- **Couverture** : cas limites manquants identifiés dans le code sous test.
- **Robustesse/style** : couplage, nommage, isolation.

Puis proposer d'appliquer les patchs (un par finding, prêts). Ne pas inventer
de problème : un scope propre = « rien à signaler », c'est un résultat valide.

## Hors périmètre

Le mutation testing outillé (cargo-mutants, mutmut…) est une suggestion à
mentionner quand la stack s'y prête, jamais exécuté par ce skill.
```

- [ ] **Step 2: référencer la grille dans test-author**

Ajouter à la FIN de `skills/gen-agents/templates/test-author.md.tmpl` :

```markdown

## Auto-audit avant livraison
Avant de livrer, passe tes tests à la grille de `/tripwire:test-review`
(assertions creuses, happy-path only, tests de mocks, couplage, parallel-safety,
nommage) et corrige ce que tu y trouves.
```

- [ ] **Step 3: valider**

Run: `bash tests/e2e.sh 2>&1 | tail -1` → `E2E: tout vert` (le check frontmatter de test-author doit rester vert).
Run: `./scripts/check.sh --fast --force 2>&1 | tail -1` → vert.

- [ ] **Step 4: commit**

```bash
git add skills/test-review/SKILL.md skills/gen-agents/templates/test-author.md.tmpl
git commit -m "feat(skill): /tripwire:test-review — audit sémantique des tests (grille 6 points)"
```

---

### Task 5: Câblage init (questions, placeholders, historique)

**Files:**
- Modify: `skills/init/SKILL.md`

**Interfaces:**
- Consumes: placeholders des Tasks 1-3.
- Produces: questions 8-9 d'init, défauts par stack, lignes de la table des placeholders, historique v0.9.0.

- [ ] **Step 1: questions Étape 2**

Après la question 7 (timeout), ajouter :

```markdown
8. **Ratchet de tests (optionnel)** — commande une-ligne qui imprime le nombre
   de tests (`{{TEST_COUNT_CMD}}`), ou « aucun » (ratchet inerte). Défauts :

   | Stack | TEST_COUNT_CMD | ASSERT_PATTERN |
   |---|---|---|
   | C host (harnais type KaSe) | `grep -rc 'TEST_ASSERT' test/ \| awk -F: '{s+=$2} END{print s+0}'` | `TEST_ASSERT` |
   | Rust | `grep -rc '#\[test\]' src/ \| awk -F: '{s+=$2} END{print s+0}'` | `assert!\|assert_eq!\|assert_ne!` |
   | Python | `grep -rc 'def test_' tests/ \| awk -F: '{s+=$2} END{print s+0}'` | `assert` |
   | Node / Go / autre | demander | demander |

   Mêmes contraintes que la commande fast (pas de `$(...)`, pas de `"`).
   Si activé : `.tripwire-testcount` est créé au premier check vert et doit
   être **committé** (comme `.tripwire-variant`) — baisser le ratchet = diff
   visible en review.
9. **Chemins de test** — dérivés de la question 3 ou demandés : patterns
   `case` (`{{TEST_PATH_PATTERNS}}`, ex. `*"/test/"*`), forme grep
   (`{{TEST_GREP}}`, ex. `^test/`) et forme grep des sources
   (`{{SRC_GREP}}`, ex. `^src/|^main/`). Vérifier que les chemins de test
   sont AUSSI dans `{{WATCHED_PATH_PATTERNS}}` (sinon la garde
   anti-affaiblissement ne voit jamais les fichiers de test).
```

- [ ] **Step 2: table des placeholders**

Ajouter les lignes :

```markdown
| `{{TEST_COUNT_CMD}}` | commande de comptage des tests (question 8) ; **vide** si aucun |
| `{{ASSERT_PATTERN}}` | regex grep -E des assertions de la stack (question 8) ; `assert` par défaut si ratchet actif sans mieux |
| `{{TEST_PATH_PATTERNS}}` | patterns `case` des fichiers de test (question 9) ; `*"/__jamais__/"*` si aucun |
| `{{TEST_GREP}}` | forme grep -E des chemins de test ; **vide** si aucun |
| `{{SRC_GREP}}` | forme grep -E des chemins source surveillés ; **vide** si aucun |
```

- [ ] **Step 3: historique des templates**

Ajouter après la ligne v0.8.0 :

```markdown
| v0.9.0 | qualité des tests — check.sh : ratchet (`TEST_COUNT_CMD` + `.tripwire-testcount` committé, strict au pre-push) + avis TDD (`SRC_GREP`/`TEST_GREP`) ; hooks post-edit : garde anti-affaiblissement (`TEST_PATH_PATTERNS`/`ASSERT_PATTERN`) ; pre-push : `TRIPWIRE_RATCHET_STRICT=1` ; nouveau skill test-review |
```

- [ ] **Step 4: valider + commit**

Run: `./scripts/check.sh --fast --force 2>&1 | tail -1` → vert.

```bash
git add skills/init/SKILL.md
git commit -m "docs(init): questions ratchet/chemins de test, placeholders qualité, historique v0.9.0"
```

---

### Task 6: README + dogfood

**Files:**
- Modify: `README.md`
- Modify: `scripts/check.sh`, `scripts/hooks/cc_post_edit.sh`, `scripts/hooks/pre-push` (régénération)
- Create: `.tripwire-testcount`

**Interfaces:**
- Consumes: tout ce qui précède.
- Produces: repo prêt pour la release v0.9.0.

- [ ] **Step 1: README — section et table**

Après la section « Gros projets », ajouter :

```markdown
## Qualité des tests

Vert ne veut pas dire protégé — trois gardes s'en occupent :

- **Ratchet de tests** : le nombre de tests (compté par `TEST_COUNT_CMD`) ne
  baisse jamais en silence. La référence vit dans `.tripwire-testcount`,
  **committé** : baisser le ratchet exige une ligne de diff visible en review.
  Baisse détectée → avertissement en local, **rouge au pre-push**.
- **Garde anti-affaiblissement** : une édition qui retire des assertions d'un
  fichier de test (vs HEAD) injecte un avertissement dans le contexte de
  l'agent — refactor légitime ou triche, il doit se positionner.
- **Avis TDD** : du source surveillé modifié sans aucun test modifié → une
  ligne d'avis avec le verdict du check.

Et pour ce que le mécanique ne voit pas : `/tripwire:test-review` audite la
qualité sémantique (assertions creuses, happy-path only, tests de mocks,
couplage, nommage menteur) avec patchs proposés.
```

Dans la table des skills, après la ligne `/tripwire:bisect` :

```markdown
| `/tripwire:test-review` | Audit sémantique des tests : creux, happy-path only, tests de mocks, couplage, parallel-safety, nommage — findings + patchs |
```

- [ ] **Step 2: dogfood — régénérer le scaffold tripwire (tampon v0.9.0)**

```bash
cd /home/mae/Documents/GitHub/tripwire
python3 - <<'EOF'
import pathlib
T = pathlib.Path('.')
def inst(name, subs, out, mode=0o755):
    s = (T/'skills/init/templates'/name).read_text()
    for k, v in subs.items():
        s = s.replace('{{'+k+'}}', v)
    assert '{{' not in s, name
    p = T/out; p.write_text(s); p.chmod(mode); print('✓', out)
inst('check.sh.tmpl', {
  'PROJECT_NAME':'tripwire','TRIPWIRE_VERSION':'v0.9.0',
  'VARIANTS_SPACE_SEPARATED':'','MODULE_FAST_ENTRIES':'',
  'FAST_CMD':'bash tests/lint.sh','VARIANT_BUILD_CMD':'bash tests/e2e.sh',
  'TEST_COUNT_CMD':"grep -c 'chk .' tests/e2e.sh",
  'SRC_GREP':'^skills/','TEST_GREP':'^tests/'}, 'scripts/check.sh')
inst('cc_post_edit.sh.tmpl', {
  'WATCHED_PATH_PATTERNS':'*"skills/"*|*"tests/"*|*".claude-plugin/"*',
  'TEST_PATH_PATTERNS':'*"tests/e2e.sh"*','ASSERT_PATTERN':'chk '}, 'scripts/hooks/cc_post_edit.sh')
s = (T/'skills/init/templates/pre-push.tmpl').read_text()
s = '\n'.join(l for l in s.split('\n') if '{{ENV_SETUP_BLOCK}}' not in l).replace('{{PROJECT_NAME}}','tripwire')
p = T/'scripts/hooks/pre-push'; p.write_text(s); p.chmod(0o755); print('✓ pre-push')
EOF
grep -rn '{{' scripts/ || echo "aucun résidu"
./scripts/check.sh --force   # full : bootstrap .tripwire-testcount + tout vert
cat .tripwire-testcount
```

Expected: full vert, `.tripwire-testcount` contient le nombre de `chk` d'e2e.

- [ ] **Step 3: validation croisée du dogfood**

```bash
sed -n '2p' scripts/check.sh                  # tampon v0.9.0
./scripts/check.sh --fast --force 2>&1 | grep -c "TDD:\|ratchet" || true   # silencieux si tree propre côté skills/
```

- [ ] **Step 4: commit + push**

```bash
git add README.md scripts/ .tripwire-testcount
git commit -m "feat: dogfood qualité des tests + README (ratchet, garde assertions, avis TDD, test-review)"
git push
```

---

## Self-review (fait à l'écriture)

- Couverture spec : pièce 1→T1, pièce 2→T2, pièce 3→T3, pièce 4→T4, init→T5, README/dogfood→T6. ✓
- Pas de placeholder de plan. Noms cohérents (`TEST_COUNT_CMD`, `.tripwire-testcount`, `TRIPWIRE_RATCHET_STRICT`, `SRC_GREP`/`TEST_GREP`, `TEST_PATH_PATTERNS`/`ASSERT_PATTERN`, `assertion(s) en moins`, `TDD:`, `ratchet`). ✓
- Pièges connus adressés : quotes dans TEST_COUNT_CMD (`'chk .'` évite le `"`), fast.sh cassé après bisect (restauré en tête du bloc ratchet), GITC réutilisé, nouveaux placeholders substitués dans TOUTES les instanciations e2e (T1 step 1 + T2 step 1). ✓
- Ordre des blocs e2e : bisect → ratchet → garde → avis TDD → « Rouge : casser fast » (chaque bloc laisse fast.sh vert et le tree géré). ✓
