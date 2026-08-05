---
name: release
description: Use when cutting a release in a tripwire-enabled project — git tag vX.Y.Z as single version source, full check.sh must be green, manual smoke-test checklist walked before tagging, build artifacts, create GitLab/GitHub release. Trigger on "/tripwire:release", "prépare une release", "cut une release", "publie vX.Y.Z".
---

# tripwire:release — workflow de release générique

## Principes (non négociables)

1. **Tag git `vX.Y.Z` = source de vérité de la version.** Jamais de fichier
   VERSION. Entre releases, la version dérive de `git describe --tags`.
2. **`./scripts/check.sh` complet VERT obligatoire avant de tagger.**
   Pas d'exception, pas de `--no-verify` sur une release.
3. Working tree propre (`git status` clean) avant de tagger.
4. Le smoke test manuel (s'il est défini) se déroule AVANT le tag — un humain a vu
   le produit fonctionner, pas seulement le build passer.

## Première utilisation sur un projet

Si le CLAUDE.md cible n'a pas de section « Release », demander :
- commande(s) de build des artefacts (et leurs chemins de sortie) ;
- artefacts à attacher à la release (globs) ;
- **fichiers dupliquant la version** : manifests portant un champ `version` qui
  doit suivre le tag (ex. `.claude-plugin/plugin.json` + `marketplace.json`,
  `package.json`, `Cargo.toml`), ou "aucun". Sans cette sync, les outils qui
  lisent le champ (ex. `claude plugin update`) ne voient jamais la release ;
- une **checklist smoke-test** : 3 à 8 vérifications manuelles du produit réel
  (lancer l'app et tester les flux critiques, flasher et tester le matériel,
  exécuter les commandes principales…), ou "aucune" explicitement.
Puis **persister** ces réponses dans une section `## Release` du CLAUDE.md
cible pour les runs suivants (commandes de build, artefacts et fichiers de
version au niveau de la section, checklist sous-section `### Smoke test`).

## Workflow

1. **Déterminer la version** : lire `git describe --tags`, puis **analyser le
   contenu réel du tag à venir** avant de proposer quoi que ce soit :
   ```bash
   git log "$(git describe --tags --abbrev=0)"..HEAD --oneline
   ```
   Dériver le bump du contenu (Conventional Commits) :
   - un `BREAKING CHANGE` / `type!:` → **major** ;
   - sinon au moins un `feat:` (ou un commit ajoutant une capacité, même mal
     préfixé — lire les messages, pas seulement les préfixes) → **minor** ;
   - sinon (fix/docs/chore uniquement) → **patch**.
   Proposer ce bump via AskUserQuestion (l'utilisateur tranche), en **citant
   les commits qui le justifient** — en particulier tout `feat` encore jamais
   release, facile à rater quand la demande initiale ne parlait que d'un fix.
   Si `git describe --tags` échoue (aucun tag existant — première release),
   proposer `v0.1.0` comme premier tag.
2. **Sync des fichiers de version** : si la section `## Release` du CLAUDE.md
   liste des fichiers dupliquant la version, les mettre à jour vers `X.Y.Z` et
   les committer AVANT de tagger (commit `chore: bump vX.Y.Z`). Le tag doit
   pointer sur un commit où manifests et tag concordent.
3. **Pré-flight** :
   ```bash
   git status --porcelain        # doit être vide
   ./scripts/check.sh            # doit être VERT (full)
   test -f VERSION && echo "ATTENTION: fichier VERSION présent — source de version ambiguë" || true
   ```
   Rouge → STOP, diagnostiquer, ne pas tagger.
4. **Smoke test manuel** : lire la sous-section `### Smoke test` du `## Release`
   du CLAUDE.md cible. La dérouler item par item avec l'utilisateur (AskUserQuestion —
   un item peut être coché, échoué, ou sauté avec raison).
   - Un item **échoué** → STOP, pas de tag.
   - Tous les items sautés → demander confirmation explicite avant de continuer.
   - Sous-section absente (projet pré-v0.2) → proposer d'en créer une ; si la
     réponse est "aucune", persister `Aucune (décision explicite)` dans la
     sous-section pour ne plus reposer la question.
   - Sous-section contenant `Aucune (décision explicite)` → passer silencieusement.
5. **Tag + push** :
   ```bash
   git tag vX.Y.Z
   git push && git push --tags
   ```
   En cas d'échec du build à l'étape 6 : ne pas laisser un tag orphelin —
   `git push origin :refs/tags/vX.Y.Z && git tag -d vX.Y.Z`, corriger, recommencer.
6. **Build des artefacts** : lire la section `## Release` du CLAUDE.md cible
   pour obtenir les commandes de build et les globs d'artefacts, puis les exécuter.
   Vérifier que chaque artefact attendu existe.
7. **Créer la release** — détecter le forge via `git remote get-url origin` :
   Vérifier d'abord que le CLI est installé (`command -v glab` / `command -v gh`) ;
   sinon, traiter comme le cas "autre".
   - contient `gitlab` → `glab release create vX.Y.Z <fichiers...> --notes "<notes>"`
     (fichiers en arguments positionnels = upload direct)
   - contient `github` → `gh release create vX.Y.Z <fichiers...> --notes "<notes>"`
   - autre → donner les fichiers et laisser l'utilisateur publier.
8. **Récap** : version, artefacts, URL de la release. Puis rappels de
   propagation :
   - repo plugin (manifests `.claude-plugin/` présents) → les installs se
     mettent à jour via `claude plugin update <plugin>@<marketplace>` ;
   - des templates scaffoldés ont changé dans cette release → rappeler que les
     projets équipés se mettent à jour en relançant le skill d'init (détection
     du retard via le tampon `# tripwire-template:` de leur check.sh).

### Échec de signature (GPG/SSH)

Si un commit ou un tag échoue sur `gpg failed to sign the data` (pinentry sans
TTY, carte/clé indisponible) :
1. proposer d'abord à l'utilisateur de déverrouiller l'agent **dans sa session
   interactive** : `! echo test | gpg --clearsign >/dev/null`, puis réessayer ;
2. sinon proposer (AskUserQuestion) le repli `--no-gpg-sign` (commit/tag non
   signé — le mentionner dans le récap final) ou l'abandon ;
3. ne jamais boucler sur des retries silencieux : chaque tentative relance un
   pinentry chez l'utilisateur.

## Notes de release

Générer les notes depuis
`git log "$(git describe --tags --abbrev=0 HEAD^)"..HEAD --oneline`
(le tag précédent ; pour une première release, prendre tout l'historique), groupées
par type (feat/fix/docs/…). Les proposer à l'utilisateur avant publication.
