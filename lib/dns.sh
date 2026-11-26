#!/usr/bin/env bash
# DNS profiles + latency based finder. System changes use systemd-resolved only.
dns_profile() {
  case "$1" in
    shecan) printf '%s' '178.22.122.100 185.51.200.2' ;;
    radar) printf '%s' '10.202.10.10 10.202.10.11' ;;
    online403) printf '%s' '10.202.10.202 10.202.10.102' ;;
    electro) printf '%s' '78.157.42.100 78.157.42.101' ;;
    begzar) printf '%s' '185.55.226.26 185.55.225.25' ;;
    shatel) printf '%s' '85.15.1.14 85.15.1.15' ;;
    shelter) printf '%s' '78.157.60.6 78.157.60.242' ;;
    beshkan) printf '%s' '181.41.194.177 181.41.194.186' ;;
    tic) printf '%s' '217.218.155.155 217.218.127.127' ;;
    pishgaman) printf '%s' '5.202.100.100 5.202.100.101' ;;
    asiatech) printf '%s' '194.36.174.161' ;;
    cloudflare) printf '%s' '1.1.1.1 1.0.0.1' ;;
    google) printf '%s' '8.8.8.8 8.8.4.4' ;;
    quad9) printf '%s' '9.9.9.9 149.112.112.112' ;;
    opendns) printf '%s' '208.67.222.222 208.67.220.220' ;;
    adguard) printf '%s' '94.140.14.14 94.140.15.15' ;;
    *) return 1 ;;
  esac
}

dns_candidate_records() {
  local region=${1:-iran}
  if [[ "$region" == iran ]]; then
    # Iranian public/ISP resolvers. Every address is probed before it can be applied.
    printf '%s\n' \
      'Shecan|178.22.122.100' 'Shecan-2|185.51.200.2' \
      'Radar|10.202.10.10' 'Radar-2|10.202.10.11' \
      '403|10.202.10.202' '403-2|10.202.10.102' \
      'Electro|78.157.42.100' 'Electro-2|78.157.42.101' \
      'Begzar|185.55.226.26' 'Begzar-2|185.55.225.25' \
      'Shatel|85.15.1.14' 'Shatel-2|85.15.1.15' \
      'Shelter|78.157.60.6' 'Shelter-2|78.157.60.242' \
      'Beshkan|181.41.194.177' 'Beshkan-2|181.41.194.186' \
      'TIC-IR|217.218.155.155' 'TIC-IR-2|217.218.127.127' \
      'Pishgaman|5.202.100.100' 'Pishgaman-2|5.202.100.101' \
      'Asiatech|194.36.174.161' 'Hostiran-private|172.29.0.100' \
      'Hostiran-private-2|172.29.2.100'
  fi
  # International resolvers are tested in every region as fallback candidates.
  printf '%s\n' \
    'Cloudflare|1.1.1.1' 'Cloudflare-2|1.0.0.1' \
    'Google|8.8.8.8' 'Google-2|8.8.4.4' \
    'Quad9|9.9.9.9' 'Quad9-2|149.112.112.112' \
    'OpenDNS|208.67.222.222' 'OpenDNS-2|208.67.220.220' \
    'AdGuard|94.140.14.14' 'AdGuard-2|94.140.15.15' \
    'ControlD|76.76.2.0' 'Yandex|77.88.8.8'
}

dns_resolv_file() { printf '/etc/resolv.conf'; }
dns_resolved_file() { printf '/etc/systemd/resolved.conf.d/90-srv-helper.conf'; }
dns_stub_file() { printf '/run/systemd/resolve/stub-resolv.conf'; }

dns_status() {
  local resolver
  resolver=$(dns_resolv_file)
  section 'DNS FELI'
  info "resolv.conf: $(readlink "$resolver" || printf '%s' "$resolver")"
  if [[ -r "$resolver" ]]; then
    awk '$1=="nameserver" {print "  nameserver " $2}' "$resolver"
  fi
  if dns_resolved_active; then
    resolvectl status 2>/dev/null | sed -n '1,80p'
  fi
}

dns_resolved_active() {
  command -v resolvectl >/dev/null && systemctl is-active --quiet systemd-resolved
}

dns_expected_servers() {
  python3 -c '
import ipaddress, sys
addresses = lambda text: {ipaddress.ip_address(value) for value in text.split()}
sys.exit(addresses(sys.argv[1]) != addresses(sys.argv[2]))
' "$1" "$2" 2>/dev/null
}

dns_verify_profile() {
  local backend=$1 servers=$2 resolver configured domains
  resolver=$(dns_resolv_file)
  if [[ "$backend" == resolved ]]; then
    [[ "$(readlink -f -- "$resolver")" == "$(dns_stub_file)" ]] || return 1
    configured=$(LC_ALL=C resolvectl dns) || return 1
    configured=$(sed -n 's/^Global:[[:blank:]]*//p' <<< "$configured")
    dns_expected_servers "$configured" "$servers" || return 1
    domains=$(LC_ALL=C resolvectl domain) || return 1
    grep -E '^Global:.*[[:blank:]]~\.([[:blank:]]|$)' <<< "$domains" >/dev/null || return 1
    if grep -E '^Link .*:([[:blank:]]+[^[:blank:]]+)*[[:blank:]]+(~\.|~?example\.com|~?com)([[:blank:]]|$)' <<< "$domains" >/dev/null; then
      fail 'DNS link ya VPN yek route ~. digar darad.'
      return 1
    fi
  else
    configured=$(awk '$1=="nameserver" {print $2}' "$resolver") || return 1
    dns_expected_servers "$configured" "$servers" || return 1
  fi
  timeout 8 dig -r +time=2 +tries=1 +short example.com A |
    grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' >/dev/null &&
    timeout 8 getent ahosts example.com >/dev/null 2>&1
}

dns_publish_file() (
  local target=$1 source=$2 contents=$3 staged
  staged=$(mktemp -d "${target%/*}/.srv-helper-dns.XXXXXXXX") || return 1
  trap 'rm -rf -- "$staged"' EXIT
  case "$source" in
    link) ln -s -- "$contents" "$staged/new" || return 1 ;;
    text) printf '%s\n' "$contents" > "$staged/new" && chmod 644 "$staged/new" || return 1 ;;
    backup) cp -aT -- "$contents" "$staged/new" || return 1 ;;
  esac
  mv -fT -- "$staged/new" "$target"
)

apply_dns() (
  local profile=$1 servers=$2 target resolver snapshot backend committed=0 server stub config
  local -a addresses
  need_root && need_cmd python3 || return 1
  target=$(dns_resolved_file)
  resolver=$(dns_resolv_file)
  stub=$(dns_stub_file)
  read -r -a addresses <<< "$servers"
  [[ -n "$servers" ]] && dns_expected_servers "$servers" "$servers" || { fail 'DNS address namotabar ast.'; return 1; }
  info "Profile DNS: $profile ($servers)"
  ensure_dig || return $?
  for server in "${addresses[@]}"; do
    if ! dig -r +time=2 +tries=1 +short "@$server" example.com A |
       grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' >/dev/null; then
      fail "DNS pasokh nadad: $server"
      return 1
    fi
  done
  if dns_resolved_active; then
    backend=resolved
    if [[ -L "$resolver" && "$(readlink -f -- "$resolver")" != "$stub" &&
          "$(readlink -f -- "$resolver")" != /run/systemd/resolve/resolv.conf ]]; then
      fail 'resolv.conf be manager digari vasl ast. Aval manager DNS ra barrasi konid.'
      return 1
    fi
  elif [[ ! -L "$resolver" && ( ! -e "$resolver" || -f "$resolver" ) ]]; then
    backend=static
  else
    fail 'resolv.conf be manager digari vasl ast va systemd-resolved faal nist.'
    return 1
  fi
  if [[ -f "$resolver" && ! -L "$resolver" ]] &&
     grep -Ei 'generated by (NetworkManager|resolvconf|dhclient)|managed by (NetworkManager|resolvconf)' "$resolver" >/dev/null; then
    fail 'resolv.conf tavasote network manager modiriat mishavad. DNS ra dar haman manager set konid.'
    return 1
  fi
  dns_status
  info "Proposed resolvers: $servers ($backend)"
  confirm 'Apply DNS settings?' || return $?
  if [[ "$backend" == resolved ]]; then install -d -m 755 "${target%/*}" || return 1; fi
  install -d -m 700 "$(backup_dir)/dns" "$(state_dir)" || return 1
  exec 9>"$(state_dir)/dns.lock" || return 1
  flock -n 9 || { fail 'Another DNS change is in progress.'; return 1; }
  snapshot=$(dns_snapshot "$target") || return 1
  dns_apply_cleanup() {
    local rc=$?
    trap - EXIT
    if ((!committed)); then
      fail 'DNS validate nashod. Dar hale bazgardani.'
      restore_dns_unchecked "$snapshot" || fail "DNS rollback incomplete: $snapshot"
    fi
    exit "$rc"
  }
  trap dns_apply_cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  if [[ "$backend" == resolved ]]; then
    printf -v config '# Managed by SRV Helper.\n[Resolve]\nDNS=\nDNS=%s\nFallbackDNS=\nDomains=\nDomains=~.\nDNSStubListener=yes' "$servers"
    dns_publish_file "$target" text "$config" && systemctl restart systemd-resolved &&
      [[ -r "$stub" ]] && dns_publish_file "$resolver" link "$stub" || return 1
  else
    config=''
    if [[ -r "$resolver" ]]; then config=$(awk '$1=="search" || $1=="domain" || $1=="options"' "$resolver"); fi
    for server in "${addresses[@]}"; do config+=$'\n'"nameserver $server"; done
    dns_publish_file "$resolver" text "$config" || return 1
  fi
  dns_verify_profile "$backend" "$servers" || return 1
  committed=1
  success "DNS profile applied: $profile ($servers)"
  info "Backup: $snapshot"
  if [[ "$backend" == resolved ]]; then info '127.0.0.53 dar resolv.conf normal ast; upstream DNS dar resolvectl namayesh dade mishavad.'; fi
  dns_status
)

dns_snapshot() {
  local target=$1 backup resolver
  resolver=$(dns_resolv_file)
  backup=$(mktemp -d "$(backup_dir)/dns/change-$(date -u +%Y%m%dT%H%M%SZ).XXXXXXXX") || return 1
  if [[ -e "$target" || -L "$target" ]]; then
    cp -aT -- "$target" "$backup/previous.conf" || return 1
    printf 'existing\n' > "$backup/previous.type" || return 1
  else
    printf 'none\n' > "$backup/previous.type" || return 1
  fi
  if [[ -e "$resolver" || -L "$resolver" ]]; then
    cp -aT -- "$resolver" "$backup/resolver.conf" || return 1
    printf 'existing\n' > "$backup/resolver.type" || return 1
  else
    printf 'none\n' > "$backup/resolver.type" || return 1
  fi
  printf '%s\n' "$backup"
}

restore_dns_unchecked() {
  local backup=$1 target resolver typ
  target=$(dns_resolved_file)
  resolver=$(dns_resolv_file)
  [[ -f "$backup/previous.type" ]] || return 1
  IFS= read -r typ < "$backup/previous.type"
  case "$typ" in
    existing) dns_publish_file "$target" backup "$backup/previous.conf" || return 1 ;;
    none) rm -f -- "$target" || return 1 ;;
    *) return 1 ;;
  esac
  if [[ -f "$backup/resolver.type" ]]; then
    IFS= read -r typ < "$backup/resolver.type"
    case "$typ" in
      existing) dns_publish_file "$resolver" backup "$backup/resolver.conf" || return 1 ;;
      none) rm -f -- "$resolver" || return 1 ;;
      *) return 1 ;;
    esac
  fi
  if dns_resolved_active; then systemctl restart systemd-resolved || return 1; fi
  timeout 8 getent ahosts example.com >/dev/null 2>&1
}

restore_dns() (
  need_root || return 1
  local root="$(backup_dir)/dns" snapshot backup choice index=0 current
  local -a options=() snapshots=()
  [[ -d "$root" ]] || { fail 'No DNS backup found.'; return 1; }
  install -d -m 700 "$(state_dir)" || return 1
  exec 9>"$(state_dir)/dns.lock" || return 1
  flock -n 9 || { fail 'Another DNS change is in progress.'; return 1; }
  while IFS= read -r backup; do
    [[ -f "$backup/previous.type" ]] || continue
    index=$((index+1))
    snapshots+=("$backup")
    options+=("$index" "${backup##*/}")
    ((index < 10)) || break
  done < <(find "$root" -maxdepth 1 -type d -name 'change-*' | LC_ALL=C sort -r)
  if [[ -f "$root/previous.type" ]]; then
    index=$((index+1))
    snapshots+=("$root")
    options+=("$index" 'Legacy DNS backup')
  fi
  ((index)) || { fail 'No DNS backup found.'; return 1; }
  choose_menu choice 'RESTORE DNS PROFILE' '' "${options[@]}" 0 'Cancel' || return
  [[ "$choice" =~ ^[1-9][0-9]?$ ]] && ((choice <= index)) || return 1
  snapshot=${snapshots[choice-1]}
  confirm "Restore ${snapshot##*/}?" || return 1
  current=$(dns_snapshot "$(dns_resolved_file)") || return 1
  if restore_dns_unchecked "$snapshot"; then
    success 'DNS profile restored.'
    dns_status
  else
    fail 'DNS restore failed validation.'
    restore_dns_unchecked "$current" || fail "DNS rollback incomplete: $current"
    return 1
  fi
)

ensure_dig() {
  command -v dig >/dev/null 2>&1 && return 0
  warn 'Baraye DNS Finder be dig niaz darim.'
  confirm 'dnsutils nasb shavad?' || return 1
  need_root || return 1
  need_cmd apt-get || return 1
  DEBIAN_FRONTEND=noninteractive apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y dnsutils
}

rank_dns_servers() {
  local region=${1:-iran} rec name ip idx=0 tmp start end elapsed out domain ok total avg
  command -v dig >/dev/null 2>&1 || return 1
  tmp=$(mktemp -d /tmp/srv-helper-dns.XXXXXXXX) || return 1
  local -a records=()
  mapfile -t records < <(dns_candidate_records "$region")
  info "DNS Finder: ${#records[@]} resolver dar 8 worker test mishavad..." >&2
  for rec in "${records[@]}"; do
    name=${rec%%|*}; ip=${rec##*|}
    (
      ok=0; total=0
      for domain in example.com github.com cloudflare.com; do
        start=$(date +%s%N 2>/dev/null || echo 0)
        out=$(dig -r +short +time=1 +tries=1 "@$ip" "$domain" A 2>/dev/null) || continue
        end=$(date +%s%N 2>/dev/null || echo 0)
        if grep -Eq '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' <<< "$out"; then
          ((ok+=1))
          if [[ "$start" =~ ^[0-9]+$ && "$end" =~ ^[0-9]+$ ]] && ((end>=start)); then
            elapsed=$(((end-start)/1000000)); total=$((total+elapsed))
          fi
        fi
      done
      if ((ok==3)); then
        avg=$((total/ok))
        printf '%s|%s|%s|%s\n' "$ok" "$avg" "$name" "$ip" > "$tmp/$idx.ok"
      else printf '%s|%s\n' "$name" "$ip" > "$tmp/$idx.fail"; fi
    ) &
    ((idx+=1))
    if ((idx%8==0)); then wait || :; fi
  done
  wait || :
  local -a results=()
  for ((idx=0;idx<${#records[@]};idx++)); do
    [[ -f "$tmp/$idx.ok" ]] && { IFS= read -r rec < "$tmp/$idx.ok"; results+=("$rec"); }
  done
  rm -rf -- "$tmp"
  if ((${#results[@]}==0)); then fail 'Hich DNS javabgo peyda nashod'; return 1; fi
  printf '%s\n' "${results[@]}" | LC_ALL=C sort -t '|' -k1,1nr -k2,2n
}

dns_finder_menu() {
  local region choice rec successes latency name ip rc
  banner; section 'DNS FINDER | TEST SORAT PASOKH'
  menu_line 1 'DNS Iran + ISP + TIC + Jahani'
  menu_line 2 'DNS Jahani'
  menu_line 0 'Bargasht'
  prompt 'Mantaghe' choice; rc=$?
  ((rc==0)) || return "$rc"
  case "$choice" in 1) region=iran ;; 2) region=global ;; 0) return 0 ;; *) warn 'Gozine namotabar'; return 1 ;; esac
  ensure_dig || return 1
  local -a ranked=()
  mapfile -t ranked < <(rank_dns_servers "$region")
  if ((${#ranked[@]}==0)); then warn 'DNS pasokhgo peyda nashod'; return 1; fi
  section 'NATAYEJ | PASOKH + ZAMAN'
  local i=0
  for rec in "${ranked[@]}"; do
    IFS='|' read -r successes latency name ip <<< "$rec"
    printf '  %2d) %-18s %-16s %s/3 | %s ms\n' "$((++i))" "$name" "$ip" "$successes" "$latency"
    ((i>=8)) && break
  done
  local first second servers
  IFS='|' read -r _ _ _ first <<< "${ranked[0]}"
  second=$first
  if ((${#ranked[@]}>1)); then IFS='|' read -r _ _ _ second <<< "${ranked[1]}"; fi
  servers="$first"
  [[ "$second" != "$first" ]] && servers+=" $second"
  info "DNS pishnahadi: $servers"
  confirm 'In DNS ha set shavand?' || return $?
  apply_dns 'DNS Finder' "$servers"
}

dns_profile_group_menu() {
  local group=$1 choice profile servers rc
  while :; do
    if [[ "$group" == iran ]]; then
      choose_menu choice 'DNS IRAN' '' \
        1 'Shecan' 2 'Radar' 3 '403' 4 'Electro' 5 'Begzar' \
        6 'Shatel' 7 'Shelter' 8 'Beshkan' 9 'TIC / Mokhaberat' \
        10 'Pishgaman' 11 'Asiatech' 0 'Bargasht'
      rc=$?
    else
      choose_menu choice 'DNS JAHANI' '' \
        1 'Cloudflare' 2 'Google' 3 'Quad9' 4 'OpenDNS' 5 'AdGuard' 0 'Bargasht'
      rc=$?
    fi
    if ((rc==20)); then SRV_BACK_REQUESTED=0; return 0; fi
    ((rc==0)) || return "$rc"
    if [[ "$choice" == 0 ]]; then return 0; fi
    if [[ "$group" == iran ]]; then
      case "$choice" in
        1) profile=shecan ;; 2) profile=radar ;; 3) profile=online403 ;;
        4) profile=electro ;; 5) profile=begzar ;; 6) profile=shatel ;;
        7) profile=shelter ;; 8) profile=beshkan ;; 9) profile=tic ;;
        10) profile=pishgaman ;; 11) profile=asiatech ;; *) warn 'Gozine namotabar'; continue ;;
      esac
    else
      case "$choice" in
        1) profile=cloudflare ;; 2) profile=google ;; 3) profile=quad9 ;;
        4) profile=opendns ;; 5) profile=adguard ;; *) warn 'Gozine namotabar'; continue ;;
      esac
    fi
    servers=$(dns_profile "$profile") || { fail 'DNS profile peyda nashod'; continue; }
    if [[ "$profile" == radar || "$profile" == online403 ]]; then
      warn 'In DNS ha momken ast faghat dar network haye Iran reachable bashand.'
    fi
    apply_dns "$profile" "$servers"
    if [[ ${SRV_BACK_REQUESTED:-0} == 1 ]]; then SRV_BACK_REQUESTED=0; return 0; fi
    [[ ${SRV_EXIT_REQUESTED:-0} == 1 ]] && return 0
    pause
    if [[ ${SRV_BACK_REQUESTED:-0} == 1 ]]; then SRV_BACK_REQUESTED=0; return 0; fi
  done
}

dns_menu() {
  local choice rc
  while :; do
    [[ ${SRV_EXIT_REQUESTED:-0} == 1 ]] && return
    choose_menu choice 'MODIRIAT DNS' '' \
      1 'DNS haye Iran' \
      2 'DNS haye Jahani' \
      3 'Peyda kardan behtarin DNS' \
      4 'Vaziat DNS feli' \
      5 'Bazgasht DNS ghabli' \
      0 'Bargasht'; rc=$?
    if ((rc==20)); then SRV_BACK_REQUESTED=0; return; fi
    ((rc==0)) || return "$rc"
    case "$choice" in
      1) dns_profile_group_menu iran ;;
      2) dns_profile_group_menu global ;;
      3) dns_finder_menu; pause ;;
      4) dns_status; pause ;;
      5) restore_dns; pause ;;
      0) return ;;
      *) warn 'Gozine namotabar'; pause ;;
    esac
    [[ ${SRV_EXIT_REQUESTED:-0} == 1 ]] && return
    if [[ ${SRV_BACK_REQUESTED:-0} == 1 ]]; then SRV_BACK_REQUESTED=0; fi
  done
}
