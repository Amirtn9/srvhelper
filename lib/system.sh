#!/usr/bin/env bash
os_label() {
  if [[ -f /etc/os-release ]]; then (. /etc/os-release; printf '%s %s' "${ID:-Linux}" "${VERSION_ID:-}")
  else uname -s; fi
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
    menu_line 4 'Vaziat / faalsazi BBR'
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
bbr_menu() {
  local current available file='/etc/sysctl.d/91-srv-helper-bbr.conf'
  section 'BEHINE SAZI BBR'
  current=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo unknown)
  available=$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || echo '')
  info "Current: $current | Available: $available"
  if [[ "$current" == bbr ]]; then success 'BBR active ast'; pause; return; fi
  if [[ " $available " != *' bbr '* ]]; then warn 'BBR dar kernel active/available nist'; pause; return; fi
  need_root || { pause; return; }
  confirm 'BBR + fq queuing ba sysctl faal shavad?' || return
  printf '%s\n' 'net.core.default_qdisc = fq' 'net.ipv4.tcp_congestion_control = bbr' > "$file"
  chmod 644 "$file"
  sysctl -p "$file" && success 'BBR enable shod' || fail 'BBR apply fail shod'
  pause
}
