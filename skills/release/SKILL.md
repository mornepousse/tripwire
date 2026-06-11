---
name: release
description: Use when cutting a release in a tripwire-enabled project — git tag vX.Y.Z as single version source, full check.sh must be green, build artifacts, create GitLab/GitHub release. Trigger on "/tripwire:release", "prépare une release", "cut une release", "publie vX.Y.Z".
---

# tripwire:release — workflow de release générique

## Principes (non négociables)

1. **Tag git `vX.Y.Z` = source de vérité de la version.** Jamais de fichier
   VERSION. Entre releases, la version dérive de `git describe --tags`.
2. **`./scripts/check.sh` complet VERT obligatoire avant de tagger.**
   Pas d'exception, pas de `--no-verify` sur une release.
3. Working tree propre (`git status` clean) avant de tagger.

## Première utilisation sur un projet

Si le CLAUDE.md cible n'a pas de section « Release », demander :
- commande(s) de build des artefacts (et leurs chemins de sortie) ;
- artefacts à attacher à la release (globs).
Puis **persister** ces réponses dans une section `## Release` du CLAUDE.md
cible pour les runs suivants.

## Workflow

1. **Déterminer la version** : lire `git describe --tags` ; proposer le bump
   (patch/minor/major) via AskUserQuestion si l'utilisateur n'a pas donné de
   version explicite.
2. **Pré-flight** :
   ```bash
   git status --porcelain        # doit être vide
   ./scripts/check.sh            # doit être VERT (full)
   ```
   Rouge → STOP, diagnostiquer, ne pas tagger.
3. **Tag + push** :
   ```bash
   git tag vX.Y.Z
   git push && git push --tags
   ```
4. **Build des artefacts** : commandes de la section Release du CLAUDE.md
   cible. Vérifier que chaque artefact attendu existe.
5. **Créer la release** — détecter le forge via `git remote get-url origin` :
   - contient `gitlab` → `glab release create vX.Y.Z <artefacts...>`
   - contient `github` → `gh release create vX.Y.Z <artefacts...>`
   - autre → donner les fichiers et laisser l'utilisateur publier.
6. **Récap** : version, artefacts, URL de la release.

## Notes de release

Générer les notes depuis `git log <tag précédent>..HEAD --oneline`, groupées
par type (feat/fix/docs/…). Les proposer à l'utilisateur avant publication.
