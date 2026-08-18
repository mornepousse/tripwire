#!/usr/bin/env bash
# Hook SessionStart du PLUGIN tripwire (pas du scaffold).
#
# Il vit ici, et non dans les fichiers scaffoldés, pour une raison précise : un
# dépôt équipé le reçoit dès `claude plugin update`, sans qu'on ait besoin d'y
# re-scaffolder quoi que ce soit. Sans ça, le mécanisme qui rappelle de propager
# aurait lui-même besoin d'être propagé — et la flotte pourrit pendant ce temps.
#
# Il ne bloque JAMAIS (exit 0 en toutes circonstances) et n'écrit RIEN : il
# compare le tampon du scaffold à la version du plugin et prescrit. L'écriture
# reste le travail de /tripwire:init, qui sait réinjecter les valeurs projet et
# arbitrer les divergences.
set -uo pipefail

CHECK="scripts/check.sh"
[ -f "$CHECK" ] || exit 0          # pas un dépôt équipé — silence total

PLUGIN_JSON="${CLAUDE_PLUGIN_ROOT:-}/.claude-plugin/plugin.json"
[ -f "$PLUGIN_JSON" ] || exit 0    # racine du plugin inconnue — on se tait plutôt que de deviner

PV="$(sed -n 's/.*"version"[: ]*"\([^"]*\)".*/\1/p' "$PLUGIN_JSON" | head -1)"
[ -n "$PV" ] || exit 0

# Tampon du scaffold : « # tripwire-template: vX.Y.Z » en ligne 2 (absent avant v0.5.0).
SV="$(sed -n '2s/^# tripwire-template: *v\{0,1\}\([0-9][0-9.]*\).*/\1/p' "$CHECK")"

emit() {
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json,sys; print(json.dumps({"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":sys.argv[1]}}, ensure_ascii=False))' "$1"
  else
    printf '%s\n' "$1"
  fi
  exit 0
}

if [ -z "$SV" ]; then
  emit "tripwire: ce dépôt est équipé mais son scripts/check.sh ne porte aucun tampon de version (scaffold antérieur à v0.5.0). Le plugin est en v$PV. Lancer /tripwire:init pour le mettre à niveau — il annoncera ce qui a changé avant d'écrire."
fi

[ "$SV" = "$PV" ] && exit 0        # à jour — silence

# Comparaison numérique champ par champ (pas de sort -V : GNU seulement).
CMP="$(awk -v a="$SV" -v b="$PV" 'BEGIN{
  na=split(a,A,"."); nb=split(b,B,"."); n=(na>nb?na:nb)
  for(i=1;i<=n;i++){ x=(i<=na?A[i]+0:0); y=(i<=nb?B[i]+0:0)
    if(x<y){print "retard"; exit} if(x>y){print "avance"; exit} }
  print "egal" }')"

case "$CMP" in
  retard) emit "tripwire: le scaffold de ce dépôt est en v$SV, le plugin en v$PV. Lancer /tripwire:init AVANT d'autre travail — il lit l'historique des versions, annonce ce qui a changé, et préserve les valeurs projet. Un scaffold en retard, c'est un garde-fou qui ne garde pas ce que la version courante garde." ;;
  avance) emit "tripwire: le scaffold de ce dépôt (v$SV) est en AVANCE sur le plugin (v$PV) — incohérence à vérifier : plugin non mis à jour, ou tampon posé à la main ?" ;;
esac
exit 0
