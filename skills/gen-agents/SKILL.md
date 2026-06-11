---
name: gen-agents
description: Use when generating project-specialized subagents (test-author, code-reviewer, debugger) into a target repo's .claude/agents/. Reads the target CLAUDE.md and repo structure to fill in project context. Trigger on "/tripwire:gen-agents", "génère les agents du projet", "ajoute un agent de review spécialisé".
---

# tripwire:gen-agents — agents spécialisés au projet

Génère dans `.claude/agents/` du repo cible jusqu'à 5 agents à partir des
templates de `templates/` : `test-author`, `code-reviewer`, `debugger`,
`maintainer`, `security-auditor`.

## Workflow

1. **Demander** (AskUserQuestion, multiSelect) lesquels générer (défaut : les 3
   de base : `test-author`, `code-reviewer`, `debugger` ; `maintainer` et
   `security-auditor` proposés en option).
2. **Collecter le contexte** — lire le `CLAUDE.md` cible et la structure du
   repo pour remplir :
   - Vérifier d'abord que `scripts/check.sh` existe dans le repo cible ;
     sinon proposer `/tripwire:init` d'abord, ou remplacer la commande de
     vérification dans les corps générés par la vraie commande de test du
     projet.
   - `{{PROJ}}` : slug court (ex. `kase`, demander si ambigu) ;
   - `{{PROJECT_NAME}}` : nom complet du projet (ex. `KaSe_firmware`) ;
   - `{{PROJECT_CONTEXT}}` : 3-6 lignes — stack, structure des dossiers,
     conventions clés ;
   - `{{TEST_CONVENTIONS}}` : où vivent les tests, comment les lancer,
     contraintes (parallel-safe, mocks…) ;
   - `{{REVIEW_CHECKLIST}}` : extraire les conventions du CLAUDE.md en liste
     vérifiable (ex. « pas de malloc dans les hot paths ») ;
   - `{{BUILD_DEBUG_CMDS}}` : commandes de build/log/diagnostic du projet ;
   - `{{DEPS_INFRA}}` : lister les fichiers de deps/lock et préoccupations
     d'infra du repo cible (ex. `idf_component.yml + dependencies.lock,
     partitions.csv…` pour KaSe, `Cargo.toml + Cargo.lock` pour Rust) ;
   - `{{ATTACK_SURFACE}}` : lister les points d'entrée d'inputs externes,
     selon la nature du projet — embedded : protocoles série/radio, OTA ;
     desktop/CLI : fichiers importés, IPC, arguments, presse-papier ;
     web/mobile : endpoints API, deep links / URL schemes, formulaires,
     storage local, désérialisation JSON. Si non évident, poser la question.
   Si le CLAUDE.md cible est pauvre, poser 1-2 questions ciblées plutôt
   qu'inventer.
3. **Générer** `.claude/agents/<proj>-<role>.md` pour chaque agent choisi.
   Ne pas écraser un agent existant sans accord explicite.
4. **Vérifier** : frontmatter présent (`name`, `description` avec exemples),
   placeholders tous remplis (`grep -n '{{' .claude/agents/<proj>-*.md` ne
   doit rien retourner) ; et valider le YAML du frontmatter de chaque agent
   généré — si pyyaml est disponible :
   `python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]).read().split('---')[1])" <fichier>` ;
   sinon vérifier structurellement que `name:` et `description:` sont des
   chaînes **double-quotées sur une seule ligne** (quotes internes échappées
   `\"`, exemples encodés avec des `\n` littéraux), comme dans les templates.
5. **Rappeler** : les agents sont disponibles à la prochaine session, et la
   section « Quand invoquer les agents » peut être ajoutée au CLAUDE.md cible.
