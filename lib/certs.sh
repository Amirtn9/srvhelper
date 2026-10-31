#!/usr/bin/env bash
# certbot remains source-of-truth; destination copies are maintained by a deploy hook.
valid_domain() {
  local value=${1,,} label
  [[ ${#value} -le 253 && "$value" == *.* && "$value" != *..* && "$value" != *'*'* ]] || return 1
  [[ "$value" =~ ^[a-z0-9.-]+$ ]] || return 1
  [[ "$value" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] && return 1
  local -a labels
  IFS='.' read -r -a labels <<< "$value"
  for label in "${labels[@]}"; do
    [[ ${#label} -ge 1 && ${#label} -le 63 && "$label" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] || return 1
  done
}
collect_domains() {
  local count=$1 _dest=$2 idx raw normalized found prev
  local -a result=()
  for ((idx=1;idx<=count;)); do
    prompt "Domain $idx/$count (mesal: site.com)" raw || return 1
    normalized=${raw,,}
    if ! valid_domain "$normalized"; then warn 'Domain namotabar ast. Faghat FQDN bedoon space va wildcard'; continue; fi
    found=0
    for prev in "${result[@]}"; do [[ "$prev" == "$normalized" ]] && found=1; done
    if ((found)); then warn 'Domain tekrari ast'; continue; fi
    result+=("$normalized")
    ((idx+=1))
  done
  # bash nameref for safe transfer without command substitution/splitting.
  local -n target="$_dest"
  target=("${result[@]}")
}
choose_method() {
  section 'RAVESH TAEED DOMAIN'
  menu_line 1 'HTTP-01 Standalone (port 80 bayad azad bashad)'
  menu_line 2 'HTTP-01 Webroot (baraye webserver faal)'
  prompt 'Method' CERT_METHOD || return 1
  case "$CERT_METHOD" in
    1)
      if command -v ss >/dev/null 2>&1 && ss -H -ltn '( sport = :80 )' 2>/dev/null | grep -q .; then
        warn 'Port 80 dar hale estefade ast; certbot standalone ehtemalan fail mishavad.'
        confirm 'Ba hamin method edame midahid?' || return 1
      fi
      ;;
    2)
      prompt 'Webroot absolute path (mesal /var/www/html)' CERT_WEBROOT || return 1
      if [[ "$CERT_WEBROOT" != /* || ! -d "$CERT_WEBROOT" ]]; then fail 'Webroot bayad yek directory mojood va absolute bashad'; return 1; fi
      ;;
    *) warn 'Method namotabar'; return 1 ;;
  esac
}
choose_email() {
  prompt 'Email baraye expiry alert (khali = bedoon email)' CERT_EMAIL || return 1
  if [[ -n "$CERT_EMAIL" && ! "$CERT_EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
    fail 'Email namotabar ast'; return 1
  fi
}
choose_destination() {
  local selection base
  section 'MASIR ZAKHIRE CERT'
  menu_line 1 'Pasarguard => /var/lib/pasarguard/certs'
  menu_line 2 'Root       => /root/ssl-certs'
  menu_line 3 'Custom     => masir delkhah'
  prompt 'Kodam masir?' selection || return 1
  case "$selection" in
    1) base='/var/lib/pasarguard/certs' ;;
    2) base='/root/ssl-certs' ;;
    3) prompt 'Absolute directory path' base || return 1 ;;
    *) fail 'Masir namotabar'; return 1 ;;
  esac
  if [[ "$base" != /* || "$base" == '/' || "$base" == */../* || "$base" == */.. || "$base" == *$'\n'* || "$base" == *$'\t'* || "$base" == /etc/letsencrypt* || "$base" == /tmp/* || "$base" == /var/tmp/* || "$base" == /dev/shm/* ]]; then
    fail 'Masir amn nist; masir absolute va joda az /etc/letsencrypt entekhab konid'; return 1
  fi
  DEST_BASE=${base%/}
  info "Har certificate dar folder khas khodash zire $DEST_BASE zakhire mishavad."
  confirm 'Masir ra taeed mikonid?' || return 1
  prompt 'Service group (khali=root, mesal pasarguard)' DEST_GROUP || return 1
  DEST_GROUP=${DEST_GROUP:-root}
  if [[ ! "$DEST_GROUP" =~ ^[a-z_][a-z0-9_-]*$ ]] || ! getent group "$DEST_GROUP" >/dev/null 2>&1; then
    fail 'Group namotabar ast ya vojood nadarad'; return 1
  fi
  if [[ "$DEST_GROUP" != root ]]; then
    warn "Private key ba group $DEST_GROUP va mode 640 deploy mishavad."
    confirm 'Dastresi group be private key ra taeed mikonid?' || return 1
  fi
}
install_certbot_if_needed() {
  if command -v certbot >/dev/null 2>&1; then return 0; fi
  warn 'Certbot nasb nist'
  confirm 'Ba APT nasb shavad?' || return 1
  need_cmd apt-get || return 1
  DEBIAN_FRONTEND=noninteractive apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y certbot
}
preflight_domains() {
  local domain
  for domain in "$@"; do
    if ! getent ahosts "$domain" >/dev/null 2>&1; then
      warn "DNS baraye $domain resolve nashod. ACME ehtemalan fail mishavad."
      confirm 'Edame bedam?' || return 1
    fi
  done
}
issue_certificate() {
  local certname=$1; shift
  local -a domains=("$@") args=(certonly --non-interactive --agree-tos --keep-until-expiring --cert-name "$certname")
  local domain
  if [[ -n "$CERT_EMAIL" ]]; then args+=(--email "$CERT_EMAIL"); else args+=(--register-unsafely-without-email); fi
  if [[ "$CERT_METHOD" == 1 ]]; then
    args+=(--standalone --preferred-challenges http)
  else
    args+=(--webroot -w "$CERT_WEBROOT" --preferred-challenges http)
  fi
  for domain in "${domains[@]}"; do args+=(-d "$domain"); done
  if [[ -d "/etc/letsencrypt/live/$certname" ]]; then
    warn "Cert name $certname az ghabl vojood darad. Agar domains avaz shode bashad, cert update mishavad."
    confirm 'Certificate mojood update/reuse shavad?' || return 1
    args+=(--expand)
  fi
  info "Certbot baraye: ${domains[*]}"
  certbot "${args[@]}"
}
setup_deploy_hook() {
  local src="$SRV_HOME/hooks/srv-helper-deploy.sh" dest='/etc/letsencrypt/renewal-hooks/deploy/srv-helper-deploy'
  if [[ ! -f "$src" ]]; then fail 'Deploy hook mojood nist; install kamel SRV Helper lazem ast'; return 1; fi
  install -d -m 700 /etc/srv-helper
  install -d -m 755 /etc/letsencrypt/renewal-hooks/deploy
  install -m 750 "$src" "$dest"
  touch /etc/srv-helper/deployments.tsv
  chmod 600 /etc/srv-helper/deployments.tsv
  chown root:root /etc/srv-helper/deployments.tsv
}
register_destination() {
  local name=$1 dest=$2 group=$3 conf='/etc/srv-helper/deployments.tsv' key path grp
  if [[ ! "$name" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ || "$name" == *'..'* || "$dest" == *$'\t'* || "$dest" == *$'\n'* ]]; then return 1; fi
  # Write to temp file atomically. Names are validated FQDNs.
  local tmp
  tmp=$(mktemp /etc/srv-helper/.deployments.XXXXXX) || return 1
  chmod 600 "$tmp"
  if [[ -f "$conf" ]]; then
    while IFS=$'\t' read -r key path grp; do
      [[ "$key" == "$name" ]] || printf '%s\t%s\t%s\n' "$key" "$path" "${grp:-root}" >> "$tmp"
    done < "$conf"
  fi
  printf '%s\t%s\t%s\n' "$name" "$dest" "$group" >> "$tmp"
  mv -f -- "$tmp" "$conf"
  RENEWED_LINEAGE="/etc/letsencrypt/live/$name" RENEWED_DOMAINS="$name" \
    /etc/letsencrypt/renewal-hooks/deploy/srv-helper-deploy
}
execute_job() {
  local mode=$1; shift
  local -a domains=("$@") successes=() failed=()
  local certname name idx=0
  need_root || return 1
  install_certbot_if_needed || { fail 'Certbot nasb nashod'; pause; return 1; }
  preflight_domains "${domains[@]}" || return 1
  step 3 5 'GEREFTAN CERTIFICATE'
  if [[ "$mode" == 'batch' ]]; then
    for name in "${domains[@]}"; do
      ((idx+=1))
      info "Batch $idx/${#domains[@]}: $name"
      if issue_certificate "$name" "$name" && [[ -f "/etc/letsencrypt/live/$name/fullchain.pem" ]]; then
        successes+=("$name")
        success "$name gerefte shod"
      else
        failed+=("$name")
        fail "$name fail shod; batch edame darad"
      fi
    done
  else
    certname=${domains[0]}
    if issue_certificate "$certname" "${domains[@]}" && [[ -f "/etc/letsencrypt/live/$certname/fullchain.pem" ]]; then
      successes+=("$certname")
    else
      failed+=("$certname")
    fi
  fi
  if ((${#successes[@]} == 0)); then fail 'Hich certificate gerefte nashod'; pause; return 1; fi
  step 4 5 'ENTEKHAB MASIR NAHAYI'
  choose_destination || { warn 'Cert dar /etc/letsencrypt/live mojood ast; deploy anjam nashod'; pause; return 1; }
  setup_deploy_hook || { pause; return 1; }
  step 5 5 'DEPLOY + HOOK TAMDID'
  local deployed=0
  for certname in "${successes[@]}"; do
    if register_destination "$certname" "$DEST_BASE/$certname" "$DEST_GROUP"; then
      success "Fullchain: $DEST_BASE/$certname/fullchain.pem"
      success "Private key: $DEST_BASE/$certname/privkey.pem"
      ((deployed+=1))
    else fail "Deploy baraye $certname fail shod"; fi
  done
  info "Natije: ${#successes[@]} cert gerefte, $deployed deploy shode, ${#failed[@]} fail."
  if ((${#failed[@]})); then warn "Fail: ${failed[*]}"; fi
  info 'Hook certbot ba har renew movafagh, fileha ra dobare deploy mikonad.'
  info "Private key group: $DEST_GROUP (root=600, service group=640)"
  pause
}
manual_ssl() {
  banner; section 'SSL DASTI | YEK DOMAIN'
  local -a domains=()
  step 1 5 'Domain'
  collect_domains 1 domains || return 1
  step 2 5 'RAVESH + EMAIL'
  choose_method && choose_email || { pause; return 1; }
  execute_job 'single' "${domains[@]}"
}
smart_ssl_menu() {
  while :; do
    banner; section 'SSL HOSHMAND'
    menu_line 1 'SAN: yek certificate baraye chand domain (2-25)'
    menu_line 2 'Batch: har domain yek certificate joda (1-50)'
    menu_line 0 'Bargasht'
    prompt 'Entekhab' choice || return
    case "$choice" in
      1) smart_ssl_flow san ;;
      2) smart_ssl_flow batch ;;
      0) return ;;
      *) warn 'Gozine namotabar'; pause ;;
    esac
  done
}
smart_ssl_flow() {
  local mode=$1 count max
  local -a domains=()
  banner; section "${mode^^} | MARAHEL HOSHMAND"
  max=50; [[ "$mode" == san ]] && max=25
  step 1 5 'Tedad domain ha'
  prompt "Chand domain darid? (1-$max)" count || return 1
  if ! valid_positive_count "$count" "$max" || { [[ "$mode" == san && "$count" =~ ^[0-9]+$ ]] && ((10#$count < 2)); }; then
    fail 'Tedad namotabar ast (SAN: 2-25, Batch: 1-50)'; pause; return 1
  fi
  step 2 5 'Daryaft domain ha'
  collect_domains "$count" domains || return 1
  section 'KHOLASE'
  printf '  %s\n' "${domains[@]}"
  if [[ "$mode" == san ]]; then
    info 'Tamam domain ha dar yek SAN certificate gharar migirand.'
  else
    info 'Baraye har domain yek certificate joda darkhast mishavad.'
  fi
  confirm 'Taeed domain ha?' || return 1
  choose_method && choose_email || { pause; return 1; }
  execute_job "$mode" "${domains[@]}"
}
certificate_dashboard() {
  banner; section 'VASIAT CERTIFICATE HA'
  if ! command -v certbot >/dev/null 2>&1; then warn 'Certbot nasb nist'; pause; return; fi
  menu_line 1 'List certificate ha (Certbot)'
  menu_line 2 'Test tamdid (dry-run)'
  menu_line 3 'Barrasi etebar + domain haye SAN'
  menu_line 4 'Masir certificate haye deploy-shode'
  menu_line 5 'Deploy certificate mojood be masir jadid'
  menu_line 0 'Bargasht'
  local ch file
  prompt 'Entekhab' ch || return
  case "$ch" in
    1) need_root && certbot certificates || : ;;
    2) need_root && certbot renew --dry-run || : ;;
    3)
      need_cmd openssl || return
      prompt 'Fullchain absolute path' file || return
      if [[ -f "$file" ]]; then
        openssl x509 -in "$file" -noout -subject -dates -ext subjectAltName
      else fail 'File peyda nashod'; fi ;;
    4)
      if need_root; then
        if [[ -r /etc/srv-helper/deployments.tsv ]]; then
          awk -F '\t' '{printf "  %s => %s (group=%s)\n",$1,$2,($3?$3:"root")}' /etc/srv-helper/deployments.tsv
        else warn 'Hanooz deploy sabt nashode'; fi
      fi ;;
    5)
      need_root || return
      certbot certificates || :
      local name
      prompt 'Cert name (az list bala)' name || return
      if [[ ! "$name" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ || "$name" == *'..'* || ! -f "/etc/letsencrypt/live/$name/fullchain.pem" ]]; then
        fail 'Cert name namotabar ast ya certificate peyda nashod'
      elif choose_destination && setup_deploy_hook; then
        register_destination "$name" "$DEST_BASE/$name" "$DEST_GROUP" && success 'Certificate ba movafaghiat deploy shod' || fail 'Deploy fail shod'
      fi ;;
    0) return ;;
    *) warn 'Gozine namotabar' ;;
  esac
  pause
}
