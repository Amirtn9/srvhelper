#!/usr/bin/env bash
os_label() {
  if [[ -f /etc/os-release ]]; then (. /etc/os-release; printf '%s %s' "${ID:-Linux}" "${VERSION_ID:-}")
  else uname -s; fi
}

cpu_usage() {
  local before after
  before=$(awk '/^cpu / {print; exit}' /proc/stat 2>/dev/null) || return 1
  sleep 0.2
  after=$(awk '/^cpu / {print; exit}' /proc/stat 2>/dev/null) || return 1
  awk -v before="$before" -v after="$after" '
    BEGIN {
      if (split(before, a) < 5 || split(after, b) < 5) exit 1
      for (i = 2; i <= 9; i++) total += b[i] - a[i]
      idle = b[5] - a[5] + b[6] - a[6]
      if (total <= 0 || idle < 0 || idle > total) exit 1
      printf "%.0f", 100 * (total - idle) / total
    }'
}

resource_meter() {
  local label=$1 percent=$2 detail=$3
  local width=16 filled=0 color=$OK bar percent_label=' --' i
  if [[ "$percent" =~ ^([0-9]{1,2}|100)$ ]]; then
    filled=$(((10#$percent * width + 50) / 100))
    printf -v percent_label '%3d%%' "$((10#$percent))"
    if ((10#$percent >= 90)); then color=$BAD
    elif ((10#$percent >= 75)); then color=$WARN
    fi
  fi
  bar=''
  for ((i=0; i<width; i++)); do
    if ((i<filled)); then bar+='#'; else bar+='-'; fi
  done
  printf '  %-5s [%s%s%s] %4s  %s\n' "$label" "$color" "$bar" "$RESET" "$percent_label" "$detail"
}

quick_status() {
  local os host cores cpu ram disk uptime_line
  os=$(os_label); host=$(hostname 2>/dev/null || printf unknown)
  cores=$(getconf _NPROCESSORS_ONLN 2>/dev/null || printf '?')
  cpu=$(cpu_usage) || cpu=''
  ram=$(awk '
    /^MemTotal:/ {total = $2}
    /^MemAvailable:/ {available = $2; found = 1}
    END {if (total > 0 && found && available <= total) printf "%.0f", 100 * (total - available) / total}
  ' /proc/meminfo 2>/dev/null) || ram=''
  disk=$(LC_ALL=C df -P / 2>/dev/null | awk 'NR==2 {sub(/%$/, "", $5); print $5}') || disk=''
  uptime_line=$(uptime -p 2>/dev/null || printf unknown)
  printf '  %s%s / %s%s\n' "$DIM" "$host" "$os" "$RESET"
  resource_meter CPU "$cpu" "$cores logical CPUs"
  resource_meter RAM "$ram" 'Memory in use'
  resource_meter 'Disk' "$disk" 'Root filesystem'
  printf '  Uptime: %s\n' "$uptime_line"
}

system_overview() {
  local action
  while :; do
    banner; section 'VASIAT SERVER'
    quick_status
    printf '\n  Kernel    : %s\n' "$(uname -r)"
    printf '  Load      : %s\n' "$(awk '{print $1,$2,$3}' /proc/loadavg 2>/dev/null)"
    if command -v free >/dev/null; then free -h | awk 'NR==2 {printf "  RAM       : %s available / %s total\n", $7, $2}'; fi
    df -h / | awk 'NR==2 {printf "  Disk /    : %s used / %s total (%s)\n", $3, $2, $5}'
    if command -v ip >/dev/null; then ip -brief -4 addr show scope global 2>/dev/null | head -6; fi
    printf '  IPv6      : %s\n' "$(sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null || echo unknown) (1=disabled)"
    printf '  Ping      : %s\n' "$(sysctl -n net.ipv4.icmp_echo_ignore_all 2>/dev/null || echo unknown) (1=ignored)"
    if systemctl list-unit-files certbot.timer >/dev/null 2>&1; then
      printf '  Certbot   : %s\n' "$(systemctl is-enabled certbot.timer 2>/dev/null || echo unknown)"
    fi
    [[ -t 0 && -t 1 ]] || return 0
    prompt 'R = refresh | Enter = bargasht' action || return 0
    [[ "${action,,}" == r ]] || return 0
  done
}
network_status() {
  banner; section 'BARRASI SHABAKE'
  if command -v ss >/dev/null; then ss -ltnp | head -30; else warn 'ss mojood nist'; fi
  printf '\n'
  if command -v ip >/dev/null; then ip route get 1.1.1.1 2>/dev/null || :; fi
  dns_status
}
# Keep persistent settings in one isolated file, without touching existing distro files.
set_sysctl_option() {
  local key=$1 value=$2 file='/etc/sysctl.d/90-srv-helper.conf' new tmp
  need_root || return 1
  [[ "$key" == net.ipv6.conf.all.disable_ipv6 || "$key" == net.ipv4.icmp_echo_ignore_all ]] || return 1
  [[ "$value" == 0 || "$value" == 1 ]] || return 1
  warn "Tanzim system: $key = $value"
  confirm 'Taghir anjam shavad? (risk baraye SSH/network)' || return 1
  tmp=$(mktemp /etc/sysctl.d/.srv-helper.XXXXXX) || return 1
  if [[ -f "$file" ]]; then
    awk -v key="$key" '
      $0 !~ "^[[:space:]]*" key "[[:space:]]*=" {print}
    ' "$file" > "$tmp"
  fi
  printf '%s = %s\n' "$key" "$value" >> "$tmp"
  chmod 644 "$tmp"
  mv -f -- "$tmp" "$file"
  if sysctl -w "$key=$value"; then success 'Tanzim system zakhire shod';
  else fail 'Ejra fail shod; file ra barrasi konid'; return 1; fi
}
reset_sysctl() {
  need_root || return 1
  local file='/etc/sysctl.d/90-srv-helper.conf'
  [[ -f "$file" ]] || { warn 'Hich setting SRV Helper mojood nist'; return 1; }
  confirm 'File sysctl pak shavad va meghdar default faal shavad?' || return 1
  rm -f -- "$file"
  # Reset to common defaults. Another distro sysctl file may override them later.
  sysctl -w net.ipv6.conf.all.disable_ipv6=0 || :
  sysctl -w net.ipv4.icmp_echo_ignore_all=0 || :
  success 'Setting ha reset shodand; baraye restore daghigh, distro config ra barresi konid.'
}
network_menu() {
  local choice
  while :; do
    choose_menu choice 'MODIRIAT SHABAKE' '' \
      1 'Gheyre faal kardan IPv6 (paydar)' \
      2 'Faal kardan IPv6 (paydar)' \
      3 'Masdood kardan pasokh Ping' \
      4 'Baz kardan pasokh Ping' \
      5 'Reset tanzimat sysctl' \
      0 'Bargasht' || return
    case "$choice" in
      1) set_sysctl_option net.ipv6.conf.all.disable_ipv6 1 ;;
      2) set_sysctl_option net.ipv6.conf.all.disable_ipv6 0 ;;
      3) set_sysctl_option net.ipv4.icmp_echo_ignore_all 1 ;;
      4) set_sysctl_option net.ipv4.icmp_echo_ignore_all 0 ;;
      5) reset_sysctl ;;
      0) return ;;
      *) warn 'Gozine namotabar' ;;
    esac
    pause
  done
}
system_menu() {
  local choice rc
  while :; do
    [[ ${SRV_EXIT_REQUESTED:-0} == 1 ]] && return
    choose_menu choice 'ABZAR SYSTEM' '' \
      1 'Vaziat server (CPU / RAM / Disk / moddat faaliat)' \
      2 'Vaziat shabake (port / route / DNS)' \
      3 'Tanzimat IPv6 va Ping' \
      4 'Test MTU (faghat khanadani)' \
      5 'Barrasi amniat SSH' \
      6 'Ezafe kardan port SSH ba amniat' \
      0 'Bargasht'; rc=$?
    if ((rc==20)); then SRV_BACK_REQUESTED=0; return; fi
    ((rc==0)) || return "$rc"
    case "$choice" in
      1) system_overview ;;
      2) network_status; pause ;;
      3) network_menu ;;
      4) mtu_finder; pause ;;
      5) ssh_audit; pause ;;
      6) ssh_add_port_safely; pause ;;
      0) return ;;
      *) warn 'Gozine namotabar'; pause ;;
    esac
    [[ ${SRV_EXIT_REQUESTED:-0} == 1 ]] && return
    if [[ ${SRV_BACK_REQUESTED:-0} == 1 ]]; then SRV_BACK_REQUESTED=0; fi
  done
}

tcp_profile_available() {
  local profile=$1 available
  available=$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || echo '')
  if [[ "$profile" == hybla && " $available " != *' hybla '* ]]; then
    modprobe tcp_hybla 2>/dev/null || :
    available=$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || echo '')
  fi
  [[ " $available " == *" $profile "* ]]
}

tcp_profile_apply() {
  local profile=$1 file='/etc/sysctl.d/91-srv-helper-tcp.conf' backup='' qdisc='fq' previous_cc previous_qdisc
  need_root || return 1
  case "$profile" in bbr|hybla|cubic) ;; *) fail 'TCP profile namotabar'; return 1 ;; esac
  tcp_profile_available "$profile" || { fail "$profile dar kernel mojood nist"; return 1; }
  [[ "$profile" == cubic ]] && qdisc='fq_codel'
  previous_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo cubic)
  previous_qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo fq_codel)
  install -d -m 700 "$(backup_dir)/sysctl"
  if [[ -f "$file" ]]; then
    backup="$(backup_dir)/sysctl/91-srv-helper-tcp.$(date -u +%Y%m%dT%H%M%SZ).bak"
    cp -a "$file" "$backup"
  fi
  printf 'net.core.default_qdisc = %s\nnet.ipv4.tcp_congestion_control = %s\n' "$qdisc" "$profile" > "$file"
  chmod 644 "$file"
  if sysctl -p "$file" >/dev/null; then
    success "TCP profile set shod: $profile / $qdisc"
    return 0
  fi
  fail 'Apply TCP profile fail shod; rollback dar hale ejra ast'
  if [[ -n "$backup" ]]; then cp -a "$backup" "$file"; else rm -f "$file"; fi
  sysctl -w net.core.default_qdisc="$previous_qdisc" >/dev/null 2>&1 || :
  sysctl -w net.ipv4.tcp_congestion_control="$previous_cc" >/dev/null 2>&1 || :
  return 1
}

bbr_enable_auto() {
  local current
  current=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo unknown)
  if [[ "$current" == bbr ]]; then success 'BBR az ghabl faal ast'; return 0; fi
  tcp_profile_apply bbr
}

tcp_optimizer_menu() {
  local current available choice
  while :; do
    banner; section 'TANZIM TCP | BBR / HYBLA'
    current=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo unknown)
    available=$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || echo unknown)
    info "Vaziat feli: $current | Gozine haye mojood: $available"
    menu_line 1 'Faal kardan BBR + fq (agar kernel poshtibani konad)'
    menu_line 2 'Faal kardan Hybla (agar module mojood bashad)'
    menu_line 3 'Bazgasht be Cubic'
    menu_line 0 'Bargasht'
    prompt 'Entekhab' choice || return
    case "$choice" in
      1) confirm 'BBR faal shavad?' && tcp_profile_apply bbr ;;
      2) confirm 'Hybla faal shavad?' && tcp_profile_apply hybla ;;
      3) confirm 'Cubic be onvan default set shavad?' && tcp_profile_apply cubic ;;
      0) return ;;
      *) warn 'Gozine namotabar' ;;
    esac
    pause
  done
}

bbr_menu() { tcp_optimizer_menu; }
