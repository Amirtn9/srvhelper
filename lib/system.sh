#!/usr/bin/env bash
os_label() {
  if [[ -f /etc/os-release ]]; then (. /etc/os-release; printf '%s %s' "${ID:-Linux}" "${VERSION_ID:-}")
  else uname -s; fi
}

quick_status() {
  local os host uptime_line cpu ram disk ipv6 ping tcp dns_state
  os=$(os_label); host=$(hostname 2>/dev/null || echo unknown)
  uptime_line=$(uptime -p 2>/dev/null || echo unknown)
  cpu=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo '?')
  ram=$(free -h 2>/dev/null | awk 'NR==2 {print $3 "/" $2}')
  disk=$(df -h / 2>/dev/null | awk 'NR==2 {print $5}')
  ipv6=$(sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null || echo '?')
  ping=$(sysctl -n net.ipv4.icmp_echo_ignore_all 2>/dev/null || echo '?')
  tcp=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo '?')
  if systemctl is-active --quiet systemd-resolved 2>/dev/null; then dns_state='resolved: active'; else dns_state='resolver: system'; fi
  printf '%b\n' "${DIM}  HOST: $host | OS: $os | CPU: $cpu core | RAM: ${ram:-?} | DISK: ${disk:-?}${RESET}"
  printf '%b\n' "${DIM}  UPTIME: $uptime_line | IPv6-disable: $ipv6 | Ping-ignore: $ping | TCP: $tcp | $dns_state${RESET}"
}

system_overview() {
  banner; section 'VASIAT SERVER'
  printf '  OS        : %s\n' "$(os_label)"
  printf '  Hostname  : %s\n' "$(hostname)"
  printf '  Kernel    : %s\n' "$(uname -r)"
  printf '  CPU cores : %s\n' "$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo unknown)"
  printf '  Uptime    : %s\n' "$(uptime -p 2>/dev/null || uptime)"
  printf '  Load      : %s\n' "$(awk '{print $1,$2,$3}' /proc/loadavg 2>/dev/null)"
  if command -v free >/dev/null; then free -h | awk 'NR==2 {printf "  RAM       : %s used / %s total\n", $3, $2}'; fi
  df -h / | awk 'NR==2 {printf "  Disk /    : %s used / %s total (%s)\n", $3, $2, $5}'
  if command -v ip >/dev/null; then ip -brief -4 addr show scope global 2>/dev/null | head -6; fi
  printf '  IPv6      : %s\n' "$(sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null || echo unknown) (1=disabled)"
  printf '  Ping      : %s\n' "$(sysctl -n net.ipv4.icmp_echo_ignore_all 2>/dev/null || echo unknown) (1=ignored)"
  if systemctl list-unit-files certbot.timer >/dev/null 2>&1; then
    printf '  Certbot   : %s\n' "$(systemctl is-enabled certbot.timer 2>/dev/null || echo unknown)"
  fi
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
  warn "System setting: $key = $value"
  confirm 'Taghir anjam shavad? (SSH/network risk)' || return 1
  tmp=$(mktemp /etc/sysctl.d/.srv-helper.XXXXXX) || return 1
  if [[ -f "$file" ]]; then
    awk -v key="$key" '
      $0 !~ "^[[:space:]]*" key "[[:space:]]*=" {print}
    ' "$file" > "$tmp"
  fi
  printf '%s = %s\n' "$key" "$value" >> "$tmp"
  chmod 644 "$tmp"
  mv -f -- "$tmp" "$file"
  if sysctl -w "$key=$value"; then success 'System setting save shod';
  else fail 'Apply fail shod; file ra barresi konid'; return 1; fi
}
reset_sysctl() {
  need_root || return 1
  local file='/etc/sysctl.d/90-srv-helper.conf'
  [[ -f "$file" ]] || { warn 'Hich setting SRV Helper mojood nist'; return 1; }
  confirm 'SRV Helper sysctl file pak shavad va default enabled shavad?' || return 1
  rm -f -- "$file"
  # Reset to common defaults. Another distro sysctl file may override them later.
  sysctl -w net.ipv6.conf.all.disable_ipv6=0 || :
  sysctl -w net.ipv4.icmp_echo_ignore_all=0 || :
  success 'Setting ha reset shodand; baraye restore daghigh, distro config ra barresi konid.'
}
network_menu() {
  local choice
  while :; do
    banner; section 'MODIRIAT SHABAKE'
    menu_line 1 'IPv6 disable (persistent)'
    menu_line 2 'IPv6 enable (persistent)'
    menu_line 3 'Ping response block (persistent)'
    menu_line 4 'Ping response allow (persistent)'
    menu_line 5 'Reset SRV Helper sysctl settings'
    menu_line 0 'Bargasht'
    prompt 'Entekhab' choice || return
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
# External installation is always user-confirmed, downloaded first, and run from disk.
external_installer() {
  local tool=$1 url tmp digest
  need_root && need_cmd curl && need_cmd sha256sum || return 1
  case "$tool" in
    3x-ui) url='https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh' ;;
    acme.sh) url='https://raw.githubusercontent.com/acmesh-official/acme.sh/master/acme.sh' ;;
    *) return 1 ;;
  esac
  warn "Script khareji az $url download mishavad. In script mitavanad dastoorate root ejra konad."
  confirm 'Download konam?' || return 1
  tmp=$(mktemp /tmp/srv-helper-installer.XXXXXXXX.sh) || return 1
  chmod 600 "$tmp"
  if ! curl --proto '=https' --tlsv1.2 -fLsS --connect-timeout 10 --max-time 60 -o "$tmp" "$url"; then
    fail 'Download fail shod'; rm -f "$tmp"; return 1
  fi
  digest=$(sha256sum "$tmp" | awk '{print $1}')
  info "SHA256: $digest"
  info "File: $tmp"
  warn 'Hash faghat baraye barresi ast; amniat source ra guarantee nemikonad.'
  confirm 'Script download-shode ra ba root ejra konam?' || { rm -f "$tmp"; return 1; }
  local status=0
  if [[ "$tool" == 'acme.sh' ]]; then sh "$tmp" --install || status=$?
  else bash "$tmp" || status=$?; fi
  rm -f "$tmp"
  ((status == 0)) && success "$tool install tamoom shod" || fail "$tool installation fail shod (code $status)"
  return "$status"
}
system_menu() {
  local choice
  while :; do
    banner; section 'ABZAR SYSTEM | YEKPARCHE'
    menu_line 1 'Vaziat server (CPU/RAM/disk/uptime)'
    menu_line 2 'Barrasi shabake (port/route/DNS)'
    menu_line 3 'Modiriat IPv6 + Ping'
    menu_line 4 'TCP Optimizer (BBR / Hybla / Cubic)'
    menu_line 5 'Nasb 3X-UI (script rasmi)'
    menu_line 6 'Nasb ACME.sh (script rasmi)'
    menu_line 0 'Bargasht'
    prompt 'Entekhab' choice || return
    case "$choice" in
      1) system_overview; pause ;;
      2) network_status; pause ;;
      3) network_menu ;;
      4) bbr_menu ;;
      5) external_installer 3x-ui; pause ;;
      6) external_installer acme.sh; pause ;;
      0) return ;;
      *) warn 'Gozine namotabar'; pause ;;
    esac
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
    banner; section 'TCP OPTIMIZER | BBR / HYBLA'
    current=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo unknown)
    available=$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || echo unknown)
    info "Current: $current | Available: $available"
    menu_line 1 'Enable BBR + fq (recommended when kernel supports it)'
    menu_line 2 'Enable Hybla (if kernel module is available)'
    menu_line 3 'Restore Cubic default'
    menu_line 0 'Back'
    prompt 'Entekhab' choice || return
    case "$choice" in
      1) confirm 'BBR apply shavad?' && tcp_profile_apply bbr ;;
      2) confirm 'Hybla apply shavad?' && tcp_profile_apply hybla ;;
      3) confirm 'Cubic default apply shavad?' && tcp_profile_apply cubic ;;
      0) return ;;
      *) warn 'Gozine namotabar' ;;
    esac
    pause
  done
}

bbr_menu() { tcp_optimizer_menu; }
