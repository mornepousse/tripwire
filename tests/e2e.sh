#!/usr/bin/env bash
# E2E tripwire : instancie les templates (cas mono-cible, sans env setup)
# sur un repo jouet et vérifie vert/rouge/hooks. Exit 0 si tout passe.
set -uo pipefail
PLUGIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"
git init -q -b main

mkdir -p scripts/hooks src
printf '#!/usr/bin/env bash\nexit 0\n' > fast.sh && chmod +x fast.sh
printf '#!/usr/bin/env bash\nexit 0\n' > build.sh && chmod +x build.sh

# --- Instanciation (sed) : mono-cible, pas d'env setup ---
sed -e 's|{{PROJECT_NAME}}|toy|g' \
    -e 's|{{VARIANTS_SPACE_SEPARATED}}||g' \
    -e 's|{{FAST_CMD}}|./fast.sh|g' \
    -e 's|{{VARIANT_BUILD_CMD}}|./build.sh|g' \
    "$PLUGIN/skills/init/templates/check.sh.tmpl" > scripts/check.sh
sed -e 's|{{PROJECT_NAME}}|toy|g' -e '/{{ENV_SETUP_BLOCK}}/d' \
    "$PLUGIN/skills/init/templates/pre-push.tmpl" > scripts/hooks/pre-push
cp "$PLUGIN/skills/init/templates/install-hooks.sh.tmpl" scripts/install-hooks.sh
sed -e 's|{{WATCHED_PATH_PATTERNS}}|*"/src/"*|g' \
    "$PLUGIN/skills/init/templates/cc_post_edit.sh.tmpl" > scripts/hooks/cc_post_edit.sh
sed -e '/{{VARIANT_STATE_BLOCK}}/d' -e '/{{ENV_SETUP_BLOCK}}/d' \
    -e 's|{{ENV_AVAILABLE_TEST}}|true|g' \
    -e 's|{{STOP_CHECK_ARGS}}||g' -e 's|{{STOP_CHECK_DESC}}|complet|g' \
    "$PLUGIN/skills/init/templates/cc_stop.sh.tmpl" > scripts/hooks/cc_stop.sh
chmod +x scripts/check.sh scripts/hooks/* scripts/install-hooks.sh

fails=0
chk() { local desc="$1" want="$2" got="$3"
  if [ "$got" = "$want" ]; then echo "✓ $desc"; else echo "✗ $desc (want $want, got $got)"; fails=1; fi }

# Aucun placeholder résiduel
if grep -rn '{{' scripts/ >/dev/null; then echo "✗ placeholders résiduels"; fails=1; else echo "✓ pas de placeholder résiduel"; fi

# Frontmatters des templates gen-agents : structurellement valides
# (name/description double-quotés sur une ligne — pas de dépendance pyyaml)
for a in test-author code-reviewer debugger; do
  F="$PLUGIN/skills/gen-agents/templates/$a.md.tmpl"
  if awk '/^---$/{c++} c==1 && /^name: "/{n=1} c==1 && /^description: "/ && /"$/{d=1} END{exit !(n&&d)}' "$F"; then
    echo "✓ frontmatter $a"
  else
    echo "✗ frontmatter $a (name/description non quotés sur une ligne)"; fails=1
  fi
done

# Vert : fast, full, stop hook, post-edit (fichier surveillé + non surveillé)
./scripts/check.sh --fast >/dev/null 2>&1;             chk "fast vert" 0 $?
./scripts/check.sh >/dev/null 2>&1;                    chk "full vert" 0 $?
scripts/hooks/cc_stop.sh </dev/null >/dev/null 2>&1;   chk "stop hook vert" 0 $?
echo '{"tool_input":{"file_path":"'"$TMP"'/src/a.c"}}' | scripts/hooks/cc_post_edit.sh >/dev/null 2>&1
chk "post-edit surveillé vert" 0 $?
echo '{"tool_input":{"file_path":"'"$TMP"'/README.md"}}' | scripts/hooks/cc_post_edit.sh >/dev/null 2>&1
chk "post-edit non surveillé ignoré" 0 $?

# install-hooks
./scripts/install-hooks.sh >/dev/null 2>&1
chk "core.hooksPath" "scripts/hooks" "$(git config --get core.hooksPath)"

# Rouge : casser fast
printf '#!/usr/bin/env bash\nexit 1\n' > fast.sh
./scripts/check.sh --fast >/dev/null 2>&1;             chk "fast rouge -> rc 1" 1 $?
scripts/hooks/pre-push </dev/null >/dev/null 2>&1;     chk "pre-push bloque" 1 $?
echo '{"tool_input":{"file_path":"'"$TMP"'/src/a.c"}}' | scripts/hooks/cc_post_edit.sh >/dev/null 2>&1
chk "post-edit rouge -> rc 2" 2 $?
scripts/hooks/cc_stop.sh </dev/null >/dev/null 2>&1;   chk "stop rouge -> rc 2" 2 $?

# Rouge : fast vert mais build cassé -> full rouge, fast vert
printf '#!/usr/bin/env bash\nexit 0\n' > fast.sh
printf '#!/usr/bin/env bash\nexit 1\n' > build.sh
./scripts/check.sh --fast >/dev/null 2>&1;             chk "fast vert (build cassé)" 0 $?
./scripts/check.sh >/dev/null 2>&1;                    chk "full rouge (build cassé)" 1 $?

echo "----------------------------------------"
if [ "$fails" -eq 0 ]; then echo "E2E: tout vert"; else echo "E2E: ROUGE"; fi
exit "$fails"
