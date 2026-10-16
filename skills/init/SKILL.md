---
name: init
description: Use when installing the tripwire anti-regression pipeline into a project — scaffolds scripts/check.sh (single source of truth), versioned git hooks (pre-push), Claude Code hooks (Stop/SessionStart), and a CLAUDE.md config section — or, in a shared repo, a personal install that commits nothing. Trigger on "installe le tripwire", "ajoute le pipeline anti-régression", "/tripwire:init", "mets en place check.sh".
---

# tripwire:init — scaffolder le pipeline anti-régression

## L'invariant à installer

> Un seul script (`scripts/check.sh`) définit ce que « vert » veut dire.
> Chaque garde-fou (hook git, hook de plateforme, CI) ne fait que l'appeler
> avec un mode adapté à son budget temps.

Ne JAMAIS dupliquer une commande de test/build dans un hook : les hooks
appellent `check.sh` et rien d'autre.

## Étape 0 — Idempotence & mise à jour

Si `scripts/check.sh` existe déjà dans le repo cible :
- Lire son tampon `# tripwire-template: vX.Y.Z` (ligne 2 ; absent → scaffold
  pré-v0.5.0) et le comparer à la version du plugin (champ `version` de
  `.claude-plugin/plugin.json` à la racine du plugin — deux niveaux au-dessus
  du dossier de cette skill).
- Scaffold en retard → annoncer **précisément ce qui a changé** entre les deux
  versions (voir « Historique des templates ») et demander (AskUserQuestion) :
  mettre à jour ces éléments / compléter ce qui manque / annuler.
- Lors d'une mise à jour : ne JAMAIS écraser les valeurs projet (commandes
  fast/build, variantes, chemins surveillés, env setup) — les relire depuis les
  fichiers existants et les réinjecter dans les nouveaux templates. Mettre à
  jour le tampon.
- **Contrepartie : préserver n'est pas figer.** Cette règle protège les valeurs
  projet, mais c'est elle aussi qui les gèle : une commande fast fixée le jour
  du scaffold n'est jamais rouverte, même quand le projet a changé sous elle.
  Avant de réinjecter, lire `.git/tripwire/history.tsv` du repo cible et poser
  le diagnostic de la section 4 du skill `status` (dérive persistante, saut
  soudain, jamais verte, fast identique à full, jamais exécutée). **Si un
  constat sort, proposer (AskUserQuestion) de revoir la commande fast** au lieu
  de la réinjecter telle quelle — en citant les chiffres (médiane, budget,
  nombre de runs concernés). La préservation reste le défaut ; la révision
  devient possible.
- **Divergences déclarées** : lire `.tripwire-divergences` du repo cible AVANT
  toute écriture. Générer depuis les templates, réinjecter chaque motif déclaré
  dans la sortie, puis lancer `./scripts/check.sh --fast` — c'est l'assertion
  qui prononce le verdict, pas votre relecture. Un motif non réinjectable :
  s'arrêter et demander l'arbitrage (AskUserQuestion), jamais écraser en silence.
- **Monolithe (scaffold < v0.16.0, pas de `scripts/tripwire.d/`)** : proposer le
  découpage. Relire les valeurs projet du monolithe (`FAST_RUN_CMD`, build,
  `ALL_VARIANTS`, `SRC_GREP`/`TEST_GREP`, `TEST_COUNT_CMD`), générer le noyau,
  et n'installer que les briques dont le fichier d'état existe déjà :
  `.tripwire-testcount` → ratchet, `.tripwire-divergences` → divergences,
  `COMPORTEMENTS.md` → contrat. Rien d'autre. Le hook par édition perd
  `--changed` (scoping monorepo retiré en v0.16.0, zéro utilisateur).
- **Mise à jour vers v0.17.0 (plus de hook par édition)** : supprimer
  `scripts/hooks/cc_post_edit.sh` et son entrée `PostToolUse` de
  `.claude/settings.json` — **seulement elle** : une entrée `PostToolUse`
  étrangère (ex. le cppcheck maison de KeSp) reste. Une ligne de
  `.tripwire-divergences` dont l'hôte est `cc_post_edit.sh` disparaît avec lui :
  la retirer et dire à l'utilisateur ce qu'elle gardait. Si la fiche n'a plus
  de ligne utile, la supprimer, et la brique `divergences` avec.
- Ne jamais écraser un `check.sh` existant sans accord explicite.

### Cas particulier : dialecte divergent (scaffold ancêtre ou modifié)

Un vieux scaffold peut avoir des **noms de modes différents** (ex. KaSe :
`--host-only`/`--board` au lieu de `--fast`/`--variant`), un **fichier de
variante custom** (`.kase-board`), un **préambule projet** (export ccache…) ou
des **hooks maison** hors tripwire dans `settings.json`. Avant de proposer la
mise à jour :
1. `grep -rl` les noms de modes dans la CI, les agents (`.claude/agents/`),
   les docs et le CLAUDE.md du repo — mesurer ce qui casserait.
2. Proposer (AskUserQuestion) : **standard + alias** (recommandé — template
   à jour, anciens modes acceptés en alias dans le `case`, fichier de variante
   custom conservé partout où les templates lisent `.tripwire-variant`) /
   backport dans le dialecte (pas de standardisation, upgrades futurs
   manuels) / migration complète (mettre aussi à jour CI, agents et docs).
3. En standard + alias : réinjecter le préambule projet après le `cd`,
   ajouter les alias dans le `case` (`--ancien|--standard)`), documenter les
   alias dans l'en-tête, et adapter `{{SESSION_VARIANT_LINE}}` au fichier de
   variante custom.
   Déclarer chaque alias dans `.tripwire-divergences` — les alias SONT des
   divergences par construction : une ligne par alias, motif = le `--ancien)` du
   `case`, pourquoi = le dialecte d'origine (ex. `dialecte KaSe : --board =
   --variant standard`).
4. Les hooks maison de `settings.json` et les scripts non-tripwire de
   `scripts/hooks/` ne sont JAMAIS touchés.

### Historique des templates

| Version | Changements nécessitant une mise à jour du scaffold |
|---|---|
| v0.2.0 | base : check.sh, pre-push, install-hooks, hooks post_edit/stop |
| v0.3.0 | support Mistral Vibe (rien à mettre à jour pour un scaffold Claude Code) |
| v0.5.0 | + hook SessionStart (`cc_session_start.sh` + entrée `settings.json`) ; tampon `# tripwire-template:` dans check.sh |
| v0.6.0 | check.sh : skip-si-déjà-vert (`--force`), scoping monorepo (`MODULE_FAST` + `--changed`), verrou flock, garde-budget (`TRIPWIRE_FAST_BUDGET`) ; hooks post-edit : debounce (`TRIPWIRE_DEBOUNCE`) + `--changed` ; templates CI à étages (gitlab/github) |
| v0.7.0 | check.sh : `last-fail.log` (détail du rouge sans re-run) + `history.tsv` (durées par mode) ; nouveaux skills status et bisect (rien à re-scaffolder, mais le check.sh mérite la mise à jour) |
| v0.8.0 | skills uniquement (mode flotte de status, procédure dialecte divergent d'init) — **aucun template modifié** : un tampon v0.7.0 est à jour |
| v0.9.0 | qualité des tests — check.sh : ratchet (`TEST_COUNT_CMD` + `.tripwire-testcount` committé, strict au pre-push) + avis TDD (`SRC_GREP`/`TEST_GREP`) ; hooks post-edit : garde anti-affaiblissement (`TEST_PATH_PATTERNS`/`ASSERT_PATTERN`) ; pre-push : `TRIPWIRE_RATCHET_STRICT=1` ; nouveau skill test-review |
| v0.10.0 | doctrine économie de modèles — section « Économie de modèles » dans les sections MD scaffoldées ; gen-agents : `model: sonnet` épinglé sur les agents de jugement ; check.sh **inchangé** (tampon v0.9.0 valide) — re-scaffold léger : section MD + regénérer les agents |
| v0.10.1 | docs uniquement (carte de cohabitation + doctrine sécurité des greffons tiers) — **rien à re-scaffolder** |
| v0.10.2 | check.sh : fix fuite `No such file or directory` sur stderr au 1er init du ratchet — la lecture `REF="$(tr … < .tripwire-testcount)"` échoue sur le `<` avant que `2>/dev/null` prenne effet quand le fichier n'existe pas encore ; remplacée par `cat … 2>/dev/null \| tr`. Cosmétique (verdict et fichier inchangés) — re-scaffold : mettre à jour cette seule ligne de check.sh |
| v0.11.0 | **support Mistral Vibe retiré** (plugin Claude Code uniquement) — un projet scaffoldé côté Vibe n'est plus mis à jour par ce skill. Hook Stop : ne lance plus que `check.sh --fast` (le build/e2e complet reste au pre-push) — re-scaffold : `cc_stop.sh` + la puce `Stop` de la section CLAUDE.md ; check.sh **inchangé** depuis v0.10.2 |
| v0.12.0 | **skills** : `status` diagnostique l'adéquation de la phase rapide depuis `history.tsv` (dérive persistante, saut soudain, jamais verte, fast == full) et `init` rouvre l'entretien de la commande fast quand un constat sort — préserver n'est pas figer. **check.sh** : assertion de divergences déclarées (`.tripwire-divergences`, TSV committé, rouge si un motif déclaré disparaît de son fichier hôte). **Hooks — échelle de gravité** : `PostToolUse` passe en avis non bloquant (`exit 0` + contexte) au lieu de `exit 2` ; la norme TDD impose un rouge avant l'implémentation, donc bloquer à chaque édition faisait sonner l'alarme à chaque pas correct, et une alarme permanente finit ignorée. `Stop` et `pre-push` restent bloquants. Re-scaffold : `check.sh`, `cc_post_edit.sh`, section CLAUDE.md, + la fiche si le repo a des écarts |
| v0.13.0 | **aucun template modifié** — mais le plugin embarque désormais un hook `SessionStart` qui détecte un scaffold en retard dans n'importe quel dépôt équipé et prescrit `/tripwire:init`. Il arrive par `claude plugin update`, rien à re-scaffolder pour en bénéficier |
| v0.14.0 | **contrat de comportements** — check.sh : `check_comportements()` (`COMPORTEMENTS.md` : `[test:X]`, `[smoke:X]`, `[NON GARDÉ]` ratcheté dans `.tripwire-nongardes`), valeur `SMOKE_DOC`, la question forcée (source modifiée sans test ni contrat → avis, rouge si `TRIPWIRE_CONTRAT_STRICT=1`) ; hooks : `cc_post_edit.sh` pose la question sur toute source (même sur vert — l'avis TDD, lui, n'arrivait jamais jusqu'à l'agent), `cc_stop.sh` et `pre-push` exportent le strict. CRLF : `$'\r'` en séquence d'échappement, plus d'octet nu. Re-scaffold : `check.sh`, les trois hooks, section CLAUDE.md, + poser la question 10 |
| v0.15.0 | **débrayage** : `TRIPWIRE_OFF=1` ou `.tripwire-off` coupe les hooks Claude Code (post-edit, Stop, SessionStart) et le hook du plugin. **Contrat allégé** : la question n'est plus qu'un avis d'une ligne au post-edit (le Stop ne bloque plus, `TRIPWIRE_CONTRAT_STRICT` disparaît), `[smoke:X]` n'est plus vérifié (note de release), `SMOKE_DOC` et la question 10 disparaissent. Re-scaffold : `check.sh`, les trois hooks, section CLAUDE.md, `.gitignore` |
| v0.16.0 | **allégé** — section CLAUDE.md scaffoldée : 64 → 12 lignes (600-780 tokens de moins par session) ; scoping monorepo retiré (`MODULE_FAST`, `--changed`, question d'init : zéro utilisateur en trois mois) ; noyau + briques : `check.sh` ne porte plus que le noyau et source `scripts/tripwire.d/*.sh` (ratchet, divergences, contrat — installées seulement si demandées, retirées par `rm`). Re-scaffold : `check.sh`, `cc_post_edit.sh`, section CLAUDE.md ; découpage du monolithe en briques (voir Étape 0) |
| v0.17.0 | **adapté aux agents actuels** — mesuré sur les transcripts : le Stop se déclenchait à chaque fin de tour (1527 fois dans une session de BDM64, 3 h d'attente cumulée sur nixos-config) et le hook par édition injectait 200 à 400 avis par dépôt. **`cc_post_edit.sh` supprimé** (avec debounce, garde anti-affaiblissement et question du contrat au post-edit — le ratchet du pre-push garde la perte nette d'assertions) ; **Stop** : un rouge donné ne bloque qu'une fois **par session** (mémoire `stop-red` = session + empreinte, effacée au vert, `TRIPWIRE_FORCE=1` relance) — autonome, marche avec n'importe quelle version de `check.sh` ; **SessionStart** : ne pose plus `core.hooksPath` par-dessus des hooks existants ; **mode perso** pour un dépôt partagé (`perso-exclude.tmpl`, `settings.local.json`, `CLAUDE.local.md`) ; check.sh : l'empreinte lit les fichiers tripwire même exclus de git. Re-scaffold : `cc_stop.sh`, `cc_session_start.sh`, suppression de `cc_post_edit.sh` et de son entrée `settings.json`, section CLAUDE.md — sur ces fichiers, **valable par-dessus tout scaffold depuis v0.10** ; `check.sh` (ligne d'empreinte) au prochain re-scaffold complet |

### Cohabitation avec l'outillage tiers (pre-commit, TDD Guard…)

- Repo avec **pre-commit/husky/lefthook** déjà en place : ne PAS s'approprier
  `core.hooksPath` — insérer un hook `pre-push` dans LEUR config qui appelle
  `./scripts/check.sh` (l'invariant survit : tout appelle check.sh). Le
  signaler dans le récap.
- Proposer (optionnel, question) **TDD Guard** pour la discipline TDD
  par-édition — il cohabite avec les hooks tripwire (le merge préserve les
  entrées étrangères). **Règle sécurité avant tout greffon tiers** : passe de
  vetting (lire le script du hook, identifier ce qui quitte la machine —
  TDD Guard envoie le code à une API de validation —, scripts postinstall),
  **version épinglée exacte**, **jamais d'auto-update** : toute montée de
  version = review du diff. Ne jamais installer un greffon tiers sans l'accord
  explicite de l'utilisateur après lui avoir présenté cette surface.

## Étape 0 bis — Dépôt partagé : commun ou perso

Si le dépôt a d'autres contributeurs (`git log --format='%ae' | sort -u` rend
plus d'une adresse, ou la forge n'appartient pas à l'utilisateur), demander
(AskUserQuestion) : **commun** (le scaffold est committé, l'équipe l'a) ou
**perso** (tripwire pour l'utilisateur seul, rien de committé, rien d'imposé).

En **perso**, mêmes templates, quatre différences :
- ajouter `templates/perso-exclude.tmpl` à `.git/info/exclude` **avant** toute
  écriture — tout ce que le scaffold crée y est listé ;
- hooks Claude Code dans `.claude/settings.local.json` (pas `settings.json`) ;
- section de doc dans `CLAUDE.local.md` (le `CLAUDE.md` de l'équipe n'est pas
  touché) ;
- pas de CI, pas de modification du `.gitignore`, et `.tripwire-testcount`
  reste local. Agents générés par `/tripwire:gen-agents` : ajouter chacun de
  leurs fichiers à `.git/info/exclude`.
L'empreinte du skip-si-déjà-vert lit `scripts/check.sh`, les briques,
`COMPORTEMENTS.md` et `.tripwire-divergences` même exclus de git.
Si le dépôt a déjà des hooks dans `.git/hooks/` (hors `*.sample`),
`core.hooksPath` les court-circuiterait : appliquer la règle de cohabitation
(insérer l'appel à `check.sh` dans le `pre-push` existant) au lieu de poser
`core.hooksPath`. Le hook SessionStart applique la même règle : il ne pose
`core.hooksPath` que si rien n'est en place, et se tait dès qu'un `pre-push`
appelle `scripts/check.sh`. Validation en plus : `git status --porcelain` doit rester
identique à avant le scaffold.

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
   Contraintes : la commande doit être relançable telle quelle depuis la racine
   du repo, ne pas contenir de substitution `$(...)` (elle est ré-affichée
   dans les messages d'échec), et **pas de guillemets doubles internes** — le
   template l'affecte à `FAST_RUN_CMD="…"`, des `"` imbriqués la tronqueraient
   silencieusement (bash concatène). Utiliser des quotes simples :
   `nix-shell shell.nix --run 'cargo test'`, pas `--run "cargo test"`.
   Les `cd` internes sont OK (exécution en subshell).
2. **Variantes** — liste de cibles de build (équivalent boards/features/targets),
   ou « aucune » (mono-cible). Si variantes : demander la commande de build
   paramétrée par `$v` et la variante par défaut (pour `.tripwire-variant`).
   Si aucune variante : demander/confirmer quand même la commande de build complet — elle alimente `{{VARIANT_BUILD_CMD}}` (le mode full mono-cible = fast + ce build). Même contrainte que la commande fast : pas de substitution `$(...)`.
3. **Setup d'environnement** — commande à sourcer avant un build
   (ex. `source ~/esp/esp-idf/export.sh`), ou « aucun ». Alimente
   `{{ENV_SETUP_BLOCK}}` dans le `pre-push` ; supprimer la ligne si aucun.

   **Règle : un outil absent n'est pas une régression.** Toute commande fast ou
   full qui dépend d'une toolchain externe (`idf.py`, `kicad-cli`, `nix`,
   compilateur croisé…) se garde par `command -v` et se **dégrade en saut
   annoncé** (`info "… SAUTÉ (raison)"` puis `return 0`), jamais en rouge. Un
   rouge qui veut dire « toolchain absente » est indiscernable d'un rouge qui
   veut dire « le code est cassé » : au bout de quelques semaines, plus personne
   ne lit les rouges du projet. Un saut annoncé n'est pas un silence vert — il
   se voit à chaque run.

   **Ne jamais capturer un environnement dans un fichier de chemins en dur.**
   Vécu sur BDM64 : `scripts/esp-env.sh` figeait des chemins `/nix/store`, tous
   garbage-collectés depuis, et le tripwire du projet a été rouge des semaines
   pour un fichier mort. Préférer une résolution en cascade — env capturé s'il
   est encore valide, puis `nix develop <flake> --command <outil>`, puis saut
   annoncé.
4. **CI (optionnel)** — jamais en mode perso — proposer de générer la CI à étages (fast sur MR/PR,
   full sur la branche par défaut + nightly). Forge déduite de
   `git remote get-url origin` (gitlab/github ; pas de remote → sauter).
   GitLab : demander l'image docker (`{{CI_IMAGE}}`, défaut `debian:stable-slim`
   avec l'avertissement d'y mettre la toolchain du projet).
   **Ne jamais écraser** un `.gitlab-ci.yml`/workflow existant — proposer le
   contenu à intégrer à la main.
5. **Timeout du hook Stop** — défaut 600 s dans `settings.json`. Le hook Stop
   ne lance que `check.sh --fast` (garde-fou léger), jamais le build/e2e complet
   (réservé au pre-push), seulement si l'état a bougé depuis le dernier vert,
   et un rouge donné ne le fait bloquer qu'une fois ; le défaut suffit ; ne le
   toucher que si la phase fast elle-même est très longue (sed après copie ; le
   template reste du JSON valide).
6. **Ratchet de tests (optionnel)** — commande une-ligne qui imprime le nombre
   de tests (`{{TEST_COUNT_CMD}}`), ou « aucun » (ratchet inerte). Défauts :

   | Stack | TEST_COUNT_CMD |
   |---|---|
   | C host (harnais type KaSe) | `grep -rho 'TEST_ASSERT' test/ \| wc -l` |
   | Rust | `grep -rho '#\[test\]' src/ \| wc -l` |
   | Python | `grep -rho 'def test_' tests/ \| wc -l` |
   | Node / Go / autre | demander |

   Mêmes contraintes que la commande fast (pas de `$(...)`, pas de `"`), et **pas de `$` non échappé** — `TEST_COUNT_CMD`, `SRC_GREP` et `TEST_GREP` sont assignés en double quotes dans le template, un `$2` d'awk y serait expansé (`set -u` → crash).
   Si activé : `.tripwire-testcount` est créé au premier check vert et doit
   être **committé** (comme `.tripwire-variant`) — baisser le ratchet = diff
   visible en review.
7. **Chemins de test et de source** — forme grep des tests (`{{TEST_GREP}}`,
   ex. `^test/`) et des sources (`{{SRC_GREP}}`, ex. `^src/|^main/`) pour l'avis
   « source sans test » de `check.sh`, ou « aucun » (avis inerte).

## Étape 3 — Génération

Templates dans `templates/` de cette skill. Remplacer les placeholders puis
écrire dans le repo cible :

| Template | Destination cible | chmod |
|---|---|---|
| `check.sh.tmpl` | `scripts/check.sh` | `+x` |
| `pre-push.tmpl` | `scripts/hooks/pre-push` | `+x` |
| `install-hooks.sh.tmpl` | `scripts/install-hooks.sh` | `+x` |
| `cc_stop.sh.tmpl` | `scripts/hooks/cc_stop.sh` | `+x` |
| `cc_session_start.sh.tmpl` | `scripts/hooks/cc_session_start.sh` | `+x` |
| `gitlab-ci.yml.tmpl` | `.gitlab-ci.yml` (si CI acceptée, forge gitlab, fichier absent) | — |
| `github-actions.yml.tmpl` | `.github/workflows/tripwire.yml` (si CI acceptée, forge github, fichier absent) | — |
| `tripwire.d/ratchet.sh.tmpl` | `scripts/tripwire.d/ratchet.sh` — **seulement si** ratchet demandé (question 6) | — |
| `tripwire.d/divergences.sh.tmpl` | `scripts/tripwire.d/divergences.sh` — **seulement si** le repo a des écarts déclarés | — |
| `tripwire.d/contrat.sh.tmpl` | `scripts/tripwire.d/contrat.sh` — **seulement si** l'utilisateur veut un `COMPORTEMENTS.md` | — |
| `settings.json.tmpl` | `.claude/settings.json` (**merge**, voir plus bas) — perso : `.claude/settings.local.json` | — |
| `claude-md-section.md.tmpl` | section ajoutée au `CLAUDE.md` — perso : `CLAUDE.local.md` | — |
| `perso-exclude.tmpl` | ajouté à `.git/info/exclude` — **mode perso seulement** | — |

### Briques : n'installer que ce qui est demandé

`check.sh` est un **noyau** (~160 lignes : modes, verrou, skip-si-déjà-vert,
phase rapide, phase complète, verdict, historique). Il source
`scripts/tripwire.d/*.sh` s'ils existent ; chaque brique s'enregistre dans
`TW_PRE_FAST` ou `TW_POST_FULL` et le noyau l'appelle. Un dépôt standard n'a
**aucune brique**. Retirer un mécanisme = `rm scripts/tripwire.d/<brique>.sh`.
Ne jamais installer une brique « au cas où » : chaque ligne installée est une
ligne à comprendre pour la retirer.

### Fiche de divergences

`.tripwire-divergences` n'a pas de template : elle n'existe que si le projet a
des écarts. Créée à la main, une ligne par écart assumé, **committée** (comme
`.tripwire-testcount`) — son diff est le mécanisme de review.

- Deux cas écrivent des lignes **dès le scaffold initial** : la procédure
  « dialecte divergent » (un alias = une divergence, voir Étape 0) et **toute
  dégradation d'environnement demandée par l'utilisateur** (test désactivé,
  étape de build sautée, garde assouplie parce que la machine ou la CI ne suit
  pas). La déclarer immédiatement : c'est exactement ce genre de dégradation
  qu'une propagation de templates a écrasé le 2026-08-05, en sortant verte.
- Le fichier hôte d'une divergence doit être **suivi par git** : un fichier
  gitignoré ne change pas l'empreinte du skip-si-déjà-vert, sa perte peut donc
  passer sous un « déjà vert — skip ».

### Contrat de comportements

`COMPORTEMENTS.md` n'a pas de template non plus : il s'écrit **avec
l'utilisateur**, jamais inventé. Chaque comportement attendu est une puce
taguée : `[test:X]` (X apparaît dans un fichier de test — c'est la seule garde
que `check.sh` vérifie : rouge si X disparaît), `[smoke:X]` (note pour le smoke
test manuel de la release, jamais vérifiée par le check), ou `[NON GARDÉ]`
(compté dans `.tripwire-nongardes`, ratchet strict au pre-push).

Une source modifiée sans test ni ligne au contrat déclenche un **avis** d'une
ligne dans la sortie de `check.sh` — jamais un blocage. Une semaine de blocage au Stop sur un
vrai projet a produit 66 commits taxés d'une ligne et un tag `[smoke:]`
grossier devenu l'échappatoire universelle : la question est utile, la
contrainte ne l'était pas.

### Débrayage

`TRIPWIRE_OFF=1` dans l'environnement (par session : `TRIPWIRE_OFF=1 claude`)
ou un fichier `.tripwire-off` à la racine (par dépôt, ignoré par git) coupe les
deux hooks Claude Code (Stop, SessionStart) et le hook SessionStart du plugin — silence total, rien
désinstallé. Le pre-push git n'est pas concerné : il ne coûte aucun token et a
son échappatoire (`--no-verify`). Ajouter `.tripwire-off` au `.gitignore` du
projet au scaffold — **sauf en mode perso** : l'exclude le couvre déjà, et le
`.gitignore` appartient à l'équipe.

## Étape 4 — Validation (OBLIGATOIRE avant de conclure)

```bash
command -v python3   # requis par les hooks (parsing JSON) — avertir si absent
bash -n scripts/check.sh scripts/hooks/*.sh scripts/hooks/pre-push scripts/install-hooks.sh
# Aucun placeholder résiduel ne doit rester :
grep -rn '{{' scripts/ .claude/settings.json CLAUDE.md && echo "PLACEHOLDERS RESTANTS — corriger avant de conclure" || true
./scripts/install-hooks.sh
test -x scripts/hooks/pre-push
git config --get core.hooksPath    # doit afficher scripts/hooks
./scripts/check.sh --fast          # doit être VERT
# Divergences : si le repo en déclare, l'assertion doit être verte.
# --force est indispensable : sans lui, le check précédent a déjà stampé l'état
# et le skip-si-déjà-vert rendrait 0 sans rien revérifier.
# Fiche absente = cas normal, ce n'est pas un échec.
if [ -f .tripwire-divergences ]; then
  ./scripts/check.sh --fast --force        # doit être VERT
else
  echo "pas de fiche de divergences — normal si le repo n'a aucun écart assumé"
fi
# Stop : rc=0 sur vert
echo '{}' | scripts/hooks/cc_stop.sh; echo "rc=$?"           # rc=0
# Mode perso : rien ne doit apparaître
git status --porcelain                                     # identique à avant le scaffold
# SessionStart : rc=0 toujours ; installe core.hooksPath s'il manque
echo '{}' | scripts/hooks/cc_session_start.sh; echo "rc=$?"   # rc=0
```

Si `check.sh --fast` est rouge : diagnostiquer avec l'utilisateur (commande
fast incorrecte ?) avant de conclure. Ne jamais livrer un tripwire rouge.

## Étape 5 — Récap final

Lister les fichiers créés/modifiés, rappeler :
- `./scripts/install-hooks.sh` à lancer sur chaque nouveau clone ;
- `echo <variante> > .tripwire-variant` pour changer la variante courante ;
- les hooks Claude Code s'activent à la prochaine session.
