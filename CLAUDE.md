# tripwire — Claude Code instructions

Plugin multi-plateforme (Claude Code / Mistral Vibe) qui scaffolde un pipeline
anti-régression. Voir `README.md` pour l'usage.

## Workflow anti-régression (OBLIGATOIRE)

Source unique de vérité : `scripts/check.sh` (le plugin mange sa propre nourriture).
- `./scripts/check.sh --fast` — lint des templates shell + validation JSON des manifests + cohérence de version (~1 s)
- `./scripts/check.sh` — fast + `tests/e2e.sh` (instancie les templates sur un repo jouet, mono-cible + multi-variantes, et vérifie vert/rouge/hooks/dégradation)
- Skip-si-déjà-vert : état inchangé depuis le dernier vert → sortie immédiate ;
  `--force` (ou `TRIPWIRE_FORCE=1`) pour relancer quand même.
- Ratchet : le nombre d'assertions `chk` d'e2e est cliqueté dans
  `.tripwire-testcount` (committé) — il ne baisse jamais sans un diff assumé ;
  rouge au pre-push si baisse.

**Activation des hooks git (une fois par clone)** :
```bash
./scripts/install-hooks.sh   # ou: git config core.hooksPath scripts/hooks
```
`pre-push` lance le check complet et bloque le push si rouge. WIP : `git push --no-verify`.

**Hooks Claude Code** (`.claude/settings.json`, automatiques) :
- `PostToolUse` sur édition de `skills/`, `tests/` ou `.claude-plugin/` → `check.sh --fast`.
- `Stop` → check complet.

### Norme TDD — nouvelle logique pure
Tout nouveau comportement des templates (mode de check.sh, garde de hook,
dégradation) : assertion e2e écrite **d'abord** dans `tests/e2e.sh`, rouge avant
l'implémentation, verte après.

### Économie de modèles (subagents)
- Haiku OK : transcription de code spécifié, extraction citée (`fichier:ligne`)
  — e2e/lint rattrapent la dérive.
- Jamais sous sonnet : review, audit, debug, écriture d'assertions (une
  tautologie passe l'oracle au vert). Revue finale : le plus fort disponible.

## Release

Workflow piloté par `/tripwire:release`. La version est portée par le tag git
`vX.Y.Z` **et** dupliquée dans les manifests `.claude-plugin/plugin.json` et
`.claude-plugin/marketplace.json` (le champ `version` que lit `claude plugin
update` — il doit suivre le tag).

- **Pré-flight** : working tree propre + `./scripts/check.sh` vert (full).
- **Tampon dogfood** : si les templates ont changé, le `# tripwire-template:`
  de `scripts/check.sh` doit être mis à jour vers la nouvelle version dans le
  commit de bump (cohérence scaffold ↔ plugin).
- **Build d'artefacts** : aucun (plugin non compilé, distribué via marketplace).
- **Artefacts à attacher** : aucun.

### Smoke test

Aucune (décision explicite) — `tests/e2e.sh` couvre l'intégralité du pipeline généré.
