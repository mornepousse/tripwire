---
name: gen-agents
description: Use when generating project-specialized subagents (test-author, code-reviewer, debugger) into a target repo's .claude/agents/. Reads the target CLAUDE.md and repo structure to fill in project context. Trigger on "/tripwire:gen-agents", "génère les agents du projet", "ajoute un agent de review spécialisé".
---

# tripwire:gen-agents — agents spécialisés au projet

Génère dans `.claude/agents/` du repo cible jusqu'à 3 agents à partir des
templates de `templates/` : `test-author`, `code-reviewer`, `debugger`.

## Workflow

1. **Demander** (AskUserQuestion, multiSelect) lesquels générer (défaut : les 3).
2. **Collecter le contexte** — lire le `CLAUDE.md` cible et la structure du
   repo pour remplir :
   - `{{PROJ}}` : slug court (ex. `kase`, demander si ambigu) ;
   - `{{PROJECT_NAME}}` : nom complet du projet (ex. `KaSe_firmware`) ;
   - `{{PROJECT_CONTEXT}}` : 3-6 lignes — stack, structure des dossiers,
     conventions clés ;
   - `{{TEST_CONVENTIONS}}` : où vivent les tests, comment les lancer,
     contraintes (parallel-safe, mocks…) ;
   - `{{REVIEW_CHECKLIST}}` : extraire les conventions du CLAUDE.md en liste
     vérifiable (ex. « pas de malloc dans les hot paths ») ;
   - `{{BUILD_DEBUG_CMDS}}` : commandes de build/log/diagnostic du projet.
   Si le CLAUDE.md cible est pauvre, poser 1-2 questions ciblées plutôt
   qu'inventer.
3. **Générer** `.claude/agents/<proj>-<role>.md` pour chaque agent choisi.
   Ne pas écraser un agent existant sans accord explicite.
4. **Vérifier** : frontmatter présent (`name`, `description` avec exemples),
   placeholders tous remplis (`grep -n '{{' .claude/agents/<proj>-*.md` ne
   doit rien retourner).
5. **Rappeler** : les agents sont disponibles à la prochaine session, et la
   section « Quand invoquer les agents » peut être ajoutée au CLAUDE.md cible.
