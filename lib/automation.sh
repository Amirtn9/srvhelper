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
    info "Server country: $code | Suggested region: ${detected^^}"
  else
    warn 'Server region az IP API detect nashod.'
  fi
  section 'ENTEKHAB REGION'
  [[ -n "$detected" ]] && menu_line 1 "Use detected region: ${detected^^}"
  menu_line 2 'Iran'
  menu_line 3 'Europe'
  menu_line 4 'USA'
  prompt 'Region' choice || return 1
  case "$choice" in
    1) [[ -n "$detected" ]] || { warn 'Region detect nashod'; return 1; }; _target=$detected ;;
    2) _target=iran ;;
    3) _target=europe ;;
    4) _target=usa ;;
    *) warn 'Gozine namotabar'; return 1 ;;
  esac
}

smart_auto_optimize() {
  local region os_id family code dns_first dns_second dns_servers='' mirror='' update_state='SKIP' dns_state='SKIP' bbr_state='SKIP'
  local -a dns_ranked=() mirror_ranked=()
  need_root || return 1
  banner; section 'SMART AUTO OPTIMIZER | NETWORK + SYSTEM'
  info 'In process DNS, Mirror, APT update va BBR ra be tartib check mikonad.'
  info 'Hich package upgrade ejra nemishavad; faghat apt-get update anjam mishavad.'
  choose_auto_region region || { pause; return 1; }
  section 'PLAN'
  info "Region: ${region^^}"
  info '1) DNS Finder: latency + successful A record checks'
  info '2) Mirror Finder: valid Release + response time'
  info '3) APT package index update'
  info '4) BBR: enable only if current kernel supports it'
  warn 'DNS va APT source taghir mikonand; backup va rollback dar nazar gerefte shode ast.'
  confirm 'Smart optimization shoroo shavad?' || return 1

  section 'PHASE 1/4 | DNS FINDER'
  if mapfile -t dns_ranked < <(rank_dns_servers "$region") && ((${#dns_ranked[@]}>0)); then
    IFS='|' read -r _ _ _ dns_first <<< "${dns_ranked[0]}"
    dns_second=$dns_first
    if ((${#dns_ranked[@]}>1)); then IFS='|' read -r _ _ _ dns_second <<< "${dns_ranked[1]}"; fi
    dns_servers="$dns_first"
    [[ "$dns_second" != "$dns_first" ]] && dns_servers+=" $dns_second"
    info "Best DNS pair: $dns_servers"
    SRV_AUTO_MODE=1 apply_dns "Smart-${region^^}" "$dns_servers" && dns_state='APPLIED' || dns_state='FAILED/SKIPPED'
  else
    warn 'DNS Finder natije motabar nadad.'
    dns_state='NO WORKING DNS FOUND'
  fi

  section 'PHASE 2/4 | MIRROR FINDER'
  os_id=$(. /etc/os-release 2>/dev/null; printf '%s' "${ID:-unknown}")
  code=$(. /etc/os-release 2>/dev/null; printf '%s' "${VERSION_CODENAME:-}")
  case "$os_id" in ubuntu) family=ubuntu ;; debian) family=debian ;; *) family='' ;; esac
  if [[ -n "$family" && -n "$code" ]] && mapfile -t mirror_ranked < <(rank_mirrors "$region" "$code" "$family") && ((${#mirror_ranked[@]}>0)); then
    mirror=${mirror_ranked[0]}
    info "Fastest verified mirror: $mirror"
    if apply_mirror "$mirror"; then update_state='UPDATED VIA SELECTED MIRROR'; else update_state='MIRROR APPLY FAILED / ROLLED BACK'; fi
  else
    warn 'Mirror finder dar in OS ya region natije nadad.'
    mirror='Not changed'
  fi

  section 'PHASE 3/4 | APT UPDATE'
  if [[ "$update_state" != 'UPDATED VIA SELECTED MIRROR' ]]; then
    if DEBIAN_FRONTEND=noninteractive apt-get update; then update_state='APT UPDATE OK (CURRENT SOURCES)';
    else update_state='APT UPDATE FAILED'; fi
  fi
  info 'apt-get update tamam shod (package upgrade ejra nashod).'

  section 'PHASE 4/4 | BBR'
  if [[ " $(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || echo '') " == *' bbr '* ]]; then
    if bbr_enable_auto; then bbr_state='ACTIVE'; else bbr_state='FAILED'; fi
  else
    warn 'Kernel feli BBR ra support nemikonad; kernel taghir nakard.'
    bbr_state='UNAVAILABLE IN KERNEL'
  fi

  banner; section 'SMART OPTIMIZATION REPORT'
  printf '  %-16s : %s\n' 'Region' "${region^^}"
  printf '  %-16s : %s\n' 'DNS' "$dns_state"
  printf '  %-16s : %s\n' 'DNS servers' "${dns_servers:-Not selected}"
  printf '  %-16s : %s\n' 'APT mirror' "${mirror:-Not changed}"
  printf '  %-16s : %s\n' 'APT update' "$update_state"
  printf '  %-16s : %s\n' 'BBR' "$bbr_state"
  success 'Smart optimization report tamam shod.'
  info 'Baraye DNS status: resolvectl status | Baraye APT restore az Mirror Manager estefade konid.'
  pause
}
