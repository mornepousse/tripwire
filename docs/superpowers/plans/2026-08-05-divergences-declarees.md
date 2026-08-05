# Divergences déclarées — plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Un écart assumé au scaffold standard, déclaré dans `.tripwire-divergences`, ne peut plus disparaître en silence — sa perte rend `check.sh` rouge.

**Architecture:** Une fonction `check_divergences()` dans le template `check.sh`, appelée sans condition avant `run_fast` (donc dans tous les modes). Elle lit un TSV committé et vérifie par `grep -qF` que chaque motif déclaré est toujours présent dans son fichier hôte. Le garde-fou vit dans l'oracle, pas dans un skill : c'est ce qui le rend inévitable, y compris pour un `cp` à la main.

**Tech Stack:** bash 4+, `grep -F`, `git`. Aucune dépendance nouvelle (`python3` déjà requis par les hooks n'est pas utilisé ici).

## Global Constraints

- Spec de référence : `docs/superpowers/specs/2026-08-05-divergences-declarees-design.md`.
- **Norme TDD du projet** (CLAUDE.md) : toute nouvelle logique de template — assertion e2e écrite **d'abord** dans `tests/e2e.sh`, **rouge avant** l'implémentation, verte après. Aucune exception.
- Nom du fichier, exact : `.tripwire-divergences` (racine du repo cible, committé).
- Format, exact : TSV `fichier<TAB>motif<TAB>pourquoi`. Lignes vides et lignes commençant par `#` ignorées. Troisième champ jamais interprété.
- Comparaison du motif : **chaîne littérale** (`grep -qF --`), jamais regex.
- Verdict : **rouge dur** (`rc=1`), jamais un simple avis.
- Fichier absent ou vide → **inerte et silencieux** (adoption progressive).
- Style des messages : réutiliser les helpers existants `fail`/`ok`/`info` du template, pas de `echo` colorisé à la main.
- Ratchet : `.tripwire-testcount` passe de **71 à 83** (12 assertions ajoutées). Toute autre valeur finale est un bug du plan.
- Jamais de signature GPG : `git commit --no-gpg-sign`.

**Deux arbitrages pris avant exécution (2026-08-05), qui font loi sur la grille de revue :**

- **La duplication de `check_divergences()` entre `skills/init/templates/check.sh.tmpl` et `scripts/check.sh` est voulue et structurelle.** Un `check.sh` scaffoldé est copié dans d'autres repos : il ne peut rien sourcer du plugin, il doit être autonome. La duplication scaffold ↔ dogfood est inhérente au produit. Elle est documentée par un commentaire dans les deux fichiers. Ce n'est pas un défaut à corriger.
- **Les assertions de la tâche 3 sont vertes dès leur écriture, et c'est correct.** Elles sont rouges contre le code d'avant la tâche 1 ; elles ne passent immédiatement que parce qu'on les écrit après. C'est une couverture de non-régression par un autre point d'entrée (le hook Stop), pas une tautologie.

---

### Task 1 : L'assertion — cas inerte, cas vert, cas rouge

**Files:**
- Modify: `tests/e2e.sh` (nouvelle section, à insérer après le bloc SessionStart et **avant** la section « Ratchet de tests » — à cet endroit `fast.sh` et `build.sh` sont encore verts)
- Modify: `skills/init/templates/check.sh.tmpl` (nouvelle fonction + un appel)

**Interfaces:**
- Consomme : les helpers `fail`/`ok`/`info` (`check.sh.tmpl:44-47`) et la variable `rc` du corps principal (`check.sh.tmpl:150`).
- Produit : la fonction `check_divergences()`, sans argument, `return 0` si tout va bien, `return 1` sinon. Les tâches 2 et 3 l'étendent et s'appuient sur son nom exact.

- [ ] **Step 1: Écrire les assertions qui échouent**

Insérer dans `tests/e2e.sh`, juste avant la ligne `# ===== Ratchet de tests =====` :

```bash
# ===== Divergences déclarées =====
# La perte d'un écart assumé doit être un verdict machine, pas une relecture.
rm -f .tripwire-divergences
./scripts/check.sh --fast --force >/dev/null 2>&1
chk "divergences: fiche absente -> inerte" 0 $?
printf '# fichier\tmotif\tpourquoi\n\n' > .tripwire-divergences
./scripts/check.sh --fast --force >/dev/null 2>&1
chk "divergences: fiche sans ligne utile -> vert" 0 $?
printf 'scripts/hooks/cc_stop.sh\t--fast\tgarde-fou leger: le Stop ne lance que la phase rapide\n' > .tripwire-divergences
./scripts/check.sh --fast --force >/dev/null 2>&1
chk "divergences: motif présent -> vert" 0 $?
cp scripts/hooks/cc_stop.sh "$TMP/cc_stop.bak"
printf '#!/usr/bin/env bash\nexit 0\n' > scripts/hooks/cc_stop.sh   # écrasement: le motif disparaît
OUT="$(./scripts/check.sh --fast --force 2>&1)"
chk "divergences: motif perdu -> rouge" 1 $?
echo "$OUT" | grep -q "divergence perdue"
chk "divergences: message cite la perte" 0 $?
echo "$OUT" | grep -q "garde-fou leger"
chk "divergences: message cite le pourquoi" 0 $?
cp "$TMP/cc_stop.bak" scripts/hooks/cc_stop.sh && chmod +x scripts/hooks/cc_stop.sh
rm -f .tripwire-divergences
```

- [ ] **Step 2: Lancer pour vérifier que c'est rouge**

Run: `bash tests/e2e.sh 2>&1 | grep divergences`
Expected: les trois assertions « vert » passent par accident (rien ne les vérifie encore), mais `divergences: motif perdu -> rouge` **ÉCHOUE** (`want 1, got 0`) ainsi que les deux assertions de message. `bash tests/e2e.sh; echo $?` renvoie 1.

- [ ] **Step 3: Écrire l'implémentation minimale**

Dans `skills/init/templates/check.sh.tmpl`, insérer la fonction juste avant le commentaire `# ---- Phase rapide` :

```bash
# ---- Divergences déclarées : un écart assumé ne disparaît pas en silence ----
# .tripwire-divergences (committé), TSV : fichier<TAB>motif<TAB>pourquoi
# Absent/vide -> inerte. Motif comparé en chaîne littérale, jamais en regex.
check_divergences() {
  [ -f .tripwire-divergences ] || return 0
  local rc=0 n=0 f m w
  while IFS=$'\t' read -r f m w || [ -n "$f" ]; do
    n=$((n + 1))
    case "$f" in ''|'#'*) continue ;; esac
    if [ ! -f "$f" ]; then
      fail "divergence perdue : $f n'existe plus (motif « $m »)"
      [ -n "$w" ] && echo "  motif déclaré : $w" >&2
      rc=1; continue
    fi
    if ! grep -qF -- "$m" "$f"; then
      fail "divergence perdue : $f ne contient plus « $m »"
      [ -n "$w" ] && echo "  motif déclaré : $w" >&2
      echo "  → rétablir la divergence, ou retirer sa ligne de .tripwire-divergences" >&2
      echo "    si l'abandon est voulu (le retrait part dans le diff, il sera vu en review)." >&2
      rc=1
    fi
  done < .tripwire-divergences
  return "$rc"
}
```

Puis, dans le corps principal, transformer :

```bash
rc=0
run_fast || rc=1
```

en :

```bash
rc=0
check_divergences || rc=1
run_fast || rc=1
```

- [ ] **Step 4: Lancer pour vérifier que c'est vert**

Run: `./scripts/check.sh --force`
Expected: `✓ check.sh: tout vert`. Le ratchet signale `77 tests vs 71 attendus` — normal, il monte.

- [ ] **Step 5: Committer**

```bash
echo 77 > .tripwire-testcount
git add tests/e2e.sh skills/init/templates/check.sh.tmpl .tripwire-testcount
git commit --no-gpg-sign -m "feat(check): assertion de divergences déclarées (inerte/vert/rouge)

Un écart assumé au scaffold, déclaré dans .tripwire-divergences, rend le check
rouge s'il disparaît. Ratchet 71 -> 77."
```

---

### Task 2 : Cas limites — fichier hôte disparu, ligne malformée, motif littéral

**Files:**
- Modify: `tests/e2e.sh` (compléter la section « Divergences déclarées »)
- Modify: `skills/init/templates/check.sh.tmpl` (fonction `check_divergences`)

**Interfaces:**
- Consomme : `check_divergences()` de la tâche 1, dans son état exact.
- Produit : la même fonction, avec la détection de ligne malformée. Aucun changement de signature.

- [ ] **Step 1: Écrire les assertions qui échouent**

Ajouter à la fin de la section « Divergences déclarées », avant la ligne `rm -f .tripwire-divergences` finale :

```bash
printf 'scripts/hooks/absent.sh\tX\tfichier hote disparu\n' > .tripwire-divergences
./scripts/check.sh --fast --force >/dev/null 2>&1
chk "divergences: fichier hôte absent -> rouge" 1 $?
printf 'un-seul-champ\n' > .tripwire-divergences
OUT="$(./scripts/check.sh --fast --force 2>&1)"
chk "divergences: ligne malformée -> rouge" 1 $?
echo "$OUT" | grep -q "ligne 1"
chk "divergences: malformée cite le numéro de ligne" 0 $?
# Motif à caractères regex : en regex, ALL_VARIANTS[@] matcherait « ALL_VARIANTS@ »,
# chaîne absente du fichier. Vert ici => la comparaison est bien littérale.
printf 'scripts/check.sh\tALL_VARIANTS[@]\tpreuve que le motif est compare en chaine litterale\n' > .tripwire-divergences
./scripts/check.sh --fast --force >/dev/null 2>&1
chk "divergences: motif littéral (-F) -> vert" 0 $?
```

- [ ] **Step 2: Lancer pour vérifier que c'est rouge**

Run: `bash tests/e2e.sh 2>&1 | grep divergences`
Expected: `divergences: ligne malformée -> rouge` **ÉCHOUE** (`want 1, got 0`) et `divergences: malformée cite le numéro de ligne` **ÉCHOUE**. Les deux autres passent déjà (le fichier hôte absent est couvert par la tâche 1, le motif littéral aussi).

- [ ] **Step 3: Écrire l'implémentation minimale**

Dans `check_divergences`, insérer la garde de ligne malformée entre le `case` et le test d'existence du fichier :

```bash
    case "$f" in ''|'#'*) continue ;; esac
    if [ -z "$m" ]; then
      fail "divergence ligne $n : ligne malformée (attendu: fichier<TAB>motif<TAB>pourquoi)"
      rc=1; continue
    fi
    if [ ! -f "$f" ]; then
```

- [ ] **Step 4: Lancer pour vérifier que c'est vert**

Run: `./scripts/check.sh --force`
Expected: `✓ check.sh: tout vert`, ratchet `81 tests vs 77 attendus`.

- [ ] **Step 5: Committer**

```bash
echo 81 > .tripwire-testcount
git add tests/e2e.sh skills/init/templates/check.sh.tmpl .tripwire-testcount
git commit --no-gpg-sign -m "feat(check): divergences — ligne malformée rouge, motif littéral prouvé

Une fiche illisible ne se dégrade pas en fiche inerte. Le motif ALL_VARIANTS[@]
discrimine le grep -F du grep regex. Ratchet 77 -> 81."
```

---

### Task 3 : Parité hooks — le Stop mord sur une divergence perdue

**Files:**
- Modify: `tests/e2e.sh` (compléter la section « Divergences déclarées »)

**Interfaces:**
- Consomme : `check_divergences()` tel que laissé par la tâche 2, et le hook `scripts/hooks/cc_stop.sh` instancié en tête d'e2e (`tests/e2e.sh:36`).
- Produit : aucune interface — c'est une tâche de couverture. Aucun code de production ne change.

Cette tâche rejoue l'incident du 2026-08-05 : un hook écrasé, et c'est un *autre* garde-fou qui doit mordre. Elle ne demande aucune implémentation — si elle échoue, c'est que les tâches 1-2 sont incomplètes, pas qu'il faut ajouter du code.

- [ ] **Step 1: Écrire les assertions**

Ajouter à la fin de la section, avant le `rm -f .tripwire-divergences` final :

```bash
printf 'scripts/hooks/cc_post_edit.sh\t*"/test/"*\tchemins de test surveilles par la garde anti-affaiblissement\n' > .tripwire-divergences
./scripts/check.sh --fast --force >/dev/null 2>&1
chk "divergences: motif présent (post-edit) -> vert" 0 $?
cp scripts/hooks/cc_post_edit.sh "$TMP/pe.bak"
printf '#!/usr/bin/env bash\nexit 0\n' > scripts/hooks/cc_post_edit.sh   # rejoue l'écrasement du 2026-08-05
scripts/hooks/cc_stop.sh </dev/null >/dev/null 2>&1
chk "divergences: hook Stop mord sur divergence perdue -> rc 2" 2 $?
cp "$TMP/pe.bak" scripts/hooks/cc_post_edit.sh && chmod +x scripts/hooks/cc_post_edit.sh
rm -f .tripwire-divergences "$TMP/cc_stop.bak" "$TMP/pe.bak"   # le repo jouet repart propre
```

Les deux `.bak` vivent dans le repo jouet : les laisser en fait des fichiers non
suivis, qui entrent dans l'empreinte du skip-si-déjà-vert et polluent les
sections suivantes. Ce `rm -f` remplace le `rm -f .tripwire-divergences` final
posé à la tâche 1 — il n'y en a qu'un, à la toute fin de la section.

- [ ] **Step 2: Lancer et constater**

Run: `bash tests/e2e.sh 2>&1 | grep divergences`
Expected: les deux assertions **PASSENT** immédiatement — c'est le résultat correct, pas un test creux. Ces assertions seraient rouges contre le code d'avant la tâche 1 (sans `check_divergences`, le hook Stop sort en 0 au lieu de 2) ; elles passent ici parce qu'on les écrit après. Leur rôle est la non-régression par un autre point d'entrée : elles interdisent qu'une refonte future des hooks fasse sauter la barrière sans que personne le voie.

Si `hook Stop mord` échoue avec `got 0`, c'est que `check_divergences` n'est pas appelée dans le mode `--fast` — revenir sur la tâche 1, étape 3.

- [ ] **Step 3: Vérifier le total**

Run: `./scripts/check.sh --force`
Expected: `✓ check.sh: tout vert`, ratchet `83 tests vs 81 attendus`.

- [ ] **Step 4: Committer**

```bash
echo 83 > .tripwire-testcount
git add tests/e2e.sh .tripwire-testcount
git commit --no-gpg-sign -m "test(e2e): le hook Stop mord sur une divergence perdue

Rejoue l'incident du 2026-08-05 : un hook écrasé, un autre garde-fou qui mord.
Ratchet 81 -> 83."
```

---

### Task 4 : Dogfood — l'assertion dans le check.sh du plugin

**Files:**
- Modify: `scripts/check.sh` (le check du repo tripwire lui-même)

**Interfaces:**
- Consomme : la fonction `check_divergences()` telle qu'écrite dans `skills/init/templates/check.sh.tmpl` après la tâche 2 — copie **à l'identique**, c'est la cohérence scaffold ↔ plugin qu'on maintient.
- Produit : rien de consommé ailleurs.

CLAUDE.md pose que « le plugin mange sa propre nourriture ». Le repo tripwire n'a aujourd'hui aucune divergence : la fiche restera absente et l'assertion inerte. On la porte quand même, sinon le dogfood ment.

- [ ] **Step 1: Porter la fonction**

Copier la fonction `check_divergences()` de `skills/init/templates/check.sh.tmpl` dans `scripts/check.sh`, au même emplacement relatif (juste avant la phase rapide), et ajouter l'appel `check_divergences || rc=1` avant `run_fast || rc=1`.

La duplication est voulue (cf. arbitrages des contraintes globales). La documenter par un commentaire **au-dessus de la fonction dans les deux fichiers**, texte exact :

```bash
# NOTE: cette fonction est dupliquée entre skills/init/templates/check.sh.tmpl
# et scripts/check.sh (dogfood). Duplication assumée : un check.sh scaffoldé est
# copié dans d'autres repos, il doit être autonome et ne rien sourcer du plugin.
# Toute correction ici se reporte à l'identique dans l'autre fichier.
```

- [ ] **Step 2: Vérifier l'inertie**

Run: `test -f .tripwire-divergences && echo "fiche présente" || echo "fiche absente (attendu)"`
Expected: `fiche absente (attendu)`

- [ ] **Step 3: Vérifier que le check reste vert**

Run: `./scripts/check.sh --force`
Expected: `✓ check.sh: tout vert`. Le ratchet ne bouge pas (aucune assertion e2e ajoutée).

- [ ] **Step 4: Vérifier que l'assertion mord aussi ici**

```bash
printf 'scripts/check.sh\tje-nexiste-pas\tsonde temporaire de dogfood\n' > .tripwire-divergences
./scripts/check.sh --fast --force; echo "rc=$?"    # attendu: rouge, rc=1
rm -f .tripwire-divergences
./scripts/check.sh --fast --force; echo "rc=$?"    # attendu: vert, rc=0
```
Expected: rc=1 puis rc=0. Ne PAS committer `.tripwire-divergences` — c'est une sonde.

- [ ] **Step 5: Committer**

```bash
git status --porcelain    # doit ne montrer que scripts/check.sh
git add scripts/check.sh
git commit --no-gpg-sign -m "chore(dogfood): assertion de divergences dans le check.sh du plugin"
```

---

### Task 5 : `/tripwire:init` — lecture, réinjection, documentation

**Files:**
- Modify: `skills/init/SKILL.md` (étape 0, étape 3, historique des templates, étape 4)
- Modify: `skills/init/templates/claude-md-section.md.tmpl`

**Interfaces:**
- Consomme : le nom de fichier `.tripwire-divergences` et le format TSV, tels que figés dans les contraintes globales.
- Produit : la prose que suivra un agent au re-scaffold. Aucune interface machine.

- [ ] **Step 1: Étape 0 — lire la fiche avant d'écrire**

Dans `skills/init/SKILL.md`, section « Étape 0 — Idempotence & mise à jour », ajouter après la puce « Lors d'une mise à jour : ne JAMAIS écraser les valeurs projet » :

```markdown
- **Divergences déclarées** : lire `.tripwire-divergences` du repo cible AVANT
  toute écriture. Générer depuis les templates, réinjecter chaque motif déclaré
  dans la sortie, puis lancer `./scripts/check.sh --fast` — c'est l'assertion
  qui prononce le verdict, pas votre relecture. Un motif non réinjectable :
  s'arrêter et demander l'arbitrage (AskUserQuestion), jamais écraser en silence.
```

- [ ] **Step 2: Procédure « dialecte divergent » — écrire les lignes**

Dans la sous-section « Cas particulier : dialecte divergent », ajouter au point 3 (« En standard + alias ») :

```markdown
   Déclarer chaque alias dans `.tripwire-divergences` — les alias SONT des
   divergences par construction : une ligne par alias, motif = le `--ancien)` du
   `case`, pourquoi = le dialecte d'origine (ex. `dialecte KaSe : --board =
   --variant standard`).
```

- [ ] **Step 3: Étape 3 — la fiche dans la table des fichiers**

Dans « Étape 3 — Génération », ajouter sous la table des templates :

```markdown
### Fiche de divergences

`.tripwire-divergences` n'a pas de template : elle n'existe que si le projet a
des écarts. Créée à la main, une ligne par écart assumé, **committée** (comme
`.tripwire-testcount`) — son diff est le mécanisme de review.
```

- [ ] **Step 4: Étape 4 — la validation**

Dans « Étape 4 — Validation », ajouter après la ligne `./scripts/check.sh --fast` :

```bash
# Divergences : si le repo en déclare, l'assertion doit être verte
test -f .tripwire-divergences && ./scripts/check.sh --fast   # doit être VERT
```

- [ ] **Step 5: Historique des templates**

Ajouter en tête de la table « Historique des templates » :

```markdown
| v0.12.0 | check.sh : assertion de divergences déclarées (`.tripwire-divergences`, TSV committé, rouge si un motif déclaré disparaît de son fichier hôte). Re-scaffold : mettre à jour check.sh + créer la fiche si le repo a des écarts |
```

- [ ] **Step 6: Section CLAUDE.md scaffoldée**

Dans `skills/init/templates/claude-md-section.md.tmpl`, ajouter après le bloc « Ratchet de tests » (ou, s'il n'y en a pas, après les puces de hooks) :

```markdown
**Divergences déclarées** : `.tripwire-divergences` (committé) liste les écarts
assumés au scaffold standard — mode maison, dégradation d'environnement, alias
de dialecte. Une ligne `fichier<TAB>motif<TAB>pourquoi` ; `check.sh` rend rouge
la disparition d'un motif déclaré. **Limite** : un écart non déclaré n'est
protégé par rien et le prochain re-scaffold l'effacera — toute divergence
délibérée se déclare au moment où on l'introduit.
```

- [ ] **Step 7: Vérifier et committer**

Run: `./scripts/check.sh --force`
Expected: `✓ check.sh: tout vert` (le lint valide la syntaxe des templates ; le ratchet ne bouge pas).

```bash
git add skills/init/SKILL.md skills/init/templates/claude-md-section.md.tmpl
git commit --no-gpg-sign -m "docs(init): lecture et réinjection des divergences déclarées au re-scaffold"
```

---

### Task 6 : Reprise de la flotte — 7 fiches écrites à la main

**Files:**
- Create: `.tripwire-divergences` dans 7 repos (hors `cheni` et `rili`, sans écart connu)

**Interfaces:**
- Consomme : l'assertion livrée par les tâches 1-2, distribuée par une release v0.12.0.
- Produit : rien pour les tâches suivantes.

**Cette tâche est interactive et ne se délègue pas à un subagent.** Chaque ligne se propose à Mae avec son *pourquoi* et se fait valider avant écriture — c'est l'exercice de documentation qui a manqué le 2026-08-05. Un *pourquoi* deviné est pire que pas de fiche.

Prérequis : la release v0.12.0 est faite et chaque repo a reçu le nouveau `check.sh` via `/tripwire:init`. Sans ça, la fiche est écrite mais rien ne la vérifie.

Divergences repérées le 2026-08-05, **à confirmer repo par repo** (relire le `check.sh` et les hooks de chacun avant de proposer) :

| repo | écart à déclarer |
|---|---|
| KaSe_firmware | dialecte `--board` / `--host-only` ; env `esp/esp-idf/export.sh` |
| WooView | mode `--release` |
| lemia-site | mode `--php` |
| nixos-config | mode `--no-link` ; cible = `.tripwire-variant` sinon `hostname` |
| BDM64 | env `../scripts/esp-env.sh` |
| esp-fp | dégradation `idf.py` / `nix` absents |
| Rouge-Gorge | dégradation `kicad-cli` ; baseline DRC dédiée CI |

- [ ] **Step 1: Pour chaque repo — relire avant de proposer**

```bash
grep -n -- '--[a-z-]*)' <repo>/scripts/check.sh        # modes réels
grep -n 'command -v\|source ' <repo>/scripts/check.sh <repo>/scripts/hooks/*  # env et dégradations
```
Ne proposer que ce que ces sorties montrent. Le tableau ci-dessus est un point de départ, pas une vérité.

- [ ] **Step 2: Proposer les lignes à Mae et faire valider**

Une question par repo (AskUserQuestion), montrant les lignes exactes qui seront écrites, motif et pourquoi. Une ligne non validée ne s'écrit pas.

- [ ] **Step 3: Écrire la fiche et vérifier qu'elle est verte**

```bash
cd <repo> && ./scripts/check.sh --fast --force    # doit être VERT
```
Rouge → le motif est mal orthographié : le corriger, ne jamais retirer la ligne pour faire passer.

- [ ] **Step 4: Vérifier que l'assertion mord vraiment sur ce repo**

Casser temporairement un motif (copie de sauvegarde d'abord), constater le rouge, restaurer. Une fiche jamais vue rouge n'est pas une fiche vérifiée.

- [ ] **Step 5: Committer dans le repo cible**

```bash
git add .tripwire-divergences
git commit --no-gpg-sign -m "tripwire: déclare les divergences au scaffold standard"
```

---

## Release

Après la tâche 5 : `/tripwire:release` → **v0.12.0** (nouvelle capacité, aucun breaking). Le bump met à jour `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` et le tampon `# tripwire-template:` de `scripts/check.sh` vers `v0.12.0`. La tâche 6 vient après.
