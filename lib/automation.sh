#!/usr/bin/env bash

server_country_code() {
  local code=''
  if command -v curl >/dev/null 2>&1; then
    code=$(curl -4fsS --connect-timeout 3 --max-time 6 https://ipinfo.io/country 2>/dev/null | tr -d '[:space:]' | head -c 2 || true)
  fi
  [[ "$code" =~ ^[A-Z]{2}$ ]] || return 1
  printf '%s' "$code"
}

region_from_country() {
  case "${1^^}" in
    IR) printf iran ;;
    US) printf usa ;;
    AL|AD|AT|BE|BA|BG|BY|CH|CY|CZ|DE|DK|EE|ES|FI|FR|GB|GR|HR|HU|IE|IS|IT|LI|LT|LU|LV|MC|MD|ME|MK|MT|NL|NO|PL|PT|RO|RS|SE|SI|SK|TR|UA|XK) printf europe ;;
    *) return 1 ;;
  esac
}

choose_auto_region() {
  local _dest=$1 code detected choice
  local -n _target="$_dest"
  code=$(server_country_code || true)
  detected=$(region_from_country "$code" 2>/dev/null || true)
  if [[ -n "$detected" ]]; then
    info "Keshvar server: $code | Mantaghe pishnahadi: ${detected^^}"
  else
    warn 'Mantaghe server az IP tashkhis dade nashod.'
  fi
  section 'ENTEKHAB MANTAGHE'
  [[ -n "$detected" ]] && menu_line 1 "Estefade az mantaghe tashkhis-dade-shode: ${detected^^}"
  menu_line 2 'Iran'
  menu_line 3 'Europe'
  menu_line 4 'USA'
  prompt 'Mantaghe' choice || return 1
  case "$choice" in
    1) [[ -n "$detected" ]] || { warn 'Mantaghe tashkhis dade nashod'; return 1; }; _target=$detected ;;
    2) _target=iran ;;
    3) _target=europe ;;
    4) _target=usa ;;
    *) warn 'Gozine namotabar'; return 1 ;;
  esac
}

smart_auto_optimize() {
  local region os_id family code dns_first dns_second dns_servers='' mirror='' update_state='ANJAM NASHOD' dns_state='ANJAM NASHOD' bbr_state='ANJAM NASHOD'
  local -a dns_ranked=() mirror_ranked=()
  need_root || return 1
  banner; section 'TANZIM HOSHMAND SHABAKE'
  info 'DNS, Mirror, package update va BBR be tartib check mishavand.'
  info 'Package ha install/upgrade nemishavand; faghat list package ha update mishavad.'
  choose_auto_region region || { pause; return 1; }
  [[ ${SRV_BACK_REQUESTED:-0} == 1 || ${SRV_EXIT_REQUESTED:-0} == 1 ]] && return 1
  section 'MARHALE HOSHMAND'
  info "Mantaghe: ${region^^}"
  info '1) DNS: test zaman pasokh va record A'
  info '2) Mirror: test Release va sorat pasokh'
  info '3) Update list package haye APT'
  info '4) BBR: faal sazi faghat ba poshtibani kernel'
  warn 'DNS va APT source taghir mikonand; backup va rollback dar nazar gerefte shode ast.'
  confirm 'Tanzim hoshmand shoroo shavad?' || return 1

  section 'MARHALE 1/4 | DNS FINDER'
  if mapfile -t dns_ranked < <(rank_dns_servers "$region") && ((${#dns_ranked[@]}>0)); then
    IFS='|' read -r _ _ _ dns_first <<< "${dns_ranked[0]}"
    dns_second=$dns_first
    if ((${#dns_ranked[@]}>1)); then IFS='|' read -r _ _ _ dns_second <<< "${dns_ranked[1]}"; fi
    dns_servers="$dns_first"
    [[ "$dns_second" != "$dns_first" ]] && dns_servers+=" $dns_second"
    info "DNS haye entekhab-shode: $dns_servers"
    SRV_AUTO_MODE=1 apply_dns "Smart-${region^^}" "$dns_servers" && dns_state='SET SHOD' || dns_state='NAMOVAFAGH / RAD SHOD'
  else
    warn 'DNS pasokhgo peyda nashod.'
    dns_state='DNS JAVABGO PEYDA NASHOD'
  fi

  section 'MARHALE 2/4 | MIRROR FINDER'
  os_id=$(. /etc/os-release 2>/dev/null; printf '%s' "${ID:-unknown}")
  code=$(. /etc/os-release 2>/dev/null; printf '%s' "${VERSION_CODENAME:-}")
  case "$os_id" in ubuntu) family=ubuntu ;; debian) family=debian ;; *) family='' ;; esac
  if [[ -n "$family" && -n "$code" ]] && mapfile -t mirror_ranked < <(rank_mirrors "$region" "$code" "$family") && ((${#mirror_ranked[@]}>0)); then
    mirror=${mirror_ranked[0]}
    info "Mirror ba behtarin pasokh: $mirror"
    if apply_mirror "$mirror"; then update_state='UPDATE BA MIRROR ENTEKHAB-SHODE MOVAFAGH'; else update_state='MIRROR FAIL SHOD / ROLLBACK ANJAM SHOD'; fi
  else
    warn 'Mirror motabar baraye in OS ya mantaghe peyda nashod.'
    mirror='Taghir nakard'
  fi

  section 'MARHALE 3/4 | APT UPDATE'
  if [[ "$update_state" != 'UPDATE BA MIRROR ENTEKHAB-SHODE MOVAFAGH' ]]; then
    if DEBIAN_FRONTEND=noninteractive apt-get update; then update_state='APT UPDATE MOVAFAGH';
    else update_state='APT UPDATE NAMOVAFAGH'; fi
  fi
  info 'Update list package ha tamam shod; package ha upgrade nashodand.'

  section 'MARHALE 4/4 | BBR'
  if [[ " $(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || echo '') " == *' bbr '* ]]; then
    if bbr_enable_auto; then bbr_state='FAAL'; else bbr_state='NAMOVAFAGH'; fi
  else
    warn 'Kernel feli BBR ra support nemikonad; kernel taghir nakard.'
    bbr_state='DAR KERNEL MOJOOD NIST'
  fi

  banner; section 'GOZARESH NAHAEI'
  printf '  %-16s : %s\n' 'Mantaghe' "${region^^}"
  printf '  %-16s : %s\n' 'DNS' "$dns_state"
  printf '  %-16s : %s\n' 'DNS ha' "${dns_servers:-Entekhab nashod}"
  printf '  %-16s : %s\n' 'Mirror APT' "${mirror:-Taghir nakard}"
  printf '  %-16s : %s\n' 'Update APT' "$update_state"
  printf '  %-16s : %s\n' 'BBR' "$bbr_state"
  success 'Gozareh tanzim hoshmand tamam shod.'
  info 'Vaziat DNS: resolvectl status | Baraye bargasht Mirror az menu Mirror estefade konid.'
  pause
}
