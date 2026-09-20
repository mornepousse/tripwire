# Alléger — design v0.16.0

Date : 2026-09-20 · Statut : validé (session avec Mae)

## Problème

« C'est devenu une usine à gaz. C'est une usine à token maxing. »

Mesures sur dix-neuf dépôts équipés :

- La section scaffoldée du `CLAUDE.md` fait 60 à 65 lignes — **600 à 780
  tokens lus à chaque session, dans chaque dépôt** — pour expliquer des
  mécanismes que l'agent n'a pas besoin de comprendre pour les subir. Dans
  `Niphargus`, 65 % du `CLAUDE.md`. Premier poste de dépense, loin devant les
  hooks.
- Chaque dépôt porte 520 lignes installées, dont un `check.sh` de 324.
  Divergences + contrat + question = 134 lignes (41 %) pour 2 à 4 dépôts sur
  18. Le scoping monorepo (`MODULE_FAST`, `--changed`) : **zéro utilisateur**.
- Tout est installé partout, qu'on s'en serve ou non. Retirer un mécanisme
  demande de comprendre un script de 324 lignes.

## Décisions

**1. La section `CLAUDE.md` scaffoldée passe de 60 à ~12 lignes.** Ce qu'un
agent doit savoir : `check.sh --fast` / `check.sh`, les hooks l'appellent, un
rouge se corrige et ne se contourne pas, `TRIPWIRE_OFF=1` débraye, et le
fichier à lire avant de toucher une source s'il existe. La philosophie — le
pourquoi de chaque mécanisme — vit dans le README du plugin, une fois.

**2. Noyau + briques.** `scripts/check.sh` devient un noyau : modes, valeurs
projet (fast, build, variantes, chemins), verrou, capture d'échec,
skip-si-déjà-vert, phase rapide, phase complète, verdict, historique. Il
source `scripts/tripwire.d/*.sh` s'ils existent. Chaque brique est un fichier
autonome qui définit ses fonctions et s'enregistre dans une des listes du
noyau : `TW_PRE_FAST` (avant la phase rapide), `TW_POST_FULL` (après la phase
complète). Le noyau les appelle dans l'ordre.

Briques : `ratchet.sh` (compte de tests, `.tripwire-testcount`),
`divergences.sh` (`.tripwire-divergences`), `contrat.sh` (`COMPORTEMENTS.md`,
`.tripwire-nongardes`). Chacune porte ses propres valeurs projet
(`TEST_COUNT_CMD` dans `ratchet.sh`). `SRC_GREP` / `TEST_GREP` restent au
noyau : ce sont des faits sur le projet, partagés.

Retirer un mécanisme = `rm scripts/tripwire.d/<brique>.sh`. L'ajouter = la
copier depuis le plugin. `init` n'installe que ce qui est demandé et ne pose
les questions d'une brique que si on l'installe. Un dépôt standard passe de
~520 à ~180 lignes installées.

Un `check.sh` scaffoldé reste **autonome** : les briques sont dans le dépôt,
rien n'est sourcé depuis le plugin.

**3. Le scoping monorepo disparaît.** `MODULE_FAST`, `--changed`, la question
d'init, la plomberie des hooks. Zéro utilisateur en trois mois. S'il en faut
un jour, ce sera une brique.

## Ce qui ne change pas

Le comportement de chaque mécanisme conservé — les assertions e2e existantes
restent vraies, brique par brique. L'échelle de gravité. Le débrayage. La
fiche de divergences et le contrat, pour les dépôts qui les ont.

## Migration

Un `check.sh` monolithique (pas de `scripts/tripwire.d/`) est reconnu par
`init` à l'Étape 0 : il propose le découpage, relit les valeurs projet du
monolithe, n'installe que les briques dont les fichiers d'état existent
(`.tripwire-testcount` → ratchet, `.tripwire-divergences` → divergences,
`COMPORTEMENTS.md` → contrat) et demande pour le reste. Les hooks perdent
`--changed`.

## Tests

- Noyau seul (aucune brique) : fast/full vert et rouge, hooks, aucun fichier
  d'état créé, aucune trace des mécanismes absents dans la sortie.
- Chaque brique : ses assertions existantes, inchangées, avec la brique
  installée.
- Une brique retirée (`rm`) → inerte, aucune erreur.
- Dogfood : chaque brique du plugin identique à son template, à l'octet.
- Section `CLAUDE.md` : ≤ 15 lignes une fois instanciée.
