#!/usr/bin/env bash
set -u

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

# ===== Banner =====
printf "%b" "${blue}"
cat << 'EOF_BANNER'
██╗   ██╗██████╗ ███████╗
██║   ██║██╔══██╗██╔════╝
██║   ██║██████╔╝███████╗
╚██╗ ██╔╝██╔═══╝ ╚════██║
 ╚████╔╝ ██║     ███████║
  ╚═══╝  ╚═╝     ╚══════╝
EOF_BANNER
printf "%b\n" "${reset}"

# ===== Helpers =====
has_cmd() { command -v "$1" >/dev/null 2>&1; }

is_proc_running() {
  local proc="$1"
  pgrep -x "$proc" >/dev/null 2>&1 || pgrep -f "$proc" >/dev/null 2>&1
}

is_service_running() {
  local svc="$1"
  if has_cmd systemctl; then
    systemctl is-active --quiet "$svc" 2>/dev/null
  elif has_cmd service; then
    service "$svc" status >/dev/null 2>&1
  else
    return 1
  fi
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
printf "%b %-12s%b ${text}%s${reset}\n" "$ROW_COLOR" "Date:" "$reset" "$(date)"
next_color
printf "%b %-12s%b ${text}%s${reset}\n" "$ROW_COLOR" "Uptime:" "$reset" "$UPTIME"
next_color
printf "%b %-12s%b ${text}%s${reset}\n" "$ROW_COLOR" "LoadAvg:" "$reset" "$CPU_LOAD"
next_color
printf "%b %-12s%b ${text}%s${reset}\n" "$ROW_COLOR" "Memory:" "$reset" "$MEM"
next_color
printf "%b %-12s%b ${text}%s${reset}\n" "$ROW_COLOR" "Disk /:" "$reset" "$DISK"
next_color
printf "%b %-12s%b ${text}%s${reset}\n" "$ROW_COLOR" "Processes:" "$reset" "$PROCS"

echo

# ===== Candidate apps list (popular VPS stack) =====
# format: display|process|service|binary_hint|package_hint
CANDIDATES=(
  "3x-ui|x-ui|x-ui|x-ui|"
  "xray|xray|xray|xray|xray"
  "phobos|phobos|phobos|phobos|"
  "amneziaWG|awg|amneziawg|awg|"
  "naiveproxy|naive|naiveproxy|naive|naiveproxy"
  "telemt|telemt|telemt|telemtd|"
  "telemt-panel|telemt-panel|telemt-panel|telemt-panel|"
  "marzban|marzban|marzban|marzban|"
  "hiddify|hiddify|hiddify-panel|hiddify|"
  "sing-box|sing-box|sing-box|sing-box|sing-box"
  "openvpn|openvpn|openvpn|openvpn|openvpn"
  "wireguard|wg|wg-quick@wg0|wg|wireguard-tools"
  "ocserv|ocserv|ocserv|ocserv|ocserv"
  "headscale|headscale|headscale|headscale|headscale"
)

INSTALLED_ROWS=()
RESTARTABLE_SERVICES=()

for item in "${CANDIDATES[@]}"; do
  IFS='|' read -r name proc svc bin pkg <<< "$item"

  detected=0
  if [ -n "$bin" ] && has_cmd "$bin"; then detected=1; fi
  if [ "$detected" -eq 0 ] && is_proc_running "$proc"; then detected=1; fi
  if [ "$detected" -eq 0 ] && is_service_running "$svc"; then detected=1; fi
  if [ "$detected" -eq 0 ] && [ -n "$pkg" ] && get_pkg_version "$pkg" >/dev/null 2>&1; then detected=1; fi

  [ "$detected" -eq 0 ] && continue

  # status
  if is_service_running "$svc" || is_proc_running "$proc"; then
    status="running"
    icon="${green}●${reset}"
    stat_color="$green"
  else
    status="stopped"
    icon="${red}●${reset}"
    stat_color="$red"
  fi

  # version: package -> binary --version fallback
  version="-"
  if [ -n "$pkg" ]; then
    version="$(get_pkg_version "$pkg" 2>/dev/null || true)"
  fi
  if [ -z "$version" ] || [ "$version" = "-" ]; then
    if [ -n "$bin" ] && has_cmd "$bin"; then
      version="$($bin --version 2>/dev/null | head -n1 | tr -s ' ')"
    fi
  fi
  [ -z "$version" ] && version="-"

  INSTALLED_ROWS+=("$name|$status|$version|$icon|$stat_color|$svc")
  RESTARTABLE_SERVICES+=("$svc")
done

# ===== Services table =====
WIDTH=72
TITLE="VPS installed services"
LEN=${#TITLE}
SIDE=$(( (WIDTH - LEN - 2) / 2 ))
LEFT=$(printf "%${SIDE}s" "" | tr " " "─")
RIGHT=$(printf "%$((WIDTH - LEN - SIDE - 2))s" "" | tr " " "─")
printf "${line}%s %s %s${reset}\n\n" "$LEFT" "$TITLE" "$RIGHT"
printf " ${orange}%-22s %-10s %s${reset}\n" "SERVICE" "STATUS" "VERSION"

if [ "${#INSTALLED_ROWS[@]}" -eq 0 ]; then
  printf " ${yellow}%s${reset}\n" "No known services from the VPS list were detected."
else
  for row in "${INSTALLED_ROWS[@]}"; do
    IFS='|' read -r name status version icon stat_color svc <<< "$row"
    next_color
    printf "%b%b %b%-22s%b %b%-10s%b ${blue}%s${reset}\n" \
      "$ROW_COLOR" "$icon" "$ROW_COLOR" "$name" "$reset" "$stat_color" "$status" "$reset" "$version"
  done
fi

printf "\n${line}%${WIDTH}s${reset}\n" "" | tr " " "─"
printf "${yellow}Type 'menu' to open VPS menu${reset}\n"

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
