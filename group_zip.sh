
#!/bin/sh
# Regroupe les fichiers .tap/.z80 présents dans FILES_DIR par titre
# (avant la 1re " (") et crée un ZIP si un groupe possède >1 fichier.
# Usage:
#   ./group_zip_from_dir.sh /chemin/vers/les/roms [dossier_sortie]
# Exemples:
#   ./group_zip_from_dir.sh ./roms
#   ./group_zip_from_dir.sh /srv/.../roms zips

set -eu

FILES_DIR="${1:-.}"
OUT_DIR="${2:-zip_groupes}"

if [ ! -d "$FILES_DIR" ]; then
  echo "Dossier introuvable: $FILES_DIR" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT INT HUP

PAIR_FILE="$TMP_DIR/key_path.pipe"
SORTED_FILE="$TMP_DIR/key_path.sorted.pipe"
GROUP_LIST="$TMP_DIR/group.list"

# 1) Lister récursivement *.tap et *.z80 (insensibles à la casse simple si souhaité)
#    BusyBox find supporte -iname ? Si non, remplace par deux find distincts.
#    On utilise -type f pour ne prendre que des fichiers.
if find "$FILES_DIR" -type f -iname '*.tap' -o -iname '*.z80' >/dev/null 2>&1; then
  # Variante iname (si supportée)
  find "$FILES_DIR" -type f \( -iname '*.tap' -o -iname '*.z80' \) > "$TMP_DIR/files_all.txt"
else
  # Variante compatible (sans -iname) : deux appels find
  find "$FILES_DIR" -type f -name '*.tap' > "$TMP_DIR/files_all.txt"
  find "$FILES_DIR" -type f -name '*.z80' >> "$TMP_DIR/files_all.txt"
fi

# 2) Pour chaque chemin, construire la "clé" => nom sans extension, tronqué avant la 1re " ("
#    La clé sert de regroupement.
: > "$PAIR_FILE"
while IFS= read -r path; do
  [ -z "$path" ] && continue
  fname="$(basename "$path")"

  # Enlever extension .tap/.z80
  base="$(printf '%s' "$fname" | sed -E 's/\.(tap|z80)$//')"

  # Tronquer à la première " (" (titre principal)
  key="$(printf '%s' "$base" | sed -E 's/ \(.*$//')"

  # (Option) Nettoyer les tags [ ... ] s'ils apparaissent dans la partie titre
  # Décommente si tu veux un regroupement plus agressif:
  # key="$(printf '%s' "$key" | sed -E 's/\[[^]]*\]//g')"

  # Normaliser espaces
  key="$(printf '%s' "$key" | sed -E 's/[[:space:]]+/ /g; s/^[[:space:]]+|[[:space:]]+$//g')"

  # Stocker "clé|chemin"
  printf '%s|%s\n' "$key" "$path" >> "$PAIR_FILE"
done < "$TMP_DIR/files_all.txt"

# 3) Trier par clé pour regrouper
sort -t '|' -k1,1 "$PAIR_FILE" > "$SORTED_FILE"

# 4) Itérer les groupes et zipper si >1 fichier
created=0
prev_key=""
count=0
: > "$GROUP_LIST"

flush_group() {
  if [ "$count" -gt 1 ]; then
    zipname="$prev_key"
    # Remplace les caractères problématiques
    zipname=$(printf '%s' "$zipname" | sed 's/[\\/:*?"<>|]/_/g; s/[[:space:]]\{1,\}/ /g; s/^[[:space:]]\{1,\}//; s/[[:space:]]\{1,\}$//')
    zipfile="$OUT_DIR/$zipname.zip"

    # Crée le zip en lisant la liste des fichiers depuis stdin
    if [ -s "$GROUP_LIST" ]; then
      zip -j -q "$zipfile" -@ < "$GROUP_LIST" && \
        echo "Créé: $zipfile ($(wc -l < "$GROUP_LIST") fichiers)" && \
        created=$((created+1))
    fi
  fi
  : > "$GROUP_LIST"
  count=0
}

while IFS='|' read -r key path; do
  [ -z "$key" ] && continue

  # Changement de groupe
  if [ -n "$prev_key" ] && [ "$key" != "$prev_key" ]; then
    flush_group
  fi
  prev_key="$key"
  count=$((count+1))

  # Ajoute le chemin tel quel (il existe forcément, on vient de find)
  printf '%s\n' "$path" >> "$GROUP_LIST"
done < "$SORTED_FILE"

# Dernier groupe
[ -n "$prev_key" ] && flush_group

echo "Terminé. ZIPs créés: $created. Dossier: $OUT_DIR"
