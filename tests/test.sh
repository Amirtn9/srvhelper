#!/usr/bin/env bash
set -euo pipefail
home=$(cd -- "$(dirname "$0")/.." && pwd -P)
for f in "$home"/srv-helper.sh "$home"/install.sh "$home"/hooks/*.sh "$home"/lib/*.sh; do bash -n "$f"; done
SRV_HOME=$home
SRV_VERSION='1.0.0'
# shellcheck source=/dev/null
source "$home/lib/ui.sh"
source "$home/lib/certs.sh"
source "$home/lib/mirrors.sh"
source "$home/lib/dns.sh"
source "$home/lib/system.sh"
assert_valid() { valid_domain "$1" || { echo "FAIL valid: $1" >&2; exit 1; }; }
assert_invalid() { if valid_domain "$1"; then echo "FAIL invalid: $1" >&2; exit 1; fi; }
assert_valid 'example.com'
assert_valid 'www.a-long-domain.co.uk'
assert_valid 'xn--mgbh0fb.xn--kgbechtv'
assert_invalid 'bad domain.com'
assert_invalid '..example.com'
assert_invalid '-x.example.com'
assert_invalid 'x-.example.com'
assert_invalid 'example'
assert_invalid '*.example.com'
assert_invalid '127.0.0.1'
assert_invalid "$(printf 'a%.0s' {1..64}).com"
valid_positive_count '5' 25
if valid_positive_count '55' 25; then echo 'FAIL count' >&2; exit 1; fi
[[ "$(dns_profile shecan)" == '178.22.122.100 185.51.200.2' ]]
[[ "$(mirror_candidates iran | wc -l)" -ge 18 ]]
[[ "$(mirror_candidates europe | wc -l)" -ge 3 ]]
[[ "$(mirror_candidates usa | wc -l)" -ge 2 ]]
[[ "$(bash "$home/srv-helper.sh" --version)" == 'SRV Helper 1.0.0' ]]
# Certbot receives one -d per SAN name, with no shell evaluation.
argsfile=$(mktemp)
certbot() { printf '%s\n' "$@" > "$argsfile"; }
CERT_METHOD=1 CERT_EMAIL=''
issue_certificate 'srv-helper-test.example.com' 'srv-helper-test.example.com' 'alternate.example.net' >/dev/null
[[ "$(grep -c -x -- '-d' "$argsfile")" == '2' ]]
grep -q -x 'alternate.example.net' "$argsfile"
grep -q -x -- '--standalone' "$argsfile"
CERT_METHOD=2 CERT_WEBROOT='/var/www/html'
issue_certificate 'srv-helper-test.example.com' 'srv-helper-test.example.com' >/dev/null
grep -q -x -- '--webroot' "$argsfile"
rm -f "$argsfile"
# Mirror ranking must output only URLs, sorted by probe result.
mirror_candidates() { printf '%s\n' 'https://one.example/ubuntu' 'https://two.example/ubuntu'; }
mirror_probe() { case "$1" in *one*) printf '0.20';; *two*) printf '0.05';; esac; }
ranking=$(rank_mirrors test jammy 2>/dev/null)
[[ "$(printf '%s\n' "$ranking" | head -1)" == 'https://two.example/ubuntu' ]]
if LC_ALL=C grep -nP '[^\x00-\x7F]' "$home"/srv-helper.sh "$home"/lib/*.sh "$home"/hooks/*.sh "$home"/install.sh; then
  echo 'FAIL non-ASCII interface strings' >&2; exit 1
fi
printf 'OK: syntax, domain checks, counts, SAN arguments, mirror ranking, DNS profiles, ASCII UI, version\n'
