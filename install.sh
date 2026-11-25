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
SRV Helper | نصب‌کنندهٔ Ubuntu و Debian

  sudo bash install.sh             نصب یا به‌روزرسانی با تأیید کاربر
  sudo bash install.sh --yes       نصب بدون سؤال
  sudo bash install.sh --launch    نصب و اجرای منو در ترمینال
  bash install.sh --check          بررسی فایل‌ها و پیش‌نیازها بدون نصب
HELP
}

fail() { printf '  %s[خطا]%s %s\n' "$red" "$reset" "$*" >&2; exit 1; }

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
    printf '  [خطا] بازگردانی کامل نشد. مسیر پشتیبان: %s %s\n' "$work" "$backup" >&2
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

while (($#)); do
  case "$1" in
    -h|--help) usage; exit ;;
    -y|--yes) yes=1 ;;
    --check) check=1 ;;
    --launch) launch=1 ;;
    *) fail "گزینهٔ ناشناخته: $1" ;;
  esac
  shift
done
if [[ -t 0 && -t 1 ]]; then tty=1; fi
if [[ -t 1 && ${TERM:-dumb} != dumb && -z ${NO_COLOR:-} ]]; then
  accent=$'\033[1;36m'; green=$'\033[1;32m'; red=$'\033[1;31m'; reset=$'\033[0m'
fi
((!check || !launch)) || fail 'گزینه‌های --check و --launch هم‌زمان قابل استفاده نیستند.'
((!launch || tty)) || fail 'اجرای منو به یک ترمینال تعاملی نیاز دارد.'
((check || EUID == 0)) || fail 'برای نصب از sudo bash install.sh استفاده کنید.'
[[ -r /etc/os-release ]] || fail 'توزیع لینوکس شناسایی نشد.'
os_id=$(. /etc/os-release; printf '%s' "${ID:-}")
case "$os_id" in ubuntu|debian) ;; *) fail 'نصب‌کننده فقط Ubuntu و Debian را پشتیبانی می‌کند.' ;; esac
command -v apt-get >/dev/null || fail 'مدیر بستهٔ APT در دسترس نیست.'

source_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
mode='فایل‌های محلی'
if [[ ! -e "$source_dir/srv-helper.sh" ]]; then mode='دانلود از GitHub'; fi
missing=()
command -v curl >/dev/null || missing+=(curl)
command -v python3 >/dev/null || missing+=(python3)
command -v ss >/dev/null || missing+=(iproute2)
command -v flock >/dev/null || missing+=(util-linux)
command -v tar >/dev/null || missing+=(tar)
[[ $(dpkg-query -W -f='${Status}' ca-certificates 2>/dev/null || :) == 'install ok installed' ]] || missing+=(ca-certificates)

printf '\n  %sSRV HELPER%s  /  نصب‌کننده\n' "$accent" "$reset"
printf '  ----------------------------------------\n'
printf '  توزیع    %s\n  منبع     %s\n  مقصد     %s\n' "$os_id" "$mode" "$app"
if (("${#missing[@]}")); then printf '  بسته‌های لازم: %s\n' "${missing[*]}"; fi
if ((!check && !yes)); then
  ((tty)) || fail 'برای اجرای غیرتعاملی گزینهٔ --yes را اضافه کنید.'
  printf '\n  نصب یا به‌روزرسانی انجام شود؟ [y/N] '
  IFS= read -r answer || exit 0
  case "${answer,,}" in y|yes|بله) ;; *) printf '  نصب لغو شد.\n'; exit 0 ;; esac
fi

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
progress 1 'بررسی پیش‌نیازها'
if (("${#missing[@]}")); then
  ((!check)) || fail 'برای بررسی کامل، بسته‌های نمایش‌داده‌شده باید موجود باشند.'
  DEBIAN_FRONTEND=noninteractive apt-get -o APT::Update::Error-Mode=any update ||
    fail 'به‌روزرسانی فهرست بسته‌ها ناموفق بود. اتصال به مخازن APT سرور را بررسی کنید.'
  DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}" ||
    fail 'نصب پیش‌نیازها ناموفق بود.'
fi

progress 2 'آماده‌سازی و بررسی فایل‌ها'
if [[ ! -e "$source_dir/srv-helper.sh" ]]; then
  work=$(mktemp -d)
  curl --proto '=https' --proto-redir '=https' --tlsv1.2 --fail --silent --show-error --location \
    --connect-timeout 15 --max-time 120 --retry 2 --output "$work/source.tar.gz" "$archive_url" ||
    fail 'دانلود GitHub ناموفق بود. مسیر نصب با فایل ZIP را در README ببینید.'
  mkdir -- "$work/source"
  tar -xzf "$work/source.tar.gz" --no-same-owner --no-same-permissions --strip-components=1 -C "$work/source"
  source_dir="$work/source"
fi
for file in "${files[@]}"; do
  [[ -f "$source_dir/$file" && ! -L "$source_dir/$file" ]] || fail "فایل معتبر پیدا نشد: $file"
  bash -n "$source_dir/$file" || fail "خطای نحوی: $file"
done
if ((check)); then printf '\n  %s[OK]%s بررسی پیش‌نیازها و فایل‌ها کامل شد.\n' "$green" "$reset"; exit 0; fi

progress 3 'آماده‌سازی نصب و نسخهٔ پشتیبان'
exec 9>/run/lock/srv-helper-install.lock
flock -n 9 || fail 'یک نصب دیگر در حال اجراست.'
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
  [[ ! -d "$path" || -L "$path" ]] || fail "مسیر نصب یک پوشه است: $path"
done
if [[ -e "$wrapper" || -L "$wrapper" ]]; then cp -a -- "$wrapper" "$work/wrapper"; fi
if [[ -e "$hook" || -L "$hook" ]]; then cp -a -- "$hook" "$work/hook"; fi

progress 4 'فعال‌سازی و آزمون دستور'
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
version=$("$wrapper" --version) || fail 'دستور نصب‌شده اجرا نشد.'
committed=1
flock -u 9

printf '\n  %s[OK]%s نصب کامل شد: %s\n' "$green" "$reset" "$version"
if [[ -n "$backup" ]]; then printf '  نسخهٔ قبلی: %s\n' "$backup"; fi
printf '  اجرای برنامه: sudo srv-helper\n'
if ((tty && !yes && !launch)); then
  printf '  منو اکنون باز شود؟ [y/N] '
  if IFS= read -r answer; then
    case "${answer,,}" in y|yes|بله) launch=1 ;; esac
  fi
fi
if ((launch)); then "$wrapper"; fi
