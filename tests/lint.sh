#!/usr/bin/env bash
# Phase rapide tripwire : lint syntaxique des templates shell + validation JSON
# des manifests. Le « vert » complet reste tests/e2e.sh (via scripts/check.sh).
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
rc=0

# Syntaxe bash : scripts de test + templates shell (les placeholders {{X}} restent
# des mots valides pour bash -n).
for f in tests/*.sh hooks/*.sh skills/init/templates/*.tmpl; do
  case "$f" in
    *.json.tmpl|*md-section*.tmpl|*.yml.tmpl) continue ;;  # non-shell
  esac
  if ! bash -n "$f" 2>/dev/null; then
    echo "✗ bash -n: $f" >&2; rc=1
  fi
done

# JSON valide : manifests plugin + templates de config JSON.
for j in .claude-plugin/plugin.json .claude-plugin/marketplace.json \
         hooks/hooks.json \
         skills/init/templates/settings.json.tmpl; do
  if ! python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$j" 2>/dev/null; then
    echo "✗ JSON invalide: $j" >&2; rc=1
  fi
done

# Cohérence de version : plugin.json et marketplace.json doivent porter la même.
if ! python3 -c '
import json
p = json.load(open(".claude-plugin/plugin.json"))["version"]
m = json.load(open(".claude-plugin/marketplace.json"))["plugins"][0]["version"]
raise SystemExit(0 if p == m else 1)
' 2>/dev/null; then
  echo "✗ versions divergentes entre plugin.json et marketplace.json" >&2; rc=1
fi

# Historique des templates (skills/init/SKILL.md) : trié du plus ancien au plus
# récent. Une ligne insérée au mauvais endroit a été commise trois fois de suite ;
# un agent qui lit la table pour savoir quoi re-scaffolder lirait un ordre faux.
if ! python3 - <<'PYEOF'
import re, sys
rows = [l for l in open("skills/init/SKILL.md") if re.match(r"^\| v\d+\.\d+\.\d+ \|", l)]
keys = [tuple(map(int, re.match(r"^\| v(\d+)\.(\d+)\.(\d+)", l).groups())) for l in rows]
sys.exit(0 if keys == sorted(keys) else 1)
PYEOF
then
  echo "✗ skills/init/SKILL.md : la table « Historique des templates » n'est pas triée par version" >&2; rc=1
fi

# Le dogfood doit lancer e2e en phase complète. Un re-scaffold a failli y mettre
# la commande fast à la place : « tout vert » sans qu'aucun test ne tourne.
if ! grep -q 'bash tests/e2e.sh' scripts/check.sh; then
  echo "✗ scripts/check.sh : la phase complète ne lance pas tests/e2e.sh — le dogfood serait un faux vert" >&2; rc=1
fi
# Le dogfood est un noyau + des briques : la brique ratchet doit être là (le
# plugin cliquette ses propres assertions), avec sa commande de comptage.
if ! grep -q "^TEST_COUNT_CMD=\"grep -c 'chk \.' tests/e2e.sh\"" scripts/tripwire.d/ratchet.sh 2>/dev/null; then
  echo "✗ scripts/tripwire.d/ratchet.sh : brique ratchet absente ou sans commande de comptage" >&2; rc=1
fi

[ "$rc" -eq 0 ] && echo "✓ lint OK"
exit "$rc"
