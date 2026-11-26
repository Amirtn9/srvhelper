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
  local width=16 filled=0 color=$OK active='' track='' percent_label=' --' i
  if [[ "$percent" =~ ^([0-9]{1,2}|100)$ ]]; then
    filled=$(((10#$percent * width + 50) / 100))
    printf -v percent_label '%3d%%' "$((10#$percent))"
    if ((10#$percent >= 90)); then color=$BAD
    elif ((10#$percent >= 75)); then color=$WARN
    fi
  fi
  for ((i=0; i<width; i++)); do
    if ((i<filled)); then active+='#'; else track+='-'; fi
  done
  printf '  %s%-5s%s [%s%s%s%s%s] %s%4s%s  %s\n' \
    "$WHITE" "$label" "$RESET" "$color" "$active" "$DIM" "$track" "$RESET" "$color" "$percent_label" "$RESET" "$detail"
}

quick_status() {
  local os host cores cpu ram disk uptime_line
  os=$(os_label); host=$(hostname 2>/dev/null || printf unknown)
  cores=$(getconf _NPROCESSORS_ONLN 2>/dev/null || printf '?')
  if (($#)); then cpu=$1; else cpu=$(cpu_usage) || cpu=''; fi
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
set_sysctl_option() (
  local key=$1 value=$2 file='/etc/sysctl.d/90-srv-helper.conf' tmp previous changed=0
  need_root || return 1
  [[ "$key" == net.ipv6.conf.all.disable_ipv6 || "$key" == net.ipv4.icmp_echo_ignore_all ]] || return 1
  [[ "$value" == 0 || "$value" == 1 ]] || return 1
  confirm "Apply $key=$value?" || return $?
  install -d -m 700 "$(state_dir)" || return 1
  exec 9>"$(state_dir)/sysctl.lock" || return 1
  flock -n 9 || return 1
  previous=$(sysctl -n "$key") || return 1
  tmp=$(mktemp /etc/sysctl.d/.srv-helper.XXXXXX) || return 1
  sysctl_cleanup() {
    local rc=$?
    trap - EXIT
    rm -f -- "$tmp"
    if ((changed)); then sysctl -w "$key=$previous" >/dev/null || fail "Runtime rollback failed: $key"; fi
    exit "$rc"
  }
  trap sysctl_cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  if [[ -f "$file" ]]; then
    awk -F= -v key="$key" '{ field=$1; gsub(/[[:space:]]/, "", field); if (field != key) print }' "$file" > "$tmp" || return 1
  fi
  printf '%s = %s\n' "$key" "$value" >> "$tmp" && chmod 644 "$tmp" || return 1
  if ! sysctl -w "$key=$value"; then
    fail 'Live change failed. Persistent configuration was preserved.'
    return 1
  fi
  changed=1
  if ! mv -fT -- "$tmp" "$file"; then
    fail 'Could not save the setting.'
    return 1
  fi
  changed=0
  success 'Setting applied and saved.'
)

reset_sysctl() (
  need_root || return 1
  local file='/etc/sysctl.d/90-srv-helper.conf' key previous
  local -a keys=() values=()
  [[ -f "$file" ]] || { warn 'No SRV Helper settings to reset.'; return 1; }
  confirm 'Remove managed settings and set their live values to 0?' || return $?
  install -d -m 700 "$(state_dir)" || return 1
  exec 9>"$(state_dir)/sysctl.lock" || return 1
  flock -n 9 || return 1
  for key in net.ipv6.conf.all.disable_ipv6 net.ipv4.icmp_echo_ignore_all; do
    if awk -F= -v key="$key" '{ field=$1; gsub(/[[:space:]]/, "", field); if (field == key) found=1 } END {exit !found}' "$file"; then
      previous=$(sysctl -n "$key") || return 1
      keys+=("$key"); values+=("$previous")
    fi
  done
  local index applied=0
  for index in "${!keys[@]}"; do
    if sysctl -w "${keys[index]}=0"; then applied=$((applied+1)); else break; fi
  done
  if ((applied == ${#keys[@]})) && rm -f -- "$file"; then
    success 'Managed settings reset. Other distro settings can still apply after reboot.'
    return 0
  fi
  for ((index=0; index<applied; index++)); do
    sysctl -w "${keys[index]}=${values[index]}" >/dev/null || fail "Runtime rollback failed: ${keys[index]}"
  done
  fail 'Reset failed. Persistent configuration was preserved.'
  return 1
)

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
      7 'Live server dashboard' \
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
      7) live_dashboard ;;
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

network_counters() {
  local iface=$1
  awk -F: -v iface="$iface" '
    NR > 2 {name=$1; gsub(/[[:space:]]/, "", name)}
    name==iface {
      sub(/^[[:space:]]+/, "", $2)
      split($2, fields, /[[:space:]]+/)
      print fields[1], fields[9]
      exit
    }
  ' /proc/net/dev
}

live_dashboard() {
  local iface key now last rx tx last_rx last_tx delta rc paused=0 index=0
  local in_rate='--' out_rate='--' cpu recent='' levels='._-~=+*#%@' level
  local -a interfaces=()
  mapfile -t interfaces < <(awk -F: 'NR>2 {gsub(/[[:space:]]/, "", $1); if ($1!="lo") print $1}' /proc/net/dev)
  (("${#interfaces[@]}")) || interfaces=(lo)
  while :; do
    iface=${interfaces[index]}
    if ((!paused)); then
      read -r now _ < /proc/uptime
      if read -r rx tx < <(network_counters "$iface") && [[ -n ${last:-} ]]; then
        read -r in_rate out_rate < <(LC_ALL=C awk -v dt="$now" -v start="$last" -v rx="$rx" -v tx="$tx" \
          -v old_rx="$last_rx" -v old_tx="$last_tx" 'BEGIN {
            dt -= start
            if (dt <= 0 || rx < old_rx || tx < old_tx) print "-- --";
            else printf "%.1f %.1f\n", (rx-old_rx)/dt/1024, (tx-old_tx)/dt/1024
          }')
      fi
      last=$now; last_rx=$rx; last_tx=$tx
      banner; section 'LIVE SERVER DASHBOARD'
      cpu=$(cpu_usage) || cpu=''
      quick_status "$cpu"
      if [[ "$cpu" =~ ^([0-9]{1,2}|100)$ ]]; then
        level=$((10#$cpu * 9 / 100))
        recent+=${levels:level:1}
        if ((${#recent} > 32)); then recent=${recent: -32}; fi
      fi
      printf '  CPU history  %s%s%s\n' "$C1" "${recent:---}" "$RESET"
      delta=$(awk '/^SwapTotal:/ {total=$2} /^SwapFree:/ {free=$2} END {if(total>0) printf "%.0f",100*(total-free)/total}' /proc/meminfo)
      resource_meter Swap "$delta" 'Swap in use'
      printf '\n  %s%-12s%s  RX %s KiB/s   TX %s KiB/s\n' "$C1" "$iface" "$RESET" "$in_rate" "$out_rate"
    fi
    [[ -t 0 && -t 1 ]] || return 0
    if ((!paused)); then printf '  [P] Pause  [N] Next interface  [Q] Back\n'; fi
    if IFS= read -rsn1 -t 1 key; then
      :
    else
      rc=$?
      ((rc > 128)) || return 0
      continue
    fi
    case "$key" in
      q|Q|''|$'\r') return 0 ;;
      p|P)
        paused=$((1-paused))
        last=''
        if ((paused)); then printf '  Paused. [P] Resume  [N] Next interface  [Q] Back\n'; fi
        ;;
      n|N)
        index=$(((index+1) % ${#interfaces[@]}))
        last='' in_rate='--' out_rate='--' paused=0
        ;;
    esac
  done
}
