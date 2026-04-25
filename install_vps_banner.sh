#!/usr/bin/env bash
set -euo pipefail

# Safe VPS banner installer.
# Does NOT edit /etc/profile directly. It installs a dedicated script into /etc/profile.d.

BANNER_FILE_DEFAULT="/etc/profile.d/99-vps-banner.sh"
MARKER_BEGIN="# >>> vps-banner >>>"
MARKER_END="# <<< vps-banner <<<"

usage() {
  cat <<'USAGE'
Usage:
  install_vps_banner.sh [--file /etc/profile.d/99-vps-banner.sh] [--force]

Options:
  --file   Target file in /etc/profile.d (default: /etc/profile.d/99-vps-banner.sh)
  --force  Overwrite existing banner block in target file
USAGE
}

TARGET_FILE="$BANNER_FILE_DEFAULT"
FORCE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --file)
      [[ $# -ge 2 ]] || { echo "[ERROR] --file requires value" >&2; exit 2; }
      TARGET_FILE="$2"
      shift 2
      ;;
    --force)
      FORCE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[ERROR] Unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ $EUID -ne 0 ]]; then
  echo "[ERROR] Run as root (sudo)." >&2
  exit 1
fi

if [[ "$TARGET_FILE" != /etc/profile.d/*.sh ]]; then
  echo "[ERROR] For safety, target file must be in /etc/profile.d and end with .sh" >&2
  exit 1
fi

mkdir -p /etc/profile.d

if [[ -f "$TARGET_FILE" ]]; then
  if grep -Fq "$MARKER_BEGIN" "$TARGET_FILE"; then
    if [[ $FORCE -eq 0 ]]; then
      echo "[INFO] Banner already installed in $TARGET_FILE. Use --force to reinstall."
      exit 0
    fi

    tmp_file="$(mktemp)"
    awk -v b="$MARKER_BEGIN" -v e="$MARKER_END" '
      $0 == b {in_block=1; next}
      $0 == e {in_block=0; next}
      !in_block {print}
    ' "$TARGET_FILE" > "$tmp_file"
    mv "$tmp_file" "$TARGET_FILE"
  elif [[ $FORCE -eq 0 ]]; then
    echo "[ERROR] $TARGET_FILE exists and does not contain managed banner block."
    echo "        Refusing to overwrite unrelated content. Use another --file path."
    exit 1
  fi
fi

cat >> "$TARGET_FILE" <<'BANNER'
# >>> vps-banner >>>
# Managed by install_vps_banner.sh

# Show banner only in interactive login shells.
case "$-" in
  *i*) ;;
  *) return 0 2>/dev/null || exit 0 ;;
esac

cat <<'EOF_BANNER'
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   Welcome to your VPS
   Unauthorized access is prohibited.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF_BANNER

# <<< vps-banner <<<
BANNER

chmod 0644 "$TARGET_FILE"

echo "[OK] Banner installed safely: $TARGET_FILE"
echo "[OK] /etc/profile was not modified."
