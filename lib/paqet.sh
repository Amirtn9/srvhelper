#!/usr/bin/env bash

paqet_launch_upstream() {
  local url='https://raw.githubusercontent.com/behzadea12/Paqet-Tunnel-Manager/main/paqet-manager.sh'
  local tmp digest version status=0
  need_root && need_cmd curl && need_cmd sha256sum || return 1
  warn 'Paqet Manager official script az GitHub download mishavad va ba root ejra mishavad.'
  warn 'Ghabl az ejra source va taghirat an ra review konid; SRV Helper owner-e upstream nist.'
  confirm 'Download va review shoroo shavad?' || return 1
  tmp=$(mktemp /tmp/srv-helper-paqet.XXXXXXXX.sh) || return 1
  chmod 600 "$tmp"
  if ! curl --proto '=https' --tlsv1.2 -fLsS --connect-timeout 10 --max-time 180 -o "$tmp" "$url"; then
    fail 'Download Paqet Manager fail shod'; rm -f "$tmp"; return 1
  fi
  digest=$(sha256sum "$tmp" | awk '{print $1}')
  version=$(grep -m1 -E '^# Version:' "$tmp" | sed 's/^# *//' || true)
  section 'PAQET SOURCE CHECK'
  info "Source: $url"
  info "${version:-Version line peyda nashod}"
  info "SHA256: $digest"
  warn 'SHA256 faghat file download shode ra identify mikonad; signature verify nashode ast.'
  confirm 'Script download-shode ejra shavad?' || { rm -f "$tmp"; return 1; }
  bash "$tmp" || status=$?
  rm -f "$tmp"
  ((status==0)) && success 'Paqet Manager tamoom shod' || fail "Paqet Manager ba code $status kharej shod"
  return "$status"
}

paqet_service_dashboard() {
  local choice selected action
  local -a services=()
  command -v systemctl >/dev/null || { fail 'systemctl mojood nist'; return 1; }
  mapfile -t services < <(systemctl list-unit-files --type=service --no-legend --no-pager 2>/dev/null | awk '$1 ~ /^paqet(-.*)?\.service$/ {print $1}' | sort -u)
  banner; section 'PAQET SERVICE DASHBOARD'
  if ((${#services[@]}==0)); then warn 'Hich Paqet service install nashode ast.'; pause; return; fi
  local i=1 svc status
  for svc in "${services[@]}"; do
    status=$(systemctl is-active "$svc" 2>/dev/null || true)
    printf '  %2d) %-34s %s\n' "$i" "$svc" "${status:-unknown}"
    ((i+=1))
  done
  menu_line 0 'Back'
  prompt 'Service number' choice || return
  [[ "$choice" =~ ^[0-9]+$ ]] && ((choice>=1 && choice<=${#services[@]})) || { warn 'Selection namotabar'; return 1; }
  selected=${services[$((choice-1))]}
  while :; do
    banner; section "PAQET SERVICE | $selected"
    info "Status: $(systemctl is-active "$selected" 2>/dev/null || echo unknown)"
    menu_line 1 'Start service'
    menu_line 2 'Stop service'
    menu_line 3 'Restart service'
    menu_line 4 'Show status'
    menu_line 5 'Show recent logs'
    menu_line 0 'Back'
    prompt 'Action' action || return
    case "$action" in
      1) confirm 'Service start shavad?' && systemctl start "$selected" && success 'Service start shod' ;;
      2) confirm 'Service stop shavad?' && systemctl stop "$selected" && success 'Service stop shod' ;;
      3) confirm 'Service restart shavad?' && systemctl restart "$selected" && success 'Service restart shod' ;;
      4) systemctl status "$selected" --no-pager -l ;;
      5) journalctl -u "$selected" -n 40 --no-pager 2>/dev/null || : ;;
      0) return ;;
      *) warn 'Gozine namotabar' ;;
    esac
    pause
  done
}

paqet_menu() {
  local choice
  while :; do
    banner; section 'PAQET TUNNEL MANAGER | BEHZAD'
    info 'Official manager: behzadea12/Paqet-Tunnel-Manager'
    menu_line 1 'Official Paqet Manager (DNS Finder: menu 7 > 2)'
    menu_line 2 'Manage installed Paqet systemd services'
    menu_line 3 'Show Paqet / DNS / Mirror references'
    menu_line 0 'Back'
    prompt 'Entekhab' choice || return
    case "$choice" in
      1) paqet_launch_upstream; pause ;;
      2) paqet_service_dashboard ;;
      3)
        section 'UPSTREAM REFERENCES'
        printf '  Paqet Manager: https://github.com/behzadea12/Paqet-Tunnel-Manager\n'
        printf '  IranDNSFinder: https://github.com/alinezamifar/IranDNSFinder\n'
        printf '  DetectUbuntuMirror: https://github.com/alinezamifar/DetectUbuntuMirror\n'
        info 'DNS Finder va Mirror Finder e SRV Helper be surat local probe ejra mishavand.'
        pause ;;
      0) return ;;
      *) warn 'Gozine namotabar'; pause ;;
    esac
  done
}
