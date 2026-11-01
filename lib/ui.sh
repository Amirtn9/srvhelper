#!/usr/bin/env bash
# Compact terminal UI. All interactive text is Finglish/ASCII.
if [[ -t 1 && -z ${NO_COLOR:-} ]]; then
  C1=$'\033[1;96m'; C2=$'\033[1;94m'; C3=$'\033[1;95m'
  OK=$'\033[1;92m'; BAD=$'\033[1;91m'; WARN=$'\033[1;93m'
  DIM=$'\033[2m'; WHITE=$'\033[1;97m'; RESET=$'\033[0m'
else
  C1='' C2='' C3='' OK='' BAD='' WARN='' DIM='' WHITE='' RESET=''
fi

SRV_EXIT_REQUESTED=${SRV_EXIT_REQUESTED:-0}
SRV_BACK_REQUESTED=${SRV_BACK_REQUESTED:-0}

banner() {
  [[ -t 1 && -z ${NO_CLEAR:-} ]] && printf '\033[2J\033[H'
  printf '%b\n' "${C1}  +--------------------------------------------------------------------+${RESET}"
  printf '%b\n' "${C1}  |${RESET}                         ${WHITE}SRV HELPER${RESET}                                 ${C1}|${RESET}"
  printf '%b\n' "${C1}  |${RESET}                    MODIRIAT SERVER                                 ${C1}|${RESET}"
  printf '%b\n' "${C1}  |${RESET}  ${C3}AMIRTN9${RESET}  |  github.com/AmirTN9/srvhelper                          ${C1}|${RESET}"
  printf '%b\n' "${C1}  |${RESET}                         VERSION 1.0.0                              ${C1}|${RESET}"
  printf '%b\n' "${C1}  +--------------------------------------------------------------------+${RESET}"
}
section() {
  printf '\n%b\n' "${C2}  $1${RESET}"
  printf '%b\n' "${DIM}  --------------------------------------------------------------------${RESET}"
}
step() {
  local current=$1 total=$2 label=$3 filled='' empty='' n
  for ((n=1;n<=total;n++)); do
    if ((n<=current)); then filled+='#'; else empty+='-'; fi
  done
  printf '\n%b\n' "${C1}  MARHALE $current/$total  [$filled$empty]  $label${RESET}"
}
menu_line() { printf '  %b%2s%b  %s\n' "$C1" "$1" "$RESET" "$2"; }
info() { printf '%b\n' "${C1}[INFO]${RESET} $*"; }
success() { printf '%b\n' "${OK}[ OK ]${RESET} $*"; }
warn() { printf '%b\n' "${WARN}[WARN]${RESET} $*"; }
fail() { printf '%b\n' "${BAD}[FAIL]${RESET} $*" >&2; }

prompt() {
  local label=$1 destination=$2 _srv_prompt_value
  printf '%b' "${C1}  > ${label}: ${RESET}"
  IFS= read -r _srv_prompt_value || return 1
  _srv_prompt_value=${_srv_prompt_value//$'\r'/}
  case "${_srv_prompt_value,,}" in
    back|b) SRV_BACK_REQUESTED=1; return 20 ;;
    exit|quit) SRV_EXIT_REQUESTED=1; return 21 ;;
  esac
  printf -v "$destination" '%s' "$_srv_prompt_value"
}

pause() {
  [[ ${SRV_BACK_REQUESTED:-0} == 1 || ${SRV_EXIT_REQUESTED:-0} == 1 ]] && return 0
  [[ -t 0 ]] || return 0
  local _srv_pause_value
  printf '%b' "${DIM}  Enter = edame | back = bargasht | exit = khorooj: ${RESET}"
  IFS= read -r _srv_pause_value || return 0
  case "${_srv_pause_value,,}" in
    back|b) SRV_BACK_REQUESTED=1 ;;
    exit|quit) SRV_EXIT_REQUESTED=1 ;;
  esac
}

confirm() {
  local ans rc
  prompt "$1 [y/N]" ans; rc=$?
  ((rc==0)) || return "$rc"
  [[ "$ans" == [yY] || "$ans" == [yY][eE][sS] ]]
}
need_root() {
  if (( EUID != 0 )); then fail 'In bakhsh be dastresi root/sudo niaz darad'; return 1; fi
}
need_cmd() { if ! command -v "$1" >/dev/null 2>&1; then fail "Abzar $1 mojood nist"; return 1; fi; }
valid_positive_count() { [[ "$1" =~ ^[0-9]+$ ]] && (( 10#$1 >= 1 && 10#$1 <= ${2:-50} )); }
state_dir() { printf '/var/lib/srv-helper'; }
backup_dir() { printf '/var/backups/srv-helper'; }
