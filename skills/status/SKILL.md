---
name: status
description: Use when checking the health of a tripwire-equipped project — scaffold up to date? git/platform hooks active? last check green and when? fast-phase duration drift? watched-path blind spots? Trigger on "/tripwire:status", "état du tripwire", "diagnostic tripwire", "le tripwire est à jour ?".
---

# tripwire:status — diagnostic one-shot

Rapport compact sur l'état du pipeline anti-régression du repo courant.
Lecture seule : ce skill ne modifie RIEN.

## Plateforme

- `CLAUDE_PROJECT_DIR` défini → hooks dans `.claude/settings.json`, préfixe `cc_`
- sinon `VIBE_PROJECT_DIR` → `.vibe/config.json`, préfixe `vibe_`

## Sections du rapport (dans l'ordre)

### 1. Pipeline
```bash
test -x scripts/check.sh || { echo "pas de tripwire — proposer /tripwire:init"; }
sed -n '2p' scripts/check.sh          # tampon "# tripwire-template: vX.Y.Z" (absent = pré-v0.5.0)
```
Comparer le tampon à la version du plugin (`version` de `.claude-plugin/plugin.json`,
deux niveaux au-dessus du dossier de cette skill). En retard → citer les
changements manqués via « Historique des templates » du skill init et
recommander `/tripwire:init`.

### 2. Hooks
```bash
git config --get core.hooksPath       # attendu: scripts/hooks (sinon: lancer scripts/install-hooks.sh)
ls scripts/hooks/                     # pre-push + hooks de plateforme présents ?
grep -o 'scripts/hooks/[a-z_]*\.sh' .claude/settings.json 2>/dev/null || true   # (ou .vibe/config.json)
```

### 3. État
```bash
GD="$(git rev-parse --git-dir)"
ls -lt "$GD/tripwire/" 2>/dev/null | head -12     # stamps green-* (fraîcheur mtime)
head -2 "$GD/tripwire/last-fail.log" 2>/dev/null  # dernier échec: commande + mode
cat .tripwire-variant 2>/dev/null                 # variante courante (multi)
```
Un stamp `green-full` plus récent que le dernier échec = le rouge a été résorbé.

### 4. Tendance (history.tsv : epoch<TAB>mode<TAB>durée_s<TAB>rc)
```bash
awk -F'\t' '$2=="fast"{d[++n]=$3} END{if(n){asort(d); print "médiane fast:", d[int((n+1)/2)] "s, dernière:", d[n] "s, runs:", n}}' "$GD/tripwire/history.tsv" 2>/dev/null
```
(gawk absent : trier avec `sort -n` en pipe.) Signaler une dérive si la
dernière durée > 2× la médiane ou > `TRIPWIRE_FAST_BUDGET` (défaut 30).

### 5. Dérive de surveillance (heuristique — « à vérifier », pas verdict)
```bash
git log --since='30 days ago' --name-only --pretty=format: 2>/dev/null | grep -v '^$' \
  | cut -d/ -f1 | sort -u        # dossiers actifs (repli: git ls-files si repo < 30 j)
grep -o 'case "\$FP" in' -A2 scripts/hooks/*post_edit.sh | sed -n '2p'   # patterns surveillés
```
Comparer : tout dossier actif contenant du code, absent des patterns, hors
`docs/`, fichiers racine, `scripts/` et dossiers de config (`.claude/`,
`.vibe/`, `.github/`) → le lister comme angle mort potentiel avec la ligne
`case` corrigée à proposer.

## Sortie

Un tableau (section → état ✓/⚠/✗ → détail court) suivi de 0 à 3 **actions
recommandées** concrètes (commande exacte ou skill à lancer). Ne pas inventer
de problème : sections vides = « rien à signaler ».
