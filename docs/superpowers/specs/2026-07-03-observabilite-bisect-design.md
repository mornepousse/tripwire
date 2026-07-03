# Observabilité & bisect — design v0.7.0

Date : 2026-07-03 · Statut : validé (brainstorm session)

## Objectif

Fermer la boucle de feedback du pipeline généré : l'échec devient lisible sans
re-run, l'état du tripwire devient interrogeable, la régression devient
localisable dans l'historique. Deux couches : **check.sh produit des données**,
**deux skills les consomment**.

## Couche 1 — données produites par `check.sh` (template `check.sh.tmpl`)

### 1.1 `last-fail.log` — feedback d'échec direct

Problème : sur rouge, la sortie de la commande part en `/dev/null` ; le message
dit « relance pour le détail » → un aller-retour de plus pour l'assistant.

- Sur **échec** d'une phase (fast ou build variant), la sortie capturée est
  écrite dans `.git/tripwire/last-fail.log` :
  - en-tête : `# cmd: <commande>` puis `# mode: <label de phase>` ;
  - corps : sortie stdout+stderr de la commande, **tronquée aux 200 dernières
    lignes** (`tail -200`).
- Le fichier est **écrasé** à chaque nouvel échec (un seul log, le dernier).
- Les messages d'échec de check.sh deviennent :
  `échec — détail: .git/tripwire/last-fail.log (ou relance: <cmd>)`.
- Les hooks (cc/vibe post_edit et stop) ne changent pas de structure : ils
  relaient déjà `tail` du résumé de check.sh, qui contient désormais le chemin
  du log. L'assistant peut `Read` le log au lieu de relancer.
- Un passage **vert n'efface pas** le log (diagnostic post-mortem possible) ;
  la fraîcheur s'évalue par mtime vs history.tsv.
- Implémentation : la commande s'exécute avec sortie redirigée vers un fichier
  temporaire (`$GITDIR/tripwire/.out.$$`), promu en `last-fail.log` sur échec,
  supprimé sur succès. Pas de double exécution.

### 1.2 `history.tsv` — historique des durées

- Chaque exécution **réelle** (pas les skips) appende une ligne TSV dans
  `.git/tripwire/history.tsv` : `epoch<TAB>mode(KEY)<TAB>durée_s<TAB>rc`.
- Rotation : si > 500 lignes, garder les 500 dernières (tail au moment de
  l'append, best-effort, jamais bloquant).
- Le skip-si-vert ne logge pas (sinon les durées ~0 noient la tendance).

### e2e (TDD, assertions d'abord)

- rouge fast → `last-fail.log` existe, contient l'en-tête `# cmd:` et la
  sortie de la commande cassée ; le message de check.sh contient
  `last-fail.log`.
- vert ensuite → le log du dernier échec subsiste (pas d'effacement).
- deux runs réels → `history.tsv` a ≥ 2 lignes, champs epoch/mode/durée/rc ;
  un skip n'ajoute pas de ligne.

## Couche 2 — skills consommateurs

### 2.1 `/tripwire:status` — diagnostic one-shot (nouveau skill `skills/status/`)

Skill d'instructions (pas de template scaffoldé). Sections du rapport :

1. **Pipeline** : `scripts/check.sh` présent ? tampon `# tripwire-template:`
   vs version du plugin (même lecture que l'Étape 0 d'init) → à jour / en
   retard (citer l'historique des templates).
2. **Hooks** : `git config core.hooksPath` = `scripts/hooks` ? hooks de
   plateforme présents dans la config (`.claude/settings.json` /
   `.vibe/config.json`) ?
3. **État** : stamps `green-*` (mode + fraîcheur mtime), variante courante
   (`.tripwire-variant`), dernier échec (`last-fail.log` : mtime + commande de
   l'en-tête).
4. **Tendance** : depuis `history.tsv`, durée médiane et dernière durée de la
   phase fast vs `TRIPWIRE_FAST_BUDGET` (défaut 30) ; signaler une dérive
   (dernière > 2× médiane ou > budget).
5. **Dérive de surveillance** : dossiers contenant des fichiers modifiés
   récemment (`git log --since='30 days ago' --name-only --pretty=format:` ;
   repli : fichiers trackés si historique < 30 j) réduits au premier niveau de
   répertoire, comparés aux patterns du `case` de `*post_edit.sh` → lister les
   dossiers actifs **non surveillés** (en excluant docs/, README, dotfiles,
   et les chemins du scaffold lui-même). Heuristique assumée : rapport
   « à vérifier », pas verdict.

Sortie : tableau compact + actions recommandées (ex. « relance
/tripwire:init pour rattraper v0.6.0 », « ajoute src2/ aux chemins
surveillés »).

### 2.2 `/tripwire:bisect` — localiser la régression (nouveau skill `skills/bisect/`)

- Pré-requis : `scripts/check.sh` présent, working tree propre (sinon stash ou
  abandon — demander).
- Choix du « bon » connu, dans l'ordre : commit donné par l'utilisateur →
  dernier tag `v*` → proposer une liste des derniers commits.
- Exécution :
  ```bash
  git bisect start HEAD <good>
  git bisect run ./scripts/check.sh --fast   # ou --variant <v> si le rouge est là
  git bisect reset
  ```
- Le skip-si-vert est **compatible** : chaque commit visité a une empreinte
  différente ; les états déjà stampés verts skippent (accélération gratuite).
  Codes de sortie : check.sh rend 0/1 (et 2 pour usage incorrect) — dans la
  plage attendue par `git bisect run` (le 125 « skip » n'est pas utilisé).
- Toujours `git bisect reset` en fin (succès ou échec), rapporter le commit
  fautif + son diff résumé.
- Garde : refuser si le rouge n'est pas reproductible sur HEAD
  (`check.sh --fast --force` vert → rien à bisecter).

### e2e bisect

Dans le repo jouet mono : committer ~6 commits dont un qui casse `fast.sh` au
milieu, `git bisect start HEAD <first>` + `git bisect run ./scripts/check.sh
--fast` → `refs/bisect/bad` pointe le commit cassant. (Le skill lui-même est
de l'instruction ; l'e2e valide que check.sh est un oracle bisect correct,
notamment ses codes de sortie.)

## Hors périmètre (décisions explicites)

- CHANGELOG.md auto à la release : écarté (accessoire).
- Quarantaine flaky / re-run auto : écarté (masque de vrais bugs).
- Garde TDD par hook : écarté (faux positifs).
- Dérive de surveillance en hook automatique : écarté au profit d'une section
  de status (heuristique → diagnostic sur demande, pas du bruit par session).

## Impacts

- `skills/init/templates/check.sh.tmpl` : capture d'échec + history (couche 1).
- `skills/init/SKILL.md` : historique des templates v0.7.0.
- `tests/e2e.sh` : assertions couche 1 + oracle bisect.
- Nouveaux : `skills/status/SKILL.md`, `skills/bisect/SKILL.md`.
- `.claude-plugin/*` : rien (les skills sont découverts par dossier).
- README : sections status/bisect dans la table des skills + « Gros projets ».
- Dogfood : régénérer `scripts/check.sh` (tampon v0.7.0) au moment du release.
