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
