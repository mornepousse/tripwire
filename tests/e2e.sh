#!/usr/bin/env bash
# E2E tripwire : instancie les templates (cas mono-cible, sans env setup)
# sur un repo jouet et vérifie vert/rouge/hooks. Exit 0 si tout passe.
set -uo pipefail
PLUGIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export TRIPWIRE_DEBOUNCE=0   # les tests enchaînent les hooks plus vite que le debounce réel
cd "$TMP"
git init -q -b main

mkdir -p scripts/hooks src
printf '#!/usr/bin/env bash\nexit 0\n' > fast.sh && chmod +x fast.sh
printf '#!/usr/bin/env bash\nexit 0\n' > build.sh && chmod +x build.sh

# --- Instanciation (sed) : mono-cible, pas d'env setup ---
sed -e 's|{{PROJECT_NAME}}|toy|g' \
    -e 's|{{TRIPWIRE_VERSION}}|v9.9.9|g' \
    -e 's|{{VARIANTS_SPACE_SEPARATED}}||g' \
    -e 's|{{MODULE_FAST_ENTRIES}}||g' \
    -e 's|{{FAST_CMD}}|./fast.sh|g' \
    -e 's|{{VARIANT_BUILD_CMD}}|./build.sh|g' \
    -e 's|{{SRC_GREP}}||g' \
    -e 's|{{TEST_GREP}}||g' \
    -e 's|{{TEST_COUNT_CMD}}|cat ntests.txt|g' \
    "$PLUGIN/skills/init/templates/check.sh.tmpl" > scripts/check.sh
sed -e 's|{{PROJECT_NAME}}|toy|g' -e '/{{ENV_SETUP_BLOCK}}/d' \
    "$PLUGIN/skills/init/templates/pre-push.tmpl" > scripts/hooks/pre-push
cp "$PLUGIN/skills/init/templates/install-hooks.sh.tmpl" scripts/install-hooks.sh
sed -e 's|{{WATCHED_PATH_PATTERNS}}|*"/src/"*\|*"/test/"*|g' \
    -e 's|{{TEST_PATH_PATTERNS}}|*"/test/"*|g' \
    -e 's|{{ASSERT_PATTERN}}|assert|g' \
    "$PLUGIN/skills/init/templates/cc_post_edit.sh.tmpl" > scripts/hooks/cc_post_edit.sh
sed -e '/{{VARIANT_STATE_BLOCK}}/d' -e '/{{ENV_SETUP_BLOCK}}/d' \
    -e 's|{{ENV_AVAILABLE_TEST}}|true|g' \
    -e 's|{{STOP_CHECK_ARGS}}||g' -e 's|{{STOP_CHECK_DESC}}|complet|g' \
    "$PLUGIN/skills/init/templates/cc_stop.sh.tmpl" > scripts/hooks/cc_stop.sh
# Templates Mistral Vibe (payload: file_path au niveau racine, pas tool_input)
sed -e 's|{{WATCHED_PATH_PATTERNS}}|*"/src/"*\|*"/test/"*|g' \
    -e 's|{{TEST_PATH_PATTERNS}}|*"/test/"*|g' \
    -e 's|{{ASSERT_PATTERN}}|assert|g' \
    "$PLUGIN/skills/init/templates/vibe_post_edit.sh.tmpl" > scripts/hooks/vibe_post_edit.sh
sed -e '/{{VARIANT_STATE_BLOCK}}/d' -e '/{{ENV_SETUP_BLOCK}}/d' \
    -e 's|{{ENV_AVAILABLE_TEST}}|true|g' \
    -e 's|{{STOP_CHECK_ARGS}}||g' -e 's|{{STOP_CHECK_DESC}}|complet|g' \
    "$PLUGIN/skills/init/templates/vibe_stop.sh.tmpl" > scripts/hooks/vibe_stop.sh
chmod +x scripts/check.sh scripts/hooks/* scripts/install-hooks.sh

fails=0
chk() { local desc="$1" want="$2" got="$3"
  if [ "$got" = "$want" ]; then echo "✓ $desc"; else echo "✗ $desc (want $want, got $got)"; fails=1; fi }

# Aucun placeholder résiduel
if grep -rn '{{' scripts/ >/dev/null; then echo "✗ placeholders résiduels"; fails=1; else echo "✓ pas de placeholder résiduel"; fi

# Tampon de version du scaffold (upgrade path de /tripwire:init)
grep -q '^# tripwire-template: v9.9.9$' scripts/check.sh
chk "tampon tripwire-template présent" 0 $?

# Frontmatters des templates gen-agents : structurellement valides
# (name/description double-quotés sur une ligne — pas de dépendance pyyaml)
for a in test-author code-reviewer debugger maintainer security-auditor; do
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
scripts/hooks/vibe_stop.sh </dev/null >/dev/null 2>&1;   chk "vibe stop hook vert" 0 $?
echo '{"file_path":"'"$TMP"'/src/a.c"}' | scripts/hooks/vibe_post_edit.sh >/dev/null 2>&1
chk "vibe post-edit surveillé vert" 0 $?
echo '{"file_path":"'"$TMP"'/README.md"}' | scripts/hooks/vibe_post_edit.sh >/dev/null 2>&1
chk "vibe post-edit non surveillé ignoré" 0 $?

# install-hooks
./scripts/install-hooks.sh >/dev/null 2>&1
chk "core.hooksPath" "scripts/hooks" "$(git config --get core.hooksPath)"

# SessionStart : auto-installe les hooks git si absents (mono : pas de ligne variante)
sed -e '/{{SESSION_VARIANT_LINE}}/d' \
    "$PLUGIN/skills/init/templates/cc_session_start.sh.tmpl" > scripts/hooks/cc_session_start.sh
chmod +x scripts/hooks/cc_session_start.sh
git config --unset core.hooksPath
OUT="$(echo '{}' | scripts/hooks/cc_session_start.sh 2>/dev/null)"; rc=$?
chk "session-start installe les hooks (rc)" 0 $rc
chk "session-start: core.hooksPath posé" "scripts/hooks" "$(git config --get core.hooksPath)"
echo "$OUT" | grep -q "hooks git installés"; chk "session-start: contexte émis" 0 $?
OUT="$(echo '{}' | scripts/hooks/cc_session_start.sh 2>/dev/null)"; rc=$?
chk "session-start idempotent (rc)" 0 $rc
chk "session-start idempotent (silencieux)" "" "$OUT"

# ===== Options gros projets =====
# Skip-si-déjà-vert : même état -> skip ; --force relance ; état modifié -> re-run
./scripts/check.sh --fast >/dev/null 2>&1                       # stampe l'état courant
OUT="$(./scripts/check.sh --fast 2>&1)"; rc=$?
chk "skip état inchangé (rc)" 0 $rc
echo "$OUT" | grep -q "skip"; chk "skip état inchangé (message)" 0 $?
OUT="$(./scripts/check.sh --fast --force 2>&1)"
echo "$OUT" | grep -q "Phase rapide OK"; chk "--force relance vraiment" 0 $?
touch src/nouveau.c                                             # empreinte différente
OUT="$(./scripts/check.sh --fast 2>&1)"
echo "$OUT" | grep -q "Phase rapide OK"; chk "état modifié -> re-run" 0 $?

# history.tsv : chaque run réel logge une ligne TSV ; les skips non
N0="$(wc -l < .git/tripwire/history.tsv 2>/dev/null || echo 0)"
./scripts/check.sh --fast --force >/dev/null 2>&1
N1="$(wc -l < .git/tripwire/history.tsv 2>/dev/null || echo 0)"
chk "history: run réel loggé" "$((N0+1))" "$N1"
./scripts/check.sh --fast >/dev/null 2>&1     # état inchangé -> skip
N2="$(wc -l < .git/tripwire/history.tsv 2>/dev/null || echo 0)"
chk "history: skip non loggé" "$N1" "$N2"
awk -F'\t' 'NF!=4{bad=1} END{exit bad}' .git/tripwire/history.tsv
chk "history: 4 champs TSV" 0 $?

# Garde-budget : dépassement -> avertissement non fatal
OUT="$(TRIPWIRE_FAST_BUDGET=-1 ./scripts/check.sh --fast --force 2>&1)"; rc=$?
chk "budget dépassé: rc reste 0" 0 $rc
echo "$OUT" | grep -q "budget"; chk "budget dépassé: avertissement émis" 0 $?

# Verrou : un check en cours -> le second sort poliment (rc 0, pas de double run)
if command -v flock >/dev/null 2>&1; then
  ( flock -x 9; sleep 2 ) 9>.git/tripwire/lock &
  LOCKPID=$!
  sleep 0.3
  OUT="$(./scripts/check.sh --fast --force 2>&1)"; rc=$?
  chk "verrou: second check sort (rc)" 0 $rc
  echo "$OUT" | grep -q "en cours"; chk "verrou: message skip" 0 $?
  wait "$LOCKPID"
else
  echo "~ flock absent — test verrou sauté"
fi

# Scoping module : --changed route la phase rapide sur le module touché
mkdir -p modA
printf '#!/usr/bin/env bash\ntouch modA.ran\nexit 0\n' > modA.sh && chmod +x modA.sh
sed -e 's|{{PROJECT_NAME}}|toy|g' \
    -e 's|{{TRIPWIRE_VERSION}}|v9.9.9|g' \
    -e 's|{{VARIANTS_SPACE_SEPARATED}}||g' \
    -e 's#{{MODULE_FAST_ENTRIES}}#"*/modA/*:./modA.sh"#' \
    -e 's|{{FAST_CMD}}|./fast.sh|g' \
    -e 's|{{VARIANT_BUILD_CMD}}|./build.sh|g' \
    -e 's|{{SRC_GREP}}||g' \
    -e 's|{{TEST_GREP}}||g' \
    -e 's|{{TEST_COUNT_CMD}}||g' \
    "$PLUGIN/skills/init/templates/check.sh.tmpl" > scripts/check_mod.sh
chmod +x scripts/check_mod.sh
rm -f modA.ran
./scripts/check_mod.sh --fast --changed "$TMP/modA/x.c" --force >/dev/null 2>&1
chk "module: rc vert" 0 $?
[ -f modA.ran ]; chk "module: commande du module exécutée" 0 $?
rm -f modA.ran
./scripts/check_mod.sh --fast --changed "$TMP/src/a.c" --force >/dev/null 2>&1
[ -f modA.ran ]; chk "module: hors module -> fast global" 1 $?

# Templates CI : instanciation sans résidu, étages fast/full présents
sed -e 's|{{CI_IMAGE}}|debian:stable-slim|g' \
    "$PLUGIN/skills/init/templates/gitlab-ci.yml.tmpl" > ci-gl.yml 2>/dev/null
sed -e 's|{{DEFAULT_BRANCH}}|main|g' \
    "$PLUGIN/skills/init/templates/github-actions.yml.tmpl" > ci-gh.yml 2>/dev/null
grep -q -- "check.sh --fast" ci-gl.yml && grep -q "scripts/check.sh$" ci-gl.yml \
  && grep -q -- "check.sh --fast" ci-gh.yml && grep -q "scripts/check.sh$" ci-gh.yml \
  && ! grep -q '{{' ci-gl.yml ci-gh.yml
chk "templates CI instanciés (étages fast/full, pas de résidu)" 0 $?

# ===== Oracle git-bisect : check.sh rend 0/1, bisect run localise le fautif =====
GITC() { git -c user.email=e2e@toy -c user.name=e2e -c commit.gpgsign=false "$@"; }
git add -A >/dev/null 2>&1 && GITC commit -qm "c1 base verte"
echo 2 > src/f2 && git add -A && GITC commit -qm "c2 verte"
echo 3 > src/f3 && git add -A && GITC commit -qm "c3 verte"
printf '#!/usr/bin/env bash\nexit 1\n' > fast.sh && git add -A && GITC commit -qm "c4 CASSE"
echo 5 > src/f5 && git add -A && GITC commit -qm "c5 toujours rouge"
BAD_EXPECTED="$(git rev-parse HEAD~1)"
git bisect start HEAD HEAD~4 >/dev/null 2>&1
git bisect run ./scripts/check.sh --fast >/dev/null 2>&1
FOUND="$(git rev-parse refs/bisect/bad 2>/dev/null)"
git bisect reset >/dev/null 2>&1
chk "bisect: commit fautif localisé" "$BAD_EXPECTED" "$FOUND"

# ===== Ratchet de tests =====
printf '#!/usr/bin/env bash\nexit 0\n' > fast.sh   # le bloc bisect laisse fast.sh cassé
echo 5 > ntests.txt
./scripts/check.sh --fast --force >/dev/null 2>&1
chk "ratchet: bootstrap crée la référence" "5" "$(cat .tripwire-testcount 2>/dev/null)"
echo 7 > ntests.txt
./scripts/check.sh --fast --force >/dev/null 2>&1
chk "ratchet: auto-bump à la hausse" "7" "$(cat .tripwire-testcount 2>/dev/null)"
echo 6 > ntests.txt
OUT="$(./scripts/check.sh --fast --force 2>&1)"; rc=$?
chk "ratchet: baisse -> avertissement, rc 0" 0 $rc
echo "$OUT" | grep -q "ratchet"; chk "ratchet: message d'avertissement" 0 $?
chk "ratchet: la référence ne baisse pas seule" "7" "$(cat .tripwire-testcount 2>/dev/null)"
OUT="$(TRIPWIRE_RATCHET_STRICT=1 ./scripts/check.sh --fast --force 2>&1)"; rc=$?
chk "ratchet: baisse + STRICT -> rouge" 1 $rc
scripts/hooks/pre-push </dev/null >/dev/null 2>&1
chk "ratchet: pre-push bloque sur baisse" 1 $?
echo 7 > ntests.txt   # remettre compte == référence (sections suivantes propres)

# ===== Garde anti-affaiblissement des tests =====
mkdir -p test
printf 'assert(a);\nassert(b);\nassert(c);\n' > test/t.c
git add -A >/dev/null 2>&1 && GITC commit -qm "c6 tests baseline"
printf 'assert(a);\n' > test/t.c            # 3 -> 1 : perte nette de 2
OUT="$(echo '{"tool_input":{"file_path":"'"$TMP"'/test/t.c"}}' | scripts/hooks/cc_post_edit.sh 2>/dev/null)"; rc=$?
chk "garde assertions: rc 0 (non bloquant)" 0 $rc
echo "$OUT" | grep -q "assertion(s) en moins"; chk "garde assertions: contexte émis" 0 $?
OUT="$(echo '{"file_path":"'"$TMP"'/test/t.c"}' | scripts/hooks/vibe_post_edit.sh 2>&1 >/dev/null)"
echo "$OUT" | grep -q "assertion(s) en moins"; chk "garde assertions: parité vibe (stderr)" 0 $?
printf 'assert(a);\nassert(b);\nassert(c);\nassert(d);\n' > test/t.c   # 3 -> 4 : gain
OUT="$(echo '{"tool_input":{"file_path":"'"$TMP"'/test/t.c"}}' | scripts/hooks/cc_post_edit.sh 2>/dev/null)"
echo "$OUT" | grep -q "assertion"; chk "garde assertions: gain -> silencieux" 1 $?
git checkout -q -- test/t.c

# Rouge : casser fast
printf '#!/usr/bin/env bash\necho BOOM\nexit 1\n' > fast.sh
./scripts/check.sh --fast >/dev/null 2>&1;             chk "fast rouge -> rc 1" 1 $?
[ -f .git/tripwire/last-fail.log ]; chk "last-fail.log créé sur rouge" 0 $?
grep -q '^# cmd: ./fast.sh' .git/tripwire/last-fail.log; chk "last-fail: en-tête cmd" 0 $?
grep -q 'BOOM' .git/tripwire/last-fail.log; chk "last-fail: sortie capturée" 0 $?
OUT="$(./scripts/check.sh --fast 2>&1)"
echo "$OUT" | grep -q "last-fail.log"; chk "message d'échec pointe le log" 0 $?
scripts/hooks/pre-push </dev/null >/dev/null 2>&1;     chk "pre-push bloque" 1 $?
echo '{"tool_input":{"file_path":"'"$TMP"'/src/a.c"}}' | scripts/hooks/cc_post_edit.sh >/dev/null 2>&1
chk "post-edit rouge -> rc 2" 2 $?
scripts/hooks/cc_stop.sh </dev/null >/dev/null 2>&1;   chk "stop rouge -> rc 2" 2 $?
echo '{"file_path":"'"$TMP"'/src/a.c"}' | scripts/hooks/vibe_post_edit.sh >/dev/null 2>&1
chk "vibe post-edit rouge -> rc 2" 2 $?

# Debounce : sous la fenêtre -> pas de re-check (rc 0 même si rouge dessous)
echo '{"tool_input":{"file_path":"'"$TMP"'/src/a.c"}}' | TRIPWIRE_DEBOUNCE=999 scripts/hooks/cc_post_edit.sh >/dev/null 2>&1
chk "debounce: 1er passage seed (rc 2, check réel)" 2 $?
echo '{"tool_input":{"file_path":"'"$TMP"'/src/a.c"}}' | TRIPWIRE_DEBOUNCE=999 scripts/hooks/cc_post_edit.sh >/dev/null 2>&1
chk "debounce: 2e passage sous la fenêtre -> rc 0" 0 $?
echo '{"tool_input":{"file_path":"'"$TMP"'/src/a.c"}}' | scripts/hooks/cc_post_edit.sh >/dev/null 2>&1
chk "debounce: désactivé (0) -> check réel rc 2" 2 $?
scripts/hooks/vibe_stop.sh </dev/null >/dev/null 2>&1; chk "vibe stop rouge -> rc 2" 2 $?
printf '{"stop_hook_active": true}' | scripts/hooks/vibe_stop.sh >/dev/null 2>&1
chk "vibe garde stop_hook_active -> rc 0" 0 $?

# Rouge : fast vert mais build cassé -> full rouge, fast vert
printf '#!/usr/bin/env bash\nexit 0\n' > fast.sh
printf '#!/usr/bin/env bash\nexit 1\n' > build.sh
./scripts/check.sh --fast >/dev/null 2>&1;             chk "fast vert (build cassé)" 0 $?
[ -f .git/tripwire/last-fail.log ]; chk "log conservé après un vert" 0 $?
./scripts/check.sh >/dev/null 2>&1;                    chk "full rouge (build cassé)" 1 $?

# ===== Multi-variantes =====
MULTI="$TMP/multi"
mkdir -p "$MULTI/scripts/hooks"
cd "$MULTI"
git init -q -b main
printf '#!/usr/bin/env bash\nexit 0\n' > fast.sh && chmod +x fast.sh
cat > build.sh <<'EOF'
#!/usr/bin/env bash
[ "${1:-}" = "bad" ] && exit 1
exit 0
EOF
chmod +x build.sh

sed -e 's|{{PROJECT_NAME}}|toy-multi|g' \
    -e 's|{{TRIPWIRE_VERSION}}|v9.9.9|g' \
    -e 's|{{VARIANTS_SPACE_SEPARATED}}|v1 v2|g' \
    -e 's|{{MODULE_FAST_ENTRIES}}||g' \
    -e 's|{{FAST_CMD}}|./fast.sh|g' \
    -e 's|{{VARIANT_BUILD_CMD}}|./build.sh "$v"|g' \
    -e 's|{{SRC_GREP}}||g' \
    -e 's|{{TEST_GREP}}||g' \
    -e 's|{{TEST_COUNT_CMD}}||g' \
    "$PLUGIN/skills/init/templates/check.sh.tmpl" > scripts/check.sh

sed -e 's#{{VARIANT_STATE_BLOCK}}#VARIANT="$(cat .tripwire-variant 2>/dev/null || true)"; VARIANT="${VARIANT:-v1}"#' \
    -e '/{{ENV_SETUP_BLOCK}}/d' \
    -e 's|{{ENV_AVAILABLE_TEST}}|true|g' \
    -e 's|{{STOP_CHECK_ARGS}}|--variant "$VARIANT"|g' \
    -e 's|{{STOP_CHECK_DESC}}|variant $VARIANT|g' \
    "$PLUGIN/skills/init/templates/cc_stop.sh.tmpl" > scripts/hooks/cc_stop.sh
chmod +x scripts/check.sh scripts/hooks/cc_stop.sh
echo v1 > .tripwire-variant

# SessionStart multi : installe les hooks + annonce la variante courante
sed -e 's#{{SESSION_VARIANT_LINE}}#V="$(cat .tripwire-variant 2>/dev/null || true)"; [ -n "$V" ] \&\& CTX="$CTX tripwire: variante courante: $V."#' \
    "$PLUGIN/skills/init/templates/cc_session_start.sh.tmpl" > scripts/hooks/cc_session_start.sh
chmod +x scripts/hooks/cc_session_start.sh
OUT="$(echo '{}' | scripts/hooks/cc_session_start.sh 2>/dev/null)"; rc=$?
chk "multi session-start (rc)" 0 $rc
chk "multi session-start: hooksPath posé" "scripts/hooks" "$(git config --get core.hooksPath)"
echo "$OUT" | grep -q "variante courante: v1"; chk "multi session-start: variante annoncée" 0 $?

bash -n scripts/check.sh && bash -n scripts/hooks/cc_stop.sh
chk "bash -n multi" 0 $?
if grep -Fn '{{' scripts/ >/dev/null 2>&1; then echo "✗ placeholders résiduels (multi)"; fails=1; else echo "✓ pas de placeholder résiduel (multi)"; fi
./scripts/check.sh >/dev/null 2>&1;                    chk "multi full vert" 0 $?
./scripts/check.sh --variant v1 >/dev/null 2>&1;       chk "multi --variant v1 vert" 0 $?
scripts/hooks/cc_stop.sh </dev/null >/dev/null 2>&1;   chk "multi stop hook vert (variant courant)" 0 $?

# v2 cassé : full rouge mais TOUTES les variantes tentées ; v1 isolé reste vert
sed -i 's|"bad"|"v2"|' build.sh
OUT="$(./scripts/check.sh 2>&1)"; rc=$?
chk "multi full rouge (v2 cassé)" 1 $rc
echo "$OUT" | grep -q "Build v1 OK" && echo "$OUT" | grep -qF "Build v2: échec"
chk "toutes les variantes tentées" 0 $?
./scripts/check.sh --variant v1 >/dev/null 2>&1;       chk "multi --variant v1 vert (v2 cassé)" 0 $?

# garde stop_hook_active : même tripwire rouge, ne re-bloque pas (anti-boucle)
printf '#!/usr/bin/env bash\nexit 1\n' > fast.sh
printf '{"stop_hook_active": true}' | scripts/hooks/cc_stop.sh >/dev/null 2>&1
chk "garde stop_hook_active -> rc 0" 0 $?
printf '{}' | scripts/hooks/cc_stop.sh >/dev/null 2>&1
chk "stop rouge sans garde -> rc 2" 2 $?

# Dégradation : env de build indisponible -> --fast seul, build sauté
sed -e 's#{{VARIANT_STATE_BLOCK}}#VARIANT="$(cat .tripwire-variant 2>/dev/null || true)"; VARIANT="${VARIANT:-v1}"#' \
    -e '/{{ENV_SETUP_BLOCK}}/d' \
    -e 's|{{ENV_AVAILABLE_TEST}}|false|g' \
    -e 's|{{STOP_CHECK_ARGS}}|--variant "$VARIANT"|g' \
    -e 's|{{STOP_CHECK_DESC}}|variant $VARIANT|g' \
    "$PLUGIN/skills/init/templates/cc_stop.sh.tmpl" > scripts/hooks/cc_stop_degraded.sh
chmod +x scripts/hooks/cc_stop_degraded.sh
printf '#!/usr/bin/env bash\nexit 0\n' > fast.sh   # fast vert, v2 toujours cassé
echo v2 > .tripwire-variant
printf '{}' | scripts/hooks/cc_stop.sh >/dev/null 2>&1
chk "stop env dispo + variant v2 cassé -> rc 2" 2 $?
printf '{}' | scripts/hooks/cc_stop_degraded.sh >/dev/null 2>&1
chk "stop dégradé (env absent) -> fast seul, rc 0" 0 $?
printf '#!/usr/bin/env bash\nexit 1\n' > fast.sh
printf '{}' | scripts/hooks/cc_stop_degraded.sh >/dev/null 2>&1
chk "stop dégradé + fast rouge -> rc 2" 2 $?

echo "----------------------------------------"
if [ "$fails" -eq 0 ]; then echo "E2E: tout vert"; else echo "E2E: ROUGE"; fi
exit "$fails"
