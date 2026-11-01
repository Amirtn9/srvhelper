#!/usr/bin/env bash
# SSL issuance, SAN/batch workflows and renewal-safe deployment.

normalize_domain() {
  local value=${1//$'\r'/} ascii
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  value=${value,,}
  [[ -n "$value" ]] || return 1
  # Accept a pasted URL, but keep only its hostname. Paths and ports are not accepted.
  if [[ "$value" == https://* || "$value" == http://* ]]; then
    value=${value#*://}
    value=${value%%/*}
  fi
  [[ "$value" != *:* && "$value" != */* && "$value" != *' '* ]] || return 1
  # Convert internationalized names to ASCII/Punycode when Python is available.
  if [[ "$value" =~ [^a-z0-9.-] ]]; then
    command -v python3 >/dev/null 2>&1 || return 1
    ascii=$(python3 - "$value" 2>/dev/null <<'PY'
import sys
try:
    print(sys.argv[1].encode("idna").decode("ascii").lower())
except Exception:
    raise SystemExit(1)
PY
    ) || return 1
    value=$ascii
  fi
  value=${value%.}
  valid_domain "$value" || return 1
  printf '%s' "$value"
}

valid_domain() {
  local value=${1,,} label last
  [[ ${#value} -le 253 && "$value" == *.* && "$value" != *..* && "$value" != *'*'* ]] || return 1
  [[ "$value" =~ ^[a-z0-9.-]+$ ]] || return 1
  [[ "$value" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] && return 1
  local -a labels=()
  IFS='.' read -r -a labels <<< "$value"
  ((${#labels[@]} >= 2)) || return 1
  for label in "${labels[@]}"; do
    [[ ${#label} -ge 1 && ${#label} -le 63 && "$label" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] || return 1
  done
  last=${labels[${#labels[@]}-1]}
  [[ "$last" =~ ^([a-z]{2,63}|xn--[a-z0-9-]{2,59})$ ]] || return 1
  return 0
}

collect_domains() {
  local count=$1 destination=$2 idx raw normalized prev rc found
  local -a result=()
  for ((idx=1;idx<=count;)); do
    prompt "Domain $idx/$count (mesal: pl24.pingyar.com)" raw; rc=$?
    ((rc==0)) || return "$rc"
    normalized=$(normalize_domain "$raw") || {
      warn 'Domain namotabar ast. Mesal: pl24.pingyar.com (bedoon path ya port)'
      continue
    }
    found=0
    for prev in "${result[@]}"; do [[ "$prev" == "$normalized" ]] && found=1; done
    if ((found)); then warn 'In domain ghablan vared shode ast'; continue; fi
    result+=("$normalized")
    ((idx+=1))
  done
  local -n target="$destination"
  target=("${result[@]}")
  return 0
}

choose_method() {
  local choice path
  if command -v ss >/dev/null 2>&1 && ss -H -ltn '( sport = :80 )' 2>/dev/null | grep -q .; then
    warn 'Port 80 busy ast. Baraye SSL az Webroot estefade konid.'
    CERT_METHOD=2
  else
    section 'RAVESH TAEED DOMAIN'
    menu_line 1 'Standalone (port 80 bayad baz bashad)'
    menu_line 2 'Webroot (baraye website mojood)'
    prompt 'Ravesh' choice || return $?
    case "$choice" in
      1) CERT_METHOD=1 ;;
      2) CERT_METHOD=2 ;;
      *) warn 'Gozine namotabar'; return 1 ;;
    esac
  fi
  if [[ "$CERT_METHOD" == 2 ]]; then
    prompt 'Masir Webroot (mesal /var/www/html)' path || return $?
    if [[ "$path" != /* || ! -d "$path" || "$path" == / ]]; then
      fail 'Webroot bayad masir absolute va folder mojood website bashad'
      return 1
    fi
    CERT_WEBROOT=${path%/}
    install -d -m 755 "$CERT_WEBROOT/.well-known/acme-challenge" || return 1
    [[ -w "$CERT_WEBROOT/.well-known/acme-challenge" ]] || { fail 'Webroot writable nist'; return 1; }
  fi
}

choose_email() {
  local rc
  prompt 'Email (khali = bedoon email)' CERT_EMAIL; rc=$?
  ((rc==0)) || return "$rc"
  if [[ -n "$CERT_EMAIL" && ! "$CERT_EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
    fail 'Email namotabar ast'
    return 1
  fi
}

choose_destination() {
  local selection base rc
  section 'MASIR ZAKHIRE CERTIFICATE'
  menu_line 1 'Pasarguard  (/var/lib/pasarguard/certs)'
  menu_line 2 'Root       (/root/ssl-certs)'
  menu_line 3 'Delkhah    (masir delkhah)'
  prompt 'Entekhab' selection; rc=$?
  ((rc==0)) || return "$rc"
  case "$selection" in
    1) base='/var/lib/pasarguard/certs' ;;
    2) base='/root/ssl-certs' ;;
    3) prompt 'Masir absolute' base || return $? ;;
    *) fail 'Masir namotabar'; return 1 ;;
  esac
  if [[ "$base" != /* || "$base" == '/' || "$base" == *'/../'* || "$base" == */.. || "$base" == *$'\n'* || "$base" == /etc/letsencrypt* || "$base" == /tmp/* || "$base" == /var/tmp/* || "$base" == /dev/shm/* ]]; then
    fail 'Masir amn nist; yek folder joda entekhab konid'
    return 1
  fi
  DEST_BASE=${base%/}
  info "Certificate ha dar $DEST_BASE zakhire mishavand."
  DEST_GROUP=root
  prompt 'Group service (khali=root, optional)' DEST_GROUP || return $?
  DEST_GROUP=${DEST_GROUP:-root}
  if [[ ! "$DEST_GROUP" =~ ^[a-z_][a-z0-9_-]*$ ]] || ! getent group "$DEST_GROUP" >/dev/null 2>&1; then
    fail 'Group namotabar ast ya vojood nadarad'
    return 1
  fi
  if [[ "$DEST_GROUP" != root ]]; then
    warn "Private key ba group $DEST_GROUP va permission 640 zakhire mishavad."
    confirm 'Dastresi group ra taeed mikonid?' || return $?
  fi
  confirm 'Masir nahayi taeed shavad?' || return $?
}

install_certbot_if_needed() {
  command -v certbot >/dev/null 2>&1 && return 0
  need_root && need_cmd apt-get || return 1
  warn 'Certbot nasb nist; az package manager nasb mishavad.'
  confirm 'Certbot nasb shavad?' || return $?
  DEBIAN_FRONTEND=noninteractive apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y certbot
}

preflight_domains() {
  local domain addresses public_ip ipv4 rc
  if [[ ${SRV_PUBLIC_IP_CHECKED:-0} != 1 ]]; then
    SRV_PUBLIC_IP=''
    if command -v curl >/dev/null 2>&1; then
      SRV_PUBLIC_IP=$(curl -4fsS --connect-timeout 3 --max-time 5 https://api.ipify.org 2>/dev/null | tr -d '[:space:]' || true)
      [[ "$SRV_PUBLIC_IP" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || SRV_PUBLIC_IP=''
    fi
    SRV_PUBLIC_IP_CHECKED=1
  fi
  public_ip=${SRV_PUBLIC_IP:-}
  for domain in "$@"; do
    addresses=$(getent ahosts "$domain" 2>/dev/null | awk '{print $1}' | sort -u | head -5 || true)
    if [[ -z "$addresses" ]]; then
      fail "DNS baraye $domain resolve nashod. Record A/AAAA ra be IP server vasl konid."
      return 1
    fi
    info "$domain -> $(tr '\n' ' ' <<< "$addresses")"
    if [[ -n "$public_ip" ]]; then
      ipv4=$(getent ahostsv4 "$domain" 2>/dev/null | awk '{print $1}' | sort -u || true)
      if [[ -n "$ipv4" ]] && ! grep -Fxq "$public_ip" <<< "$ipv4"; then
        warn "A record $domain ba IP public server ($public_ip) yeki nist. Agar CDN/Proxy darid, route challenge ra check konid."
        confirm 'Ba hamin DNS edame bedam?' ; rc=$?
        ((rc==0)) || return "$rc"
      fi
    fi
    if command -v dig >/dev/null 2>&1 && [[ -n $(dig +short AAAA "$domain" 2>/dev/null | head -1) ]]; then
      warn "$domain record IPv6 ham darad; AAAA bayad be hamin server beresad."
    fi
  done
  info 'DNS check tamam shod. Baraye ACME, inbound TCP/80 bayad az internet dastresi dashte bashad.'
}

find_matching_certificate() {
  local renewal_dir=${CERT_RENEWAL_DIR:-/etc/letsencrypt/renewal} conf existing wanted name
  wanted=$(printf '%s\n' "$@" | LC_ALL=C sort | tr '\n' '|')
  for conf in "$renewal_dir"/*.conf; do
    [[ -f "$conf" ]] || continue
    existing=$(awk -F= '/^[[:space:]]*domains[[:space:]]*=/ {sub(/^[[:space:]]*/, "", $2); sub(/[[:space:]]*$/, "", $2); print $2; exit}' "$conf")
    [[ -n "$existing" ]] || continue
    existing=$(tr ',' '\n' <<< "$existing" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | LC_ALL=C sort | tr '\n' '|')
    if [[ "$existing" == "$wanted" ]]; then
      name=${conf##*/}; name=${name%.conf}
      printf '%s' "$name"
      return 0
    fi
  done
  return 1
}

certificate_name() {
  local mode=$1; shift
  local existing digest slug
  existing=$(find_matching_certificate "$@" 2>/dev/null || true)
  if [[ -n "$existing" ]]; then
    printf '%s' "$existing"
    return 0
  fi
  digest=$(printf '%s\n' "$@" | LC_ALL=C sort | sha256sum | awk '{print substr($1,1,12)}')
  if [[ "$mode" == san ]]; then
    printf 'srv-san-%s' "$digest"
  else
    slug=${1//./-}
    slug=${slug:0:32}
    slug=${slug%-}
    printf 'srv-%s-%s' "$slug" "$digest"
  fi
}

issue_certificate() {
  local certname=$1; shift
  local -a domains=("$@") args=(certonly --non-interactive --agree-tos --keep-until-expiring --cert-name "$certname")
  local domain
  if [[ -n ${CERT_EMAIL:-} ]]; then args+=(--email "$CERT_EMAIL"); else args+=(--register-unsafely-without-email); fi
  if [[ "${CERT_METHOD:-1}" == 1 ]]; then
    args+=(--standalone --preferred-challenges http)
  else
    args+=(--webroot -w "$CERT_WEBROOT" --preferred-challenges http)
  fi
  for domain in "${domains[@]}"; do args+=(-d "$domain"); done
  info "Darkhast certificate baraye: ${domains[*]}"
  certbot "${args[@]}"
}

setup_deploy_hook() {
  local src="$SRV_HOME/hooks/srv-helper-deploy.sh" dest='/etc/letsencrypt/renewal-hooks/deploy/srv-helper-deploy'
  [[ -f "$src" ]] || { fail 'Deploy hook peyda nashod'; return 1; }
  install -d -m 700 /etc/srv-helper
  install -d -m 755 /etc/letsencrypt/renewal-hooks/deploy
  install -m 750 "$src" "$dest"
  touch /etc/srv-helper/deployments.tsv
  chmod 600 /etc/srv-helper/deployments.tsv
  chown root:root /etc/srv-helper/deployments.tsv
}

register_destination() {
  local name=$1 dest=$2 group=$3 conf='/etc/srv-helper/deployments.tsv' key path grp tmp
  [[ "$name" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ && "$name" != *'..'* && "$dest" == /* && "$dest" != *$'\t'* && "$dest" != *$'\n'* ]] || return 1
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
  local -a domains=("$@") successes=() failed=() destination_names=()
  local cert_live_dir=${CERT_LIVE_DIR:-/etc/letsencrypt/live}
  local certname name idx=0 rc deployed=0 destination_name
  need_root || return 1
  if [[ "$mode" != batch ]]; then
    preflight_domains "${domains[@]}" || { pause; return 1; }
  fi
  install_certbot_if_needed || { fail 'Certbot nasb nashod'; pause; return 1; }
  step 3 5 'DARYAFT CERTIFICATE'
  if [[ "$mode" == batch ]]; then
    for name in "${domains[@]}"; do
      ((idx+=1))
      info "Barrasi DNS $idx/${#domains[@]}: $name"
      preflight_domains "$name"; rc=$?
      if ((rc!=0)); then
        if [[ ${SRV_BACK_REQUESTED:-0} == 1 || ${SRV_EXIT_REQUESTED:-0} == 1 ]]; then return "$rc"; fi
        failed+=("$name")
        fail "$name DNS amade nist; domain badi check mishavad"
        continue
      fi
      certname=$(certificate_name single "$name")
      info "Darkhast certificate: $name"
      if issue_certificate "$certname" "$name" && [[ -f "$cert_live_dir/$certname/fullchain.pem" && -f "$cert_live_dir/$certname/privkey.pem" ]]; then
        successes+=("$certname")
        destination_names+=("$name")
        success "$name certificate gereft"
      else
        failed+=("$name")
        fail "$name fail shod; baghie domain ha edame darand"
      fi
    done
  else
    certname=$(certificate_name "$mode" "${domains[@]}")
    if issue_certificate "$certname" "${domains[@]}" && [[ -f "$cert_live_dir/$certname/fullchain.pem" && -f "$cert_live_dir/$certname/privkey.pem" ]]; then
      successes+=("$certname")
      if [[ "$mode" == san ]]; then
        if [[ "$certname" == srv-san-* ]]; then destination_name="san-${domains[0]}-${certname#srv-san-}"; else destination_name="san-${domains[0]}"; fi
      else
        destination_name=${domains[0]}
      fi
      destination_names+=("$destination_name")
      success 'Certificate ba movafaghiat gerefte shod'
    else
      failed+=("${domains[*]}")
    fi
  fi
  if ((${#successes[@]}==0)); then
    fail 'Hich certificate gerefte nashod. DNS, port 80 va firewall ra check konid.'
    pause
    return 1
  fi
  step 4 5 'MASIR ZAKHIRE'
  choose_destination; rc=$?
  if ((rc!=0)); then
    if [[ ${SRV_BACK_REQUESTED:-0} == 1 || ${SRV_EXIT_REQUESTED:-0} == 1 ]]; then return "$rc"; fi
    warn 'Certificate dar /etc/letsencrypt/live mojood ast; deploy anjam nashod.'
    pause
    return 1
  fi
  setup_deploy_hook || { pause; return 1; }
  step 5 5 'SABT PATH + TAMDID'
  for ((idx=0;idx<${#successes[@]};idx++)); do
    certname=${successes[$idx]}
    destination_name=${destination_names[$idx]}
    if register_destination "$certname" "$DEST_BASE/$destination_name" "$DEST_GROUP"; then
      success "Fullchain: $DEST_BASE/$destination_name/fullchain.pem"
      success "Private key: $DEST_BASE/$destination_name/privkey.pem"
      ((deployed+=1))
    else
      fail "Deploy baraye $destination_name fail shod"
    fi
  done
  info "Natije: ${#successes[@]} certificate gerefte, $deployed deploy shode, ${#failed[@]} fail."
  ((${#failed[@]}==0)) || warn "Fail: ${failed[*]}"
  info 'Renewal hook ba har tamdid movafagh, certificate ra dobare deploy mikonad.'
  info "Private key group: $DEST_GROUP | Permission: root=600, service group=640"
  pause
}

manual_ssl() {
  banner; section 'GEREFTAN SSL | YEK DOMAIN'
  local -a domains=()
  step 1 5 'DOMAIN'
  collect_domains 1 domains || return $?
  step 2 5 'RAVESH + EMAIL'
  choose_method || return $?
  choose_email || return $?
  execute_job single "${domains[@]}"
}

smart_ssl_flow() {
  local mode=$1 count max rc
  local -a domains=()
  banner
  [[ "$mode" == san ]] && section 'SAN | YEK CERTIFICATE BARAYE CHAND DOMAIN' || section 'BATCH | HAR DOMAIN YEK CERTIFICATE'
  max=50
  if [[ "$mode" == san ]]; then max=25; fi
  step 1 5 'TEDAD DOMAIN'
  prompt "Tedad domain? (1-$max)" count; rc=$?
  ((rc==0)) || return "$rc"
  if ! valid_positive_count "$count" "$max" || { [[ "$mode" == san ]] && ((10#$count<2)); }; then
    fail 'Tedad namotabar ast. SAN: 2-25 | Batch: 1-50'
    return 1
  fi
  step 2 5 'VARED KARDAN DOMAIN HA'
  collect_domains "$count" domains || return $?
  section 'KHOLASE'
  printf '  %s\n' "${domains[@]}"
  if [[ "$mode" == san ]]; then
    info 'Tamam domain ha dar yek certificate gharar migirand.'
  else
    info 'Baraye har domain yek certificate joda gerefte mishavad.'
  fi
  confirm 'Domain ha ra taeed mikonid?' || return $?
  choose_method || return $?
  choose_email || return $?
  execute_job "$mode" "${domains[@]}"
}

certificate_dashboard() {
  local choice file
  if ! command -v certbot >/dev/null 2>&1; then warn 'Hanooz certificate manager nasb nist'; return 1; fi
  section 'VASIAT CERTIFICATE HA'
  menu_line 1 'Namayesh certificate ha'
  menu_line 2 'Test tamdid khodkar'
  menu_line 3 'Barrasi file certificate'
  prompt 'Entekhab' choice || return $?
  case "$choice" in
    1) certbot certificates ;;
    2) need_root && certbot renew --dry-run ;;
    3)
      need_cmd openssl || return 1
      prompt 'Masir Fullchain' file || return $?
      if [[ -f "$file" ]]; then openssl x509 -in "$file" -noout -subject -issuer -dates -ext subjectAltName
      else fail 'File peyda nashod'; return 1; fi ;;
    *) warn 'Gozine namotabar' ;;
  esac
}

ssl_menu() {
  local choice rc
  while :; do
    [[ ${SRV_EXIT_REQUESTED:-0} == 1 ]] && return
    banner; section 'MODIRIAT SSL'
    menu_line 1 'Dasti   | Yek domain, yek certificate'
    menu_line 2 'SAN     | Chand domain, yek certificate'
    menu_line 3 'Batch   | Har domain, yek certificate joda'
    menu_line 4 'Vaziat  | Namayesh / barrasi / test tamdid'
    menu_line 0 'Bargasht'
    prompt 'Entekhab' choice; rc=$?
    if ((rc==20)); then SRV_BACK_REQUESTED=0; return; fi
    if ((rc!=0)); then return; fi
    case "$choice" in
      1) manual_ssl; rc=$? ;;
      2) smart_ssl_flow san; rc=$? ;;
      3) smart_ssl_flow batch; rc=$? ;;
      4) certificate_dashboard; rc=$?; pause ;;
      0) return ;;
      *) warn 'Gozine namotabar'; pause; rc=0 ;;
    esac
    [[ ${SRV_EXIT_REQUESTED:-0} == 1 ]] && return
    if [[ ${SRV_BACK_REQUESTED:-0} == 1 ]]; then SRV_BACK_REQUESTED=0; fi
  done
}
