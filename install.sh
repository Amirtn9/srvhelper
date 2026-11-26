#!/usr/bin/env bash
set -euo pipefail
umask 022

archive_url='https://github.com/Amirtn9/srvhelper/archive/refs/heads/main.tar.gz'
app='/opt/srv-helper'
wrapper='/usr/local/bin/srv-helper'
hook='/etc/letsencrypt/renewal-hooks/deploy/srv-helper-deploy'
files=(srv-helper.sh lib/{ui,certs,mirrors,dns,system,maintenance,tunnels,automation}.sh hooks/srv-helper-deploy.sh)
yes=0 check=0 launch=0 tty=0
accent='' green='' red='' reset=''
work='' stage='' backup='' wrapper_stage='' hook_stage=''
app_changed=0 wrapper_changed=0 hook_changed=0 committed=0

usage() {
  cat <<'HELP'
SRV Helper | Ubuntu and Debian installer

  sudo bash install.sh             Install or update with confirmation
  sudo bash install.sh --yes       Install without confirmation
  sudo bash install.sh --launch    Install and open the terminal menu
  bash install.sh --check          Check files and requirements without installing
HELP
}

fail() { printf '  %s[ERROR]%s %s\n' "$red" "$reset" "$*" >&2; exit 1; }

progress() {
  local step=$1 label=$2 filled='' empty='' i
  for ((i=1; i<=4; i++)); do
    if ((i<=step)); then filled+='###'; else empty+='---'; fi
  done
  printf '\n  %s[%s%s] %s/4%s  %s\n' "$accent" "$filled" "$empty" "$step" "$reset" "$label"
}

cleanup() {
  local status=$? restore_failed=0
  trap - EXIT INT TERM
  if (( !committed )); then
    if ((hook_changed)); then restore_file "$work/hook" "$hook" || restore_failed=1; fi
    if ((wrapper_changed)); then restore_file "$work/wrapper" "$wrapper" || restore_failed=1; fi
    if ((app_changed)); then
      rm -rf -- "$app" || restore_failed=1
      if [[ -n "$backup" ]]; then mv -T -- "$backup" "$app" || restore_failed=1; fi
    fi
  fi
  if ((restore_failed)); then
    printf '  [ERROR] Rollback incomplete. Backup location: %s %s\n' "$work" "$backup" >&2
  elif [[ -n "$work" ]]; then rm -rf -- "$work"; fi
  if [[ -n "$stage" ]]; then rm -rf -- "$stage"; fi
  if [[ -n "$wrapper_stage" ]]; then rm -f -- "$wrapper_stage"; fi
  if [[ -n "$hook_stage" ]]; then rm -f -- "$hook_stage"; fi
  exit "$status"
}

restore_file() {
  if [[ -e "$1" || -L "$1" ]]; then
    cp -aT -- "$1" "$2"
  else
    rm -f -- "$2"
  fi
}

confirm() {
  local answer
  printf '\n  %s [y/N] ' "$1"
  read -r answer || return 1
  answer=${answer%$'\r'}
  answer=${answer%"${answer##*[![:blank:]]}"}
  case "${answer,,}" in
    y|yes) return 0 ;;
    *) return 1 ;;
  esac
}

while (($#)); do
  case "$1" in
    -h|--help) usage; exit ;;
    -y|--yes) yes=1 ;;
    --check) check=1 ;;
    --launch) launch=1 ;;
    *) fail "Unknown option: $1" ;;
  esac
  shift
done
if [[ -t 0 && -t 1 ]]; then tty=1; fi
if [[ -t 1 && ${TERM:-dumb} != dumb && -z ${NO_COLOR:-} ]]; then
  accent=$'\033[1;36m'; green=$'\033[1;32m'; red=$'\033[1;31m'; reset=$'\033[0m'
fi
((!check || !launch)) || fail 'Use --check and --launch separately.'
((!launch || tty)) || fail 'Opening the menu requires an interactive terminal.'
((check || EUID == 0)) || fail 'Run sudo bash install.sh to install.'
[[ -r /etc/os-release ]] || fail 'Could not detect the Linux distribution.'
os_id=$(. /etc/os-release; printf '%s' "${ID:-}")
case "$os_id" in ubuntu|debian) ;; *) fail 'This installer supports Ubuntu and Debian.' ;; esac
command -v apt-get >/dev/null || fail 'APT is missing.'

source_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
mode='Local checkout'
if [[ ! -e "$source_dir/srv-helper.sh" ]]; then mode='GitHub archive'; fi
missing=()
command -v curl >/dev/null || missing+=(curl)
command -v python3 >/dev/null || missing+=(python3)
command -v ss >/dev/null || missing+=(iproute2)
command -v flock >/dev/null || missing+=(util-linux)
command -v tar >/dev/null || missing+=(tar)
[[ $(dpkg-query -W -f='${Status}' ca-certificates 2>/dev/null || :) == 'install ok installed' ]] || missing+=(ca-certificates)

printf '\n  %sSRV HELPER%s  /  Installer\n' "$accent" "$reset"
printf '  ----------------------------------------\n'
printf '  OS          %s\n  Source      %s\n  Destination %s\n' "$os_id" "$mode" "$app"
if (("${#missing[@]}")); then printf '  Required packages: %s\n' "${missing[*]}"; fi
if ((!check && !yes)); then
  ((tty)) || fail 'Pass --yes for non-interactive installation.'
  if ! confirm 'Install or update SRV Helper?'; then
    printf '  Installation cancelled.\n'
    exit 0
  fi
fi

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
progress 1 'Check requirements'
if (("${#missing[@]}")); then
  ((!check)) || fail 'Install the listed packages and rerun the check.'
  DEBIAN_FRONTEND=noninteractive apt-get -o APT::Update::Error-Mode=any update ||
    fail 'APT update failed. Check connectivity to your configured APT repositories.'
  DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}" ||
    fail 'Could not install the required packages.'
fi

progress 2 'Prepare and validate source files'
if [[ ! -e "$source_dir/srv-helper.sh" ]]; then
  work=$(mktemp -d)
  curl --proto '=https' --proto-redir '=https' --tlsv1.2 --fail --silent --show-error --location \
    --connect-timeout 15 --max-time 120 --retry 2 --output "$work/source.tar.gz" "$archive_url" ||
    fail 'GitHub download failed. See the README for ZIP installation.'
  mkdir -- "$work/source"
  tar -xzf "$work/source.tar.gz" --no-same-owner --no-same-permissions --strip-components=1 -C "$work/source"
  source_dir="$work/source"
fi
for file in "${files[@]}"; do
  [[ -f "$source_dir/$file" && ! -L "$source_dir/$file" ]] || fail "Missing or invalid file: $file"
  bash -n "$source_dir/$file" || fail "Shell syntax error: $file"
done
if ((check)); then printf '\n  %s[OK]%s Source files and requirements passed.\n' "$green" "$reset"; exit 0; fi

progress 3 'Stage files and back up the existing installation'
exec 9>/run/lock/srv-helper-install.lock
flock -n 9 || fail 'Another installation is in progress.'
if [[ -z "$work" ]]; then work=$(mktemp -d); fi
stage=$(mktemp -d /opt/.srv-helper.XXXXXXXX)
chmod 755 "$stage"
install -d -m 755 "$stage/lib" "$stage/hooks" "$(dirname "$wrapper")" "$(dirname "$hook")"
for file in "${files[@]}"; do install -m 644 "$source_dir/$file" "$stage/$file"; done
chmod 755 "$stage/srv-helper.sh"
chmod 750 "$stage/hooks/srv-helper-deploy.sh"
wrapper_stage=$(mktemp "$(dirname "$wrapper")/.srv-helper.XXXXXXXX")
hook_stage=$(mktemp "$(dirname "$hook")/.srv-helper.XXXXXXXX")
cat > "$wrapper_stage" <<'WRAPPER'
#!/usr/bin/env bash
exec /opt/srv-helper/srv-helper.sh "$@"
WRAPPER
chmod 755 "$wrapper_stage"
install -m 750 "$stage/hooks/srv-helper-deploy.sh" "$hook_stage"
for path in "$wrapper" "$hook"; do
  [[ ! -d "$path" || -L "$path" ]] || fail "Expected a file but found a directory: $path"
done
if [[ -e "$wrapper" || -L "$wrapper" ]]; then cp -a -- "$wrapper" "$work/wrapper"; fi
if [[ -e "$hook" || -L "$hook" ]]; then cp -a -- "$hook" "$work/hook"; fi

progress 4 'Activate and verify the command'
if [[ -e "$app" || -L "$app" ]]; then
  previous="$app.previous.$(date -u +%Y%m%dT%H%M%SZ).$$"
  mv -T -- "$app" "$previous"
  backup=$previous
fi
app_changed=1
mv -T -- "$stage" "$app"
stage=''
wrapper_changed=1
mv -T -- "$wrapper_stage" "$wrapper"
wrapper_stage=''
hook_changed=1
mv -T -- "$hook_stage" "$hook"
hook_stage=''
version=$("$wrapper" --version) || fail 'The installed command failed to start.'
committed=1
flock -u 9

printf '\n  %s[OK]%s Installed: %s\n' "$green" "$reset" "$version"
if [[ -n "$backup" ]]; then printf '  Previous version: %s\n' "$backup"; fi
printf '  To start: sudo srv-helper\n'
if ((tty && !yes && !launch)); then
  if confirm 'Open the menu now?'; then launch=1; fi
fi
if ((launch)); then "$wrapper"; fi
