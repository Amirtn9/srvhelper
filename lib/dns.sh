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

dns_status() {
  section 'DNS FELI'
  if command -v resolvectl >/dev/null; then resolvectl status 2>/dev/null | sed -n '1,80p'
  else cat /etc/resolv.conf 2>/dev/null || :; fi
}

apply_dns() {
  local profile=$1 servers=$2 target='/etc/systemd/resolved.conf.d/90-srv-helper.conf'
  need_root || return 1
  if ! command -v systemctl >/dev/null || ! systemctl is-active --quiet systemd-resolved; then
    fail 'systemd-resolved faal nist. Baraye jologiri az DNS outage hich taghiri anjam nashod.'
    return 1
  fi
  command -v resolvectl >/dev/null || { fail 'resolvectl peyda nashod'; return 1; }
  local dns_re='^[0-9a-fA-F:. ]+$'
  [[ "$servers" =~ $dns_re ]] || { fail 'DNS address ha namotabar hastand'; return 1; }
  info "Profile DNS: $profile ($servers)"
  if command -v dig >/dev/null 2>&1; then
    local primary=${servers%% *}
    info "Test dastresi DNS: $primary"
    if ! dig +time=2 +tries=1 +short "@$primary" example.com A 2>/dev/null | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
      warn 'DNS probe javab nadad. In DNS momken ast az network shoma ghabele dastres nabashad.'
      if [[ ${SRV_AUTO_MODE:-0} == 1 ]]; then return 1; fi
      confirm 'Ba vojood DNS probe fail edame midahid?' || return 1
    fi
  else warn 'dig nasb nist; DNS probe external anjam nashod.'; fi
  warn 'Taghir DNS momken ast session SSH / network ra mokhtal konad.'
  if [[ ${SRV_AUTO_MODE:-0} != 1 ]]; then confirm 'DNS system taghir konad?' || return 1; fi
  install -d -m 755 /etc/systemd/resolved.conf.d
  install -d -m 700 "$(backup_dir)/dns"
  if [[ -f "$target" ]]; then
    cp -a "$target" "$(backup_dir)/dns/previous.conf"
    printf 'existing\n' > "$(backup_dir)/dns/previous.type"
  else
    printf 'none\n' > "$(backup_dir)/dns/previous.type"
    rm -f "$(backup_dir)/dns/previous.conf"
  fi
  cat > "$target" <<EOF2
# Managed by SRV Helper. Remove/restore from menu to return to previous resolver.
[Resolve]
DNS=$servers
FallbackDNS=
Domains=~.
EOF2
  if systemctl restart systemd-resolved && resolvectl status >/dev/null 2>&1; then
    success 'DNS set shod. Baraye check: resolvectl status'
    warn 'Link-specific DHCP DNS momken ast priority motefavet dashte bashad.'
  else
    fail 'DNS restart fail shod; dar hale rollback'
    restore_dns_unchecked
    return 1
  fi
}

restore_dns_unchecked() {
  local backup="$(backup_dir)/dns" target='/etc/systemd/resolved.conf.d/90-srv-helper.conf' typ
  [[ -f "$backup/previous.type" ]] || return 1
  IFS= read -r typ < "$backup/previous.type"
  if [[ "$typ" == existing && -f "$backup/previous.conf" ]]; then cp -a "$backup/previous.conf" "$target"
  else rm -f "$target"; fi
  systemctl restart systemd-resolved
}
restore_dns() {
  need_root || return 1
  [[ -f "$(backup_dir)/dns/previous.type" ]] || { fail 'DNS backup peyda nashod'; return 1; }
  confirm 'DNS ghabli restore shavad?' || return 1
  if restore_dns_unchecked; then success 'DNS restore shod'; else fail 'DNS restore fail shod'; fi
}

ensure_dig() {
  command -v dig >/dev/null 2>&1 && return 0
  warn 'Baraye DNS Finder be dig niaz darim.'
  confirm 'dnsutils nasb shavad?' || return 1
  need_root || return 1
  need_cmd apt-get || return 1
  DEBIAN_FRONTEND=noninteractive apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y dnsutils
}

rank_dns_servers() {
  local region=${1:-iran} rec name ip idx=0 tmp start end elapsed out domain ok total
  ensure_dig >&2 || return 1
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
        out=$(dig +short +time=1 +tries=1 "@$ip" "$domain" A 2>/dev/null || true)
        end=$(date +%s%N 2>/dev/null || echo 0)
        if grep -Eq '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' <<< "$out"; then
          ((ok+=1))
          if [[ "$start" =~ ^[0-9]+$ && "$end" =~ ^[0-9]+$ ]] && ((end>=start)); then
            elapsed=$(((end-start)/1000000)); ((total+=elapsed))
          fi
        fi
      done
      if ((ok>0)); then
        ((ok>0)) && avg=$((total/ok)) || avg=9999
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
    banner
    if [[ "$group" == iran ]]; then
      section 'DNS IRAN'
      menu_line 1 'Shecan'
      menu_line 2 'Radar'
      menu_line 3 '403'
      menu_line 4 'Electro'
      menu_line 5 'Begzar'
      menu_line 6 'Shatel'
      menu_line 7 'Shelter'
      menu_line 8 'Beshkan'
      menu_line 9 'TIC / Mokhaberat'
      menu_line 10 'Pishgaman'
      menu_line 11 'Asiatech'
    else
      section 'DNS JAHANI'
      menu_line 1 'Cloudflare'
      menu_line 2 'Google'
      menu_line 3 'Quad9'
      menu_line 4 'OpenDNS'
      menu_line 5 'AdGuard'
    fi
    menu_line 0 'Bargasht'
    prompt 'Entekhab' choice; rc=$?
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
    banner; section 'MODIRIAT DNS'
    menu_line 1 'DNS haye Iran'
    menu_line 2 'DNS haye Jahani'
    menu_line 3 'Peyda kardan behtarin DNS'
    menu_line 4 'Vaziat DNS feli'
    menu_line 5 'Bazgasht DNS ghabli'
    menu_line 0 'Bargasht'
    prompt 'Entekhab' choice; rc=$?
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
