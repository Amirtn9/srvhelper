#!/usr/bin/env bash
# Only persistent systemd-resolved changes. No direct resolv.conf overwrite.
dns_profile() {
  case "$1" in
    shecan) printf '%s' '178.22.122.100 185.51.200.2' ;;
    radar) printf '%s' '10.202.10.10 10.202.10.11' ;;
    online403) printf '%s' '10.202.10.202 10.202.10.102' ;;
    electro) printf '%s' '78.157.42.100 78.157.42.101' ;;
    begzar) printf '%s' '185.55.226.26 185.55.225.25' ;;
    cloudflare) printf '%s' '1.1.1.1 1.0.0.1' ;;
    google) printf '%s' '8.8.8.8 8.8.4.4' ;;
    quad9) printf '%s' '9.9.9.9 149.112.112.112' ;;
    *) return 1 ;;
  esac
}
dns_status() {
  section 'DNS FELI'
  if command -v resolvectl >/dev/null; then resolvectl status 2>/dev/null | sed -n '1,65p';
  else cat /etc/resolv.conf 2>/dev/null || :; fi
}
apply_dns() {
  local profile=$1 servers=$2 target='/etc/systemd/resolved.conf.d/90-srv-helper.conf' prev=''
  need_root || return 1
  if ! command -v systemctl >/dev/null || ! systemctl is-active --quiet systemd-resolved; then
    fail 'systemd-resolved active nist. Baraye jologiri az DNS outage hich taghiri anjam nashod.'
    return 1
  fi
  # /etc/resolv.conf may point to a separate resolver. Explain this explicitly.
  if ! command -v resolvectl >/dev/null; then fail 'resolvectl peyda nashod'; return 1; fi
  info "DNS profile: $profile ($servers)"
  if command -v dig >/dev/null 2>&1; then
    local primary=${servers%% *}
    info "DNS reachability test: $primary"
    if ! dig +time=2 +tries=1 +short @"$primary" example.com A 2>/dev/null | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
      warn 'DNS probe javab nadad. In DNS momken ast az network shoma ghabele dastres nabashad.'
      confirm 'Ba vojood DNS probe fail edame midahid?' || return 1
    fi
  else
    warn 'dig nasb nist; DNS probe external anjam nashod.'
  fi
  warn 'Taghir DNS momken ast session SSH / network ra mokhtal konad.'
  confirm 'DNS system taghir konad?' || return 1
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
# Managed by SRV Helper. Remove this file to restore external resolver defaults.
[Resolve]
DNS=$servers
FallbackDNS=
Domains=~.
EOF2
  if systemctl restart systemd-resolved && resolvectl status >/dev/null 2>&1; then
    success 'DNS set shod. Baraye check: resolvectl status'
    warn 'DNS link-specific DHCP momken ast priority motefavet dashte bashad.'
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
dns_menu() {
  local ch profile servers
  banner; section 'MODIRIAT DNS'
  menu_line 1 'Iran - Shecan'
  menu_line 2 'Iran - Radar'
  menu_line 3 'Iran - 403'
  menu_line 4 'Iran - Electro'
  menu_line 5 'Iran - Begzar'
  menu_line 6 'Global - Cloudflare'
  menu_line 7 'Global - Google'
  menu_line 8 'Global - Quad9'
  menu_line 9 'Vaziat DNS feli'
  menu_line 10 'Bargardandan DNS ghabli'
  menu_line 0 'Bargasht'
  prompt 'Entekhab' ch || return
  case "$ch" in
    1) profile=shecan ;; 2) profile=radar ;; 3) profile=online403 ;;
    4) profile=electro ;; 5) profile=begzar ;; 6) profile=cloudflare ;;
    7) profile=google ;; 8) profile=quad9 ;;
    9) dns_status; pause; return ;;
    10) restore_dns; pause; return ;;
    0) return ;; *) warn 'Gozine namotabar'; pause; return ;;
  esac
  servers=$(dns_profile "$profile") || return 1
  if [[ "$profile" == radar || "$profile" == online403 ]]; then
    warn 'In DNS haye private-range faghat dar shabake haye Iran momken ast kar konand.'
  fi
  apply_dns "$profile" "$servers"
  pause
}
