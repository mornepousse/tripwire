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
   Si `git describe --tags` échoue (aucun tag existant — première release),
   proposer `v0.1.0` comme premier tag.
2. **Pré-flight** :
   ```bash
   git status --porcelain        # doit être vide
   ./scripts/check.sh            # doit être VERT (full)
   test -f VERSION && echo "ATTENTION: fichier VERSION présent — source de version ambiguë" || true
   ```
   Rouge → STOP, diagnostiquer, ne pas tagger.
3. **Tag + push** :
   ```bash
   git tag vX.Y.Z
   git push && git push --tags
   ```
   En cas d'échec du build à l'étape 4 : ne pas laisser un tag orphelin —
   `git push origin :refs/tags/vX.Y.Z && git tag -d vX.Y.Z`, corriger, recommencer.
4. **Build des artefacts** : lire la section `## Release` du `CLAUDE.md` cible
   pour obtenir les commandes de build et les globs d'artefacts, puis les exécuter.
   Vérifier que chaque artefact attendu existe.
5. **Créer la release** — détecter le forge via `git remote get-url origin` :
   Vérifier d'abord que le CLI est installé (`command -v glab` / `command -v gh`) ;
   sinon, traiter comme le cas "autre".
   - contient `gitlab` → `glab release create vX.Y.Z <fichiers...> --notes "<notes>"`
     (fichiers en arguments positionnels = upload direct)
   - contient `github` → `gh release create vX.Y.Z <fichiers...> --notes "<notes>"`
   - autre → donner les fichiers et laisser l'utilisateur publier.
6. **Récap** : version, artefacts, URL de la release.

## Notes de release

Générer les notes depuis
`git log "$(git describe --tags --abbrev=0 HEAD^)"..HEAD --oneline`
(le tag précédent ; pour une première release, prendre tout l'historique), groupées
par type (feat/fix/docs/…). Les proposer à l'utilisateur avant publication.
