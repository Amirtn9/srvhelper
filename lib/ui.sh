#!/usr/bin/env bash
if [[ -t 1 && -z ${NO_COLOR:-} ]]; then
  C1=$'\033[1;96m'; C2=$'\033[1;94m'; OK=$'\033[1;92m'; BAD=$'\033[1;91m'
  WARN=$'\033[1;93m'; DIM=$'\033[2m'; RESET=$'\033[0m'
else C1='' C2='' OK='' BAD='' WARN='' DIM='' RESET=''; fi
banner() {
  [[ -t 1 && -z ${NO_CLEAR:-} ]] && printf '\033[2J\033[H'
  printf '%b\n' "${C1}  +----------------------------------------------------------+${RESET}"
  printf '%b\n' "${C1}  |      S R V   H E L P E R             v${SRV_VERSION}          |${RESET}"
  printf '%b\n' "${C2}  |       SSL  /  SHABAKE  /  MODIRIAT SERVER          |${RESET}"
  printf '%b\n' "${C1}  +----------------------------------------------------------+${RESET}"
}
section() { printf '\n%b\n' "${C2}  [ $1 ]${RESET}"; printf '  %s\n' '----------------------------------------------------------'; }
step() {
  local current=$1 total=$2 label=$3 filled='' empty='' n
  for ((n=1;n<=total;n++)); do
    if ((n<=current)); then filled+='#'; else empty+='-'; fi
  done
  printf '\n%b\n' "${C1}  [$current/$total] [$filled$empty] $label${RESET}"
}
menu_line() { printf '  %b%2s%b) %s\n' "$C1" "$1" "$RESET" "$2"; }
info() { printf '%b\n' "${C1}[INFO]${RESET} $*"; }
success() { printf '%b\n' "${OK}[OK]${RESET} $*"; }
warn() { printf '%b\n' "${WARN}[WARN]${RESET} $*"; }
fail() { printf '%b\n' "${BAD}[ERROR]${RESET} $*" >&2; }
prompt() {
  local label=$1 _dest=$2
  printf '%b' "${C1}  > ${label}: ${RESET}"
  IFS= read -r "$_dest" || return 1
}
pause() { local _skip; [[ -t 0 ]] && prompt 'Baraye edame Enter bezanid' _skip || :; }
confirm() {
  local ans
  prompt "$1 [y/N]" ans || return 1
  [[ "$ans" == [yY] || "$ans" == [yY][eE][sS] ]]
}
need_root() {
  if (( EUID != 0 )); then fail 'In bakhsh be root/sudo niaz darad'; return 1; fi
}
need_cmd() { if ! command -v "$1" >/dev/null 2>&1; then fail "Abzar $1 mojood nist"; return 1; fi; }
valid_positive_count() { [[ "$1" =~ ^[0-9]+$ ]] && (( 10#$1 >= 1 && 10#$1 <= ${2:-50} )); }
state_dir() { printf '/var/lib/srv-helper'; }
backup_dir() { printf '/var/backups/srv-helper'; }
