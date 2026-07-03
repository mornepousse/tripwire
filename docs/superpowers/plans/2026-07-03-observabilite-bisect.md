# Observabilité & bisect — plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `check.sh` produit `last-fail.log` + `history.tsv` ; deux nouveaux skills (`status`, `bisect`) les consomment ; e2e prouve que check.sh est un oracle `git bisect` correct.

**Architecture:** Couche 1 = template `check.sh.tmpl` (capture d'échec sans double exécution via fichier tampon, append TSV des durées hors skips). Couche 2 = skills d'instructions (pas de code scaffoldé). Tout ce qui est shell est testé dans `tests/e2e.sh` AVANT implémentation.

**Tech Stack:** bash (templates sed-instanciés), git plumbing (`hash-object`, `bisect run`), skills markdown Claude Code/Vibe.

## Global Constraints

- Spec : `docs/superpowers/specs/2026-07-03-observabilite-bisect-design.md`.
- TDD obligatoire (CLAUDE.md) : assertion e2e rouge avant chaque comportement de template.
- Aucune double exécution des commandes de check (capture via fichier tampon).
- Les écritures d'observabilité ne bloquent jamais un check (`|| true`, `2>/dev/null`).
- Skips (déjà-vert) : ne loggent PAS dans history.tsv.
- Commits : `--no-gpg-sign` (carte GPG indisponible), messages Conventional Commits.
- Après chaque tâche : `./scripts/check.sh` doit être vert (`--force` si besoin après edits de templates — le hook PostToolUse lance déjà le fast).

---

### Task 1: last-fail.log dans check.sh.tmpl

**Files:**
- Modify: `tests/e2e.sh` (section « Rouge : casser fast » + section « Rouge : fast vert mais build cassé »)
- Modify: `skills/init/templates/check.sh.tmpl`

**Interfaces:**
- Produces: fichier `$GITDIR/tripwire/last-fail.log` — ligne 1 `# cmd: <commande>`, ligne 2 `# mode: <label>`, puis `tail -200` de la sortie ; message d'échec contenant `last-fail.log`. Consommé par Task 4 (status).

- [ ] **Step 1: assertions e2e (rouges)**

Dans `tests/e2e.sh`, remplacer la ligne qui casse fast (section « Rouge : casser fast ») :

```bash
printf '#!/usr/bin/env bash\nexit 1\n' > fast.sh
```

par :

```bash
printf '#!/usr/bin/env bash\necho BOOM\nexit 1\n' > fast.sh
```

Puis, juste après `chk "fast rouge -> rc 1" 1 $?`, ajouter :

```bash
[ -f .git/tripwire/last-fail.log ]; chk "last-fail.log créé sur rouge" 0 $?
grep -q '^# cmd: ./fast.sh' .git/tripwire/last-fail.log; chk "last-fail: en-tête cmd" 0 $?
grep -q 'BOOM' .git/tripwire/last-fail.log; chk "last-fail: sortie capturée" 0 $?
OUT="$(./scripts/check.sh --fast 2>&1)"
echo "$OUT" | grep -q "last-fail.log"; chk "message d'échec pointe le log" 0 $?
```

Et dans la section « Rouge : fast vert mais build cassé », après `chk "fast vert (build cassé)" 0 $?`, ajouter :

```bash
[ -f .git/tripwire/last-fail.log ]; chk "log conservé après un vert" 0 $?
```

- [ ] **Step 2: vérifier le rouge**

Run: `bash tests/e2e.sh 2>&1 | grep -E 'last-fail|pointe|conservé|E2E'`
Expected: 4-5 `✗`, `E2E: ROUGE`.

- [ ] **Step 3: implémentation dans check.sh.tmpl**

Après le bloc verrou (juste après `fi` du flock), ajouter :

```bash
# ---- Capture d'échec : la sortie du dernier rouge reste lisible sans re-run ----
OUTBUF="$GITDIR/tripwire/.out.$$"
trap 'rm -f "$OUTBUF"' EXIT
capture_fail() { # $1=label $2=commande affichée ; la sortie est déjà dans $OUTBUF
  {
    printf '# cmd: %s\n# mode: %s\n' "$2" "$1"
    tail -200 "$OUTBUF" 2>/dev/null
  } > "$GITDIR/tripwire/last-fail.log" 2>/dev/null || true
}
```

Dans `run_fast()`, remplacer :

```bash
  if ( eval "$FAST_RUN_CMD" ) >/dev/null 2>&1; then
    ok "$FAST_LABEL OK"
  else
    fail "$FAST_LABEL: échec (relance pour le détail: $FAST_RUN_CMD)"
    rc=1
  fi
```

par :

```bash
  if ( eval "$FAST_RUN_CMD" ) >"$OUTBUF" 2>&1; then
    ok "$FAST_LABEL OK"
  else
    capture_fail "$FAST_LABEL" "$FAST_RUN_CMD"
    fail "$FAST_LABEL: échec — détail: $GITDIR/tripwire/last-fail.log (ou relance: $FAST_RUN_CMD)"
    rc=1
  fi
```

Dans `build_variant()`, remplacer :

```bash
  if ( {{VARIANT_BUILD_CMD}} ) >/dev/null 2>&1; then
    ok "Build ${v:-complet} OK"
    return 0
  else
    fail "Build ${v:-complet}: échec (relance pour le détail: {{VARIANT_BUILD_CMD}})"
    return 1
  fi
```

par :

```bash
  if ( {{VARIANT_BUILD_CMD}} ) >"$OUTBUF" 2>&1; then
    ok "Build ${v:-complet} OK"
    return 0
  else
    capture_fail "Build ${v:-complet}" "{{VARIANT_BUILD_CMD}}"
    fail "Build ${v:-complet}: échec — détail: $GITDIR/tripwire/last-fail.log (ou relance: {{VARIANT_BUILD_CMD}})"
    return 1
  fi
```

- [ ] **Step 4: vérifier le vert**

Run: `bash tests/e2e.sh 2>&1 | tail -1`
Expected: `E2E: tout vert`.

- [ ] **Step 5: commit**

```bash
git add tests/e2e.sh skills/init/templates/check.sh.tmpl
git commit --no-gpg-sign -m "feat(check): last-fail.log — le détail du rouge lisible sans re-run"
```

---

### Task 2: history.tsv dans check.sh.tmpl

**Files:**
- Modify: `tests/e2e.sh` (section « Options gros projets », état vert)
- Modify: `skills/init/templates/check.sh.tmpl`

**Interfaces:**
- Consumes: `KEY` (clé de mode, déjà définie), `$GITDIR/tripwire/`.
- Produces: `$GITDIR/tripwire/history.tsv` — lignes `epoch<TAB>KEY<TAB>durée_s<TAB>rc`, rotation 500 lignes, skips exclus. Consommé par Task 4 (status).

- [ ] **Step 1: assertions e2e (rouges)**

Dans la section « Options gros projets », après `chk "état modifié -> re-run" 0 $?`, ajouter :

```bash
# history.tsv : chaque run réel logge une ligne TSV ; les skips non
N0="$(wc -l < .git/tripwire/history.tsv 2>/dev/null || echo 0)"
./scripts/check.sh --fast --force >/dev/null 2>&1
N1="$(wc -l < .git/tripwire/history.tsv 2>/dev/null || echo 0)"
chk "history: run réel loggé" "$((N0+1))" "$N1"
./scripts/check.sh --fast >/dev/null 2>&1     # état inchangé -> skip
N2="$(wc -l < .git/tripwire/history.tsv 2>/dev/null || echo 0)"
chk "history: skip non loggé" "$N1" "$N2"
awk -F'\t' 'NF!=4{bad=1} END{exit bad}' .git/tripwire/history.tsv
chk "history: 4 champs TSV" 0 $?
```

- [ ] **Step 2: vérifier le rouge**

Run: `bash tests/e2e.sh 2>&1 | grep -E 'history|E2E'`
Expected: `✗ history: run réel loggé …`, `E2E: ROUGE`.

- [ ] **Step 3: implémentation**

Dans check.sh.tmpl, juste après le bloc skip-si-vert (après son `fi`), ajouter :

```bash
T_START=$SECONDS
```

Puis dans le bloc final, remplacer :

```bash
if [ "$rc" -eq 0 ]; then
  printf '%s\n' "$FP" > "$STAMP" 2>/dev/null || true
  ok "check.sh: tout vert"
else
  fail "check.sh: ROUGE"
fi
```

par :

```bash
if [ "$rc" -eq 0 ]; then
  printf '%s\n' "$FP" > "$STAMP" 2>/dev/null || true
  ok "check.sh: tout vert"
else
  fail "check.sh: ROUGE"
fi
# Historique des durées (jamais bloquant) — les skips sortent avant ce point.
{
  HIST="$GITDIR/tripwire/history.tsv"
  printf '%s\t%s\t%s\t%s\n' "$(date +%s)" "$KEY" "$((SECONDS - T_START))" "$rc" >> "$HIST"
  if [ "$(wc -l < "$HIST")" -gt 500 ]; then
    tail -500 "$HIST" > "$HIST.$$" && mv "$HIST.$$" "$HIST"
  fi
} 2>/dev/null || true
```

- [ ] **Step 4: vérifier le vert**

Run: `bash tests/e2e.sh 2>&1 | tail -1`
Expected: `E2E: tout vert`.

- [ ] **Step 5: commit**

```bash
git add tests/e2e.sh skills/init/templates/check.sh.tmpl
git commit --no-gpg-sign -m "feat(check): history.tsv — durées et verdicts par mode (skips exclus)"
```

---

### Task 3: e2e — check.sh est un oracle git-bisect correct

**Files:**
- Modify: `tests/e2e.sh` (fin de la section mono, APRÈS le bloc « Templates CI », AVANT « Rouge : casser fast »)

**Interfaces:**
- Consumes: `scripts/check.sh` instancié du repo jouet mono (rc 0 vert / 1 rouge).
- Produces: garantie testée pour Task 5 (le skill bisect s'appuie sur ces codes de sortie).

- [ ] **Step 1: assertion e2e**

Après le bloc « Templates CI » (après `chk "templates CI instanciés …"`), ajouter :

```bash
# ===== Oracle git-bisect : check.sh rend 0/1, bisect run localise le fautif =====
GITC() { git -c user.email=e2e@toy -c user.name=e2e "$@"; }
git add -A >/dev/null 2>&1 && GITC commit -qm "c1 base verte"
echo 2 > src/f2 && git add -A && GITC commit -qm "c2 verte"
echo 3 > src/f3 && git add -A && GITC commit -qm "c3 verte"
printf '#!/usr/bin/env bash\nexit 1\n' > fast.sh && git add -A && GITC commit -qm "c4 CASSE"
echo 5 > src/f5 && git add -A && GITC commit -qm "c5 toujours rouge"
BAD_EXPECTED="$(git rev-parse HEAD~1)"
git bisect start HEAD HEAD~4 >/dev/null 2>&1
git bisect run ./scripts/check.sh --fast >/dev/null 2>&1
FOUND="$(git rev-parse refs/bisect/bad 2>/dev/null)"
git bisect reset >/dev/null 2>&1
chk "bisect: commit fautif localisé" "$BAD_EXPECTED" "$FOUND"
```

Note : après ce bloc, `fast.sh` est cassé à HEAD (c5) — la section « Rouge :
casser fast » qui suit le casse elle-même, la continuité est assurée.

- [ ] **Step 2: run**

Run: `bash tests/e2e.sh 2>&1 | grep -E 'bisect|E2E'`
Expected: `✓ bisect: commit fautif localisé`, `E2E: tout vert`. (Si rouge :
diagnostiquer — c'est précisément le contrat qu'on veut garantir.)

- [ ] **Step 3: commit**

```bash
git add tests/e2e.sh
git commit --no-gpg-sign -m "test(e2e): check.sh est un oracle git-bisect correct"
```

---

### Task 4: skill /tripwire:status

**Files:**
- Create: `skills/status/SKILL.md`

**Interfaces:**
- Consumes: tampon `# tripwire-template:` (ligne 2 de scripts/check.sh), `.git/tripwire/{green-*,last-fail.log,history.tsv}` (Tasks 1-2), patterns du `case` de `scripts/hooks/*post_edit.sh`.
- Produces: skill invocable `/tripwire:status`.

- [ ] **Step 1: écrire le skill**

```markdown
---
name: status
description: Use when checking the health of a tripwire-equipped project — scaffold up to date? git/platform hooks active? last check green and when? fast-phase duration drift? watched-path blind spots? Trigger on "/tripwire:status", "état du tripwire", "diagnostic tripwire", "le tripwire est à jour ?".
---

# tripwire:status — diagnostic one-shot

Rapport compact sur l'état du pipeline anti-régression du repo courant.
Lecture seule : ce skill ne modifie RIEN.

## Plateforme

- `CLAUDE_PROJECT_DIR` défini → hooks dans `.claude/settings.json`, préfixe `cc_`
- sinon `VIBE_PROJECT_DIR` → `.vibe/config.json`, préfixe `vibe_`

## Sections du rapport (dans l'ordre)

### 1. Pipeline
```bash
test -x scripts/check.sh || { echo "pas de tripwire — proposer /tripwire:init"; }
sed -n '2p' scripts/check.sh          # tampon "# tripwire-template: vX.Y.Z" (absent = pré-v0.5.0)
```
Comparer le tampon à la version du plugin (`version` de `.claude-plugin/plugin.json`,
deux niveaux au-dessus du dossier de cette skill). En retard → citer les
changements manqués via « Historique des templates » du skill init et
recommander `/tripwire:init`.

### 2. Hooks
```bash
git config --get core.hooksPath       # attendu: scripts/hooks (sinon: lancer scripts/install-hooks.sh)
ls scripts/hooks/                     # pre-push + hooks de plateforme présents ?
grep -o 'scripts/hooks/[a-z_]*\.sh' .claude/settings.json 2>/dev/null || true   # (ou .vibe/config.json)
```

### 3. État
```bash
GD="$(git rev-parse --git-dir)"
ls -lt "$GD/tripwire/" 2>/dev/null | head -12     # stamps green-* (fraîcheur mtime)
head -2 "$GD/tripwire/last-fail.log" 2>/dev/null  # dernier échec: commande + mode
cat .tripwire-variant 2>/dev/null                 # variante courante (multi)
```
Un stamp `green-full` plus récent que le dernier échec = le rouge a été résorbé.

### 4. Tendance (history.tsv : epoch<TAB>mode<TAB>durée_s<TAB>rc)
```bash
awk -F'\t' '$2=="fast"{d[++n]=$3} END{if(n){asort(d); print "médiane fast:", d[int((n+1)/2)] "s, dernière:", d[n] "s, runs:", n}}' "$GD/tripwire/history.tsv" 2>/dev/null
```
(gawk absent : trier avec `sort -n` en pipe.) Signaler une dérive si la
dernière durée > 2× la médiane ou > `TRIPWIRE_FAST_BUDGET` (défaut 30).

### 5. Dérive de surveillance (heuristique — « à vérifier », pas verdict)
```bash
git log --since='30 days ago' --name-only --pretty=format: 2>/dev/null | grep -v '^$' \
  | cut -d/ -f1 | sort -u        # dossiers actifs (repli: git ls-files si repo < 30 j)
grep -o 'case "\$FP" in' -A2 scripts/hooks/*post_edit.sh | sed -n '2p'   # patterns surveillés
```
Comparer : tout dossier actif contenant du code, absent des patterns, hors
`docs/`, fichiers racine, `scripts/` et dossiers de config (`.claude/`,
`.vibe/`, `.github/`) → le lister comme angle mort potentiel avec la ligne
`case` corrigée à proposer.

## Sortie

Un tableau (section → état ✓/⚠/✗ → détail court) suivi de 0 à 3 **actions
recommandées** concrètes (commande exacte ou skill à lancer). Ne pas inventer
de problème : sections vides = « rien à signaler ».
```

- [ ] **Step 2: valider**

Run: `./scripts/check.sh --fast --force 2>&1 | tail -2` (lint verra le nouveau .md ignoré — vert attendu)
Puis auto-test : dérouler le skill sur le repo tripwire lui-même et vérifier
que les 5 sections produisent du contenu cohérent (tampon v0.7.0 vs plugin,
hooks OK, stamps présents).

- [ ] **Step 3: commit**

```bash
git add skills/status/SKILL.md
git commit --no-gpg-sign -m "feat(skill): /tripwire:status — diagnostic one-shot (pipeline, hooks, état, tendance, angles morts)"
```

---

### Task 5: skill /tripwire:bisect

**Files:**
- Create: `skills/bisect/SKILL.md`

**Interfaces:**
- Consumes: contrat d'oracle garanti par Task 3 (`check.sh` → 0 vert / 1 rouge).
- Produces: skill invocable `/tripwire:bisect`.

- [ ] **Step 1: écrire le skill**

```markdown
---
name: bisect
description: Use when a tripwire check turned red and nobody knows which commit broke it — drives git bisect with scripts/check.sh as the oracle. Trigger on "/tripwire:bisect", "depuis quand c'est rouge", "quel commit a cassé", "bisect la régression".
---

# tripwire:bisect — localiser le commit fautif

`scripts/check.sh` rend 0 (vert) / 1 (rouge) : c'est exactement le contrat de
`git bisect run`. Ce skill automatise la chasse.

## Pré-requis (vérifier dans l'ordre, STOP si échec)

1. `scripts/check.sh` existe et est exécutable — sinon proposer `/tripwire:init`.
2. Le rouge est **reproductible maintenant** :
   `./scripts/check.sh --fast --force` (ou `--variant <v>` si le rouge est là).
   Vert → rien à bisecter, pointer `.git/tripwire/last-fail.log` pour le
   dernier échec historique.
3. Working tree propre (`git status --porcelain` vide). Sale → proposer
   `git stash` (et le rappeler à la fin) ou abandonner.

## Choix du « bon » connu (premier qui marche)

1. Commit/tag donné par l'utilisateur.
2. Dernier tag : `git describe --tags --abbrev=0` — le vérifier :
   `git stash -q 2>/dev/null; git checkout -q <tag> && ./scripts/check.sh --fast --force` → doit être vert (sinon remonter d'un tag).
   Revenir : `git checkout -q -` (et dé-stash).
3. Sinon AskUserQuestion avec `git log --oneline -15`.

## Exécution

```bash
git bisect start HEAD <good>
git bisect run ./scripts/check.sh --fast        # ou --variant <v> ; PAS --force :
                                                # le skip-si-vert accélère les états déjà connus
BAD="$(git rev-parse refs/bisect/bad)"
git bisect reset
```

**TOUJOURS `git bisect reset`**, même sur interruption ou échec — ne jamais
laisser le repo en état bisect.

## Rapport

- Le commit fautif : `git show --stat <BAD>` (hash, auteur, date, fichiers).
- Le lien avec l'échec : `head -2 .git/tripwire/last-fail.log` (commande qui casse).
- Proposer la suite : lire le diff complet, ou `git revert <BAD>`, ou corriger.
- Si un stash a été fait au début : le rappeler (`git stash pop`).

## Cas limites

- Bisect > ~12 étapes (gros historique) : prévenir de la durée estimée
  (étapes × durée de la phase fast) avant de lancer.
- `git bisect run` s'arrête sur un code ≥ 128 ou 125 : check.sh n'en émet pas
  (0/1/2) ; le 2 (mauvais usage) ferait échouer le bisect proprement.
- Le commit fautif touche check.sh lui-même : le signaler explicitement.
```

- [ ] **Step 2: valider**

Run: `./scripts/check.sh --fast --force 2>&1 | tail -2`
Expected: vert. (Le contrat d'oracle est déjà couvert par l'assertion e2e de Task 3.)

- [ ] **Step 3: commit**

```bash
git add skills/bisect/SKILL.md
git commit --no-gpg-sign -m "feat(skill): /tripwire:bisect — git bisect piloté par check.sh"
```

---

### Task 6: intégration — historique templates, README, dogfood

**Files:**
- Modify: `skills/init/SKILL.md` (table « Historique des templates »)
- Modify: `README.md` (table des skills + section Gros projets)
- Modify: `scripts/check.sh` (régénération dogfood, tampon v0.7.0)

**Interfaces:**
- Consumes: tout ce qui précède.
- Produces: repo prêt pour `/tripwire:release` v0.7.0.

- [ ] **Step 1: historique des templates**

Dans `skills/init/SKILL.md`, ajouter à la table « Historique des templates » :

```markdown
| v0.7.0 | check.sh : `last-fail.log` (détail du rouge sans re-run) + `history.tsv` (durées par mode) ; nouveaux skills status et bisect (rien à re-scaffolder, mais le check.sh mérite la mise à jour) |
```

- [ ] **Step 2: README**

Dans la table des skills, ajouter après la ligne `/tripwire:release` :

```markdown
| `/tripwire:status` | Diagnostic one-shot : scaffold à jour ? hooks actifs ? dernier vert/rouge ? dérive des durées ? angles morts de surveillance ? |
| `/tripwire:bisect` | Localise le commit qui a cassé le check : `git bisect run` avec check.sh comme oracle |
```

Dans la section « Gros projets », ajouter à la fin de la liste à puces :

```markdown
- **Échec lisible sans re-run** : la sortie du dernier rouge est capturée dans
  `.git/tripwire/last-fail.log` (l'assistant la lit au lieu de relancer la
  commande) ; chaque passage réel logge sa durée dans `history.tsv` —
  `/tripwire:status` en tire la tendance.
```

- [ ] **Step 3: dogfood — régénérer scripts/check.sh**

```bash
sed -e 's|{{PROJECT_NAME}}|tripwire|g' \
    -e 's|{{TRIPWIRE_VERSION}}|v0.7.0|g' \
    -e 's|{{VARIANTS_SPACE_SEPARATED}}||g' \
    -e 's|{{MODULE_FAST_ENTRIES}}||g' \
    -e 's|{{FAST_CMD}}|bash tests/lint.sh|g' \
    -e 's|{{VARIANT_BUILD_CMD}}|bash tests/e2e.sh|g' \
    skills/init/templates/check.sh.tmpl > scripts/check.sh
chmod +x scripts/check.sh
grep -rn '{{' scripts/ || echo OK
```

- [ ] **Step 4: validation complète + dogfood réel**

```bash
./scripts/check.sh --force            # full vert
bash -c 'exit 1'                      # rien — puis test réel du last-fail :
sed -i 's/^exit "\$rc"$/exit "$rc"/' scripts/check.sh   # no-op, juste pour dater
./scripts/check.sh --fast 2>&1 | tail -2                 # vert (état modifié par le no-op ? sinon --force)
```
Expected: full vert ; `.git/tripwire/history.tsv` existe et grossit.

- [ ] **Step 5: commit + push**

```bash
git add -A
git commit --no-gpg-sign -m "feat: observabilité (last-fail.log, history.tsv) + skills status/bisect"
git push
```

---

## Self-review (fait à l'écriture)

- Couverture spec : 1.1→Task 1, 1.2→Task 2, 2.1→Task 4, 2.2→Task 5, e2e oracle→Task 3, impacts→Task 6. ✓
- Pas de placeholder. Types/chemins cohérents (`$GITDIR/tripwire/*`, `KEY`, codes 0/1/2). ✓
- Interaction connue : la section rouge d'e2e suit le bloc bisect qui laisse fast.sh cassé — documenté dans Task 3, la section rouge le recasse elle-même (idempotent). ✓
