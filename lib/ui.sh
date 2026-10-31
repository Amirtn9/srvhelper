#!/usr/bin/env bash
# SRV Helper terminal UI. All interactive strings are Finglish/ASCII.
if [[ -t 1 && -z ${NO_COLOR:-} ]]; then
  C1=$'\033[1;96m'; C2=$'\033[1;94m'; C3=$'\033[1;95m'
  OK=$'\033[1;92m'; BAD=$'\033[1;91m'; WARN=$'\033[1;93m'
  DIM=$'\033[2m'; WHITE=$'\033[1;97m'; RESET=$'\033[0m'
else C1='' C2='' C3='' OK='' BAD='' WARN='' DIM='' WHITE='' RESET=''; fi

SRV_EXIT_REQUESTED=${SRV_EXIT_REQUESTED:-0}

banner() {
  [[ -t 1 && -z ${NO_CLEAR:-} ]] && printf '\033[2J\033[H'
  printf '%b\n' "${C1}  +======================================================================+${RESET}"
  printf '%b\n' "${C1}  |${RESET}  ${WHITE} ____  ____  __      __  _   _  _____ _     ____  _____ ____  ${RESET}        ${C1}|${RESET}"
  printf '%b\n' "${C1}  |${RESET}  ${WHITE}/ ___||  _ \ \ \    / / | | | || ____| |   |  _ \| ____|  _ \ ${RESET}       ${C1}|${RESET}"
  printf '%b\n' "${C1}  |${RESET}  ${WHITE}\___ \| |_) | \ \  / /  | |_| ||  _| | |   | |_) |  _| | |_) |${RESET}       ${C1}|${RESET}"
  printf '%b\n' "${C1}  |${RESET}  ${WHITE} ___) |  _ <   \ \/ /   |  _  || |___| |___|  __/| |___|  _ < ${RESET}       ${C1}|${RESET}"
  printf '%b\n' "${C1}  |${RESET}  ${WHITE}|____/|_| \_\   \/    |_| |_||_____|_____|_|   |_____|_| \_${RESET}       ${C1}|${RESET}"
  printf '%b\n' "${C1}  +----------------------------------------------------------------------+${RESET}"
  printf '%b\n' "${C2}  |  SRV HELPER - SERVER CONTROL CENTER                                  |${RESET}"
  printf '%b\n' "${C3}  |  DEVELOPER: AmirTN9  |  GITHUB: github.com/AmirTN9/srvhelper         |${RESET}"
  printf '%b\n' "${C1}  |  VERSION: ${SRV_VERSION:-1.0.0}  |  SSL / DNS / MIRROR / BBR / SYS TOOLS  |${RESET}"
  printf '%b\n' "${C1}  +======================================================================+${RESET}"
}
section() {
  printf '\n%b\n' "${C2}  >>> $1${RESET}"
  printf '%b\n' "${DIM}  ----------------------------------------------------------------------${RESET}"
}
step() {
  local current=$1 total=$2 label=$3 filled='' empty='' n
  for ((n=1;n<=total;n++)); do
    if ((n<=current)); then filled+='#'; else empty+='-'; fi
  done
  printf '\n%b\n' "${C1}  STEP $current/$total  [$filled$empty]  $label${RESET}"
}
menu_line() { printf '  %b%2s%b  %-64s\n' "$C1" "$1" "$RESET" "$2"; }
info() { printf '%b\n' "${C1}[INFO]${RESET} $*"; }
success() { printf '%b\n' "${OK}[ OK ]${RESET} $*"; }
warn() { printf '%b\n' "${WARN}[WARN]${RESET} $*"; }
fail() { printf '%b\n' "${BAD}[FAIL]${RESET} $*" >&2; }
prompt() {
  local label=$1 _dest=$2 raw rc=0
  printf '%b' "${C1}  > ${label}: ${RESET}"
  IFS= read -r raw || return 1
  case "${raw,,}" in
    back|b) return 20 ;;
    exit|quit) SRV_EXIT_REQUESTED=1; return 21 ;;
  esac
  printf -v "$_dest" '%s' "$raw"
  return 0
}
pause() {
  local _skip
  [[ -t 0 ]] && prompt 'Baraye edame Enter bezanid' _skip || :
}
confirm() {
  local ans
  prompt "$1 [y/N]" ans || return 1
  [[ "$ans" == [yY] || "$ans" == [yY][eE][sS] ]]
}
need_root() {
  if (( EUID != 0 )); then fail 'In bakhsh be dastresi root/sudo niaz darad'; return 1; fi
}
need_cmd() { if ! command -v "$1" >/dev/null 2>&1; then fail "Abzar $1 mojood nist"; return 1; fi; }
valid_positive_count() { [[ "$1" =~ ^[0-9]+$ ]] && (( 10#$1 >= 1 && 10#$1 <= ${2:-50} )); }
state_dir() { printf '/var/lib/srv-helper'; }
backup_dir() { printf '/var/backups/srv-helper'; }
