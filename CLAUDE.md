# tripwire — Claude Code instructions

Plugin multi-plateforme (Claude Code / Mistral Vibe) qui scaffolde un pipeline
anti-régression. Voir `README.md` pour l'usage.

## Tests

Le « vert » de ce repo est `tests/e2e.sh` : il instancie les templates sur un
repo jouet (mono-cible + multi-variantes) et vérifie vert/rouge/hooks/dégradation.

```bash
bash tests/e2e.sh   # doit afficher « E2E: tout vert » (exit 0)
```

## Release

Workflow piloté par `/tripwire:release`. La version est portée par le tag git
`vX.Y.Z` **et** dupliquée dans les manifests `.claude-plugin/plugin.json` et
`.claude-plugin/marketplace.json` (le champ `version` que lit `claude plugin
update` — il doit suivre le tag).

- **Pré-flight** : working tree propre + `bash tests/e2e.sh` vert.
- **Build d'artefacts** : aucun (plugin non compilé, distribué via marketplace).
- **Artefacts à attacher** : aucun.

### Smoke test

Aucune (décision explicite) — `tests/e2e.sh` couvre l'intégralité du pipeline généré.
