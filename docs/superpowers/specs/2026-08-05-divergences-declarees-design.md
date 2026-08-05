# Divergences déclarées — design v0.12.0

Date : 2026-08-05 · Statut : validé (brainstorm session)

## Problème

Un repo équipé dérive du scaffold standard : mode maison (`--php` sur
lemia-site, `--release` sur WooView, `--no-link` sur nixos-config), dégradation
d'environnement (`kicad-cli` sur Rouge-Gorge, `idf.py`/`nix` sur esp-fp),
dialecte entier (`--board`/`--host-only` sur KaSe_firmware). Ces écarts sont
**délibérés** et **invisibles** : rien ne les enregistre, rien ne les protège.

Le re-scaffold les efface donc en silence. Vécu le 2026-08-05 pendant la
propagation de v0.11.0 : `cc_stop.sh` écrasé par le template sur quatre repos,
emportant la dégradation `kicad-cli` de Rouge-Gorge et le `--variant $hostname`
de nixos-config. `check.sh --fast` a été lancé derrière dans les deux repos —
**vert**. Aucun garde-fou n'a mordu.

La leçon n'est pas « mieux lire avant d'écraser ». C'est que la perte doit être
un **verdict machine**, pas le produit d'une relecture attentive.

Le garde-fou ne peut pas vivre dans un skill : l'écrasement du 2026-08-05 est
passé par un `cp`, sans `/tripwire:init` ni skill de propagation. Il vit donc
là où la doctrine du projet le place déjà — dans `check.sh`, l'oracle que tout
le monde appelle.

## Pièce 1 — La fiche `.tripwire-divergences`

Fichier **committé** à la racine du repo équipé (comme `.tripwire-testcount`),
TSV à trois champs, une ligne par écart assumé :

```
# fichier	motif	pourquoi
scripts/check.sh	--php)	mode maison : lint PHP séparé du build front
scripts/hooks/cc_stop.sh	kicad-cli	dégradation : pas de DRC si kicad-cli absent
scripts/check.sh	--board)	dialecte KaSe : --board = --variant standard
```

Une divergence se réduit à une affirmation vérifiable : *ce motif doit
apparaître dans ce fichier*. Pas de types (`mode:`, `degrade:`), pas de
sémantique connue de `check.sh` — sinon chaque nouveau cas demande du code.
Le troisième champ s'adresse à l'humain et n'est **jamais** interprété.

Comparaison en **chaîne littérale** (`grep -qF`), jamais en regex : les motifs
réels contiennent `--php)`, `$v`, `*"/test/"*`.

Séparateur : tabulation. Un motif contenant une tabulation n'est pas
représentable — limite acceptée, aucun motif réel n'en contient.

## Pièce 2 — L'assertion dans `check.sh` (mécanique, bloquante)

Dans la **phase rapide**, donc dans tous les modes, et **avant** le lint
(quelques `grep`, coût négligeable) :

- fichier absent ou vide → inerte, silencieux (adoption progressive, comme le
  ratchet sans `TEST_COUNT_CMD`) ;
- lignes vides et lignes commençant par `#` ignorées ;
- ligne malformée (moins de deux champs) → rouge, en citant le numéro de ligne
  (une fiche illisible ne doit pas se dégrader en fiche inerte) ;
- fichier hôte absent → **rouge** (la divergence n'a plus de support) ;
- motif introuvable dans le fichier hôte → **rouge**, message citant fichier,
  motif perdu et *pourquoi*.

**Rouge dur, pas un avis.** Contrairement au ratchet — où un refactor légitime
fait baisser le compte souvent —, une divergence déclarée qui disparaît est
soit une erreur, soit un abandon volontaire. Les deux demandent une action
immédiate et la correction tient en une ligne.

Le message d'échec nomme les deux issues, pour que le rouge ne se règle pas par
réflexe en supprimant la ligne :

```
✗ divergence perdue : scripts/hooks/cc_stop.sh ne contient plus « kicad-cli »
  motif déclaré : dégradation : pas de DRC si kicad-cli absent
  → rétablir la divergence, ou retirer sa ligne de .tripwire-divergences si
    l'abandon est voulu (le retrait part dans le diff, il sera vu en review).
```

Conséquence voulue : hook Stop et post-edit sortent en rc 2 dès l'écrasement —
le moment exact où l'incident du 2026-08-05 aurait été arrêté.

Deux mécaniques du template ont été vérifiées, parce qu'en les supposant on
construirait la barrière sur du vide :

- `run_fast` est appelé **sans condition** avant l'aiguillage de mode
  (`check.sh.tmpl:151`) : se loger dans la phase rapide suffit à couvrir tous
  les modes.
- l'empreinte du skip-si-déjà-vert (`check.sh.tmpl:96-103`) inclut
  `git diff HEAD` et `git ls-files -o --exclude-standard` : écraser un fichier
  **suivi par git** (ou au moins non gitignoré) change l'empreinte, donc le skip
  ne masque pas une divergence fraîchement perdue — à cette condition près.
  **Limite connue** : `--exclude-standard` exclut les fichiers gitignorés. Le
  fichier hôte d'une divergence qui serait gitignoré ne change pas l'empreinte ;
  `check.sh --fast` sans `--force` sort alors « déjà vert — skip » (rc 0) alors
  que le motif a disparu. Vérifié empiriquement. Le fichier hôte d'une
  divergence doit donc être suivi par git — un fichier gitignoré n'est pas
  protégé de façon fiable.

## Pièce 3 — Ce que `/tripwire:init` en fait

« Ne JAMAIS écraser les valeurs projet » est aujourd'hui de la prose sans
mécanisme. La fiche lui en donne un.

- **Scaffold initial** : en général aucune divergence. Deux exceptions écrivent
  des lignes immédiatement — la procédure « dialecte divergent » (standard +
  alias : les alias *sont* des divergences par construction) et une dégradation
  d'environnement demandée par l'utilisateur.
- **Re-scaffold** : lire la fiche **avant** toute écriture ; générer depuis les
  templates ; réinjecter chaque motif déclaré ; puis lancer `check.sh --fast` —
  c'est l'assertion qui prononce le verdict, pas le jugement de l'agent. Un
  motif non réinjectable → s'arrêter et demander l'arbitrage. Jamais écraser en
  silence.
- **Section `CLAUDE.md` scaffoldée** : documenter la fiche et sa limite (voir
  ci-dessous).

## Limite assumée

Une divergence introduite à la main et **non déclarée** n'est protégée par
rien, et le prochain re-scaffold l'effacera. La fiche protège ce qu'on a pris
la peine de déclarer ; elle ne devine rien. C'est le prix de la simplicité du
format — l'alternative (inférer les écarts en diffant contre les templates)
produirait des *pourquoi* devinés, et un pourquoi inventé est pire que pas de
fiche : il donne une fausse assurance.

Le rappel vit dans la section `CLAUDE.md` scaffoldée : toute divergence
délibérée se déclare au moment où on l'introduit.

## Tests (TDD — écrits et rouges avant l'implémentation)

Dans `tests/e2e.sh`, sur le repo jouet :

| assertion | attendu |
|---|---|
| fiche absente | vert, inerte |
| fiche vide / uniquement des commentaires | vert |
| tous les motifs présents | vert |
| motif effacé du fichier hôte | **rouge**, message citant motif + pourquoi |
| fichier hôte supprimé | **rouge** |
| ligne malformée (un seul champ) | **rouge**, cite le numéro de ligne |
| motif à caractères regex (`--php)`, `$v`) présent | vert — prouve le `-F` |
| hook Stop après effacement d'un motif | rc 2 |

La dernière rejoue l'incident : on écrase un `cc_stop.sh` porteur d'une
dégradation déclarée et on vérifie que le tripwire mord.

Ratchet attendu : 71 → 83 (les huit lignes ci-dessus se traduisent en douze
assertions `chk`, plusieurs cas vérifiant à la fois le code de retour et le
contenu du message).

## Reprise de la flotte (9 repos)

Fiches écrites **à la main, repo par repo**, chaque ligne proposée avec son
*pourquoi* et validée avant écriture. Le déploiement du mécanisme est
l'exercice de documentation qui a manqué le 2026-08-05.

Divergences connues à ce jour, à confirmer repo par repo :

| repo | écart |
|---|---|
| KaSe_firmware | dialecte `--board` / `--host-only` ; env `esp/esp-idf/export.sh` |
| WooView | mode `--release` |
| lemia-site | mode `--php` |
| nixos-config | mode `--no-link` ; cible = `.tripwire-variant` sinon `hostname` |
| BDM64 | env `../scripts/esp-env.sh` |
| esp-fp | dégradation `idf.py` / `nix` absents |
| Rouge-Gorge | dégradation `kicad-cli` ; baseline DRC dédiée CI |
| cheni, rili | aucun écart connu — fiche absente (inerte) |

## Hors périmètre (décisions explicites)

- **`/tripwire:status` n'affiche pas les fiches** dans cette version. La
  barrière d'abord, le confort de décision ensuite.
- **Pas de `/tripwire:propagate`.** Un rapport de flotte est une aide à la
  décision, pas une protection ; il ne se justifie qu'une fois la flotte
  protégée.
- **Pas d'inférence automatique des divergences** (voir « Limite assumée »).

## Impacts

- `skills/init/templates/check.sh.tmpl` : l'assertion en phase rapide.
- `skills/init/templates/claude-md-section.md.tmpl` : documentation de la fiche
  et de sa limite.
- `skills/init/SKILL.md` : lecture/réinjection au re-scaffold, écriture des
  lignes à la procédure « dialecte divergent », entrée d'historique v0.12.0.
- `tests/e2e.sh` : les 8 assertions ci-dessus.
- `scripts/check.sh` (dogfood) : l'assertion, + tampon de version.
- 9 repos de la flotte : une fiche chacun, hors cheni et rili.
