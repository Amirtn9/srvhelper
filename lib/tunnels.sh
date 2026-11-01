#!/usr/bin/env bash

# Manage tunnel services already installed on the server. No external script is run.
tunnel_service_dashboard() {
  local choice selected action svc status
  local -a services=()
  command -v systemctl >/dev/null || { fail 'systemctl mojood nist'; return 1; }
  mapfile -t services < <(systemctl list-unit-files --type=service --no-legend --no-pager 2>/dev/null | awk '$1 ~ /^(paqet|tunnel)([-@][A-Za-z0-9_.@-]+)?\.service$/ {print $1}' | sort -u)
  banner; section 'SERVICE HAYE TUNNEL'
  if ((${#services[@]}==0)); then
    info 'Hich service tunnel peyda nashod.'
    info 'Service haye install-shode ba systemd dar in bakhsh namayesh dade mishavand.'
    return 0
  fi
  local i=1
  for svc in "${services[@]}"; do
    status=$(systemctl is-active "$svc" 2>/dev/null || true)
    printf '  %2d) %-34s %s\n' "$i" "$svc" "${status:-unknown}"
    ((i+=1))
  done
  menu_line 0 'Bargasht'
  prompt 'Shomare service' choice || return $?
  [[ "$choice" =~ ^[0-9]+$ ]] && ((10#$choice>=1 && 10#$choice<=${#services[@]})) || { warn 'Selection namotabar'; return 1; }
  selected=${services[$((10#$choice-1))]}
  while :; do
    banner; section 'KONTROL SERVICE'
    info "Service: $selected | Vaziat: $(systemctl is-active "$selected" 2>/dev/null || echo unknown)"
    menu_line 1 'Shoroo'
    menu_line 2 'Tavaqof'
    menu_line 3 'Restart service'
    menu_line 4 'Namayesh vaziat'
    menu_line 5 'Log haye akhar'
    menu_line 0 'Bargasht'
    prompt 'Amaliat' action || return $?
    case "$action" in
      1) confirm 'Service start shavad?' && systemctl start "$selected" && success 'Service shoroo shod' ;;
      2) confirm 'Service stop shavad?' && systemctl stop "$selected" && success 'Service motavaqef shod' ;;
      3) confirm 'Service restart shavad?' && systemctl restart "$selected" && success 'Service dobare shoroo shod' ;;
      4) systemctl status "$selected" --no-pager -l ;;
      5) journalctl -u "$selected" -n 35 --no-pager 2>&1 || : ;;
      0) return 0 ;;
      *) warn 'Gozine namotabar' ;;
    esac
    [[ ${SRV_EXIT_REQUESTED:-0} == 1 ]] && return 0
    [[ ${SRV_BACK_REQUESTED:-0} == 1 ]] && return 0
    pause
    [[ ${SRV_BACK_REQUESTED:-0} == 1 ]] && return 0
  done
}

tunnel_menu() {
  local choice rc
  while :; do
    [[ ${SRV_EXIT_REQUESTED:-0} == 1 ]] && return
    banner; section 'MODIRIAT TUNNEL'
    menu_line 1 'Modiriat service haye nasb-shode'
    menu_line 2 'Namayesh vaziat service ha'
    menu_line 0 'Bargasht'
    prompt 'Entekhab' choice; rc=$?
    if ((rc==20)); then SRV_BACK_REQUESTED=0; return; fi
    ((rc==0)) || return "$rc"
    case "$choice" in
      1) tunnel_service_dashboard ;;
      2)
        systemctl list-units --type=service --all --no-pager 2>/dev/null | grep -Ei 'paqet|tunnel' || info 'Tunnel service peyda nashod.'
        pause ;;
      0) return ;;
      *) warn 'Gozine namotabar'; pause ;;
    esac
    [[ ${SRV_EXIT_REQUESTED:-0} == 1 ]] && return
    if [[ ${SRV_BACK_REQUESTED:-0} == 1 ]]; then SRV_BACK_REQUESTED=0; fi
  done
}
