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
(
  dpkg() { printf '%s\n' amd64; }
  [[ "$(mirror_candidates iran | wc -l)" -ge 18 ]]
  [[ "$(mirror_candidates europe | wc -l)" -ge 3 ]]
  [[ "$(mirror_candidates usa | wc -l)" -ge 2 ]]
  dpkg() { printf '%s\n' arm64; }
  [[ "$(mirror_candidates iran)" == 'https://ports.ubuntu.com/ubuntu-ports' ]]
)
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

# A resolver with partial answers must never become a recommended server.
(
  dns_candidate_records() { printf '%s\n' 'Full|192.0.2.1' 'Partial|192.0.2.2'; }
  dig() {
    if [[ "$*" == *'@192.0.2.2'* && "$*" != *'example.com'* ]]; then
      return 1
    fi
    printf '%s\n' '192.0.2.10'
  }
  result=$(rank_dns_servers iran)
  [[ "$result" == '3|'*'|Full|192.0.2.1' ]]
)

# Release metadata must identify the requested suite and support the local APT architecture.
(
  dpkg() { printf '%s\n' amd64; }
  curl() {
    while [[ "$1" != -o ]]; do shift; done
    printf '%s\n' "$release" > "$2"
    printf '%s' '0.05'
  }
  release=$'Codename: jammy\nArchitectures: amd64 arm64'
  [[ "$(mirror_probe https://example.com/ubuntu jammy)" == '0.05' ]]
  release=$'Codename: noble\nArchitectures: amd64'
  ! mirror_probe https://example.com/ubuntu jammy
  release=$'Codename: jammy\nArchitectures: arm64'
  ! mirror_probe https://example.com/ubuntu jammy
  release='<html>OK</html>'
  ! mirror_probe https://example.com/ubuntu jammy
)

# Mirror ranking keeps the measured latency and returns fastest first.
mirror_candidates() { printf '%s\n' 'https://one.example/ubuntu' 'https://two.example/ubuntu'; }
mirror_probe() { case "$1" in *one*) printf '0.20';; *two*) printf '0.05';; esac; }
ranking=$(rank_mirrors test jammy 2>/dev/null)
[[ "$(printf '%s\n' "$ranking" | head -1)" == '0.05|https://two.example/ubuntu' ]]

# The tenth entry can be selected, and the results omit the eleventh.
(
  rank_mirrors() {
    local i
    for ((i=1; i<=11; i++)); do
      printf '0.%02d|https://mirror%s.example/ubuntu\n' "$i" "$i"
    done
  }
  output=$(
    select_ranked_mirror selected iran noble ubuntu <<< '10'
    printf '\nSelected: %s\n' "$selected"
  )
  [[ "$output" == *'100 ms  |  https://mirror10.example/ubuntu'* ]]
  [[ "$output" == *'Selected: https://mirror10.example/ubuntu'* ]]
  [[ "$output" != *'mirror11.example'* ]]
  if select_ranked_mirror selected iran noble ubuntu <<< '0' >/dev/null; then exit 1; fi
)

# APT planning includes active pockets and leaves unrelated or disabled stanzas alone.
(
  tmp=$(mktemp -d)
  trap 'rm -rf -- "$tmp"' EXIT
  apt_source_files() { printf '%s\n' "$tmp/custom.sources" "$tmp/custom.list"; }
  state_dir() { printf '%s/state\n' "$tmp"; }
  cat > "$tmp/custom.sources" <<'SOURCES'
Types: deb
URIs: https://archive.ubuntu.com/ubuntu/
Suites: noble
 noble-updates
Components: main

Types: deb
URIs: https://security.ubuntu.com/ubuntu/
Suites: noble-security

Types: deb
URIs: https://archive.ubuntu.com/ubuntu/
Suites: noble-proposed
Enabled: no
SOURCES
  printf '%s\n' 'deb [signed-by=/usr/share/keyrings/test.gpg] https://archive.ubuntu.com/ubuntu noble-backports main # example' > "$tmp/custom.list"
  [[ "$(apt_archive_plan ubuntu --suites)" == $'noble\nnoble-backports\nnoble-updates' ]]
  apt_archive_plan ubuntu --apply 'https://mirror.example/ubuntu'
  grep -Fx 'URIs: https://mirror.example/ubuntu' "$tmp/custom.sources" >/dev/null
  grep -Fx 'URIs: https://security.ubuntu.com/ubuntu/' "$tmp/custom.sources" >/dev/null
  grep -Fx 'URIs: https://archive.ubuntu.com/ubuntu/' "$tmp/custom.sources" >/dev/null
  grep -Fx 'deb [signed-by=/usr/share/keyrings/test.gpg] https://mirror.example/ubuntu noble-backports main # example' "$tmp/custom.list" >/dev/null
)

# Smart Setup must propagate a cancellation returned by a subshell.
(
  need_root() { return 0; }
  choose_auto_region() { printf -v "$1" '%s' iran; }
  confirm() { return 0; }
  ensure_dig() { return 0; }
  rank_dns_servers() { printf '3|10|Mock DNS|192.0.2.53\n'; }
  apply_dns() ( return 21; )
  select_ranked_mirror() { exit 99; }
  smart_auto_optimize >/dev/null
  [[ "$SRV_EXIT_REQUESTED" == 1 ]]
)

# An APT restore must recover the current sources if refreshing indexes fails.
(
  tmp=$(mktemp -d)
  trap 'rm -rf -- "$tmp"' EXIT
  mkdir -p "$tmp/etc/apt" "$tmp/state" "$tmp/backups/apt-old$tmp/etc/apt"
  source <(sed "s@/etc/apt@$tmp/etc/apt@g" "$home/lib/mirrors.sh")
  need_root() { return 0; }
  state_dir() { printf '%s/state' "$tmp"; }
  backup_dir() { printf '%s/backups' "$tmp"; }
  choose_menu() { printf -v "$1" '%s' 1; }
  confirm() { return 0; }
  apt-get() { return 1; }
  printf 'current\n' > "$tmp/etc/apt/sources.list"
  printf 'old\n' > "$tmp/backups/apt-old$tmp/etc/apt/sources.list"
  printf 'current-mirror\n' > "$tmp/state/last-mirror"
  if restore_mirror >/dev/null 2>&1; then exit 1; fi
  [[ "$(cat "$tmp/etc/apt/sources.list")" == current ]]
  [[ "$(cat "$tmp/state/last-mirror")" == current-mirror ]]
)

# Failed runtime writes must leave persistent sysctl files alone.
(
  tmp=$(mktemp -d)
  trap 'rm -rf -- "$tmp"' EXIT
  mkdir -p "$tmp/sysctl.d"
  source <(sed "s@/etc/sysctl.d@$tmp/sysctl.d@g" "$home/lib/system.sh")
  need_root() { return 0; }
  state_dir() { printf '%s/state' "$tmp"; }
  confirm() { return 0; }
  sysctl() { if [[ "$1" == -n ]]; then printf '0\n'; else return 1; fi; }
  printf 'net.ipv4.icmp_echo_ignore_all = 0\n' > "$tmp/sysctl.d/90-srv-helper.conf"
  if set_sysctl_option net.ipv4.icmp_echo_ignore_all 1 >/dev/null 2>&1; then exit 1; fi
  [[ "$(cat "$tmp/sysctl.d/90-srv-helper.conf")" == 'net.ipv4.icmp_echo_ignore_all = 0' ]]
)

# Mirror Lab reports download rate only for a complete bounded response.
(
  dpkg() { printf 'amd64\n'; }
  curl() {
    while (($#)); do
      case "$1" in
        --range) printf '206 131072 65536'; return ;;
        -o)
          printf 'Date: Thu, 26 Nov 2026 01:00:00 UTC\nSHA256:\n hash 200000 main/binary-amd64/Packages.xz\n' > "$2"
          return ;;
      esac
      shift
    done
    return 1
  }
  result=$(mirror_lab_sample https://example.com/ubuntu noble)
  [[ "$result" == *'Release metadata:'*'128 KiB package-index sample: 64 KiB/s'* ]]
)

# The real menu must accept the reported hostname and reach the validation-method screen.
ssl_menu_output=$(printf '1\n1\npl24.pingyar.com\nback\n0\n0\n' | env NO_COLOR=1 NO_CLEAR=1 bash "$home/srv-helper.sh" 2>&1)
[[ "$ssl_menu_output" == *'RAVESH TAEED DOMAIN'* ]]
[[ "$ssl_menu_output" != *'Domain namotabar'* ]]

# Prompt navigation commands are recognized.
back_rc=$(printf 'back\n' | bash -c 'source "$1/lib/ui.sh"; prompt test value >/dev/null; echo $?' _ "$home")
[[ "$back_rc" == 20 ]]
exit_rc=$(printf 'exit\n' | bash -c 'source "$1/lib/ui.sh"; prompt test value >/dev/null; echo "$?:$SRV_EXIT_REQUESTED"' _ "$home")
[[ "$exit_rc" == '21:1' ]]

# Dashboard meters also remain legible without color and with missing metrics.
[[ "$(resource_meter CPU 100 '4 logical CPUs')" == *'[################] 100%'* ]]
[[ "$(resource_meter CPU 0 '')" == *'[----------------]   0%'* ]]
[[ "$(resource_meter CPU '' '')" == *'[----------------]   --'* ]]
bash "$home/install.sh" --help | grep -- '--check' >/dev/null

# DNS must replace a stale resolver path and roll both files back on a routing conflict.
(
  fixture=$(mktemp -d)
  trap 'rm -rf -- "$fixture"' EXIT
  state_dir() { printf '%s/state' "$fixture"; }
  backup_dir() { printf '%s/backups' "$fixture"; }
  dns_resolv_file() { printf '%s/resolv.conf' "$fixture"; }
  dns_resolved_file() { printf '%s/resolved.d/helper.conf' "$fixture"; }
  dns_stub_file() { printf '%s/stub.conf' "$fixture"; }
  need_root() { return 0; }
  confirm() { return 0; }
  timeout() { shift; "$@"; }
  dig() { printf '192.0.2.1\n'; }
  getent() { return 0; }
  systemctl() { return 0; }
  resolvectl() {
    case "$1" in
      dns) printf 'Global: 8.8.8.8 8.8.4.4\nLink 2 (eth0): 192.0.2.53\n' ;;
      domain)
        printf 'Global: ~.\n'
        if [[ ${conflict:-0} == 1 ]]; then printf 'Link 2 (eth0): vendor.local ~.\n'; fi
        ;;
    esac
  }
  printf 'nameserver 192.0.2.53\n' > "$fixture/old"
  cp "$fixture/old" "$fixture/resolv.conf"
  printf 'nameserver 127.0.0.53\n' > "$fixture/stub.conf"
  conflict=1
  if apply_dns Google '8.8.8.8 8.8.4.4' >/dev/null 2>&1; then exit 1; fi
  cmp "$fixture/old" "$fixture/resolv.conf"
  [[ ! -e "$fixture/resolved.d/helper.conf" ]]
  conflict=0
  apply_dns Google '8.8.8.8 8.8.4.4' >/dev/null
  [[ "$(readlink "$fixture/resolv.conf")" == "$fixture/stub.conf" ]]
  grep -Fx 'DNS=8.8.8.8 8.8.4.4' "$fixture/resolved.d/helper.conf" >/dev/null

  rm "$fixture/resolv.conf"
  cp "$fixture/old" "$fixture/resolv.conf"
  dns_resolved_active() { return 1; }
  apply_dns Google '8.8.8.8 8.8.4.4' >/dev/null
  grep -Fx 'nameserver 8.8.8.8' "$fixture/resolv.conf" >/dev/null
  if grep -q '192.0.2.53' "$fixture/resolv.conf"; then exit 1; fi
)

# The migration wizard must be reachable and reject unsafe restore scope and SSH operands.
migration_screen=$(printf '6\n0\n0\n' | NO_COLOR=1 bash "$home/srv-helper.sh")
[[ "$migration_screen" == *'BACKUP VA ENTEGHAL SERVER'* ]]
(
  source "$home/lib/migration.sh"
  info() { :; }
  fail() { :; }
  ssh() { exit 99; }
  if migration_remote postgres '16;invalid'; then exit 1; fi
  fixture=$(mktemp)
  trap 'rm -f -- "$fixture"' EXIT
  printf 'DATA=/etc\n' > "$fixture"
  if migration_preflight_restore "$fixture"; then exit 1; fi
)
bash "$home/lib/migration-remote.sh" unsupported >/dev/null 2>&1 && exit 1

# Backup-only operation can be followed by an archive restore without the SSH source.
(
  source "$home/lib/migration.sh"
  fixture=$(mktemp -d)
  trap 'rm -rf -- "$fixture"' EXIT
  mkdir "$fixture/input" "$fixture/output" "$fixture/bad"
  migration_path_supported /opt/example
  migration_path_supported /home/example
  if migration_path_supported /opt/srv-helper; then exit 1; fi
  if migration_path_supported /home/example/.ssh; then exit 1; fi
  cd "$fixture/input"
  for name in inventory packages.tsv services.txt mounts.txt root.tar.gz; do printf '%s\n' "$name" > "$name"; done
  sha256sum inventory packages.tsv services.txt mounts.txt root.tar.gz > SHA256SUMS
  tar -cf "$fixture/good.tar" inventory packages.tsv services.txt mounts.txt root.tar.gz SHA256SUMS
  migration_unpack_bundle "$fixture/good.tar" "$fixture/output"
  cmp inventory "$fixture/output/inventory"
  printf 'tampered\n' > inventory
  tar -cf "$fixture/bad.tar" inventory packages.tsv services.txt mounts.txt root.tar.gz SHA256SUMS
  if migration_unpack_bundle "$fixture/bad.tar" "$fixture/bad" >/dev/null 2>&1; then exit 1; fi
)

# Terminal UI is ASCII/Finglish. Check branding in loaded modules only.
if LC_ALL=C grep -nP '[^\x00-\x7F]' "$home"/srv-helper.sh "$home"/install.sh "$home"/hooks/*.sh "$home"/lib/*.sh; then
  echo 'FAIL non-ASCII interface strings' >&2; exit 1
fi
if grep -nEi 'behzad|netoptix|syshelper|mexenon|alinezamifar|mhsanaei' "$home"/srv-helper.sh "$home"/install.sh "$home"/lib/{ui,certs,mirrors,dns,system,maintenance,tunnels,automation}.sh; then
  echo 'FAIL third-party author/project name in interactive scripts' >&2; exit 1
fi
[[ -s "$home/assets/srv-helper-banner.png" ]]
grep -q 'sudo srv-helper' "$home/README.md"
grep -q 'sudo srv-helper' "$home/README_FA.md"
grep -q 'assets/srv-helper-banner.png' "$home/README.md"
grep -q 'assets/srv-helper-banner.png' "$home/README_FA.md"
printf 'OK: syntax, domain input, SAN/Batch flow, DNS, mirrors, navigation, UI, README\n'
