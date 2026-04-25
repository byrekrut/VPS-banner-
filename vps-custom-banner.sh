#!/usr/bin/env bash
set -u

SCRIPT_BASENAME="vps-custom-banner"
INSTALL_PATH="/usr/local/bin/${SCRIPT_BASENAME}"
PROFILE_SNIPPET="/etc/profile.d/${SCRIPT_BASENAME}-menu.sh"
MODE="${1:-}"

# Install/update mode:
#   ./vps-custom-banner.sh --install
# This will replace previous installation (if exists) and register `menu` alias.
if [ "$MODE" = "--install" ]; then
  SRC_PATH="$(readlink -f "$0")"
  if [ ! -f "$SRC_PATH" ]; then
    echo "Не удалось найти файл скрипта для установки."
    exit 1
  fi

  if [ -f "$INSTALL_PATH" ]; then
    sudo rm -f "$INSTALL_PATH"
    echo "Старая версия удалена: $INSTALL_PATH"
  fi

  sudo install -m 0755 "$SRC_PATH" "$INSTALL_PATH"

  TMP_SNIPPET="$(mktemp)"
  cat > "$TMP_SNIPPET" <<EOF_SNIPPET
# ${SCRIPT_BASENAME} menu alias
if command -v ${SCRIPT_BASENAME} >/dev/null 2>&1; then
  alias menu='${SCRIPT_BASENAME} --menu'
fi
EOF_SNIPPET
  sudo mv "$TMP_SNIPPET" "$PROFILE_SNIPPET"
  sudo chmod 0644 "$PROFILE_SNIPPET"

  echo "Установлено: $INSTALL_PATH"
  echo "Добавлен alias 'menu' через $PROFILE_SNIPPET"
  echo "Перезайдите по SSH или выполните: source $PROFILE_SNIPPET"
  exit 0
fi

# VPS SSH banner with auto-detection of popular proxy/VPN tools and panels.
# Compatible with Debian/Ubuntu/CentOS/Alpine systems with systemd or SysV init.

# ===== Colors =====
purple="\033[38;5;141m"
pink="\033[38;5;212m"
green="\033[38;5;78m"
blue="\033[38;5;117m"
orange="\033[38;5;214m"
line="\033[38;5;250m"
text="\033[38;5;252m"
yellow="\033[38;5;220m"
red="\033[38;5;196m"
reset="\033[0m"

clear

# Collect all banner output first and print once at the end so the
# login banner appears instantly as a single block.
OUTPUT=""
append_line() {
  OUTPUT+="$1"$'\n'
}

# ===== Banner =====
append_line "${blue}██╗   ██╗██████╗ ███████╗"
append_line "██║   ██║██╔══██╗██╔════╝"
append_line "██║   ██║██████╔╝███████╗"
append_line "╚██╗ ██╔╝██╔═══╝ ╚════██║"
append_line " ╚████╔╝ ██║     ███████║"
append_line "  ╚═══╝  ╚═╝     ╚══════╝${reset}"
append_line ""

# ===== Helpers =====
has_cmd() { command -v "$1" >/dev/null 2>&1; }
can_exec() { [ -n "${1:-}" ] && { [ -x "$1" ] || has_cmd "$1"; }; }

is_proc_running() {
  local proc="$1"
  [ -z "$proc" ] && return 1
  grep -qiE "(^|[[:space:]/])${proc}([[:space:]]|$)" <<< "$PROC_SNAPSHOT"
}

is_service_running() {
  local svc="$1"
  [ -z "$svc" ] && return 1
  [ -n "${ACTIVE_SERVICE_SET[$svc]+x}" ]
}

restart_service() {
  local svc="$1"
  if has_cmd systemctl; then
    systemctl restart "$svc"
  elif has_cmd service; then
    service "$svc" restart
  else
    return 1
  fi
}

get_pkg_version() {
  local pkg="$1"
  if has_cmd dpkg-query; then
    dpkg-query -W -f='${Version}' "$pkg" 2>/dev/null && return 0
  fi
  if has_cmd rpm; then
    rpm -q --qf '%{VERSION}-%{RELEASE}' "$pkg" 2>/dev/null && return 0
  fi
  if has_cmd apk; then
    apk info -e "$pkg" >/dev/null 2>&1 && apk info "$pkg" 2>/dev/null | head -n1 && return 0
  fi
  return 1
}

extract_version_line() {
  local raw="$1"
  local picked
  picked="$(printf "%s" "$raw" | tr -d '\r' | sed 's/[[:space:]]\+$//' | grep -m1 -E 'v?[0-9]+(\.[0-9]+){2,4}')"
  if [ -z "$picked" ]; then
    picked="$(printf "%s" "$raw" | tr -d '\r' | sed 's/[[:space:]]\+$//' | grep -m1 -Ei 'version.*[0-9]+\.[0-9]+')"
  fi
  # Ignore noisy non-version output.
  if [ -z "$picked" ] || ! printf "%s" "$picked" | grep -Eq '[0-9]'; then
    return 1
  fi
  printf "%s" "$picked"
}

run_version_cmd() {
  # Usage: run_version_cmd <command...>
  if has_cmd timeout; then
    timeout 1 "$@" 2>&1
  else
    "$@" 2>&1
  fi
}

deep_version_fallback() {
  local name="$1"
  local bin="$2"
  local svc="$3"
  local v=""
  local d=""
  local db=""

  # x-ui / 3x-ui often keep values in sqlite settings DB.
  if [[ "$name" == "x-ui" || "$name" == "3x-ui" ]]; then
    if can_exec "$bin"; then
      v="$(run_version_cmd "$bin" setting -show true | grep -m1 -Ei 'version[^0-9]*[0-9]+\.[0-9]+(\.[0-9]+)?' || true)"
      if [ -n "$v" ]; then
        v="$(printf "%s" "$v" | grep -Eo 'v?[0-9]+(\.[0-9]+){1,3}' | head -n1)"
        [ -n "$v" ] && { printf "%s" "$v"; return 0; }
      fi
    fi
    if has_cmd sqlite3; then
      for db in /etc/x-ui/x-ui.db /usr/local/x-ui/x-ui.db; do
        if [ -f "$db" ]; then
          v="$(sqlite3 "$db" "select value from settings where key in ('xuiVersion','version','xrayVersion','panelVersion','webPanelVersion','x_ui_version','XrayVersion') and value!='' limit 1;" 2>/dev/null | sed -n '1p')"
          [ -n "$v" ] && { printf "%s" "$v"; return 0; }
        fi
      done
    fi
  fi

  # Try nearby version files.
  if [ -n "$bin" ]; then
    d="$(dirname "$bin" 2>/dev/null || true)"
    for f in "$d/VERSION" "$d/version" "$d/.version" "$d/../VERSION" "$d/../version"; do
      if [ -r "$f" ]; then
        v="$(sed -n '1p' "$f" | tr -d '\r')"
        if printf "%s" "$v" | grep -Eq '[0-9]+\.[0-9]+'; then
          printf "%s" "$v"
          return 0
        fi
      fi
    done
  fi

  # Last resort: parse semantic version from binary strings.
  if has_cmd strings && [ -r "$bin" ]; then
    v="$(strings "$bin" 2>/dev/null | grep -m1 -Eo 'v?[0-9]+(\.[0-9]+){2,4}')"
    if [ -n "$v" ]; then
      printf "%s" "$v"
      return 0
    fi
  fi

  # Binary byte-scan fallback for stripped executables.
  if [ -r "$bin" ]; then
    v="$(grep -aoE 'v?[0-9]+\.[0-9]+\.[0-9]+' "$bin" 2>/dev/null | head -n1 || true)"
    if [ -n "$v" ]; then
      printf "%s" "$v"
      return 0
    fi
  fi

  # systemd status line can sometimes expose app version.
  if has_cmd systemctl && [ -n "$svc" ]; then
    v="$(systemctl status "$svc" --no-pager 2>/dev/null \
      | grep -iE 'version|v[0-9]' \
      | grep -m1 -Eo 'v?[0-9]+(\.[0-9]+){2,4}' || true)"
    if [ -n "$v" ]; then
      printf "%s" "$v"
      return 0
    fi
  fi

  return 1
}

resolve_bin_path() {
  local name="$1"
  local bin="$2"
  local proc="$3"
  local svc="$4"
  local candidate=""
  local p=""

  if [ -n "$bin" ] && has_cmd "$bin"; then
    command -v "$bin"
    return 0
  fi

  for p in \
    "/usr/local/bin/$bin" "/usr/bin/$bin" "/bin/$bin" \
    "/usr/local/sbin/$bin" "/usr/sbin/$bin" \
    "/usr/local/bin/$proc" "/usr/bin/$proc" "/bin/$proc"; do
    if [ -n "$p" ] && [ -x "$p" ]; then
      printf "%s" "$p"
      return 0
    fi
  done

  case "$name" in
    3x-ui|x-ui)
      for p in "/usr/local/x-ui/x-ui" "/opt/x-ui/x-ui"; do
        [ -x "$p" ] && { printf "%s" "$p"; return 0; }
      done
      ;;
    xray)
      for p in "/usr/local/bin/xray" "/usr/bin/xray" "/usr/local/x-ui/bin/xray" /usr/local/x-ui/bin/xray*; do
        [ -x "$p" ] && { printf "%s" "$p"; return 0; }
      done
      ;;
    sing-box)
      for p in "/usr/local/bin/sing-box" "/usr/bin/sing-box"; do
        [ -x "$p" ] && { printf "%s" "$p"; return 0; }
      done
      ;;
  esac

  # Try to resolve executable from running process command line.
  if has_cmd pgrep && [ -n "$proc" ]; then
    local p_line p_pid p_cmd p_exec p_exec_abs
    p_line="$(pgrep -af "$proc" 2>/dev/null | head -n1 || true)"
    p_pid="${p_line%% *}"
    p_cmd="${p_line#* }"
    p_exec="${p_cmd%% *}"
    if [ -n "$p_exec" ] && [ -x "$p_exec" ]; then
      printf "%s" "$p_exec"
      return 0
    fi
    # Resolve relative executable path using process CWD.
    if [ -n "$p_exec" ] && [ -n "$p_pid" ] && [ -d "/proc/$p_pid/cwd" ]; then
      p_exec_abs="$(readlink -f "/proc/$p_pid/cwd/$p_exec" 2>/dev/null || true)"
      if [ -n "$p_exec_abs" ] && [ -x "$p_exec_abs" ]; then
        printf "%s" "$p_exec_abs"
        return 0
      fi
    fi
    # Last-resort for xray custom names (e.g. xray-linux-amd64).
    if [ "$name" = "xray" ] && [ -n "$p_exec" ]; then
      p_exec_abs="$(readlink -f "$p_exec" 2>/dev/null || true)"
      if [ -n "$p_exec_abs" ] && [ -x "$p_exec_abs" ]; then
        printf "%s" "$p_exec_abs"
        return 0
      fi
    fi
    if [ -n "$p_exec" ] && [ -n "$p_pid" ] && [ -d "/proc/$p_pid/cwd/bin" ] && [ "$name" = "xray" ]; then
      p_exec_abs="$(find "/proc/$p_pid/cwd/bin" -maxdepth 1 -type f -name 'xray*' 2>/dev/null | head -n1 || true)"
      if [ -n "$p_exec_abs" ]; then
        p_exec_abs="$(readlink -f "$p_exec_abs" 2>/dev/null || true)"
      fi
      if [ -n "$p_exec_abs" ] && [ -x "$p_exec_abs" ]; then
        printf "%s" "$p_exec_abs"
        return 0
      fi
    fi
    if [ -n "$p_exec" ] && [ -x "/usr/local/x-ui/$p_exec" ]; then
      printf "%s" "/usr/local/x-ui/$p_exec"
      return 0
    fi
  fi

  # Try to resolve executable from systemd unit ExecStart.
  if has_cmd systemctl && [ -n "$svc" ]; then
    local s_line s_exec
    s_line="$(systemctl show -p ExecStart --value "$svc" 2>/dev/null | sed -n '1p' || true)"
    s_exec="$(printf "%s" "$s_line" | sed -n 's/.*path=\\([^ ;]*\\).*/\\1/p' | sed -n '1p')"
    if [ -n "$s_exec" ] && [ -x "$s_exec" ]; then
      printf "%s" "$s_exec"
      return 0
    fi
  fi

  printf "%s" "$bin"
}

get_tool_version() {
  local name="$1"
  local bin="$2"
  local pkg="$3"
  local out=""
  local parsed=""

  case "$name" in
    xray) out="$(run_version_cmd "$bin" version | sed -n '1p')" ;;
    v2ray) out="$(run_version_cmd "$bin" version | sed -n '1p')" ;;
    xrayr) out="$(run_version_cmd "$bin" --version | sed -n '1p')" ;;
    sing-box) out="$(run_version_cmd "$bin" version | sed -n '1p')" ;;
    nginx) out="$(run_version_cmd "$bin" -v | sed -n '1p')" ;;
    docker) out="$(run_version_cmd "$bin" --version | sed -n '1p')" ;;
    3x-ui|x-ui) out="$(run_version_cmd "$bin" version | sed -n '1p')" ;;
    marzban) out="$(run_version_cmd "$bin" version | sed -n '1p')" ;;
    hiddify) out="$(run_version_cmd "$bin" --version | sed -n '1p')" ;;
    s-ui) out="$(run_version_cmd "$bin" version | sed -n '1p')" ;;
    remnawave) out="$(run_version_cmd "$bin" --version | sed -n '1p')" ;;
    telemt|telemt-panel) out="$(run_version_cmd "$bin" --version | sed -n '1p')" ;;
    shadowsocks) out="$(run_version_cmd "$bin" -h | grep -m1 -E '([Vv]ersion|[0-9]+\\.[0-9]+)')" ;;
    shadowsocks-rust|shadowsocks-go) out="$(run_version_cmd "$bin" --version | sed -n '1p')" ;;
    trojan|trojan-go) out="$(run_version_cmd "$bin" --version | sed -n '1p')" ;;
    hysteria|hysteria2) out="$(run_version_cmd "$bin" version | sed -n '1p')" ;;
    tuic) out="$(run_version_cmd "$bin" -V | sed -n '1p')" ;;
    naiveproxy) out="$(run_version_cmd "$bin" --version | sed -n '1p')" ;;
    wireguard) out="$(run_version_cmd "$bin" --version | sed -n '1p')" ;;
    wg-easy) out="$(run_version_cmd "$bin" --version | sed -n '1p')" ;;
    amneziaWG) out="$(run_version_cmd "$bin" --version | sed -n '1p')" ;;
    openvpn) out="$(run_version_cmd "$bin" --version | sed -n '1p')" ;;
    ocserv) out="$(run_version_cmd "$bin" --version | sed -n '1p')" ;;
    strongswan) out="$(run_version_cmd "$bin" --version | sed -n '1p')" ;;
    softether) out="$(run_version_cmd "$bin" version | sed -n '1p')" ;;
    pptpd) out="$(run_version_cmd "$bin" --version | sed -n '1p')" ;;
    tailscale) out="$(run_version_cmd "$bin" version | sed -n '1p')" ;;
    headscale) out="$(run_version_cmd "$bin" version | sed -n '1p')" ;;
    squid) out="$(run_version_cmd "$bin" -v | sed -n '1p')" ;;
    tinyproxy) out="$(run_version_cmd "$bin" -v | sed -n '1p')" ;;
    privoxy) out="$(run_version_cmd "$bin" --version | sed -n '1p')" ;;
    apache) out="$(run_version_cmd "$bin" -v | sed -n '1p')" ;;
    caddy) out="$(run_version_cmd "$bin" version | sed -n '1p')" ;;
    fail2ban) out="$(run_version_cmd "$bin" --version | sed -n '1p')" ;;
    *) ;;
  esac

  if [ -z "$out" ] && can_exec "$bin"; then
    out="$(run_version_cmd "$bin" --version | sed -n '1p')"
  fi
  if [ -z "$out" ] && can_exec "$bin"; then
    out="$(run_version_cmd "$bin" -v | sed -n '1p')"
  fi
  if [ -z "$out" ] && can_exec "$bin"; then
    out="$(run_version_cmd "$bin" version | sed -n '1p')"
  fi
  if [ -z "$out" ] && [ -n "$pkg" ]; then
    out="$(get_pkg_version "$pkg" 2>/dev/null || true)"
  fi

  parsed="$(extract_version_line "$out" 2>/dev/null || true)"
  if [ -n "$parsed" ]; then
    printf "%s" "$parsed"
  else
    printf "%s" "-"
  fi
}

# ===== Resource block =====
CPU_LOAD="$(awk '{print $1", "$2", "$3}' /proc/loadavg 2>/dev/null || echo 'N/A')"
PROCS="$(ps -e --no-headers 2>/dev/null | wc -l || echo 'N/A')"
MEM="$(free -h 2>/dev/null | awk '/^Mem:/ {print $3"/"$2}' || echo 'N/A')"
DISK="$(df -h / 2>/dev/null | awk 'NR==2 {print $3"/"$2" ("$5")"}' || echo 'N/A')"
UPTIME="$(uptime -p 2>/dev/null | sed 's/^up //' || cat /proc/uptime | awk '{print int($1/86400)"d "int(($1%86400)/3600)"h "int(($1%3600)/60)"m"}')"

ROW=0
next_color() {
  if [ $((ROW % 2)) -eq 0 ]; then
    ROW_COLOR="$purple"
  else
    ROW_COLOR="$pink"
  fi
  ROW=$((ROW+1))
}

next_color
append_line "$(printf "%b %-12s%b ${text}%s${reset}" "$ROW_COLOR" "Date:" "$reset" "$(date)")"
next_color
append_line "$(printf "%b %-12s%b ${text}%s${reset}" "$ROW_COLOR" "Uptime:" "$reset" "$UPTIME")"
next_color
append_line "$(printf "%b %-12s%b ${text}%s${reset}" "$ROW_COLOR" "LoadAvg:" "$reset" "$CPU_LOAD")"
next_color
append_line "$(printf "%b %-12s%b ${text}%s${reset}" "$ROW_COLOR" "Memory:" "$reset" "$MEM")"
next_color
append_line "$(printf "%b %-12s%b ${text}%s${reset}" "$ROW_COLOR" "Disk /:" "$reset" "$DISK")"
next_color
append_line "$(printf "%b %-12s%b ${text}%s${reset}" "$ROW_COLOR" "Processes:" "$reset" "$PROCS")"
append_line ""

# ===== Fast snapshots for detection (avoid many slow systemctl/pgrep calls) =====
PROC_SNAPSHOT="$(ps -eo comm=,args= 2>/dev/null | tr '[:upper:]' '[:lower:]')"
ACTIVE_SERVICES=""
declare -A ACTIVE_SERVICE_SET=()
if has_cmd systemctl; then
  ACTIVE_SERVICES="$(systemctl list-units --type=service --state=active --no-legend --plain 2>/dev/null \
    | awk '{print $1}' | sed 's/\\.service$//' | tr '[:upper:]' '[:lower:]')"
  while IFS= read -r s; do
    [ -n "$s" ] && ACTIVE_SERVICE_SET["$s"]=1
  done <<< "$ACTIVE_SERVICES"
fi

# ===== Candidate apps list (popular VPS stack) =====
# format: display|process|service|binary_hint|package_hint
CANDIDATES=(
  # ===== Панели =====
  "xray|xray|xray|xray|xray"
  "3x-ui|x-ui|x-ui|x-ui|"
  "x-ui|x-ui|x-ui|x-ui|"
  "marzban|marzban|marzban|marzban|"
  "hiddify|hiddify|hiddify-panel|hiddify|"
  "s-ui|s-ui|s-ui|s-ui|"
  "remnawave|remnawave|remnawave|remnawave|"
  "v2board|v2board|v2board|v2board|"
  "sspanel|sspanel|sspanel|sspanel|"
  "telemt|telemt|telemt|telemtd|"
  "telemt-panel|telemt-panel|telemt-panel|telemt-panel|"

  # ===== Xray / V2Ray =====
  "v2ray|v2ray|v2ray|v2ray|v2ray"
  "xrayr|xrayr|xrayr|xrayr|"

  # ===== Sing-box =====
  "sing-box|sing-box|sing-box|sing-box|sing-box"

  # ===== Shadowsocks =====
  "shadowsocks|ss-server|shadowsocks|ss-server|shadowsocks-libev"
  "shadowsocks-rust|ssserver|shadowsocks-rust|ssserver|"
  "shadowsocks-go|ssserver|shadowsocks-go|ssserver|"

  # ===== Trojan =====
  "trojan|trojan|trojan|trojan|"
  "trojan-go|trojan-go|trojan-go|trojan-go|"

  # ===== Hysteria =====
  "hysteria|hysteria|hysteria-server|hysteria|"
  "hysteria2|hysteria|hysteria-server|hysteria|"

  # ===== TUIC =====
  "tuic|tuic|tuic|tuic-server|"

  # ===== NaiveProxy =====
  "naiveproxy|naive|naiveproxy|naive|naiveproxy"

  # ===== WireGuard / VPN =====
  "wg-easy|wg-easy|wg-easy|wg-easy|"
  "amneziaWG|awg|amneziawg|awg|"
  "openvpn|openvpn|openvpn|openvpn|openvpn"
  "strongswan|charon|strongswan|ipsec|strongswan"
  "softether|vpnserver|softether|vpnserver|"
  "pptpd|pptpd|pptpd|pptpd|"
  "wireguard|wg|wg-quick@wg0|wg|wireguard-tools"
  "ocserv|ocserv|ocserv|ocserv|ocserv"

  # ===== Mesh VPN =====
  "tailscale|tailscaled|tailscaled|tailscale|tailscale"
  "headscale|headscale|headscale|headscale|headscale"

  # ===== Прокси =====
  "squid|squid|squid|squid|squid"
  "tinyproxy|tinyproxy|tinyproxy|tinyproxy|tinyproxy"
  "privoxy|privoxy|privoxy|privoxy|privoxy"

  # ===== Web servers (часто маскируют VPN) =====
  "nginx|nginx|nginx|nginx|nginx"
  "apache|apache2|apache2|apache2|apache2"
  "caddy|caddy|caddy|caddy|caddy"

  # ===== Дополнительно =====
  "docker|dockerd|docker|docker|docker"
  "fail2ban|fail2ban-server|fail2ban|fail2ban-server|fail2ban"
)

INSTALLED_ROWS=()
RESTARTABLE_SERVICES=()
declare -A SEEN_SERVICES=()

for item in "${CANDIDATES[@]}"; do
  IFS='|' read -r name proc svc bin pkg <<< "$item"

  detected=0
  proc_lc="$proc"
  svc_lc="$svc"
  bin_lc="$bin"

  if can_exec "$bin_lc"; then detected=1; fi
  if [ "$detected" -eq 0 ] && is_proc_running "$proc"; then detected=1; fi
  if [ "$detected" -eq 0 ] && is_service_running "$svc_lc"; then detected=1; fi

  [ "$detected" -eq 0 ] && continue

  bin_path="$(resolve_bin_path "$name" "$bin_lc" "$proc_lc" "$svc_lc")"

  # status
  if is_service_running "$svc_lc" || is_proc_running "$proc_lc"; then
    status="running"
    icon="${green}●${reset}"
    stat_color="$green"
  else
    status="stopped"
    icon="${red}●${reset}"
    stat_color="$red"
  fi

  INSTALLED_ROWS+=("$name|$status|$icon|$stat_color|$svc_lc")
  if [ -n "$svc_lc" ] && [ -z "${SEEN_SERVICES[$svc_lc]+x}" ]; then
    RESTARTABLE_SERVICES+=("$svc_lc")
    SEEN_SERVICES["$svc_lc"]=1
  fi
done

# ===== Services table =====
WIDTH=72
TITLE="VPS installed services"
LEN=${#TITLE}
SIDE=$(( (WIDTH - LEN - 2) / 2 ))
LEFT=$(printf "%${SIDE}s" "" | tr " " "─")
RIGHT=$(printf "%$((WIDTH - LEN - SIDE - 2))s" "" | tr " " "─")
append_line "$(printf "${line}%s %s %s${reset}" "$LEFT" "$TITLE" "$RIGHT")"
append_line ""
append_line "$(printf " ${orange}%-22s %-10s${reset}" "SERVICE" "STATUS")"

if [ "${#INSTALLED_ROWS[@]}" -eq 0 ]; then
  append_line "$(printf " ${yellow}%s${reset}" "No known services from the VPS list were detected.")"
else
  for row in "${INSTALLED_ROWS[@]}"; do
    IFS='|' read -r name status icon stat_color svc <<< "$row"
    next_color
    append_line "$(printf "%b%b %b%-22s%b %b%-10s%b" \
      "$ROW_COLOR" "$icon" "$ROW_COLOR" "$name" "$reset" "$stat_color" "$status" "$reset")"
  done
fi

append_line ""
append_line "$(printf "${line}%${WIDTH}s${reset}" "" | tr " " "─")"
append_line "${yellow}Type 'menu' to open VPS menu${reset}"

# Print all banner text in one write.
printf "%b" "$OUTPUT"

menu() {
  while true; do
    local choice
    choice=$(whiptail --title "VPS Menu" --menu "Выберите действие" 18 65 10 \
      "1" "System update (apt/yum/apk)" \
      "2" "System upgrade (apt/yum/apk)" \
      "3" "Show detected services" \
      "4" "Restart detected service" \
      "0" "Exit" 3>&1 1>&2 2>&3)
    [ $? -ne 0 ] && break

    case "$choice" in
      1)
        if has_cmd apt-get; then sudo apt-get update
        elif has_cmd yum; then sudo yum makecache
        elif has_cmd apk; then sudo apk update
        else echo "No supported package manager found."; fi
        ;;
      2)
        if has_cmd apt-get; then sudo apt-get upgrade -y
        elif has_cmd yum; then sudo yum update -y
        elif has_cmd apk; then sudo apk upgrade
        else echo "No supported package manager found."; fi
        ;;
      3)
        if [ "${#INSTALLED_ROWS[@]}" -eq 0 ]; then
          whiptail --msgbox "Сервисы из списка не обнаружены." 8 50
        else
          local msg=""
          for row in "${INSTALLED_ROWS[@]}"; do
            IFS='|' read -r n s v _ _ _ <<< "$row"
            msg+="$n — $s\n"
          done
          whiptail --msgbox "$msg" 20 70
        fi
        ;;
      4)
        if [ "${#RESTARTABLE_SERVICES[@]}" -eq 0 ]; then
          whiptail --msgbox "Нет сервисов для перезапуска (из списка не найдено)." 8 60
          continue
        fi

        local ws_args=()
        local idx=1
        local svc
        for svc in "${RESTARTABLE_SERVICES[@]}"; do
          ws_args+=("$idx" "$svc")
          idx=$((idx+1))
        done

        local selected
        selected=$(whiptail --title "Restart service" --menu "Выберите сервис" 20 70 12 "${ws_args[@]}" 3>&1 1>&2 2>&3)
        [ $? -ne 0 ] && continue

        local selected_svc="${RESTARTABLE_SERVICES[$((selected-1))]}"
        if restart_service "$selected_svc"; then
          whiptail --msgbox "Сервис '$selected_svc' перезапущен." 8 55
        else
          whiptail --msgbox "Не удалось перезапустить '$selected_svc'." 8 55
        fi
        ;;
      0)
        break
        ;;
    esac
  done
}

if [ "$MODE" = "--menu" ] || [ "$MODE" = "menu" ]; then
  menu
fi
