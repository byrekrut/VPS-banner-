 (cd "$(git rev-parse --show-toplevel)" && git apply --3way <<'EOF' 
diff --git a/install_vps_banner.sh b/install_vps_banner.sh
new file mode 100755
index 0000000000000000000000000000000000000000..faac087933311e952e773965ea653c6f31adcac8
--- /dev/null
+++ b/install_vps_banner.sh
@@ -0,0 +1,133 @@
+#!/usr/bin/env bash
+set -euo pipefail
+
+# Ubuntu-friendly VPS custom banner installer.
+# Installs banner as standalone script and a safe /etc/profile.d launcher.
+# Does NOT modify /etc/profile.
+
+DEFAULT_SOURCE_URL="https://raw.githubusercontent.com/byrekrut/VPS-banner-/refs/heads/main/vps-custom-banner.sh"
+DEFAULT_PROFILED_FILE="/etc/profile.d/vps-custom-banner.sh"
+DEFAULT_BANNER_SCRIPT="/usr/local/lib/vps-custom-banner.sh"
+MANAGED_LINE="# Managed by install_vps_banner.sh"
+
+usage() {
+  cat <<'USAGE'
+Usage:
+  install_vps_banner.sh [--source URL] [--profiled-file /etc/profile.d/vps-custom-banner.sh] [--banner-file /usr/local/lib/vps-custom-banner.sh]
+
+Options:
+  --source         URL to banner script (default: byrekrut/vps-custom-banner.sh)
+  --profiled-file  Launcher file in /etc/profile.d/*.sh
+  --banner-file    Stored banner script path that will be executed by bash
+USAGE
+}
+
+SOURCE_URL="$DEFAULT_SOURCE_URL"
+PROFILED_FILE="$DEFAULT_PROFILED_FILE"
+BANNER_FILE="$DEFAULT_BANNER_SCRIPT"
+
+while [[ $# -gt 0 ]]; do
+  case "$1" in
+    --source)
+      [[ $# -ge 2 ]] || { echo "[ERROR] --source requires value" >&2; exit 2; }
+      SOURCE_URL="$2"
+      shift 2
+      ;;
+    --profiled-file)
+      [[ $# -ge 2 ]] || { echo "[ERROR] --profiled-file requires value" >&2; exit 2; }
+      PROFILED_FILE="$2"
+      shift 2
+      ;;
+    --banner-file)
+      [[ $# -ge 2 ]] || { echo "[ERROR] --banner-file requires value" >&2; exit 2; }
+      BANNER_FILE="$2"
+      shift 2
+      ;;
+    -h|--help)
+      usage
+      exit 0
+      ;;
+    *)
+      echo "[ERROR] Unknown argument: $1" >&2
+      usage
+      exit 2
+      ;;
+  esac
+done
+
+if [[ $EUID -ne 0 ]]; then
+  echo "[ERROR] Run as root (sudo)." >&2
+  exit 1
+fi
+
+if [[ "$PROFILED_FILE" != /etc/profile.d/*.sh ]]; then
+  echo "[ERROR] --profiled-file must be inside /etc/profile.d and end with .sh" >&2
+  exit 1
+fi
+
+fetch_file() {
+  local url="$1"
+  local out="$2"
+
+  if command -v curl >/dev/null 2>&1; then
+    curl -fsSL "$url" -o "$out"
+    return
+  fi
+
+  if command -v wget >/dev/null 2>&1; then
+    wget -qO "$out" "$url"
+    return
+  fi
+
+  echo "[ERROR] curl/wget not found." >&2
+  exit 1
+}
+
+sanitize_banner() {
+  local src="$1"
+  local dst="$2"
+
+  awk '
+    NR == 1 && $0 ~ /^#!/ { next }
+    $0 ~ /^set -[a-zA-Z]*u[a-zA-Z]*$/ { next }
+    { print }
+  ' "$src" > "$dst"
+}
+
+raw_banner="$(mktemp)"
+clean_banner="$(mktemp)"
+trap 'rm -f "$raw_banner" "$clean_banner"' EXIT
+
+fetch_file "$SOURCE_URL" "$raw_banner"
+sanitize_banner "$raw_banner" "$clean_banner"
+
+if [[ ! -s "$clean_banner" ]]; then
+  echo "[ERROR] Downloaded banner is empty after sanitization: $SOURCE_URL" >&2
+  exit 1
+fi
+
+install -d -m 0755 "$(dirname "$BANNER_FILE")"
+install -m 0755 "$clean_banner" "$BANNER_FILE"
+
+install -d -m 0755 /etc/profile.d
+cat > "$PROFILED_FILE" <<EOF_LAUNCHER
+$MANAGED_LINE
+# Ubuntu-safe launcher for vps-custom-banner
+# Run only for interactive shells
+case "\$-" in
+  *i*) ;;
+  *) return 0 2>/dev/null || exit 0 ;;
+esac
+
+# Execute banner with bash so bash-specific syntax in banner is safe
+if command -v bash >/dev/null 2>&1 && [ -r "$BANNER_FILE" ]; then
+  bash "$BANNER_FILE"
+fi
+EOF_LAUNCHER
+
+chmod 0644 "$PROFILED_FILE"
+
+echo "[OK] vps-custom-banner installed"
+echo "[OK] Banner script: $BANNER_FILE"
+echo "[OK] Profile launcher: $PROFILED_FILE"
+echo "[OK] /etc/profile not modified"
 
EOF
)
