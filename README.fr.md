# tripwire

*[English version](README.md)*

Plugin Claude Code qui scaffolde un pipeline anti-régression dans n'importe quel repo.
Extrait du workflow du projet KaSe_firmware.

## L'invariant

> Un seul script (`scripts/check.sh`) définit ce que « vert » veut dire.
> Chaque garde-fou (hook git, hook de plateforme, CI) ne fait que l'appeler
> avec un mode adapté à son budget temps.

- `check.sh --fast` — boucle courte (< 30 s), lancée après chaque édition
  surveillée et à chaque Stop
- `check.sh --variant <name>` — fast + build d'une variante
- `check.sh` — full : fast + toutes les variantes (pre-push, CI)

## Ce qui fait qu'un garde-fou cesse de garder

Un pipeline vert par défaut, dont le rouge est routinier et dont les
avertissements se répètent indéfiniment, ne garde plus rien : il rassure.
Quatre règles, toutes apprises à la dure, l'empêchent de dériver là.

**Une échelle de gravité, pas une alarme unique.** Pendant le travail → informe.
À la conclusion → bloque. Au push → bloque. Le hook `PostToolUse` signale un
rouge sans interrompre, parce que la norme TDD exige d'écrire l'assertion qui
échoue **d'abord** : une alarme bloquante à ce moment-là sonnerait à chaque pas
correct, et une alarme qui sonne toujours finit ignorée. `Stop` et `pre-push`
bloquent — on ne conclut pas un tour, et on ne pousse pas, sur du rouge.

**Un outil absent n'est pas une régression.** Toute commande fast ou full
dépendant d'une toolchain externe se garde par `command -v` et se dégrade en
**saut annoncé**, jamais en rouge. Un rouge qui veut dire « toolchain absente »
est indiscernable d'un rouge qui veut dire « le code est cassé » : en quelques
semaines, plus personne ne lit les rouges du projet. Un saut annoncé n'est pas
un silence vert — il se voit à chaque run. Corollaire : ne jamais figer un
environnement dans un fichier de chemins en dur, ils pourrissent, et le pipeline
devient rouge pour un fichier mort.

**Préserver n'est pas figer.** Relancer init n'écrase jamais vos valeurs projet
— mais c'est cette règle même qui les gèle. Une commande fast choisie le jour du
scaffold n'est jamais rouverte, même quand le projet a grossi sous elle.
`/tripwire:status` lit donc `history.tsv` et nomme la dérive (dépassement
persistant, saut soudain, jamais verte, fast identique à full), chacune avec une
action concrète ; et `/tripwire:init` propose de revoir la commande fast quand
les données montrent qu'elle ne tient plus.

**Un écart délibéré se déclare, ou il meurt en silence.**
`.tripwire-divergences` (TSV committé : `fichier<TAB>motif<TAB>pourquoi`) liste
ce qu'un dépôt fait délibérément autrement que le scaffold standard. `check.sh`
devient rouge quand un motif déclaré disparaît de son fichier hôte — un
re-scaffold, un `cp` ou un agent pressé ne peuvent plus l'effacer discrètement.
Fichier absent → inerte.

## Gros projets

Le contrat « fast < 30 s à chaque édition » tient aussi sur les gros repos grâce
à quatre mécanismes du `check.sh` généré :

- **Skip-si-déjà-vert** : empreinte de l'état du repo (HEAD + diff + fichiers
  non trackés) mémorisée par mode dans `.git/tripwire/` ; si rien n'a bougé
  depuis le dernier vert, le check sort immédiatement. `--force` ou
  `TRIPWIRE_FORCE=1` pour outrepasser (ex. toolchain mise à jour).
- **Scoping monorepo** : table `MODULE_FAST=("glob:commande" …)` dans check.sh ;
  les hooks passent le fichier édité (`--changed`) et la phase rapide ne lance
  que les tests du module touché.
- **Verrou + debounce** : `flock` empêche deux checks concurrents (le second
  sort poliment) ; les hooks post-édition ne relancent pas de check à moins de
  `TRIPWIRE_DEBOUNCE` secondes du précédent (défaut 10).
- **Garde-budget** : si la phase rapide dérive au-delà de `TRIPWIRE_FAST_BUDGET`
  secondes (défaut 30), check.sh l'annonce — le tripwire surveille son propre
  contrat.
- **Échec lisible sans re-run** : la sortie du dernier rouge est capturée dans
  `.git/tripwire/last-fail.log` (l'assistant la lit au lieu de relancer la
  commande) ; chaque passage réel logge sa durée dans `history.tsv` —
  `/tripwire:status` en tire la tendance.

`/tripwire:init` propose aussi une **CI à étages** (fast sur MR/PR, full sur la
branche par défaut + nightly) et ajuste le timeout du hook Stop aux builds longs.

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

## S'adosser à tripwire (cohabitation)

Les briques de tripwire — `check.sh` (oracle 0/1), les slots de hooks (le merge
de `settings.json` préserve les hooks étrangers), la phase fast, la CI à
étages — sont des points d'ancrage pour l'outillage tiers :

| Outil | Point d'ancrage | Intégration |
|---|---|---|
| [TDD Guard](https://github.com/nizos/tdd-guard) | slot hooks (PreToolUse) | Discipline TDD *par édition* en amont ; tripwire reste l'oracle en aval (Stop/pre-push) + ratchet. Installer à côté — le merge d'init le préserve. ⚠ envoie le code édité à un modèle de validation via API |
| pre-commit / lefthook | l'oracle | Leur config appelle `./scripts/check.sh --fast` — l'invariant survit. Un seul propriétaire du routage : si le repo a déjà pre-commit, tripwire s'y insère comme entrée au lieu de posséder `core.hooksPath` |
| [Betterer](https://phenomnomnominal.github.io/betterer/) (JS) | la phase fast | `betterer ci` dans `FAST_CMD` = ratchet multi-métriques committé, son rouge devient le rouge du check |
| Mutation testing (cargo-mutants, mutmut, Stryker) | CI à étages (slot nightly) | La « preuve de morsure » systématisée, hors boucle locale |

### Sécurité des greffons tiers (NON NÉGOCIABLE)

Un hook tiers s'exécute **avec vos permissions, dans votre session, à chaque
édition** — c'est une dépendance à accès shell, pas un gadget. Avant d'adosser
quoi que ce soit :

1. **Passe de vetting** : lire le script de hook lui-même (pas le README) ;
   identifier ce qui **quitte la machine** (ex. TDD Guard envoie le code à une
   API de validation) ; vérifier les scripts `postinstall` npm et les
   dépendances transitives ; mainteneur, activité, licence.
2. **Épingler la version exacte** : version npm exacte (pas de `^`/`~`),
   `rev:` en SHA pour pre-commit, commit épinglé pour les plugins de
   marketplace. Le lockfile est committé.
3. **Jamais de mise à jour automatique** : toute montée de version passe par
   une **review du diff** (le vecteur malware classique est la mise à jour
   compromise d'un paquet sain — la version que vous avez auditée n'est pas
   celle que l'update installera). Même discipline que le ratchet : un
   changement de version = une ligne de diff assumée en review.
4. En organisation : `strictKnownMarketplaces` (voir section Équipes) pour
   borner les sources installables.

## Économie de modèles (haiku sans hallucination)

L'oracle mécanique de tripwire (check.sh, ratchet, preuve de morsure) rend les
modèles économiques **sûrs là où une erreur est rattrapée**, et seulement là :

| Tâche | Modèle | Pourquoi c'est sûr (ou pas) |
|---|---|---|
| Transcription de code spécifié, refactor mécanique | haiku | le check/la compilation attrapent toute dérive |
| Extraction/lecture (audits gros scope) | haiku | citations `fichier:ligne` obligatoires = vérifiables ; greps ciblés (compressés par rtk) |
| Review, audit, debug, **écriture d'assertions** | sonnet minimum | une tautologie ou un verdict halluciné passent l'oracle au vert — rien ne les rattrape |
| Revue finale avant release | le plus fort disponible | c'est elle qui attrape ce que tout le reste a raté |

Cette doctrine est encodée dans le plugin : section « Économie de modèles » du
CLAUDE.md scaffoldé, `model: sonnet` épinglé sur les agents de jugement de
`gen-agents`, protocole extracteurs/juge de `/tripwire:test-review`.

## Tokens & rtk (optionnel)

tripwire est déjà frugal en tokens par design : `check.sh` exécute tests et
builds en `>/dev/null` (seul le code de retour compte), et les hooks ne
renvoient à l'assistant qu'un résumé tronqué en cas de rouge. Aucune sortie
verbeuse n'entre dans le contexte via le pipeline lui-même.

Le seul moment verbeux est volontaire : quand `check.sh` est rouge, il invite
à relancer la commande pour le détail (`relance pour le détail : <cmd>`). Ce
re-run est une commande shell normale — si vous utilisez [rtk](https://github.com/rtk-ai/rtk)
(proxy qui compresse les sorties de 60-90 %) en interception globale, ce détail
est compressé automatiquement, sans que tripwire ait à s'en occuper.

Autrement dit : **aucune intégration n'est nécessaire.** tripwire reste
sans dépendance et portable ; rtk, s'il est présent, agit sur la seule étape
qui en bénéficie.

## Installation

```bash
# Depuis GitHub :
claude plugin marketplace add https://github.com/mornepousse/tripwire
# Ou depuis GitLab :
claude plugin marketplace add https://gitlab.com/harrael/tripwire
# Ou depuis un clone local :
claude plugin marketplace add ~/Documents/GitHub/tripwire

claude plugin install tripwire@tripwire
```

## Skills

| Skill | Usage |
|---|---|
| `/tripwire:init` | Scaffolde check.sh (skip-si-vert, scoping monorepo, verrou, garde-budget, ratchet de tests, assertion de divergences déclarées), hooks git, hooks Claude Code (PostToolUse en avis / Stop et pre-push bloquants, SessionStart), CI à étages optionnelle, section CLAUDE.md. **Relancé sur un projet équipé** : détecte les scaffolds en retard via le tampon `# tripwire-template:` et propose une mise à jour ciblée sans écraser vos commandes |
| `/tripwire:gen-agents` | Génère jusqu'à 5 agents spécialisés au projet : test-author / code-reviewer / debugger / maintainer / security-auditor (les deux derniers avec mémoire persistante inter-sessions) |
| `/tripwire:release` | Workflow de release : tag git = version, bump semver proposé depuis les commits, check vert obligatoire, sync des manifests de version, glab/gh release |
| `/tripwire:status` | Diagnostic one-shot : scaffold à jour ? hooks actifs ? dernier vert/rouge ? **adéquation de la phase rapide** — dépassement persistant, saut soudain, jamais verte, fast identique à full — chacun avec une action concrète ; angles morts de surveillance. Mode `--fleet` : tableau de tous les repos équipés |
| `/tripwire:bisect` | Localise le commit qui a cassé le check : `git bisect run` avec check.sh comme oracle |
| `/tripwire:test-review` | Audit sémantique des tests : creux, happy-path only, tests de mocks, couplage, parallel-safety, nommage — findings + patchs |

## Mettre à jour un projet équipé

Chaque `check.sh` généré porte un tampon `# tripwire-template: vX.Y.Z`. Après un
`claude plugin update tripwire@tripwire`, relancez `/tripwire:init` dans le
projet : le skill compare le tampon à la version du plugin, annonce ce qui a
changé et met à jour les fichiers scaffoldés en préservant vos commandes
fast/build, variantes et chemins surveillés.

Le hook `SessionStart` installe par ailleurs les hooks git automatiquement à
chaque nouveau clone — plus besoin de penser à `./scripts/install-hooks.sh`.

## Équipes (Claude for Teams / Enterprise)

Pour déployer le pipeline à toute une organisation, deux mécanismes Claude Code
se combinent avec tripwire (Admin Settings → Claude Code → Managed settings) :

- **Marketplace contrôlé** : `strictKnownMarketplaces` dans les managed settings
  limite les marketplaces autorisés — ajoutez-y l'URL de ce repo pour distribuer
  tripwire officiellement (`claude plugin marketplace add <url>` chez chaque dev).
- **Hooks managés** : les managed settings acceptent une clé `hooks` identique à
  celle que `/tripwire:init` écrit dans `.claude/settings.json`. Un admin peut
  donc pousser les hooks `PostToolUse`/`Stop`/`SessionStart` org-wide. Pour que
  les repos non-tripwire restent silencieux, garder les commandes derrière un
  test d'existence :
  ```json
  { "type": "command",
    "command": "H=\"$CLAUDE_PROJECT_DIR/scripts/hooks/cc_stop.sh\"; [ -x \"$H\" ] && exec \"$H\"; exit 0" }
  ```

L'invariant reste inchangé : les hooks managés n'appellent que `scripts/check.sh`
du repo courant ; chaque projet garde la définition de son « vert ».

## Licence

[MIT](LICENSE). Par ailleurs, **les fichiers que `/tripwire:init` et
`/tripwire:gen-agents` génèrent dans vos projets vous appartiennent** — aucune
attribution ni mention de licence requise sur le code scaffoldé.
