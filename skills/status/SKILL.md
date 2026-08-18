---
name: status
description: Use when checking the health of a tripwire-equipped project — scaffold up to date? git/platform hooks active? last check green and when? fast-phase duration drift? watched-path blind spots? Also fleet mode across all equipped repos. Trigger on "/tripwire:status", "état du tripwire", "diagnostic tripwire", "le tripwire est à jour ?", "/tripwire:status --fleet", "état de la flotte tripwire".
---

# tripwire:status — diagnostic one-shot

Rapport compact sur l'état du pipeline anti-régression du repo courant.
Lecture seule : ce skill ne modifie RIEN.

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
ls scripts/hooks/                     # pre-push + hooks cc_ présents ?
grep -o 'scripts/hooks/[a-z_]*\.sh' .claude/settings.json 2>/dev/null || true
```

### 3. État
```bash
GD="$(git rev-parse --git-dir)"
ls -lt "$GD/tripwire/" 2>/dev/null | head -12     # stamps green-* (fraîcheur mtime)
head -2 "$GD/tripwire/last-fail.log" 2>/dev/null  # dernier échec: commande + mode
cat .tripwire-variant 2>/dev/null                 # variante courante (multi)
```
Un stamp `green-full` plus récent que le dernier échec = le rouge a été résorbé.

### 4. Adéquation de la phase rapide (history.tsv : epoch<TAB>mode<TAB>durée_s<TAB>rc)

La phase rapide est fixée à l'entretien d'init et **ne se rouvre jamais toute
seule** : un projet grossit, sa boucle courte cesse d'être courte, et le
garde-budget se contente d'avertir à chaque run — un avertissement permanent ne
se distingue plus du silence. Cette section transforme la mesure en diagnostic
nommé, avec une action.

```bash
awk -F'\t' -v B="${TRIPWIRE_FAST_BUDGET:-30}" '
$2=="fast" { n++; d[n]=$3; last=$3; if($4!=0) ko++; if($3>B) over++ }
END{
  if(n==0){ print "phase rapide : jamais exécutée — elle ne vérifie rien"; exit }
  for(i=1;i<n;i++) for(j=i+1;j<=n;j++) if(d[i]>d[j]){t=d[i];d[i]=d[j];d[j]=t}
  med=d[int((n+1)/2)]
  printf "runs:%d mediane:%ds derniere:%ds hors-budget:%d/%d echecs:%d/%d\n", n,med,last,over+0,n,ko+0,n
  if (med > B) printf "  DERIVE persistante : mediane %ds > budget %ds\n", med, B
  else if (last > 2*med && last > 5) printf "  SAUT soudain : %ds contre une mediane de %ds\n", last, med
  if (ko >= n && n >= 3) printf "  JAMAIS VERTE : %d/%d runs en echec\n", ko, n
}' "$GD/tripwire/history.tsv" 2>/dev/null
# La phase rapide est-elle un doublon de la phase complète ?
grep -m1 '^FAST_RUN_CMD=' scripts/check.sh
grep -m1 -A4 '^build_variant()' scripts/check.sh
```
(Tri à la main plutôt que `asort` : `asort` est propre à gawk.)

**Chaque constat sort avec une action, jamais seul :**

| constat | ce que ça veut dire | action à proposer |
|---|---|---|
| DÉRIVE persistante | la boucle courte n'en est plus une ; le garde-budget crie dans le vide depuis longtemps | découper par module (`MODULE_FAST` existe déjà), ou déplacer la partie lente vers la phase complète |
| SAUT soudain | un changement récent l'a alourdie, et rien ne l'a signalé comme un événement | identifier ce qui a été ajouté depuis le dernier run court, puis découper ou déplacer |
| JAMAIS VERTE | elle signale autre chose qu'une régression — environnement absent, chemin mort, fichier d'env périmé | lire `last-fail.log` : si la cause est un outil manquant, elle doit **sauter en annonçant**, pas rougir (voir la règle de l'Étape 2 d'init) |
| phase rapide == phase complète | il n'y a pas de boucle courte du tout | lui donner un oracle rapide propre au projet (tests hôte, lint, ERC…) et laisser le build en phase complète |
| jamais exécutée | elle ne vérifie rien depuis le scaffold | la revoir entièrement |

Si un constat sort, recommander `/tripwire:init` — il rouvre l'entretien de la
phase rapide au lieu de la préserver aveuglément (voir son Étape 0).

### 5. Dérive de surveillance (heuristique — « à vérifier », pas verdict)
```bash
git log --since='30 days ago' --name-only --pretty=format: 2>/dev/null | grep -v '^$' \
  | cut -d/ -f1 | sort -u        # dossiers actifs (repli: git ls-files si repo < 30 j)
grep -h -A1 'case "\$FP" in' scripts/hooks/*post_edit.sh | sed -n '2p'   # la ligne de patterns suit le case
```
Comparer : tout dossier actif contenant du code, absent des patterns, hors
`docs/`, fichiers racine, `scripts/` et dossiers de config (`.claude/`,
`.github/`) → le lister comme angle mort potentiel avec la ligne
`case` corrigée à proposer.

## Sortie

Un tableau (section → état ✓/⚠/✗ → détail court) suivi de 0 à 3 **actions
recommandées** concrètes (commande exacte ou skill à lancer). Ne pas inventer
de problème : sections vides = « rien à signaler ».

## Mode flotte (`--fleet` / « état de la flotte »)

Vue d'ensemble de TOUS les repos équipés, au lieu du diagnostic profond d'un
seul. Racine du scan : le dossier parent du repo courant (ou le chemin donné
par l'utilisateur). Toujours en lecture seule.

```bash
ROOT="$(dirname "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")"
for d in "$ROOT"/*/; do
  [ -f "$d/scripts/check.sh" ] || continue
  # v suivi d'un chiffre — sinon le « v » de « vérité » matche sur les scaffolds pré-tampon
  TAMPON="$(sed -n '2p' "$d/scripts/check.sh" | grep -o 'v[0-9][0-9.]*' || echo 'pré-v0.5.0')"
  GD="$(git -C "$d" rev-parse --absolute-git-dir 2>/dev/null)"
  # pas de glob green-* : un glob vide est une erreur sous zsh
  LASTGREEN="$(ls -t "$GD/tripwire" 2>/dev/null | grep '^green-' | head -1)"
  [ -n "$LASTGREEN" ] && LASTGREEN="$(date -r "$GD/tripwire/$LASTGREEN" '+%F %H:%M' 2>/dev/null)"
  LASTFAIL="$(date -r "$GD/tripwire/last-fail.log" '+%F %H:%M' 2>/dev/null || true)"
  BRANCH="$(git -C "$d" branch --show-current 2>/dev/null)"
  DIRTY="$(git -C "$d" status --porcelain 2>/dev/null | head -1)"
  echo "$(basename "$d")|$TAMPON|$BRANCH${DIRTY:+ (dirty)}|vert:${LASTGREEN:--}|rouge:${LASTFAIL:--}"
done
```

Rapport : un tableau **repo | scaffold | branche | dernier vert | dernier
rouge**, avec la version courante du plugin en référence. Terminer par les
actions : repos en retard de version → `/tripwire:init` dans chacun (citer
l'écart via l'historique des templates) ; repo sans stamp vert récent →
suggérer d'y lancer `./scripts/check.sh`.
