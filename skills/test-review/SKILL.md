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
