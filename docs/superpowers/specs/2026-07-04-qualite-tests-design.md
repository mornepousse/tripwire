# Qualité des tests — design v0.9.0

Date : 2026-07-04 · Statut : validé (brainstorm session)

## Problème

Le pipeline garantit que les tests **passent**, pas qu'ils **protègent**.
Trois failles vécues (KaSe) : tests creux écrits par l'IA, assertions
affaiblies/supprimées pour faire passer un Stop, nouvelle logique livrée sans
test. Posture retenue : **avertir l'agent en ligne, bloquer au pre-push**
(le mécanique sûr bloque au push ; l'heuristique avertit ; le sémantique est
un skill à la demande).

## Pièce 1 — Ratchet de tests (mécanique, bloquant au push)

Contre les tests supprimés/désactivés.

- Nouvelle valeur projet dans `check.sh.tmpl` : `TEST_COUNT_CMD`
  (placeholder `{{TEST_COUNT_CMD}}`) — commande une-ligne qui imprime un
  entier (nombre de tests). Vide → toute la pièce est inerte.
  Défauts proposés à l'init (table de stack) :
  - C host (KaSe-like) : `grep -rhoc 'TEST_ASSERT' test/*.c | paste -sd+ | bc`
    (ou équivalent adapté au harnais détecté)
  - Rust : `grep -rc '#\[test\]' src/ | awk -F: '{s+=$2} END{print s+0}'`
  - Python : `grep -rc 'def test_' tests/ | awk -F: '{s+=$2} END{print s+0}'`
  - Node/Go : demander (pas de défaut fiable).
  Même contrainte que FAST_CMD : pas de `$(...)`, pas de `"` internes.
- Référence : fichier **`.tripwire-testcount`, committé** (comme
  `.tripwire-variant`). Baisser le ratchet = modifier un fichier versionné =
  ligne de diff visible en review. C'est le mécanisme anti-triche.
- Comportement dans check.sh (run réel, après la phase rapide verte) :
  - `count > ref` → écrire la nouvelle valeur dans `.tripwire-testcount`
    (fichier laissé modifié : il part avec le prochain commit) + info.
  - `count < ref` → avertissement (`⚠ ratchet: N tests vs M attendus…`) ;
    si `TRIPWIRE_RATCHET_STRICT=1` → **rc=1** (rouge).
  - `count == ref` ou `TEST_COUNT_CMD` vide/échoue → silencieux (l'échec de
    comptage ne casse jamais un check ; `2>/dev/null`).
- `pre-push.tmpl` : exporte `TRIPWIRE_RATCHET_STRICT=1` avant d'appeler
  check.sh. Échappatoire assumée : `git push --no-verify` (déjà documentée).
- Fichier absent (adoption progressive) : premier run réel avec
  `TEST_COUNT_CMD` non vide → le créer avec le compte courant (bootstrap).

## Pièce 2 — Garde anti-affaiblissement (heuristique, avertit l'agent)

Contre les assertions supprimées/affaiblies sous pression.

- Nouvelles valeurs projet dans les hooks post-edit :
  `{{TEST_PATH_PATTERNS}}` (patterns `case` des fichiers de test, ex.
  `*"/test/"*|*"_test."*`) et `{{ASSERT_PATTERN}}` (regex grep des
  assertions, ex. `TEST_ASSERT|assert` pour C, `assert!|assert_eq!` Rust,
  `assert` Python).
- Dans `cc_post_edit.sh.tmpl` : si le fichier édité matche
  TEST_PATH_PATTERNS, comparer `grep -cE ASSERT_PATTERN` sur
  `git show HEAD:<fichier>` vs le fichier courant. Perte nette (>0) →
  émettre sur stdout le JSON PostToolUse :
  `{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":
  "tripwire: N assertion(s) en moins dans <fichier> vs HEAD — refactor
  légitime ou affaiblissement ? Rétablir ou justifier."}}` puis `exit 0`
  (non bloquant). Fichier nouveau (pas dans HEAD) ou binaire → silencieux.
- La garde s'exécute APRÈS le debounce et le check fast existants (un fichier
  de test édité passe d'abord par le circuit normal ; la garde s'ajoute).
  Précision : les fichiers de test doivent être inclus dans
  `WATCHED_PATH_PATTERNS` pour que le hook les voie — l'init le vérifie
  (question 3 : proposer d'inclure les chemins de test).
- `vibe_post_edit.sh.tmpl` : même garde, message texte sur stderr, `exit 0`.
- python3 déjà requis par les hooks ; la garde n'ajoute aucune dépendance
  (git + grep).

## Pièce 3 — Avis « logique sans test » (heuristique, informatif)

Contre le code nouveau sans test.

- Dans `check.sh.tmpl`, sur run réel uniquement (après le verdict, jamais
  bloquant) : deux nouvelles valeurs projet en forme grep -E —
  `{{SRC_GREP}}` (fichiers source, dérivé des chemins surveillés, ex.
  `^src/|^main/`) et `{{TEST_GREP}}` (fichiers de test, ex. `^test/|_test\.`).
  `git diff --name-only HEAD` → compter les modifiés matchant chacun.
  `src > 0 && test == 0` → une ligne d'avis :
  `⚠ du code surveillé est modifié sans test modifié — la norme TDD demande
  le test d'abord`.
- Working tree propre (tout committé) → silencieux (l'avis vise la session de
  travail en cours, pas l'historique).

## Pièce 4 — Skill `/tripwire:test-review` (sémantique, à la demande)

Contre les tests creux.

- Nouveau skill `skills/test-review/SKILL.md`. Scope au choix : le diff
  courant (`git diff HEAD` + `--cached`), un module/dossier, ou un fichier.
- Grille d'audit (chaque finding avec fichier:ligne + patch proposé) :
  1. **Assertions creuses** : toujours-vraies, sur des constantes, absentes
     (test qui ne peut pas échouer).
  2. **Happy-path only** : cas limites absents au regard de la logique testée
     (bornes, vide, erreurs, débordements) — lire le code sous test, pas
     seulement le test.
  3. **Tests de mocks** : le test vérifie le mock/stub, pas le comportement.
  4. **Couplage à l'implémentation** : casse au refactor sans changement de
     comportement.
  5. **Parallel-safety / état global** (norme TDD du CONFIG_MD cible).
  6. **Nommage menteur** : le nom promet plus que ce que le test vérifie.
- Sortie : tableau des findings par sévérité (bloquant pour la confiance /
  amélioration / style) + patchs prêts à appliquer sur demande. Ne pas
  inventer de problème.
- Maillage : le template `test-author` de gen-agents référence la grille
  (une ligne « avant de livrer, auto-audite avec la grille de
  /tripwire:test-review »).

## Hors périmètre (décisions explicites)

- Mutation testing : trop lourd/stack-spécifique ; la grille du skill le
  mentionne comme suggestion manuelle (cargo-mutants…), rien d'outillé.
- Couverture (coverage %) : métrique gameable, pas de gate.
- Blocage au PostToolUse : refusé (faux positifs sur refactors légitimes).

## Impacts

- `check.sh.tmpl` : pièce 1 (ratchet) + pièce 3 (avis) ; placeholders
  `{{TEST_COUNT_CMD}}`, `{{SRC_GREP}}`, `{{TEST_GREP}}` —
  e2e TDD (rouge d'abord) sur le repo jouet : bootstrap, auto-bump, baisse →
  warning, baisse + STRICT=1 → rouge, TEST_COUNT_CMD vide → inerte.
- `cc_post_edit.sh.tmpl` / `vibe_post_edit.sh.tmpl` : pièce 2 ; placeholders
  `{{TEST_PATH_PATTERNS}}`, `{{ASSERT_PATTERN}}` — e2e : perte d'assertion →
  additionalContext émis ; ajout/refactor neutre → silencieux.
- `pre-push.tmpl` : export `TRIPWIRE_RATCHET_STRICT=1`.
- `skills/init/SKILL.md` : questions (TEST_COUNT_CMD avec défauts par stack,
  patterns de test, ASSERT_PATTERN), placeholders, historique v0.9.0,
  `.tripwire-testcount` committé (comme `.tripwire-variant`).
- Nouveau : `skills/test-review/SKILL.md` ; une ligne dans
  `gen-agents/templates/test-author.md.tmpl`.
- README : section « Qualité des tests » ; table des skills.
- Dogfood : tripwire lui-même adopte le ratchet (`TEST_COUNT_CMD` = nombre
  d'assertions `chk`/frontmatter dans e2e.sh, ex.
  `grep -c 'chk "' tests/e2e.sh`).
