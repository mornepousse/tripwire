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

## Protocole gros scope (> ~10 fichiers de test) — fan-out économique

Le coût d'un gros audit est dans la **lecture**, pas le jugement. Deux étages :

1. **Extracteurs** (un subagent par lot de 3-5 fichiers, **modèle économique**
   type haiku — c'est sûr car ils n'émettent AUCUN verdict) : chaque extracteur
   produit une fiche par fichier au format imposé, **chaque affirmation citée
   `fichier:ligne`** :
   - quel(s) `.c`/module réel(s) ce test compile/linke (d'après le CMakeLists
     ou l'équivalent du harnais) — ou « aucun : logique locale/copiée » ;
   - liste brute des assertions (pattern + ligne) ;
   - `#define`/constantes recopiés du code de prod (citer les deux côtés) ;
   - fonctions de prod appelées vs réimplémentées localement.
2. **Juge unique** (modèle fort — jugement = jamais de modèle économique) :
   rend le verdict de la grille depuis les fiches, en n'ouvrant lui-même que
   les fichiers où une fiche est ambiguë ou suspecte.

Règle de sûreté : une extraction **citée** est vérifiable (le juge ou un grep
recoupe la ligne) ; un **jugement** halluciné n'est rattrapé par rien. Les
extracteurs collectent, le juge conclut — jamais l'inverse. Toute fiche sans
citations est rejetée et re-demandée.

Économie d'entrée : les extracteurs travaillent en **greps/sed ciblés**
(`grep -n 'assert' f.c`, `sed -n '10,30p'`) plutôt qu'en lecture intégrale —
le gros du coût d'un extracteur est ce qu'il lit, pas ce qu'il écrit. Si
[rtk](https://github.com/rtk-ai/rtk) intercepte le shell, ces sorties sont en
plus compressées de 60-90 % : le tandem extracteur-économique × rtk divise le
coût de lecture d'un facteur 5 à 10 vs un juge fort qui lirait tout.

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
   (norme TDD du CLAUDE.md cible si elle existe : la citer).
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
