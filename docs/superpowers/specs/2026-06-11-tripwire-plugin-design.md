# Plugin Claude Code `tripwire` — design

**Date** : 2026-06-11
**Statut** : approuvé
**Origine** : extraction du pipeline anti-régression du projet KaSe_firmware
(`~/Documents/GitHub/KaSe_firmware`) pour le rendre réutilisable sur tout
futur projet, quel que soit le langage/stack.

## Philosophie — l'invariant extrait

Le pattern qui marche chez KaSe n'est pas une liste de fichiers, c'est un
invariant :

> **Un seul script (`scripts/check.sh`) définit ce que « vert » veut dire.
> Chaque garde-fou (hook git, hook Claude Code, CI) ne fait que l'appeler
> avec un mode adapté à son budget temps.** Fast pour les boucles courtes,
> full avant de pousser, avec dégradation gracieuse quand l'environnement
> n'est pas disponible.

Corollaires :
- Pas de duplication du « quoi vérifier » entre hooks/CI — ils appellent
  tous le même script.
- Exit code fiable (pas de grep sur la sortie).
- En mode full, **toutes** les variantes sont tentées (pas d'arrêt au
  premier rouge) pour un diagnostic complet en un run.
- L'automatisation (hooks) prime sur les agents pour les problèmes de
  process. Les agents sont un complément spécialisé par projet.

## Livrable

Un plugin Claude Code nommé `tripwire` :
- **Repo local** : `~/Documents/GitHub/tripwire`
- **Remote** : `gitlab.com/harrael/tripwire` (push après création)
- **Installation** : le repo est sa propre marketplace via
  `.claude-plugin/marketplace.json` (entrée unique, `source: "./"`). Puis :
  ```bash
  claude plugin marketplace add ~/Documents/GitHub/tripwire
  claude plugin install tripwire@tripwire
  ```

## Structure du plugin

```
tripwire/
├── .claude-plugin/
│   ├── plugin.json            # manifest (name, version, description, author)
│   └── marketplace.json       # self-marketplace : liste le plugin avec source "./"
├── README.md
├── skills/
│   ├── init/                  # /tripwire:init — scaffolde le pipeline dans un repo
│   │   ├── SKILL.md
│   │   └── templates/
│   │       ├── check.sh.tmpl
│   │       ├── pre-push.tmpl
│   │       ├── install-hooks.sh.tmpl
│   │       ├── cc_post_edit.sh.tmpl
│   │       ├── cc_stop.sh.tmpl
│   │       ├── settings.json.tmpl
│   │       └── claude-md-section.md.tmpl
│   ├── gen-agents/            # /tripwire:gen-agents — génère les agents spécialisés
│   │   ├── SKILL.md
│   │   └── templates/
│   │       ├── test-author.md.tmpl
│   │       ├── code-reviewer.md.tmpl
│   │       └── debugger.md.tmpl
│   └── release/               # /tripwire:release — workflow de release générique
│       └── SKILL.md
└── docs/superpowers/specs/    # ce document
```

Note : pas de dossier `skills/agents/` — ce nom collisionne avec le dossier
composant réservé `agents/` (subagents) à la racine d'un plugin, d'où
`gen-agents`.

Les templates utilisent des placeholders `{{NOM}}` que la skill remplit en
suivant les instructions du SKILL.md (génération par Claude, pas par un
moteur de template — les templates sont la référence de structure).

## Skill `/tripwire:init`

Workflow guidé, idempotent :

1. **Détection de stack** — cherche les marqueurs (`Cargo.toml`,
   `CMakeLists.txt`, `idf_component.yml`, `package.json`, `pyproject.toml`,
   `go.mod`…) et propose des commandes par défaut. Exemples :
   - Rust : fast = `cargo test`, full = `cargo clippy -- -D warnings` +
     `cargo build --release`
   - ESP-IDF : fast = tests host CMake, full = builds `idf.py` par board
   - Node : fast = `npm test`, full = `npm run lint` + `npm run build`
2. **Questions** (AskUserQuestion, une à la fois) :
   - commande **fast** (boucle courte, cible < 30 s) ;
   - commande(s) **full** ;
   - liste de **variantes** optionnelle (équivalent des 6 boards KaSe ;
     peut être vide → projet mono-cible) ;
   - **chemins surveillés** pour le hook post-edit (ex. `src/`, `main/`) ;
   - **setup d'environnement** optionnel (équivalent du
     `source ~/esp/esp-idf/export.sh`).
3. **Génération** :
   - `scripts/check.sh` — modes `--fast` / `--variant <name>` / full.
     Mono-cible : pas de mode `--variant`, full = fast + build unique.
   - `scripts/hooks/pre-push` + `scripts/install-hooks.sh`
     (`git config core.hooksPath scripts/hooks`).
   - Hooks Claude Code dans `.claude/settings.json` — **merge** si le
     fichier existe déjà, jamais d'écrasement.
   - Fichier d'état `.tripwire-variant` **seulement** si multi-variantes
     (équivalent `.kase-board` — paramètre le hook Stop sans toucher la
     config).
4. **Section CLAUDE.md** — insère le bloc « Workflow anti-régression »
   (commandes check.sh, activation des hooks, interdits spécifiques) +
   **norme TDD** (logique pure → test écrit d'abord), adaptés aux commandes
   du projet. Crée le CLAUDE.md s'il n'existe pas.
5. **Validation** — lance `install-hooks.sh` puis `check.sh --fast` et
   confirme le vert avant de conclure.
6. **Idempotence** — si un tripwire est déjà installé (présence de
   `scripts/check.sh` généré), proposer mise à jour plutôt que régénération
   aveugle.

## `check.sh` générique (template)

Même squelette que KaSe : `set -uo pipefail`, helpers couleur
`fail/ok/info`, parsing des modes, exit code agrégé, bannière finale
vert/rouge. Deux zones paramétrées :

- `run_fast()` — la phase rapide.
- `VARIANTS=(...)` + `build_variant <name>` — la phase complète
  (absente en mono-cible).

Chaque échec affiche la commande de relance manuelle pour le détail
(les sorties sont silencées en temps normal).

## Hooks Claude Code (templates)

- **PostToolUse** (`cc_post_edit.sh`) : extrait `file_path` du JSON stdin,
  filtre sur les chemins surveillés (case/glob paramétré à l'init), lance
  `check.sh --fast`, exit 2 + 8 dernières lignes si rouge.
- **Stop** (`cc_stop.sh`) : source le setup d'env si défini et absent de
  l'environnement ; lance le check du variant courant (lu dans
  `.tripwire-variant`) ou full-light en mono-cible. **Dégradation** : si
  l'env n'est pas disponible, retombe sur `--fast` au lieu de bloquer
  chaque Stop, avec message explicite.

## Skill `/tripwire:gen-agents`

Génère dans `.claude/agents/` du projet cible 3 squelettes spécialisés à
partir du contexte du repo (la skill lit le CLAUDE.md et la structure) :

- `<proj>-test-author` — applique la norme TDD du projet ;
- `<proj>-code-reviewer` — conventions du projet, à invoquer avant
  merge/release ;
- `<proj>-debugger` — diagnostic d'échecs (build, tests, runtime).

Frontmatter avec `description` riche en exemples de déclenchement (format
KaSe : « Examples: user says X → launch Y »).

## Skill `/tripwire:release`

Workflow générique :
1. Tag git `vX.Y.Z` = source de vérité de la version (jamais de fichier
   VERSION). Entre releases : `git describe --tags`.
2. `check.sh` complet vert **obligatoire** avant tag.
3. Build des artefacts (commandes paramétrées au premier usage, mémorisées
   dans la section CLAUDE.md du projet).
4. `glab release create` ou `gh release create` selon le remote détecté.

## Tests / validation du plugin

- Validation structurelle via l'agent `plugin-dev:plugin-validator`.
- Test d'intégration manuel : exécuter `/tripwire:init` sur un repo jetable
  (mini projet Rust ou C) et vérifier : check.sh fonctionne dans les 3
  modes, pre-push bloque sur rouge, hooks CC déclenchent, merge
  settings.json non destructif, section CLAUDE.md insérée.

## Hors périmètre

- CI (GitLab CI/GitHub Actions) : check.sh est conçu pour y être appelé
  tel quel, mais la génération de config CI n'est pas dans ce plugin (v2
  possible).
- Migration de KaSe_firmware lui-même vers le plugin : KaSe garde ses
  scripts existants.
