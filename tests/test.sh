#!/usr/bin/env bash
set -euo pipefail
home=$(cd -- "$(dirname -- "$0")/.." && pwd -P)
for f in "$home"/srv-helper.sh "$home"/install.sh "$home"/hooks/*.sh "$home"/lib/*.sh; do bash -n "$f"; done
SRV_HOME=$home
SRV_VERSION='1.0.0'
for module in ui certs mirrors dns system maintenance tunnels automation; do source "$home/lib/$module.sh"; done

assert_valid() { valid_domain "$1" || { echo "FAIL valid: $1" >&2; exit 1; }; }
assert_invalid() { if valid_domain "$1"; then echo "FAIL invalid: $1" >&2; exit 1; fi; }
assert_valid 'example.com'
assert_valid 'www.a-long-domain.co.uk'
assert_valid 'xn--mgbh0fb.xn--kgbechtv'
assert_valid 'pl24.pingyar.com'
assert_valid 'node-2.sub.example.net'
assert_invalid 'bad domain.com'
assert_invalid '..example.com'
assert_invalid '-x.example.com'
assert_invalid 'x-.example.com'
assert_invalid 'example'
assert_invalid '*.example.com'
assert_invalid '127.0.0.1'
assert_invalid 'a..example.com'
assert_invalid "$(printf 'a%.0s' {1..64}).com"
[[ "$(normalize_domain '  PL24.PINGYAR.COM.  ')" == 'pl24.pingyar.com' ]]
[[ "$(normalize_domain 'https://pl24.pingyar.com/')" == 'pl24.pingyar.com' ]]
[[ "$(normalize_domain 'pl24.pingyar.com')" == 'pl24.pingyar.com' ]]

# Regression test: prompt must assign to the caller's variable (the old raw/raw collision).
collected=$(printf 'pl24.pingyar.com\n' | bash -c 'set -e; source "$1/lib/ui.sh"; source "$1/lib/certs.sh"; domains=(); collect_domains 1 domains >/dev/null; printf "%s" "${domains[0]}"' _ "$home")
[[ "$collected" == 'pl24.pingyar.com' ]]
collected=$(printf '  PL24.PINGYAR.COM.  \r\n' | bash -c 'set -e; source "$1/lib/ui.sh"; source "$1/lib/certs.sh"; domains=(); collect_domains 1 domains >/dev/null; printf "%s" "${domains[0]}"' _ "$home")
[[ "$collected" == 'pl24.pingyar.com' ]]

valid_positive_count '5' 25
if valid_positive_count '55' 25; then echo 'FAIL count' >&2; exit 1; fi
[[ "$(dns_profile shecan)" == '178.22.122.100 185.51.200.2' ]]
[[ "$(dns_profile tic)" == '217.218.155.155 217.218.127.127' ]]
[[ "$(dns_candidate_records iran | wc -l)" -ge 30 ]]
! dns_candidate_records global | grep -q 'TIC-IR'
[[ "$(mirror_candidates iran | wc -l)" -ge 18 ]]
[[ "$(mirror_candidates europe | wc -l)" -ge 3 ]]
[[ "$(mirror_candidates usa | wc -l)" -ge 2 ]]
[[ "$(mirror_candidates iran debian | wc -l)" -ge 4 ]]
[[ "$(mirror_candidates europe debian | wc -l)" -ge 4 ]]
[[ "$(region_from_country IR)" == iran ]]
[[ "$(region_from_country US)" == usa ]]
[[ "$(region_from_country TR)" == europe ]]
[[ "$(bash "$home/srv-helper.sh" --version)" == 'SRV Helper 1.0.0' ]]

# Certbot argument construction: SAN domains stay separate and safely quoted.
argsfile=$(mktemp)
certbot() { printf '%s\n' "$@" > "$argsfile"; }
CERT_METHOD=1 CERT_EMAIL=''
issue_certificate 'srv-san-123456789abc' 'pl24.pingyar.com' 'api.pingyar.com' 'www.pingyar.com' 'cdn.pingyar.com' 'status.pingyar.com' >/dev/null
[[ "$(grep -c -x -- '-d' "$argsfile")" == '5' ]]
grep -q -x 'api.pingyar.com' "$argsfile"
grep -q -x 'status.pingyar.com' "$argsfile"
grep -q -x -- '--standalone' "$argsfile"
CERT_METHOD=2 CERT_WEBROOT='/var/www/html'
issue_certificate 'pl24.pingyar.com' 'pl24.pingyar.com' >/dev/null
grep -q -x -- '--webroot' "$argsfile"
grep -q -x '/var/www/html' "$argsfile"
[[ "$(certificate_name san 'pl24.pingyar.com' 'api.pingyar.com')" == "$(certificate_name san 'api.pingyar.com' 'pl24.pingyar.com')" ]]
single_name=$(certificate_name single 'pl24.pingyar.com')
[[ "$single_name" == srv-pl24-pingyar-com-* ]]
[[ "$(certificate_name batch 'pl24.pingyar.com')" == "$single_name" ]]
renewal_dir=$(mktemp -d)
printf '[renewalparams]\ndomains = api.pingyar.com, pl24.pingyar.com\n' > "$renewal_dir/legacy-san.conf"
[[ "$(CERT_RENEWAL_DIR="$renewal_dir" certificate_name san 'pl24.pingyar.com' 'api.pingyar.com')" == 'legacy-san' ]]
rm -rf "$renewal_dir"
rm -f "$argsfile"

# End-to-end flow tests with mocked Certbot: SAN is one request, Batch is one request per domain.
(
  tmp=$(mktemp -d /tmp/srv-helper-cert-test.XXXXXX)
  trap 'rm -rf "$tmp"' EXIT
  CERT_LIVE_DIR="$tmp/live"
  CERT_RENEWAL_DIR="$tmp/renewal"
  mkdir -p "$CERT_LIVE_DIR" "$CERT_RENEWAL_DIR"
  SRV_BACK_REQUESTED=0 SRV_EXIT_REQUESTED=0
  need_root() { return 0; }
  preflight_domains() { printf '%s\n' "$*" >> "$tmp/preflight.log"; return 0; }
  install_certbot_if_needed() { return 0; }
  issue_certificate() {
    local certname=$1; shift
    printf '%s|%s\n' "$certname" "$*" >> "$tmp/issue.log"
    mkdir -p "$CERT_LIVE_DIR/$certname"
    : > "$CERT_LIVE_DIR/$certname/fullchain.pem"
    : > "$CERT_LIVE_DIR/$certname/privkey.pem"
    return 0
  }
  choose_destination() { DEST_BASE="$tmp/destination"; DEST_GROUP=root; return 0; }
  setup_deploy_hook() { return 0; }
  register_destination() { printf '%s|%s|%s\n' "$1" "$2" "$3" >> "$tmp/deploy.log"; return 0; }
  pause() { :; }
  CERT_METHOD=1 CERT_EMAIL=''
  execute_job san a.example.com b.example.com c.example.com d.example.com e.example.com >/dev/null
  [[ "$(wc -l < "$tmp/issue.log")" == '1' ]]
  [[ "$(wc -l < "$tmp/preflight.log")" == '1' ]]
  [[ "$(wc -l < "$tmp/deploy.log")" == '1' ]]
  rm -f "$tmp/issue.log" "$tmp/preflight.log" "$tmp/deploy.log"
  execute_job batch a.example.com b.example.com c.example.com >/dev/null
  [[ "$(wc -l < "$tmp/issue.log")" == '3' ]]
  [[ "$(wc -l < "$tmp/preflight.log")" == '3' ]]
  [[ "$(wc -l < "$tmp/deploy.log")" == '3' ]]
)

# Mirror ranking returns only validated URLs and sorts by measured latency.
mirror_candidates() { printf '%s\n' 'https://one.example/ubuntu' 'https://two.example/ubuntu'; }
mirror_probe() { case "$1" in *one*) printf '0.20';; *two*) printf '0.05';; esac; }
ranking=$(rank_mirrors test jammy 2>/dev/null)
[[ "$(printf '%s\n' "$ranking" | head -1)" == 'https://two.example/ubuntu' ]]

# The real menu must accept the reported hostname and reach the validation-method screen.
ssl_menu_output=$(printf '1\n1\npl24.pingyar.com\nback\n0\n0\n' | env NO_COLOR=1 NO_CLEAR=1 bash "$home/srv-helper.sh" 2>&1)
[[ "$ssl_menu_output" == *'RAVESH TAEED DOMAIN'* ]]
[[ "$ssl_menu_output" != *'Domain namotabar'* ]]

# Prompt navigation commands are recognized.
back_rc=$(printf 'back\n' | bash -c 'source "$1/lib/ui.sh"; prompt test value >/dev/null; echo $?' _ "$home")
[[ "$back_rc" == 20 ]]
exit_rc=$(printf 'exit\n' | bash -c 'source "$1/lib/ui.sh"; prompt test value >/dev/null; echo "$?:$SRV_EXIT_REQUESTED"' _ "$home")
[[ "$exit_rc" == '21:1' ]]

# Terminal UI is ASCII/Finglish, compact and does not mention other project authors.
if LC_ALL=C grep -nP '[^\x00-\x7F]' "$home"/srv-helper.sh "$home"/install.sh "$home"/hooks/*.sh "$home"/lib/*.sh; then
  echo 'FAIL non-ASCII interface strings' >&2; exit 1
fi
if grep -nEi 'behzad|netoptix|syshelper|mexenon|alinezamifar|mhsanaei' "$home"/srv-helper.sh "$home"/install.sh "$home"/lib/*.sh; then
  echo 'FAIL third-party author/project name in interactive scripts' >&2; exit 1
fi
[[ -s "$home/assets/srv-helper-banner.png" ]]
grep -q 'sudo srv-helper' "$home/README.md"
grep -q 'sudo srv-helper' "$home/README_FA.md"
grep -q 'assets/srv-helper-banner.png' "$home/README.md"
grep -q 'assets/srv-helper-banner.png' "$home/README_FA.md"
printf 'OK: syntax, domain input, SAN/Batch flow, DNS, mirrors, navigation, UI, README\n'
