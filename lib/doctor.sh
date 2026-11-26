#!/usr/bin/env bash
# The report omits hostnames, addresses, domain names, and credential paths.
server_doctor() {
  local fs family address target certificates=0 expired=0 read_errors=0 cert
  section 'SERVER DOCTOR'
  printf '  OS: %s\n' "$(os_label)"
  fs=$(df -P / 2>/dev/null | awk 'NR==2 {print $5}')
  if [[ "$fs" =~ ^[0-9]+%$ ]]; then
    if (( ${fs%%%} >= 90 )); then warn "Root disk: $fs used. Free space before updating packages."
    else success "Root disk: $fs used."; fi
  else warn 'Root disk usage unavailable.'; fi

  if timeout 8 getent ahosts example.com >/dev/null 2>&1; then
    success 'System DNS query succeeded.'
  else
    warn 'System DNS query failed. Inspect resolver status from the DNS menu.'
  fi
  if systemctl is-active --quiet systemd-resolved 2>/dev/null; then
    info 'Resolver: systemd-resolved. Use the DNS menu for per-link addresses.'
  elif [[ -r /etc/resolv.conf ]]; then
    info 'Resolver: systemd-resolved inactive. Check the host network configuration.'
  else
    warn 'No readable resolver configuration.'
  fi
  for family in 4 6; do
    if [[ "$family" == 4 ]]; then address=1.1.1.1; else address=2606:4700:4700::1111; fi
    if ip "-$family" route get "$address" >/dev/null 2>&1; then
      success "IPv$family: route available."
    else
      warn "IPv$family: no route detected. Check the address and gateway if this family is required."
    fi
  done

  if command -v apt-cache >/dev/null && apt-cache policy >/dev/null 2>&1; then
    target=$(find /var/lib/apt/lists -maxdepth 1 -type f \( -name '*_InRelease' -o -name '*_Release' \) -mtime -7 -print -quit 2>/dev/null)
    if [[ -n "$target" ]]; then success 'APT: cached repository metadata updated within seven days.'
    else warn 'APT: no recent repository metadata. Check the configured sources and run apt update.'; fi
  else
    warn 'APT metadata could not be read.'
  fi

  if systemctl is-active --quiet ssh.socket 2>/dev/null || systemctl is-active --quiet sshd.socket 2>/dev/null; then
    success 'SSH: active socket listener. Port changes are managed by systemd.'
  elif systemctl is-active --quiet ssh.service 2>/dev/null || systemctl is-active --quiet sshd.service 2>/dev/null; then
    success 'SSH: active service.'
  else
    warn 'SSH: systemd could not confirm a listener. Check the host console before changing SSH.'
  fi

  if [[ -d /etc/letsencrypt/live && -r /etc/letsencrypt/live && -x /etc/letsencrypt/live ]] &&
     command -v openssl >/dev/null; then
    for cert in /etc/letsencrypt/live/*/cert.pem; do
      [[ -e "$cert" || -L "$cert" ]] || continue
      if ! openssl x509 -in "$cert" -noout >/dev/null 2>&1; then
        read_errors=$((read_errors+1))
        continue
      fi
      certificates=$((certificates+1))
      openssl x509 -in "$cert" -noout -checkend 1209600 >/dev/null 2>&1 || expired=$((expired+1))
    done
    if ((expired || read_errors)); then
      warn "Certificates: $expired expire within 14 days or have expired; $read_errors unreadable."
    else
      success "Certificates: $certificates readable; none expire within 14 days."
    fi
  else
    info 'Certificates: no readable Certbot store. Run as root to inspect an existing store.'
  fi
}

doctor_menu() {
  local choice
  while :; do
    choose_menu choice 'SERVER DOCTOR' '' \
      1 'Run a read-only health check' \
      2 'Save a baseline for comparison' \
      3 'Compare with the saved baseline' \
      0 'Back' || return $?
    case "$choice" in
      1) server_doctor ;;
      2)
        # Retain the redacted baseline for this SRV Helper session.
        SRV_DOCTOR_BASELINE=$(server_doctor)
        success 'Baseline saved for this session.'
        ;;
      3)
        if [[ -n ${SRV_DOCTOR_BASELINE:-} ]]; then
          local current difference rc=0
          current=$(server_doctor)
          difference=$(diff -u --label Before --label After <(printf '%s\n' "$SRV_DOCTOR_BASELINE") <(printf '%s\n' "$current")) || rc=$?
          case "$rc" in
            0) success 'No differences from the baseline.' ;;
            1) printf '%s\n' "$difference" ;;
            *) fail 'Could not compare the reports.' ;;
          esac
        else warn 'Save a baseline first.'; fi
        ;;
      0) return ;;
      *) warn 'Invalid option.' ;;
    esac
    pause
    [[ $SRV_EXIT_REQUESTED == 0 && $SRV_BACK_REQUESTED == 0 ]] || return 0
  done
}
