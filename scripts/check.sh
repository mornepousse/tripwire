#!/usr/bin/env bash
# Tripwire anti-régression tripwire — source unique de vérité du "quoi vérifier".
# Généré par /tripwire:init. Adapter ICI ; les hooks ne font qu'appeler ce script.
# Modes:
#   check.sh                  -> full: phase rapide + toutes les variantes
#   check.sh --fast           -> phase rapide uniquement (~secondes)
#   check.sh --variant <name> -> phase rapide + une seule variante
# Sortie non-zéro si au moins un rouge (toutes les variantes sont tentées en mode full).
# Conçu pour hooks git/Claude Code + CI.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR" || exit 1

# Variantes de build. Laisser vide pour un projet mono-cible.
ALL_VARIANTS=()

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YEL=$'\033[1;33m'; NC=$'\033[0m'
fail() { echo "${RED}✗ $*${NC}" >&2; }
ok()   { echo "${GREEN}✓ $*${NC}"; }
info() { echo "${YEL}» $*${NC}"; }

MODE="full"
SINGLE_VARIANT=""
case "${1:-}" in
  --fast)    MODE="fast" ;;
  --variant) MODE="single"; SINGLE_VARIANT="${2:-}";
             [ -z "$SINGLE_VARIANT" ] && { fail "--variant requires a name"; exit 2; } ;;
  "" )       MODE="full" ;;
  *)         fail "unknown arg: $1"; exit 2 ;;
esac

# ---- Phase rapide (boucle courte, cible < 30 s) ----
run_fast() {
  info "Phase rapide…"
  if ( bash tests/lint.sh ) >/dev/null 2>&1; then
    ok "Phase rapide OK"
    return 0
  else
    fail "Phase rapide: échec (relance pour le détail: bash tests/lint.sh)"
    return 1
  fi
}

# ---- Phase complète ----
# Multi-variantes: appelée une fois par variante ($v = nom).
# Mono-cible: appelée une fois avec $v vide.
build_variant() {
  local v="$1"
  info "Build ${v:-complet}…"
  if ( bash tests/e2e.sh ) >/dev/null 2>&1; then
    ok "Build ${v:-complet} OK"
    return 0
  else
    fail "Build ${v:-complet}: échec (relance pour le détail: bash tests/e2e.sh)"
    return 1
  fi
}

rc=0
run_fast || rc=1

if [ "$MODE" = "single" ]; then
  build_variant "$SINGLE_VARIANT" || rc=1
elif [ "$MODE" = "full" ]; then
  if [ "${#ALL_VARIANTS[@]}" -eq 0 ]; then
    build_variant "" || rc=1
  else
    for v in "${ALL_VARIANTS[@]}"; do
      build_variant "$v" || rc=1
    done
  fi
fi

echo "========================================"
if [ "$rc" -eq 0 ]; then ok "check.sh: tout vert"; else fail "check.sh: ROUGE"; fi
echo "========================================"
exit "$rc"
