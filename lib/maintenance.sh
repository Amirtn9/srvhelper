#!/usr/bin/env bash

swap_status() {
  section 'VASIAT SWAP'
  if command -v swapon >/dev/null 2>&1; then swapon --show --bytes | awk 'NR==1 {print "  " $0; next} {printf "  %-28s %8.1f MB  %8.1f MB  %s\n", $1,$3/1048576,$4/1048576,$5}'; fi
  [[ -e /swapfile-srv-helper ]] && info 'File Swap modiriat-shode mojood ast.'
}

swap_create() {
  local size file='/swapfile-srv-helper' marker='/var/lib/srv-helper/swap-managed'
  need_root || return 1
  [[ ! -e "$file" ]] || { warn 'SRV Helper swap file az ghabl vojood darad'; return 1; }
  if command -v swapon >/dev/null 2>&1 && swapon --show=NAME --noheadings 2>/dev/null | grep -Fxq "$file"; then
    warn 'Swap file ghablan faal shode ast'; return 1
  fi
  prompt 'Swap size be MB (128-65536)' size || return 1
  if ! [[ "$size" =~ ^[0-9]+$ ]] || ((10#$size<128 || 10#$size>65536)); then fail 'Size bayad 128 ta 65536 MB bashad'; return 1; fi
  confirm "Swap ${size}MB ijad shavad?" || return 1
  if command -v fallocate >/dev/null 2>&1; then fallocate -l "${size}M" "$file" || return 1
  else dd if=/dev/zero of="$file" bs=1M count="$size" status=progress || { rm -f "$file"; return 1; }; fi
  chmod 600 "$file"
  if ! mkswap "$file" >/dev/null || ! swapon "$file"; then rm -f "$file"; fail 'Swap create/activate fail shod'; return 1; fi
  install -d -m 700 /var/lib/srv-helper "$(backup_dir)"
  cp -a /etc/fstab "$(backup_dir)/fstab.$(date -u +%Y%m%dT%H%M%SZ).bak" 2>/dev/null || :
  grep -Fq "$file none swap" /etc/fstab || printf '%s none swap sw 0 0 # srv-helper-managed\n' "$file" >> /etc/fstab
  printf '%s\n' "$file" > "$marker"; chmod 600 "$marker"
  success "Swap ${size}MB faal va paydar shod"
}

swap_remove() {
  local marker='/var/lib/srv-helper/swap-managed' file
  need_root || return 1
  [[ -r "$marker" ]] || { fail 'Swap file managed tavasote SRV Helper nist; remove nemishavad'; return 1; }
  IFS= read -r file < "$marker"
  [[ "$file" == '/swapfile-srv-helper' && -f "$file" ]] || { fail 'Swap marker namotabar ast'; return 1; }
  confirm 'SRV Helper swap disable va delete shavad?' || return 1
  swapoff "$file" || { fail 'swapoff fail shod'; return 1; }
  install -d -m 700 "$(backup_dir)"
  cp -a /etc/fstab "$(backup_dir)/fstab.$(date -u +%Y%m%dT%H%M%SZ).bak" 2>/dev/null || :
  local tmp; tmp=$(mktemp /etc/.fstab.srv-helper.XXXXXX) || return 1
  awk -v p="$file" '$1 != p {print}' /etc/fstab > "$tmp"
  cat "$tmp" > /etc/fstab; rm -f "$tmp" "$file" "$marker"
  success 'File Swap hazf shod'
}

zram_status() {
  section 'VASIAT ZRAM'
  if [[ -r /sys/block/zram0/disksize ]]; then
    local bytes used
    bytes=$(cat /sys/block/zram0/disksize); used=$(cat /sys/block/zram0/mem_used_total 2>/dev/null || echo 0)
    printf '  Size: %s MB | RAM estefade-shode: %s MB\n' "$((bytes/1048576))" "$((used/1048576))"
    swapon --show 2>/dev/null | grep -E 'zram|NAME' || :
  else warn 'zram0 faal ya mojood nist'; fi
  [[ -f /etc/systemd/system/srv-helper-zram.service ]] && info 'Service paydar ZRAM nasb shode ast.'
}

zram_create() {
  local size bytes service='/etc/systemd/system/srv-helper-zram.service'
  need_root || return 1
  [[ ! -f "$service" ]] || { warn 'SRV Helper ZRAM service az ghabl mojood ast'; return 1; }
  if swapon --show=NAME --noheadings 2>/dev/null | grep -Fxq /dev/zram0; then
    warn 'ZRAM ghablan faal shode ast; config ghabli taghir nemikonad'; return 1
  fi
  prompt 'ZRAM size be MB (128-32768)' size || return 1
  if ! [[ "$size" =~ ^[0-9]+$ ]] || ((10#$size<128 || 10#$size>32768)); then fail 'Size bayad 128 ta 32768 MB bashad'; return 1; fi
  confirm "ZRAM ${size}MB create shavad va bad az reboot ham faal bashad?" || return 1
  need_cmd modprobe && need_cmd mkswap && need_cmd swapon || return 1
  modprobe zram || { fail 'Kernel module zram load nashod'; return 1; }
  [[ -e /sys/block/zram0 ]] || { fail 'Device zram0 peyda nashod'; return 1; }
  if [[ -r /sys/block/zram0/disksize ]] && (( $(cat /sys/block/zram0/disksize) > 0 )); then
    warn 'zram0 tavasote yek service digar config shode; taghir nemikonam'; return 1
  fi
  bytes=$((10#$size*1048576))
  cat > "$service" <<EOF2
[Unit]
Description=SRV Helper ZRAM swap
After=systemd-modules-load.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c 'modprobe zram && echo $bytes > /sys/block/zram0/disksize && mkswap -f /dev/zram0 && swapon -p 100 /dev/zram0'
ExecStop=/bin/bash -c 'swapoff /dev/zram0 2>/dev/null || true; echo 1 > /sys/block/zram0/reset 2>/dev/null || true'

[Install]
WantedBy=multi-user.target
EOF2
  chmod 644 "$service"
  systemctl daemon-reload
  if systemctl enable --now srv-helper-zram.service; then success "ZRAM ${size}MB faal va paydar shod"
  else systemctl disable srv-helper-zram.service 2>/dev/null || :; rm -f "$service"; systemctl daemon-reload; swapoff /dev/zram0 2>/dev/null || :; echo 1 > /sys/block/zram0/reset 2>/dev/null || :; modprobe -r zram 2>/dev/null || :; fail 'ZRAM start fail shod'; return 1; fi
}

zram_remove() {
  need_root || return 1
  [[ -f /etc/systemd/system/srv-helper-zram.service ]] || { fail 'SRV Helper ZRAM service peyda nashod'; return 1; }
  confirm 'ZRAM stop va service delete shavad?' || return 1
  systemctl disable --now srv-helper-zram.service || return 1
  rm -f /etc/systemd/system/srv-helper-zram.service
  systemctl daemon-reload
  modprobe -r zram 2>/dev/null || :
  success 'Service ZRAM hazf shod'
}

resource_menu() {
  local choice
  while :; do
    banner; section 'MODIRIAT RAM | SWAP + ZRAM'
    menu_line 1 'Namayesh vaziat Swap'
    menu_line 2 'Sakht file Swap'
    menu_line 3 'Hazf file Swap'
    menu_line 4 'Namayesh vaziat ZRAM'
    menu_line 5 'Sakht ZRAM paydar'
    menu_line 6 'Hazf ZRAM'
    menu_line 0 'Bargasht'
    prompt 'Entekhab' choice || return
    case "$choice" in
      1) swap_status; pause ;;
      2) swap_create; pause ;;
      3) swap_remove; pause ;;
      4) zram_status; pause ;;
      5) zram_create; pause ;;
      6) zram_remove; pause ;;
      0) return ;;
      *) warn 'Gozine namotabar'; pause ;;
    esac
  done
}

mtu_finder() {
  local target mtu payload best=0
  banner; section 'TEST MTU | BEDOON TAGHIR SYSTEM'
  prompt 'Maqsad domain/IP (mesal 1.1.1.1)' target || return
  [[ "$target" =~ ^[a-zA-Z0-9.-]+$ ]] || { fail 'Destination namotabar ast'; return 1; }
  need_cmd ping || return 1
  info 'MTU test faghat ICMP probe ast; NIC config ra taghir nemidahad.'
  for mtu in 1500 1472 1450 1400 1350 1300 1250 1200 1150 1100 1000; do
    payload=$((mtu-28))
    if ping -4 -M do -c 1 -W 1 -s "$payload" "$target" >/dev/null 2>&1; then
      best=$mtu; printf '  [OK]   MTU %s\n' "$mtu"
    else printf '  [FAIL] MTU %s\n' "$mtu"; fi
  done
  if ((best>0)); then success "Bozorgtarin probe movafagh: $best bytes"; else warn 'MTU probe natije nadad; ICMP momken block bashad.'; fi
  info 'In natije baraye masir shabake ast; taghir NIC be backup va maintenance window niaz darad.'
}

fail2ban_status() {
  if command -v fail2ban-client >/dev/null 2>&1; then fail2ban-client status 2>&1; else warn 'Fail2ban nasb nist'; fi
}

fail2ban_enable() {
  need_root && need_cmd apt-get || return 1
  confirm 'Fail2ban install va SSH jail faal shavad?' || return 1
  DEBIAN_FRONTEND=noninteractive apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y fail2ban || return 1
  install -d -m 755 /etc/fail2ban/jail.d
  local file='/etc/fail2ban/jail.d/90-srv-helper-sshd.local'
  install -d -m 700 "$(backup_dir)"
  if [[ -f "$file" ]]; then cp -a "$file" "$(backup_dir)/fail2ban.$(date -u +%Y%m%dT%H%M%SZ).bak"; fi
  cat > "$file" <<'EOF2'
[sshd]
enabled = true
backend = systemd
port = ssh
maxretry = 5
findtime = 10m
bantime = 1h
EOF2
  systemctl enable --now fail2ban && systemctl restart fail2ban && success 'Fail2ban SSH jail faal shod'
}

fail2ban_disable() {
  need_root || return 1
  confirm 'Fail2ban stop/disable shavad? (SSH security kamtar mishavad)' || return 1
  systemctl disable --now fail2ban && success 'Fail2ban disable shod'
}

fail2ban_menu() {
  local choice
  while :; do
    banner; section 'HIFAZAT SSH | FAIL2BAN'
    menu_line 1 'Nasb va faalsazi SSH jail'
    menu_line 2 'Namayesh vaziat Fail2ban'
    menu_line 3 'Gheyre faal kardan Fail2ban'
    menu_line 4 'Namayesh vaziat SSH jail'
    menu_line 0 'Bargasht'
    prompt 'Entekhab' choice || return
    case "$choice" in
      1) fail2ban_enable; pause ;;
      2) fail2ban_status; pause ;;
      3) fail2ban_disable; pause ;;
      4) fail2ban-client status sshd 2>&1 || :; pause ;;
      0) return ;;
      *) warn 'Gozine namotabar'; pause ;;
    esac
  done
}

clamav_install() {
  need_root && need_cmd apt-get || return 1
  confirm 'ClamAV install shavad? (package ha download mishavand)' || return 1
  DEBIAN_FRONTEND=noninteractive apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y clamav clamav-daemon || return 1
  systemctl stop clamav-freshclam 2>/dev/null || :
  freshclam || warn 'Freshclam update fail shod; baad az check internet dobare emtehan konid.'
  systemctl enable --now clamav-freshclam 2>/dev/null || :
  success 'ClamAV install shod. Scan az menu ejra konid.'
}

clamav_scan() {
  local target
  need_root && need_cmd clamscan || return 1
  prompt 'Masir baraye scan (mesal /var/www)' target || return 1
  [[ "$target" == /* && -e "$target" && "$target" != / ]] || { fail 'Path namotabar ast'; return 1; }
  warn 'Scan faghat report mide; file ha ra delete ya quarantine nemikonad.'
  confirm "Scan $target anjam shavad?" || return 1
  clamscan -r -i --infected "$target"
}

clamav_menu() {
  local choice
  while :; do
    banner; section 'SCAN FILE | CLAMAV'
    menu_line 1 'Nasb ClamAV + update signature ha'
    menu_line 2 'Scan faghat khanadani rooye masir'
    menu_line 3 'Namayesh vaziat ClamAV'
    menu_line 0 'Bargasht'
    prompt 'Entekhab' choice || return
    case "$choice" in
      1) clamav_install; pause ;;
      2) clamav_scan; pause ;;
      3) systemctl status clamav-freshclam clamav-daemon --no-pager 2>&1 || :; pause ;;
      0) return ;;
      *) warn 'Gozine namotabar'; pause ;;
    esac
  done
}

ssh_add_port_safely() {
  local port cfg='/etc/ssh/sshd_config' backup svc old_port
  local -a current_ports=()
  need_root && need_cmd sshd && need_cmd ss && need_cmd systemctl || return 1
  prompt 'SSH port jadid (1024-65535; port ghabli baz mimanad)' port || return 1
  if ! [[ "$port" =~ ^[0-9]+$ ]] || ((10#$port<1024 || 10#$port>65535)); then fail 'Port bayad 1024 ta 65535 bashad'; return 1; fi
  port=$((10#$port))
  if ss -H -ltn "sport = :$port" 2>/dev/null | grep -q .; then fail 'In port dar hale listen ast'; return 1; fi
  [[ -f "$cfg" ]] || { fail 'sshd_config peyda nashod'; return 1; }
  mapfile -t current_ports < <(sshd -T 2>/dev/null | awk '$1=="port" && $2 ~ /^[0-9]+$/ {print $2}' | sort -un)
  ((${#current_ports[@]}>0)) || current_ports=(22)
  backup="$(backup_dir)/sshd_config.$(date -u +%Y%m%dT%H%M%SZ).bak"
  install -d -m 700 "$(backup_dir)"
  cp -a "$cfg" "$backup" || return 1
  if grep -Eiq "^[[:space:]]*Port[[:space:]]+$port([[:space:]]|$)" "$cfg" /etc/ssh/sshd_config.d/*.conf 2>/dev/null; then
    warn 'In port dar config sshd vojood darad'; return 1
  fi
  {
    printf '\n# Added by SRV Helper. Existing SSH ports are kept until the new connection is verified.\n'
    for old_port in "${current_ports[@]}"; do printf 'Port %s\n' "$old_port"; done
    printf 'Port %s\n' "$port"
  } >> "$cfg"
  if ! sshd -t -f "$cfg"; then cp -a "$backup" "$cfg"; fail 'SSH config invalid bood; rollback shod'; return 1; fi
  if command -v ufw >/dev/null 2>&1; then
    ufw allow "$port/tcp" || { cp -a "$backup" "$cfg"; return 1; }
  elif command -v firewall-cmd >/dev/null 2>&1; then
    firewall-cmd --permanent --add-port="$port/tcp" && firewall-cmd --reload || { cp -a "$backup" "$cfg"; return 1; }
  else warn 'Firewall detect nashod; port jadid ro dar firewall provider baz konid.'; fi
  if systemctl list-unit-files --no-legend 2>/dev/null | grep -q '^ssh.service'; then svc=ssh; else svc=sshd; fi
  if ! systemctl reload "$svc"; then
    cp -a "$backup" "$cfg"; systemctl reload "$svc" 2>/dev/null || :
    fail 'SSH reload fail shod; config rollback shod'; return 1
  fi
  sleep 1
  if ss -H -ltn "sport = :$port" 2>/dev/null | grep -q .; then
    success "SSH dar port $port ham listen mikonad. Port ghabli hanooz dar config hast."
    info 'Aval ba port jadid vasl shodan ra test konid; port ghabli ra faghat ba session jadid bebandid.'
  else
    cp -a "$backup" "$cfg"; systemctl reload "$svc" 2>/dev/null || :
    warn 'Port jadid dar ss peyda nashod; config rollback shod. Port ghabli ra dast nazanid.'
    return 1
  fi
}

ssh_audit() {
  banner; section 'BARRASI AMNIAT SSH'
  if command -v sshd >/dev/null 2>&1; then
    sshd -T 2>/dev/null | awk '$1=="port" || $1=="permitrootlogin" || $1=="passwordauthentication" || $1=="pubkeyauthentication" {print "  " $1 " = " $2}'
  else warn 'sshd binary peyda nashod'; fi
  if command -v ufw >/dev/null 2>&1; then ufw status verbose | sed -n '1,18p';
  elif command -v firewall-cmd >/dev/null 2>&1; then firewall-cmd --list-all 2>/dev/null | sed -n '1,22p'; fi
  info 'Port jadid ezafe mishavad va port ghabli baz mimanad ta vaghti khodetan hazf konid.'
}

cockpit_install() {
  need_root && need_cmd apt-get || return 1
  confirm 'Cockpit monitoring install va socket faal shavad?' || return 1
  DEBIAN_FRONTEND=noninteractive apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y cockpit || return 1
  systemctl enable --now cockpit.socket && success 'Cockpit faal shod; panel rooye TCP/9090 ast.'
  warn 'Port 9090 dar firewall khodkar baz nashod. Faghat az IP haye motmaen dastresi bedahid.'
}

server_services_menu() {
  local choice rc
  while :; do
    [[ ${SRV_EXIT_REQUESTED:-0} == 1 ]] && return
    banner; section 'KHADAMAT SERVER'
    menu_line 1 'Modiriat service haye tunnel'
    menu_line 2 'Modiriat RAM (Swap / ZRAM)'
    menu_line 3 'Tanzim TCP (BBR / Hybla / Cubic)'
    menu_line 4 'Hifazat SSH (Fail2ban)'
    menu_line 5 'Scan malware (ClamAV)'
    menu_line 6 'Monitor server (Cockpit)'
    menu_line 0 'Bargasht'
    prompt 'Entekhab' choice; rc=$?
    if ((rc==20)); then SRV_BACK_REQUESTED=0; return; fi
    ((rc==0)) || return "$rc"
    case "$choice" in
      1) tunnel_menu ;;
      2) resource_menu ;;
      3) tcp_optimizer_menu ;;
      4) fail2ban_menu ;;
      5) clamav_menu ;;
      6) cockpit_install; pause ;;
      0) return ;;
      *) warn 'Gozine namotabar'; pause ;;
    esac
    [[ ${SRV_EXIT_REQUESTED:-0} == 1 ]] && return
    if [[ ${SRV_BACK_REQUESTED:-0} == 1 ]]; then SRV_BACK_REQUESTED=0; fi
  done
}
