#!/usr/bin/env bash
# E2E tripwire : instancie les templates (cas mono-cible, sans env setup)
# sur un repo jouet et vérifie vert/rouge/hooks. Exit 0 si tout passe.
set -uo pipefail
PLUGIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export TRIPWIRE_RATCHET_STRICT=0   # un pre-push parent ne doit pas rendre les toys stricts
cd "$TMP"
git init -q -b main

mkdir -p scripts/hooks src
printf '#!/usr/bin/env bash\nexit 0\n' > fast.sh && chmod +x fast.sh
printf '#!/usr/bin/env bash\nexit 0\n' > build.sh && chmod +x build.sh

# --- Instanciation (sed) : mono-cible, pas d'env setup ---
sed -e 's|{{PROJECT_NAME}}|toy|g' \
    -e 's|{{TRIPWIRE_VERSION}}|v9.9.9|g' \
    -e 's|{{VARIANTS_SPACE_SEPARATED}}||g' \
    -e 's|{{FAST_CMD}}|./fast.sh|g' \
    -e 's|{{VARIANT_BUILD_CMD}}|./build.sh|g' \
    -e 's|{{SRC_GREP}}|^src/|g' \
    -e 's|{{TEST_GREP}}|^test/|g' \
    "$PLUGIN/skills/init/templates/check.sh.tmpl" > scripts/check.sh
# Briques : chaque mécanisme optionnel est un fichier de scripts/tripwire.d/,
# sourcé par le noyau s'il existe. Ici on les installe toutes.
mkdir -p scripts/tripwire.d
sed -e 's|{{TEST_COUNT_CMD}}|cat ntests.txt|g' \
    "$PLUGIN/skills/init/templates/tripwire.d/ratchet.sh.tmpl" > scripts/tripwire.d/ratchet.sh
cp "$PLUGIN/skills/init/templates/tripwire.d/divergences.sh.tmpl" scripts/tripwire.d/divergences.sh
cp "$PLUGIN/skills/init/templates/tripwire.d/contrat.sh.tmpl" scripts/tripwire.d/contrat.sh
sed -e 's|{{PROJECT_NAME}}|toy|g' -e '/{{ENV_SETUP_BLOCK}}/d' \
    "$PLUGIN/skills/init/templates/pre-push.tmpl" > scripts/hooks/pre-push
cp "$PLUGIN/skills/init/templates/install-hooks.sh.tmpl" scripts/install-hooks.sh
# Stop : garde-fou --fast pur, plus aucun placeholder (build complet = pre-push)
cp "$PLUGIN/skills/init/templates/cc_stop.sh.tmpl" scripts/hooks/cc_stop.sh
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

# Vert : fast, full, stop hook
./scripts/check.sh --fast >/dev/null 2>&1;             chk "fast vert" 0 $?
./scripts/check.sh >/dev/null 2>&1;                    chk "full vert" 0 $?
scripts/hooks/cc_stop.sh </dev/null >/dev/null 2>&1;   chk "stop hook vert" 0 $?
! grep '"$REPO/scripts/check.sh"' scripts/hooks/cc_stop.sh | grep -qv -- '--fast'
chk "cc stop: tout appel check.sh est en --fast (e2e complet = pre-push)" 0 $?
# Plus de hook par édition (v0.17.0) : les agents lancent leurs tests eux-mêmes,
# et ce hook injectait 200 à 400 avis par dépôt dans le contexte, pour rien.
[ ! -e "$PLUGIN/skills/init/templates/cc_post_edit.sh.tmpl" ]
chk "plus de template post-édition" 0 $?
grep -q 'PostToolUse' "$PLUGIN/skills/init/templates/settings.json.tmpl"
chk "settings scaffoldé : plus d'entrée PostToolUse" 1 $?

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

# ===== Débrayage : TRIPWIRE_OFF=1 ou un fichier .tripwire-off coupe les hooks =====
# Les hooks Claude Code coûtent des tokens et du temps à chaque fin de
# tour. On doit pouvoir les couper d'un geste, par session (env) ou par dépôt
# (fichier, non suivi), sans rien désinstaller. Le pre-push git n'est pas
# concerné : il ne coûte rien à l'agent et a déjà son échappatoire (--no-verify).
printf '#!/usr/bin/env bash\necho BOOM\nexit 1\n' > fast.sh              # rouge en dessous
OUT="$(TRIPWIRE_OFF=1 scripts/hooks/cc_stop.sh </dev/null 2>&1)"
chk "débrayage env: stop rc 0 même sur rouge" 0 $?
chk "débrayage env: stop silencieux" "" "$OUT"
OUT="$(echo '{}' | TRIPWIRE_OFF=1 scripts/hooks/cc_session_start.sh 2>&1)"
chk "débrayage env: session-start silencieux" "" "$OUT"
touch .tripwire-off
scripts/hooks/cc_stop.sh </dev/null >/dev/null 2>&1; chk "débrayage fichier: stop rc 0 même sur rouge" 0 $?
OUT="$(cd "$TMP" && CLAUDE_PLUGIN_ROOT="$PLUGIN" bash "$PLUGIN/hooks/session_start.sh" </dev/null 2>&1)"
chk "débrayage fichier: hook plugin silencieux" "" "$OUT"
rm -f .tripwire-off
scripts/hooks/cc_stop.sh </dev/null >/dev/null 2>&1; chk "embrayé: stop bloque à nouveau (rc 2)" 2 $?
printf '#!/usr/bin/env bash\nexit 0\n' > fast.sh
./scripts/check.sh --fast --force >/dev/null 2>&1

# ===== Section CLAUDE.md scaffoldée : courte =====
# Elle est lue à chaque session dans chaque dépôt : 60 lignes = 600-780 tokens
# de doctrine que l'agent n'a pas besoin de comprendre pour subir les hooks.
sed -e 's|{{FAST_DESC}}|tests rapides|g' -e 's|{{VARIANT_LIST_DESC}}|le build|g' -e 's|{{TDD_SCOPE}}|logique pure|g' \
    "$PLUGIN/skills/init/templates/claude-md-section.md.tmpl" > section.md
N="$(grep -cv '^[[:space:]]*$' section.md)"
[ "$N" -le 15 ]; chk "section CLAUDE.md: <= 15 lignes non vides (got $N)" 0 $?
grep -q 'TRIPWIRE_OFF' section.md; chk "section CLAUDE.md: dit comment débrayer" 0 $?
grep -q 'check.sh --fast' section.md; chk "section CLAUDE.md: dit la commande" 0 $?
rm -f section.md

# ===== Noyau seul : sans brique, rien ne manque et rien ne traîne =====
# Un dépôt standard n'a que le noyau. Il doit être vert, rouge, et ne créer
# aucun fichier d'état ni mentionner un mécanisme absent.
NU="$(mktemp -d)"; mkdir -p "$NU/scripts/hooks" && ( cd "$NU" && git init -q -b main )   # HORS du repo jouet : un .git imbriqué casserait son empreinte
printf '#!/usr/bin/env bash\nexit 0\n' > "$NU/fast.sh"; chmod +x "$NU/fast.sh"; cp "$NU/fast.sh" "$NU/build.sh"
sed -e 's|{{PROJECT_NAME}}|nu|g' -e 's|{{TRIPWIRE_VERSION}}|v9.9.9|g' -e 's|{{VARIANTS_SPACE_SEPARATED}}||g' \
    -e 's|{{FAST_CMD}}|./fast.sh|g' -e 's|{{VARIANT_BUILD_CMD}}|./build.sh|g' -e 's|{{SRC_GREP}}||g' -e 's|{{TEST_GREP}}||g' \
    "$PLUGIN/skills/init/templates/check.sh.tmpl" > "$NU/scripts/check.sh"; chmod +x "$NU/scripts/check.sh"
( cd "$NU" && ./scripts/check.sh --force >/dev/null 2>&1 ); chk "noyau seul: full vert" 0 $?
[ ! -e "$NU/.tripwire-testcount" ]; chk "noyau seul: aucun fichier d'état créé" 0 $?
OUT="$(cd "$NU" && ./scripts/check.sh --force 2>&1)"
echo "$OUT" | grep -qi 'ratchet\|divergence\|contrat'; chk "noyau seul: aucun mécanisme absent mentionné" 1 $?
printf '#!/usr/bin/env bash\nexit 1\n' > "$NU/fast.sh"
( cd "$NU" && ./scripts/check.sh --fast --force >/dev/null 2>&1 ); chk "noyau seul: fast rouge" 1 $?
N="$(grep -cv '^[[:space:]]*$' "$NU/scripts/check.sh")"
[ "$N" -le 160 ]; chk "noyau seul: <= 160 lignes non vides — plafond, pas cible (got $N)" 0 $?
rm -rf "$NU"
# Une brique se retire par rm : le mécanisme devient inerte, rien ne casse.
mv scripts/tripwire.d/divergences.sh "$TMP/div.bak"
printf 'scripts/check.sh\tje-nexiste-pas\tsonde\n' > .tripwire-divergences
./scripts/check.sh --fast --force >/dev/null 2>&1; chk "brique retirée: divergences inertes (vert malgré une divergence perdue)" 0 $?
mv "$TMP/div.bak" scripts/tripwire.d/divergences.sh
./scripts/check.sh --fast --force >/dev/null 2>&1; chk "brique remise: divergences actives (rouge)" 1 $?
rm -f .tripwire-divergences

# ===== Dogfood : les fonctions dupliquées restent identiques au template =====
# La duplication est voulue (un check.sh scaffoldé est autonome). Elle a dérivé un
# mois sans que rien le voie : un bump via un outil texte a avalé l'octet CR de
# scripts/check.sh, tuant sa protection CRLF. Comparaison à l'octet, pas au diff.
# Chaque brique installée dans le plugin est identique à son template, hors la
# ligne de valeur projet (la seule qui diffère légitimement).
for br in "$PLUGIN"/scripts/tripwire.d/*.sh; do
  n="$(basename "$br")"
  A="$(grep -v '^TEST_COUNT_CMD=' "$br" | md5sum | cut -d' ' -f1)"
  B="$(grep -v '^TEST_COUNT_CMD=' "$PLUGIN/skills/init/templates/tripwire.d/$n.tmpl" | md5sum | cut -d' ' -f1)"
  chk "dogfood: brique $n identique au template (octet)" "$B" "$A"
done

# ===== Hook SessionStart du plugin : un scaffold en retard se signale tout seul =====
# Ce hook vit dans le PLUGIN, pas dans le scaffold : il fonctionne donc sur un
# dépôt équipé dès `claude plugin update`, sans rien y re-scaffolder. C'est ce qui
# casse l'œuf et la poule — sinon le correctif de la propagation aurait lui-même
# besoin d'être propagé.
PSS="$PLUGIN/hooks/session_start.sh"
# Référence = tampon du check.sh du plugin (son dogfood). Il n'avance que quand
# les templates changent : une release qui n'en touche aucun ne doit pas
# déclarer toute la flotte en retard. fx-ajour vérifie exactement ce cas, le
# manifest du plugin étant plus récent que son tampon.
PV="$(sed -n '2s/^# tripwire-template: *v\{0,1\}\([0-9][0-9.]*\).*/\1/p' "$PLUGIN/scripts/check.sh")"
mkfx() { mkdir -p "$TMP/$1/scripts"; [ -n "${2:-}" ] && printf '#!/usr/bin/env bash\n# tripwire-template: %s\n' "$2" > "$TMP/$1/scripts/check.sh"; return 0; }
mkfx fx-none ""
mkfx fx-ajour "v$PV"
mkfx fx-retard "v0.1.0"
mkfx fx-sanstampon "x"
printf '#!/usr/bin/env bash\necho rien\n' > "$TMP/fx-sanstampon/scripts/check.sh"
run_pss() { ( cd "$TMP/$1" && CLAUDE_PLUGIN_ROOT="$PLUGIN" bash "$PSS" </dev/null 2>/dev/null ); }

OUT="$(run_pss fx-none)"; chk "session-start plugin: hors dépôt tripwire -> rc 0" 0 $?
chk "session-start plugin: hors dépôt tripwire -> silencieux" "" "$OUT"
OUT="$(run_pss fx-ajour)"; chk "session-start plugin: scaffold à jour -> rc 0" 0 $?
chk "session-start plugin: scaffold à jour -> silencieux" "" "$OUT"
OUT="$(run_pss fx-retard)"; chk "session-start plugin: scaffold en retard -> rc 0 (jamais bloquant)" 0 $?
echo "$OUT" | grep -q "tripwire:init"; chk "session-start plugin: en retard -> prescrit /tripwire:init" 0 $?
echo "$OUT" | grep -q "v0.1.0"; chk "session-start plugin: en retard -> cite la version du scaffold" 0 $?
echo "$OUT" | grep -q "$PV"; chk "session-start plugin: en retard -> cite la version de référence" 0 $?
OUT="$(run_pss fx-sanstampon)"
echo "$OUT" | grep -q "tripwire:init"; chk "session-start plugin: tampon absent -> prescrit /tripwire:init" 0 $?

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

# ===== Divergences déclarées =====
# La perte d'un écart assumé doit être un verdict machine, pas une relecture.
printf '#!/usr/bin/env bash\nexit 0\n' > fast.sh   # le bloc bisect laisse fast.sh cassé
rm -f .tripwire-divergences
./scripts/check.sh --fast --force >/dev/null 2>&1
chk "divergences: fiche absente -> inerte" 0 $?
printf '# fichier\tmotif\tpourquoi\n\n' > .tripwire-divergences
./scripts/check.sh --fast --force >/dev/null 2>&1
chk "divergences: fiche sans ligne utile -> vert" 0 $?
printf 'scripts/hooks/cc_stop.sh\t--fast\tgarde-fou leger: le Stop ne lance que la phase rapide\n' > .tripwire-divergences
./scripts/check.sh --fast --force >/dev/null 2>&1
chk "divergences: motif présent -> vert" 0 $?
cp scripts/hooks/cc_stop.sh "$TMP/cc_stop.bak"
printf '#!/usr/bin/env bash\nexit 0\n' > scripts/hooks/cc_stop.sh   # écrasement: le motif disparaît
OUT="$(./scripts/check.sh --fast --force 2>&1)"
chk "divergences: motif perdu -> rouge" 1 $?
echo "$OUT" | grep -q "divergence perdue"
chk "divergences: message cite la perte" 0 $?
echo "$OUT" | grep -q "garde-fou leger"
chk "divergences: message cite le pourquoi" 0 $?
cp "$TMP/cc_stop.bak" scripts/hooks/cc_stop.sh && chmod +x scripts/hooks/cc_stop.sh
rm -f "$TMP/cc_stop.bak"
printf 'scripts/hooks/absent.sh\tX\tfichier hote disparu\n' > .tripwire-divergences
OUT="$(./scripts/check.sh --fast --force 2>&1)"
chk "divergences: fichier hôte absent -> rouge" 1 $?
echo "$OUT" | grep -q "rétablir la divergence"
chk "divergences: fichier hôte absent -> conseil de rétablissement" 0 $?
# Malformée : le fichier hôte EXISTE, sinon la branche « hôte absent » rendrait
# rouge toute seule et l'assertion ne prouverait rien. Sans garde de
# malformation, grep -qF -- "" matche tout et la ligne serait VERTE.
printf 'scripts/check.sh\n' > .tripwire-divergences
OUT="$(./scripts/check.sh --fast --force 2>&1)"
chk "divergences: ligne malformée -> rouge" 1 $?
echo "$OUT" | grep -q "ligne 1"
chk "divergences: malformée cite le numéro de ligne" 0 $?
# Tabulations consécutives : le motif est VIDE (malformée), pas « le pourquoi
# décalé d'un champ ». IFS=$'\t' fusionne les tabs -> m=pourquoi -> vert à tort.
printf 'scripts/check.sh\t\tALL_VARIANTS\n' > .tripwire-divergences
./scripts/check.sh --fast --force >/dev/null 2>&1
chk "divergences: tabs consécutifs -> motif vide -> rouge" 1 $?
# Numéro de ligne PHYSIQUE : commentaire et ligne vide comptent aussi
printf '# entete\n\nscripts/check.sh\n' > .tripwire-divergences
OUT="$(./scripts/check.sh --fast --force 2>&1)"
echo "$OUT" | grep -q "ligne 3"
chk "divergences: numéro de ligne compte commentaires et lignes vides" 0 $?
# Fiche en CRLF : le \r ne doit pas coller au dernier champ (faux rouge indébuggable)
printf 'scripts/check.sh\tALL_VARIANTS[@]\r\n' > .tripwire-divergences
./scripts/check.sh --fast --force >/dev/null 2>&1
chk "divergences: fiche CRLF -> pas de faux rouge" 0 $?
# Dernière ligne sans retour chariot final : lue quand même (sinon vert silencieux)
printf 'scripts/hooks/absent.sh\tX\tsans newline finale' > .tripwire-divergences
./scripts/check.sh --fast --force >/dev/null 2>&1
chk "divergences: dernière ligne sans newline finale -> lue quand même" 1 $?
# Fiche présente mais illisible : jamais un vert silencieux
printf 'scripts/check.sh\tALL_VARIANTS[@]\tfiche lisible\n' > .tripwire-divergences
chmod 000 .tripwire-divergences
if [ -r .tripwire-divergences ]; then
  echo "~ fiche encore lisible malgré chmod 000 (root ?) — test d'illisibilité sauté"
else
  OUT="$(./scripts/check.sh --fast --force 2>&1)"
  chk "divergences: fiche illisible -> rouge" 1 $?
  echo "$OUT" | grep -q "illisible"
  chk "divergences: fiche illisible -> message explicite" 0 $?
fi
chmod 644 .tripwire-divergences
# Motif à caractères regex : en regex, ALL_VARIANTS[@] matcherait « ALL_VARIANTS@ »,
# chaîne absente du fichier. Vert ici => la comparaison est bien littérale.
printf 'scripts/check.sh\tALL_VARIANTS[@]\tpreuve que le motif est compare en chaine litterale\n' > .tripwire-divergences
./scripts/check.sh --fast --force >/dev/null 2>&1
chk "divergences: motif littéral (-F) -> vert" 0 $?
printf 'scripts/install-hooks.sh\tcore.hooksPath\tle pre-push passe par scripts/hooks\n' > .tripwire-divergences
./scripts/check.sh --fast --force >/dev/null 2>&1
chk "divergences: motif présent (install-hooks) -> vert" 0 $?
cp scripts/install-hooks.sh "$TMP/ih.bak"
printf '#!/usr/bin/env bash\nexit 0\n' > scripts/install-hooks.sh   # rejoue l'écrasement du 2026-08-05
scripts/hooks/cc_stop.sh </dev/null >/dev/null 2>&1
chk "divergences: hook Stop mord sur divergence perdue -> rc 2" 2 $?
cp "$TMP/ih.bak" scripts/install-hooks.sh && chmod +x scripts/install-hooks.sh
rm -f .tripwire-divergences "$TMP/cc_stop.bak" "$TMP/ih.bak"   # le repo jouet repart propre

# ===== Ratchet de tests =====
echo 5 > ntests.txt
./scripts/check.sh --fast --force >/dev/null 2>&1
chk "ratchet: bootstrap crée la référence" "5" "$(cat .tripwire-testcount 2>/dev/null)"
echo 7 > ntests.txt
./scripts/check.sh --fast --force >/dev/null 2>&1
chk "ratchet: auto-bump à la hausse" "7" "$(cat .tripwire-testcount 2>/dev/null)"
echo 6 > ntests.txt
OUT="$(TRIPWIRE_RATCHET_STRICT=0 ./scripts/check.sh --fast --force 2>&1)"; rc=$?
chk "ratchet: baisse -> avertissement, rc 0" 0 $rc
echo "$OUT" | grep -q "ratchet"; chk "ratchet: message d'avertissement" 0 $?
chk "ratchet: la référence ne baisse pas seule" "7" "$(cat .tripwire-testcount 2>/dev/null)"
OUT="$(TRIPWIRE_RATCHET_STRICT=1 ./scripts/check.sh --fast --force 2>&1)"; rc=$?
chk "ratchet: baisse + STRICT -> rouge" 1 $rc
scripts/hooks/pre-push </dev/null >/dev/null 2>&1
chk "ratchet: pre-push bloque sur baisse" 1 $?
./scripts/check.sh --force >/dev/null 2>&1          # full NON-strict : vert (avertissement) + stampe green-full
scripts/hooks/pre-push </dev/null >/dev/null 2>&1   # même état : le strict ne doit PAS réutiliser ce stamp
chk "ratchet: strict ne réutilise pas un stamp non-strict" 1 $?
echo 7 > ntests.txt   # remettre compte == référence (sections suivantes propres)

mkdir -p test
printf 'assert(a);\nassert(b);\nassert(c);\n' > test/t.c
git add -A >/dev/null 2>&1 && GITC commit -qm "c6 tests baseline"

# ===== Contrat de comportements =====
# COMPORTEMENTS.md : chaque comportement est tagué par ce qui le garde —
# [test:X] (X doit exister sous les chemins de test), [smoke:X] (X doit exister
# dans SMOKE_DOC), ou l'aveu [NON GARDÉ], compté et ratcheté. Une garde qui
# disparaît = rouge ; un comportement inventé n'est pas le problème du pipeline.
rm -f COMPORTEMENTS.md .tripwire-nongardes
./scripts/check.sh --fast --force >/dev/null 2>&1; chk "comportements: contrat absent -> inerte" 0 $?
printf '# Contrat\n\nProse libre.\n- [test:assert(a)] le comportement A est gardé par t.c\n' > COMPORTEMENTS.md
./scripts/check.sh --fast --force >/dev/null 2>&1; chk "comportements: [test:X] présent -> vert" 0 $?
printf -- '- [test:je_nexiste_pas] comportement orphelin\n' > COMPORTEMENTS.md
OUT="$(./scripts/check.sh --fast --force 2>&1)"; chk "comportements: [test:X] absent -> rouge" 1 $?
echo "$OUT" | grep -q "je_nexiste_pas"; chk "comportements: message cite la garde perdue" 0 $?
echo "$OUT" | grep -q "NON GARDÉ"; chk "comportements: message propose l'aveu" 0 $?
# [smoke:X] est une note de vérification manuelle, pas une garde : le check ne la
# vérifie pas. Vérifiée contre un doc, elle est devenue l'échappatoire universelle
# (32 lignes en une semaine, tag grossier réutilisé) — pour zéro protection.
printf -- '- [smoke:n importe quoi] note manuelle\n' > COMPORTEMENTS.md
./scripts/check.sh --fast --force >/dev/null 2>&1; chk "comportements: [smoke:X] -> note, jamais vérifiée, vert" 0 $?
printf -- '- [bidule:x] tag inconnu\n' > COMPORTEMENTS.md
OUT="$(./scripts/check.sh --fast --force 2>&1)"; chk "comportements: tag inconnu -> rouge" 1 $?
echo "$OUT" | grep -q "bidule"; chk "comportements: tag inconnu cité" 0 $?
printf '# Titre\nDu texte sans tag.\n- une puce sans tag\n' > COMPORTEMENTS.md
./scripts/check.sh --fast --force >/dev/null 2>&1; chk "comportements: prose sans tag -> vert" 0 $?
# Ratchet des NON GARDÉ : référence committée, même mécanique que .tripwire-testcount
rm -f .tripwire-nongardes
printf -- '- [NON GARDÉ] a\n- [NON GARDÉ] b\n' > COMPORTEMENTS.md
./scripts/check.sh --fast --force >/dev/null 2>&1; chk "nongardes: premier run -> vert" 0 $?
chk "nongardes: référence bootstrappée" "2" "$(cat .tripwire-nongardes 2>/dev/null)"
./scripts/check.sh --fast --force >/dev/null 2>&1; chk "nongardes: compte == référence -> vert" 0 $?
printf -- '- [NON GARDÉ] c\n' >> COMPORTEMENTS.md
OUT="$(./scripts/check.sh --fast --force 2>&1)"; chk "nongardes: compte > référence, normal -> vert" 0 $?
echo "$OUT" | grep -qi "non gardé"; chk "nongardes: avis émis" 0 $?
TRIPWIRE_RATCHET_STRICT=1 ./scripts/check.sh --fast --force >/dev/null 2>&1; chk "nongardes: compte > référence, strict -> rouge" 1 $?
printf -- '- [NON GARDÉ] a\n' > COMPORTEMENTS.md
./scripts/check.sh --fast --force >/dev/null 2>&1; chk "nongardes: compte < référence -> vert" 0 $?
chk "nongardes: référence abaissée" "1" "$(cat .tripwire-nongardes 2>/dev/null)"
# La question forcée : pendant -> question, à la conclusion -> blocage
git add -A >/dev/null 2>&1 && GITC commit -qm "c7 contrat"
echo mod >> src/f2                                    # source modifiée, ni test ni contrat
OUT="$(./scripts/check.sh --fast --force 2>&1)"; chk "question: sans réponse -> vert (avis, jamais rouge)" 0 $?
echo "$OUT" | grep -q "COMPORTEMENTS"; chk "question: sans réponse -> avis émis" 0 $?
# Le Stop NE bloque PLUS sur la question : en une semaine sur un vrai projet,
# 17 blocages et 66 commits taxés d'une ligne au contrat. La question reste un
# avis ; le rouge du contrat est réservé à une garde [test:X] qui disparaît.
scripts/hooks/cc_stop.sh </dev/null >/dev/null 2>&1; chk "question: le Stop ne bloque pas -> rc 0" 0 $?
git checkout -q -- src/f2 COMPORTEMENTS.md
git rm -q COMPORTEMENTS.md .tripwire-nongardes && GITC commit -qm "c8 sans contrat"   # sections suivantes inchangées

# ===== Avis TDD : source modifié sans test modifié =====
echo mod >> src/f2                                    # source tracké modifié
OUT="$(./scripts/check.sh --fast --force 2>&1)"
echo "$OUT" | grep -q "TDD:"; chk "avis TDD: source sans test -> avis" 0 $?
echo t >> test/t.c                                    # un test modifié aussi
OUT="$(./scripts/check.sh --fast --force 2>&1)"
echo "$OUT" | grep -q "TDD:"; chk "avis TDD: test modifié -> silencieux" 1 $?
git checkout -q -- src/f2 test/t.c

# Rouge : casser fast
printf '#!/usr/bin/env bash\necho BOOM\nexit 1\n' > fast.sh
./scripts/check.sh --fast >/dev/null 2>&1;             chk "fast rouge -> rc 1" 1 $?
[ -f .git/tripwire/last-fail.log ]; chk "last-fail.log créé sur rouge" 0 $?
grep -q '^# cmd: ./fast.sh' .git/tripwire/last-fail.log; chk "last-fail: en-tête cmd" 0 $?
grep -q 'BOOM' .git/tripwire/last-fail.log; chk "last-fail: sortie capturée" 0 $?
OUT="$(./scripts/check.sh --fast 2>&1)"
echo "$OUT" | grep -q "last-fail.log"; chk "message d'échec pointe le log" 0 $?
scripts/hooks/pre-push </dev/null >/dev/null 2>&1;     chk "pre-push bloque" 1 $?
# À la conclusion -> bloque.
scripts/hooks/cc_stop.sh </dev/null >/dev/null 2>&1;   chk "stop rouge -> rc 2 (bloque)" 2 $?
# Un rouge donné ne bloque qu'une fois (v0.17.0). Les agents finissent un tour
# chaque fois qu'ils attendent un subagent ou une tâche de fond : 1527 Stop dans
# une seule session de BDM64. Même état rouge qu'au dernier Stop -> l'agent le
# sait déjà, on ne relance pas le check et on ne re-bloque pas. Le pre-push reste.
# La mémoire est par session : une autre session (ou celle du lendemain) n'a
# jamais vu ce rouge, elle doit être bloquée à son tour.
SA='{"session_id":"A"}'; SB='{"session_id":"B"}'
echo "$SA" | scripts/hooks/cc_stop.sh >/dev/null 2>&1; chk "stop: session A, rouge -> rc 2" 2 $?
H0="$(wc -l < .git/tripwire/history.tsv)"
OUT="$(echo "$SA" | scripts/hooks/cc_stop.sh 2>&1)";   chk "stop: même rouge déjà signalé à A -> rc 0" 0 $?
chk "stop: même rouge déjà signalé -> check pas relancé" "$H0" "$(wc -l < .git/tripwire/history.tsv)"
chk "stop: même rouge déjà signalé -> silencieux" "" "$OUT"
echo "$SA" | TRIPWIRE_FORCE=1 scripts/hooks/cc_stop.sh >/dev/null 2>&1; chk "stop: TRIPWIRE_FORCE=1 relance -> rc 2" 2 $?
echo "$SB" | scripts/hooks/cc_stop.sh >/dev/null 2>&1; chk "stop: session B n'a pas vu ce rouge -> rc 2" 2 $?
./scripts/check.sh --fast >/dev/null 2>&1;             chk "check direct: le même rouge reste rouge" 1 $?
echo mod >> src/f2                                    # l'état bouge, toujours rouge
echo "$SA" | scripts/hooks/cc_stop.sh >/dev/null 2>&1; chk "stop: rouge sur un nouvel état -> rc 2" 2 $?
git checkout -q -- src/f2
# Rouge X -> vert Y -> retour au rouge X : le vert efface la mémoire du rouge.
cp fast.sh "$TMP/fast.red"; printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/fast.green"
echo "$SA" | scripts/hooks/cc_stop.sh >/dev/null 2>&1  # X déjà signalé
cp "$TMP/fast.green" fast.sh; echo y >> src/f2
echo "$SA" | scripts/hooks/cc_stop.sh >/dev/null 2>&1; chk "stop: état Y vert -> rc 0" 0 $?
cp "$TMP/fast.red" fast.sh; git checkout -q -- src/f2
echo "$SA" | scripts/hooks/cc_stop.sh >/dev/null 2>&1; chk "stop: retour au rouge X après un vert -> rc 2" 2 $?
rm -f "$TMP/fast.red" "$TMP/fast.green"

# Rouge : fast vert mais build cassé -> full rouge, fast vert
printf '#!/usr/bin/env bash\nexit 0\n' > fast.sh
printf '#!/usr/bin/env bash\nexit 1\n' > build.sh
./scripts/check.sh --fast >/dev/null 2>&1;             chk "fast vert (build cassé)" 0 $?
[ -f .git/tripwire/last-fail.log ]; chk "log conservé après un vert" 0 $?
./scripts/check.sh >/dev/null 2>&1;                    chk "full rouge (build cassé)" 1 $?

# ===== Mode perso : un dépôt partagé ne reçoit rien =====
# apex-sdk a d'autres contributeurs : tripwire y tourne pour une seule personne.
# Tout ce que le scaffold écrit est listé dans .git/info/exclude (jamais
# committé, jamais poussé) ; un fichier oublié par la liste sortirait dans
# git status, donc dans le prochain commit d'un collègue.
PERSO="$TMP/perso"; mkdir -p "$PERSO" && cd "$PERSO" && git init -q -b main
echo projet > README.md && git add README.md && GITC commit -qm "c0 projet d'équipe"
cat "$PLUGIN/skills/init/templates/perso-exclude.tmpl" >> .git/info/exclude
mkdir -p scripts/hooks scripts/tripwire.d .claude
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/perso-fast.sh"; chmod +x "$TMP/perso-fast.sh"
sed -e 's|{{PROJECT_NAME}}|perso|g' -e 's|{{TRIPWIRE_VERSION}}|v9.9.9|g' \
    -e 's|{{VARIANTS_SPACE_SEPARATED}}||g' -e "s|{{FAST_CMD}}|$TMP/perso-fast.sh|g" \
    -e "s|{{VARIANT_BUILD_CMD}}|$TMP/perso-fast.sh|g" -e 's|{{SRC_GREP}}||g' -e 's|{{TEST_GREP}}||g' \
    "$PLUGIN/skills/init/templates/check.sh.tmpl" > scripts/check.sh
sed -e 's|{{TEST_COUNT_CMD}}|echo 3|g' "$PLUGIN/skills/init/templates/tripwire.d/ratchet.sh.tmpl" > scripts/tripwire.d/ratchet.sh
sed -e 's|{{PROJECT_NAME}}|perso|g' -e '/{{ENV_SETUP_BLOCK}}/d' "$PLUGIN/skills/init/templates/pre-push.tmpl" > scripts/hooks/pre-push
cp "$PLUGIN/skills/init/templates/cc_stop.sh.tmpl" scripts/hooks/cc_stop.sh
sed -e '/{{SESSION_VARIANT_LINE}}/d' "$PLUGIN/skills/init/templates/cc_session_start.sh.tmpl" > scripts/hooks/cc_session_start.sh
cp "$PLUGIN/skills/init/templates/install-hooks.sh.tmpl" scripts/install-hooks.sh
cp "$PLUGIN/skills/init/templates/settings.json.tmpl" .claude/settings.local.json
sed -e 's|{{PROJECT_NAME}}|perso|g' "$PLUGIN/skills/init/templates/claude-md-section.md.tmpl" > CLAUDE.local.md
printf -- '- [NON GARDÉ] a\n' > COMPORTEMENTS.md
touch .tripwire-off .tripwire-variant .tripwire-divergences && rm .tripwire-off
chmod +x scripts/check.sh scripts/hooks/* scripts/install-hooks.sh
./scripts/install-hooks.sh >/dev/null 2>&1
./scripts/check.sh >/dev/null 2>&1;                    chk "perso: check complet vert" 0 $?
[ -f .tripwire-testcount ];                            chk "perso: le ratchet a bien écrit sa référence" 0 $?
chk "perso: git status vide — rien ne part chez les autres" "" "$(git status --porcelain)"
# Les fichiers tripwire sont exclus de git, donc de git diff : l'empreinte doit
# les lire quand même, sinon un contrat cassé passe en « déjà vert — skip ».
cp "$PLUGIN/skills/init/templates/tripwire.d/contrat.sh.tmpl" scripts/tripwire.d/contrat.sh
./scripts/check.sh --fast >/dev/null 2>&1
printf -- '- [test:JE_NEXISTE_PAS] garde perdue\n' > COMPORTEMENTS.md
./scripts/check.sh --fast >/dev/null 2>&1;             chk "perso: fichier exclu modifié -> pas de faux « déjà vert »" 1 $?
rm scripts/tripwire.d/contrat.sh; printf -- '- [NON GARDÉ] a\n' > COMPORTEMENTS.md
printf '#!/usr/bin/env bash\nexit 1\n' > "$TMP/perso-fast.sh"
scripts/hooks/pre-push </dev/null >/dev/null 2>&1;     chk "perso: le pre-push local bloque un rouge" 1 $?
# SessionStart ne pose core.hooksPath que s'il ne court-circuite rien : des hooks
# d'équipe dans .git/hooks, ou un core.hooksPath déjà choisi, restent maîtres.
git config --unset core.hooksPath
printf '#!/bin/sh\nexit 0\n' > .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit
OUT="$(echo '{}' | scripts/hooks/cc_session_start.sh 2>/dev/null)"
chk "session-start: hooks d'équipe dans .git/hooks -> core.hooksPath pas posé" "" "$(git config --get core.hooksPath)"
echo "$OUT" | grep -q "pre-push tripwire inactif"; chk "session-start: court-circuit évité -> signalé" 0 $?
rm .git/hooks/pre-commit; git config core.hooksPath .githooks
echo '{}' | scripts/hooks/cc_session_start.sh >/dev/null 2>&1
chk "session-start: core.hooksPath de l'équipe pas écrasé" ".githooks" "$(git config --get core.hooksPath)"
mkdir -p .githooks && printf '#!/bin/sh\n./scripts/check.sh\n' > .githooks/pre-push
OUT="$(echo '{}' | scripts/hooks/cc_session_start.sh 2>/dev/null)"
chk "session-start: check.sh déjà appelé par le pre-push de l'équipe -> silencieux" "" "$OUT"
rm -rf .githooks; git config --unset core.hooksPath
cd "$TMP"

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
    -e 's|{{FAST_CMD}}|./fast.sh|g' \
    -e 's|{{VARIANT_BUILD_CMD}}|./build.sh "$v"|g' \
    -e 's|{{SRC_GREP}}||g' \
    -e 's|{{TEST_GREP}}||g' \
    -e 's|{{TEST_COUNT_CMD}}||g' \
    "$PLUGIN/skills/init/templates/check.sh.tmpl" > scripts/check.sh

# Stop multi : même garde-fou --fast, indépendant de la variante (pas de build ici)
cp "$PLUGIN/skills/init/templates/cc_stop.sh.tmpl" scripts/hooks/cc_stop.sh
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
scripts/hooks/cc_stop.sh </dev/null >/dev/null 2>&1;   chk "multi stop hook (--fast) vert" 0 $?
! grep '"$REPO/scripts/check.sh"' scripts/hooks/cc_stop.sh | grep -qv -- '--fast'
chk "multi stop: tout appel check.sh est en --fast" 0 $?

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

# Nouveau contrat : le Stop ne lance QUE --fast. Une casse de build variant (v2)
# ne le fait PLUS bloquer (c'est le rôle du pre-push) ; seule la phase fast bloque.
printf '#!/usr/bin/env bash\nexit 0\n' > fast.sh   # fast vert, v2 toujours cassé
echo v2 > .tripwire-variant
printf '{}' | scripts/hooks/cc_stop.sh >/dev/null 2>&1
chk "stop --fast ignore le build variant cassé (e2e = pre-push) -> rc 0" 0 $?
printf '#!/usr/bin/env bash\nexit 1\n' > fast.sh   # phase fast rouge -> le Stop bloque
printf '{}' | scripts/hooks/cc_stop.sh >/dev/null 2>&1
chk "stop --fast rouge quand la phase fast est rouge -> rc 2" 2 $?

echo "----------------------------------------"
if [ "$fails" -eq 0 ]; then echo "E2E: tout vert"; else echo "E2E: ROUGE"; fi
exit "$fails"
