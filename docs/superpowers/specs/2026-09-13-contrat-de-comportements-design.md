# Contrat de comportements — design v0.14.0

Date : 2026-09-13 · Statut : validé (session avec Mae)

## Problème

Sur KeSp_firmware, un mois de travail : 109 commits, dont 30 correctifs. La
majorité des correctifs touchent le code source **sans toucher un seul test**,
et ce qu'ils corrigent est de la radio, de la veille, du timing — « chien de
garde radio », « la carte se rendormait 10 ms après un réveil », « aucune
temporisation du driver nRF24 n'attendait ».

Pendant ce temps le tripwire est vert. Il ne ment pas : la phase rapide couvre
la logique testable sur hôte, la phase complète compile. « Vert » n'a jamais
voulu dire « le firmware se comporte ». Mais c'est ce qu'on lui fait dire.

Deux causes.

**Le comportement attendu n'est écrit nulle part avant de casser.** Chaque
correctif nomme une règle après coup — « un réveil est une activité », « la
gauche réaffirme ses maintiens ». Ces règles n'existent que dans le message du
commit qui les a réparées. Un agent qui modifie `rf_rx_task.c` ne peut pas
savoir qu'il en viole une, et aucun test ne peut en dériver.

**L'avis TDD n'atteint jamais l'agent.** `check.sh` l'émet sur stdout ; le hook
par édition capture cette sortie et ne la relaie que sur rouge. Sur vert, elle
est jetée. L'avis « source modifiée sans test » n'a donc jamais été *posé* aux
neuf correctifs sans test de ce mois — il n'a pas été ignoré, il n'a pas été vu.
Et même vu, il ne demande rien : l'agent n'a rien à répondre.

Le savoir existe pourtant. `CLAUDE.md` de KeSp contient des règles de
comportement noyées entre des consignes de build ; `HARDWARE_SMOKE_TEST.md`
existe et la section Release ne le référence pas ; `host_clock.c` et
`nvs_fake.c` prouvent que veille et timing **peuvent** se tester sur hôte. Ce
qui manque, c'est le comportement écrit dont dériver le test — et une question
à laquelle il faille répondre.

## Pièce 1 — Le contrat : `COMPORTEMENTS.md`

À la racine du repo équipé, committé, à côté de `CLAUDE.md`. Du **markdown
lisible**, pas un TSV : c'est un document fait pour être lu avant de toucher.
Chaque comportement est une puce dont le tag est ce que la machine lit :

```markdown
- [test:test_rf_rearm_on_wake] Au réveil, la réception RF est réarmée — sinon
  la gauche ne reçoit plus rien.
- [smoke:veille-batterie] La carte tient une nuit sur batterie, moins de 0,2 V
  perdus.
- [NON GARDÉ] Un slot recyclé ne conserve pas le keycode du cycle précédent.
```

Trois gardes possibles :

- `[test:X]` — `X` est une chaîne littérale qui doit apparaître dans au moins
  un fichier de test (chemins `TEST_GREP` du projet). Un nom de fonction de
  test, typiquement.
- `[smoke:X]` — `X` doit apparaître dans le document de smoke test matériel
  (`SMOKE_DOC`, nouvelle valeur projet). Pour ce que l'hôte ne peut pas
  exercer.
- `[NON GARDÉ]` — l'aveu. Autorisé, compté, ratcheté.

Toute ligne sans tag est de la prose libre : titres, contexte, explications.
Le contrat reste un document, pas un formulaire.

Un motif de garde est comparé en **chaîne littérale** (`grep -F`), comme les
divergences.

## Pièce 2 — Ce que `check.sh` vérifie (phase rapide, tous modes)

Fonction `check_comportements()`, appelée après `check_divergences`, avant
`run_fast`. Fichier absent → inerte, silencieux.

- `[test:X]` dont `X` n'apparaît dans aucun fichier de test → **rouge** : un
  comportement a perdu sa garde. Message : le comportement, la garde disparue,
  et les deux issues — rétablir le test, ou passer la ligne en `[NON GARDÉ]`
  (visible au diff, compté par le ratchet).
- `[smoke:X]` dont `X` n'apparaît pas dans `SMOKE_DOC` → **rouge**, même
  forme.
- `SMOKE_DOC` vide alors qu'un `[smoke:]` existe → rouge : garde invérifiable
  déclarée. Une garde qu'on ne peut pas vérifier n'en est pas une.
- `[NON GARDÉ]` : **ratchet à référence committée** — `.tripwire-nongardes`,
  même mécanique exacte que `.tripwire-testcount` : bootstrap au premier run,
  baisse automatique quand le compte baisse (fichier laissé modifié, part avec
  le prochain commit), avis quand il monte, **rouge** au pre-push
  (`TRIPWIRE_RATCHET_STRICT=1`). Pas au Stop : l'échappatoire à la question
  forcée est justement une ligne `[NON GARDÉ]`, le Stop ne peut pas la punir.
  Une référence « contre HEAD » ne marcherait pas — au push l'arbre est propre,
  donc égal à HEAD, et le ratchet ne mordrait jamais. Assumer un comportement
  non gardé reste possible ; monter la référence est un diff visible en review.
- Tag inconnu (`[xyz:…]`) → rouge, ligne citée : une faute de frappe ne doit
  pas se dégrader en prose ignorée.

## Pièce 3 — La question forcée

Deux moments, deux gravités, cohérents avec l'échelle de v0.12.0.

**Pendant (hook par édition) — la question.** Quand le fichier édité est une
source surveillée et non un fichier de test, le hook émet, **même sur vert**,
un contexte :

> Source modifiée. Quel comportement de `COMPORTEMENTS.md` ce changement
> touche-t-il, et quel test le garde ? Si aucun : l'ajouter au contrat — gardé,
> ou `[NON GARDÉ]` assumé — avant de conclure. Le Stop bloquera sinon.

Ce n'est plus un avertissement, c'est une question avec une réponse attendue.
Elle remplace l'avis TDD dans le hook (qui, lui, n'y arrivait jamais).

**À la conclusion (hook Stop) — le blocage.** `check.sh` gagne une vérification
de « question sans réponse » : des sources (`SRC_GREP`) sont modifiées depuis
`HEAD`, aucun fichier de test (`TEST_GREP`) ne l'est, et `COMPORTEMENTS.md`
non plus. En mode normal → avis. Avec `TRIPWIRE_CONTRAT_STRICT=1` → **rouge**.
`cc_stop.sh` et `pre-push` exportent cette variable.

L'échappatoire est une ligne `[NON GARDÉ]` — une ligne, mais elle est comptée,
et le ratchet la rend visible au push. C'est la seule version où la question
est vraiment forcée : les deux avis précédents (TDD, post-edit) ont montré ce
que devient une question facultative.

Un repo sans `COMPORTEMENTS.md` n'est soumis à rien de tout ceci : adoption
progressive, comme chaque pièce du pipeline.

## Pièce 4 — Le smoke test matériel devient une gate

`SMOKE_DOC` (ex. `docs/HARDWARE_SMOKE_TEST.md`) est référencé par la section
Release du `CLAUDE.md` scaffoldé. `/tripwire:release` déroule les items du
smoke test **et** vérifie que chaque `[smoke:X]` du contrat y correspond. C'est
là que « vert ≠ fonctionne » se ferme, au moment où ça compte.

## Ce que ça ne fait pas

- Ça n'écrit pas le contrat. Le contrat initial de KeSp s'écrit **avec Mae** :
  les règles de `CLAUDE.md` et les trente correctifs du mois sont la matière,
  mais c'est elle qui sait lesquels sont des invariants. Un comportement inventé
  par un agent est pire qu'un comportement absent — même leçon que les
  divergences.
- Ça ne juge pas la qualité d'un test : `[test:X]` prouve que `X` existe, pas
  que `X` teste bien. C'est le travail de `/tripwire:test-review`.
- Ça ne remplace pas le matériel : un `[smoke:]` est vérifié par un humain à la
  release, pas par le pipeline.

## Tests (TDD — écrits et rouges avant l'implémentation)

Sur le repo jouet d'e2e :

| assertion | attendu |
|---|---|
| contrat absent | vert, inerte |
| `[test:X]` présent sous `test/` | vert |
| `[test:X]` absent | **rouge**, message cite X et les deux issues |
| `[smoke:X]` présent dans `SMOKE_DOC` | vert |
| `[smoke:X]` absent | **rouge** |
| `[smoke:X]` avec `SMOKE_DOC` vide | **rouge** (garde invérifiable) |
| tag inconnu | **rouge**, ligne citée |
| prose sans tag | ignorée, vert |
| `[NON GARDÉ]` : premier run | vert, référence bootstrappée |
| `[NON GARDÉ]` : compte == référence | vert |
| `[NON GARDÉ]` : compte > référence, mode normal | vert + avis |
| `[NON GARDÉ]` : compte > référence, ratchet strict | **rouge** |
| `[NON GARDÉ]` : compte < référence | vert, référence abaissée |
| post-edit sur une source, vert | question émise en contexte |
| post-edit sur un fichier de test | pas de question |
| source modifiée, ni test ni contrat, mode normal | vert + avis |
| source modifiée, ni test ni contrat, strict | **rouge** |
| idem mais contrat modifié | vert |
| hook Stop sur source sans test ni contrat | rc 2 |

## Reprise sur KeSp

1. Section Release → `SMOKE_DOC=docs/HARDWARE_SMOKE_TEST.md`.
2. Contrat initial, avec Mae : partir des règles déjà dans `CLAUDE.md` (réarmement
   RF au réveil, `rf_driver` refuse d'émettre après, NVS 64 KB…) et des trente
   correctifs — chaque « fix » du mois est un candidat. Pour chacun : test hôte
   existant ? test hôte possible avec `host_clock`/`nvs_fake` ? sinon smoke,
   sinon `[NON GARDÉ]` assumé.
3. Le nombre de `[NON GARDÉ]` au premier run bootstrappe `.tripwire-nongardes`
   (à committer) — il n'a le droit que de baisser.

## Impacts

- `skills/init/templates/check.sh.tmpl` : `check_comportements()`, valeur
  `SMOKE_DOC`, vérification « question sans réponse », `TRIPWIRE_CONTRAT_STRICT`.
- `skills/init/templates/cc_post_edit.sh.tmpl` : la question sur source.
- `skills/init/templates/cc_stop.sh.tmpl`, `pre-push.tmpl` : export strict.
- `skills/init/templates/claude-md-section.md.tmpl` : le contrat, la question.
- `skills/init/SKILL.md` : question `SMOKE_DOC`, placeholder, historique v0.14.0.
- `skills/release/SKILL.md` : gate smoke ↔ `[smoke:]`.
- `scripts/check.sh` + hooks (dogfood) : à l'identique.
- `tests/e2e.sh` : les 17 assertions ci-dessus.
