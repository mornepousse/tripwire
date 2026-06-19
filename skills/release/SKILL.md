---
name: release
description: Use when cutting a release in a tripwire-enabled project — git tag vX.Y.Z as single version source, full check.sh must be green, manual smoke-test checklist walked before tagging, build artifacts, create GitLab/GitHub release. Trigger on "/tripwire:release", "prépare une release", "cut une release", "publie vX.Y.Z".
---

# tripwire:release — workflow de release générique

## Détection de plateforme (Étape 0)

**D'abord, détecter la plateforme pour savoir quel fichier de config lire** :
- Si `CLAUDE_PROJECT_DIR` est défini → CONFIG_MD = "CLAUDE.md"
- Sinon si `VIBE_PROJECT_DIR` est défini → CONFIG_MD = "VIBE.md"
- Sinon → CONFIG_MD = "CLAUDE.md" (défaut pour compatibilité descendante)

## Principes (non négociables)

1. **Tag git `vX.Y.Z` = source de vérité de la version.** Jamais de fichier
   VERSION. Entre releases, la version dérive de `git describe --tags`.
2. **`./scripts/check.sh` complet VERT obligatoire avant de tagger.**
   Pas d'exception, pas de `--no-verify` sur une release.
3. Working tree propre (`git status` clean) avant de tagger.
4. Le smoke test manuel (s'il est défini) se déroule AVANT le tag — un humain a vu
   le produit fonctionner, pas seulement le build passer.

## Première utilisation sur un projet

Si le {CONFIG_MD} cible n'a pas de section « Release », demander :
- commande(s) de build des artefacts (et leurs chemins de sortie) ;
- artefacts à attacher à la release (globs) ;
- une **checklist smoke-test** : 3 à 8 vérifications manuelles du produit réel
  (lancer l'app et tester les flux critiques, flasher et tester le matériel,
  exécuter les commandes principales…), ou "aucune" explicitement.
Puis **persister** ces réponses dans une section `## Release` du {CONFIG_MD}
cible pour les runs suivants (commandes de build et artefacts au niveau de la
section, checklist sous-section `### Smoke test`).

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
3. **Smoke test manuel** : lire la sous-section `### Smoke test` du `## Release`
   du {CONFIG_MD} cible. La dérouler item par item avec l'utilisateur (AskUserQuestion —
   un item peut être coché, échoué, ou sauté avec raison).
   - Un item **échoué** → STOP, pas de tag.
   - Tous les items sautés → demander confirmation explicite avant de continuer.
   - Sous-section absente (projet pré-v0.2) → proposer d'en créer une ; si la
     réponse est "aucune", persister `Aucune (décision explicite)` dans la
     sous-section pour ne plus reposer la question.
   - Sous-section contenant `Aucune (décision explicite)` → passer silencieusement.
4. **Tag + push** :
   ```bash
   git tag vX.Y.Z
   git push && git push --tags
   ```
   En cas d'échec du build à l'étape 5 : ne pas laisser un tag orphelin —
   `git push origin :refs/tags/vX.Y.Z && git tag -d vX.Y.Z`, corriger, recommencer.
5. **Build des artefacts** : lire la section `## Release` du {CONFIG_MD} cible
   pour obtenir les commandes de build et les globs d'artefacts, puis les exécuter.
   Vérifier que chaque artefact attendu existe.
6. **Créer la release** — détecter le forge via `git remote get-url origin` :
   Vérifier d'abord que le CLI est installé (`command -v glab` / `command -v gh`) ;
   sinon, traiter comme le cas "autre".
   - contient `gitlab` → `glab release create vX.Y.Z <fichiers...> --notes "<notes>"`
     (fichiers en arguments positionnels = upload direct)
   - contient `github` → `gh release create vX.Y.Z <fichiers...> --notes "<notes>"`
   - autre → donner les fichiers et laisser l'utilisateur publier.
7. **Récap** : version, artefacts, URL de la release.

## Notes de release

Générer les notes depuis
`git log "$(git describe --tags --abbrev=0 HEAD^)"..HEAD --oneline`
(le tag précédent ; pour une première release, prendre tout l'historique), groupées
par type (feat/fix/docs/…). Les proposer à l'utilisateur avant publication.
