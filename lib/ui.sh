#!/usr/bin/env bash
# Compact terminal UI. All interactive text is Finglish/ASCII.
if [[ -t 1 && ${TERM:-dumb} != dumb && -z ${NO_COLOR:-} ]]; then
  C1=$'\033[1;96m'; C2=$'\033[1;94m'; C3=$'\033[1;95m'
  OK=$'\033[1;92m'; BAD=$'\033[1;91m'; WARN=$'\033[1;93m'
  DIM=$'\033[2m'; WHITE=$'\033[1;97m'; RESET=$'\033[0m'
else
  C1='' C2='' C3='' OK='' BAD='' WARN='' DIM='' WHITE='' RESET=''
fi

SRV_EXIT_REQUESTED=${SRV_EXIT_REQUESTED:-0}
SRV_BACK_REQUESTED=${SRV_BACK_REQUESTED:-0}

banner() {
  if [[ -t 1 && ${TERM:-dumb} != dumb && -z ${NO_CLEAR:-} ]]; then
    printf '\033[2J\033[H'
  fi
  printf '\n  %sSRV HELPER%s  %sv%s%s\n' "$WHITE" "$RESET" "$DIM" "${SRV_VERSION:-}" "$RESET"
}
section() {
  printf '\n  %s%s%s\n' "$C2" "$1" "$RESET"
  printf '  %s------------------------------------%s\n' "$DIM" "$RESET"
}
step() {
  local current=$1 total=$2 label=$3 filled='' empty='' n
  for ((n=1;n<=total;n++)); do
    if ((n<=current)); then filled+='#'; else empty+='-'; fi
  done
  printf '\n%b\n' "${C1}  MARHALE $current/$total  [$filled$empty]  $label${RESET}"
}
menu_line() { printf '  %b%2s%b  %s\n' "$C1" "$1" "$RESET" "$2"; }
info() { printf '  %s[INFO]%s %s\n' "$C1" "$RESET" "$*"; }
success() { printf '  %s[ OK ]%s %s\n' "$OK" "$RESET" "$*"; }
warn() { printf '  %s[WARN]%s %s\n' "$WARN" "$RESET" "$*"; }
fail() { printf '  %s[FAIL]%s %s\n' "$BAD" "$RESET" "$*" >&2; }

prompt() {
  local label=$1 destination=$2 _srv_prompt_value
  printf '  %s> %s: %s' "$C1" "$label" "$RESET"
  IFS= read -r _srv_prompt_value || return 1
  _srv_prompt_value=${_srv_prompt_value//$'\r'/}
  case "${_srv_prompt_value,,}" in
    back|b) SRV_BACK_REQUESTED=1; return 20 ;;
    exit|quit) SRV_EXIT_REQUESTED=1; return 21 ;;
  esac
  printf -v "$destination" '%s' "$_srv_prompt_value"
}

choose_menu() {
  local _menu_destination=$1 _menu_title=$2 _menu_summary=$3
  shift 3
  local -a _menu_ids=() _menu_labels=()
  while (($# >= 2)); do
    _menu_ids+=("$1")
    _menu_labels+=("$2")
    shift 2
  done
  local _menu_size=${#_menu_ids[@]} _menu_row=0 _menu_index _menu_key _menu_sequence
  local _menu_keyboard=0 _menu_number= _menu_candidate
  if [[ -t 0 && -t 1 && ${TERM:-dumb} != dumb && -z ${NO_CLEAR:-} && -z ${SRV_PLAIN_MENU:-} ]]; then
    _menu_keyboard=1
  fi

  while :; do
    banner
    if [[ -n "$_menu_summary" ]]; then printf '%s\n' "$_menu_summary"; fi
    section "$_menu_title"
    for ((_menu_index=0; _menu_index<_menu_size; _menu_index++)); do
      if ((_menu_keyboard && _menu_index == _menu_row)); then
        printf '  %s>%s %2s  %s%s%s\n' "$C1" "$RESET" "${_menu_ids[_menu_index]}" "$WHITE" "${_menu_labels[_menu_index]}" "$RESET"
      else
        printf '  %s%4s%s  %s\n' "$C1" "${_menu_ids[_menu_index]}" "$RESET" "${_menu_labels[_menu_index]}"
      fi
    done
    if ((!_menu_keyboard)); then
      printf '\n  %sback = menu ghabli | exit = khorooj%s\n' "$DIM" "$RESET"
      prompt 'Entekhab' "$_menu_destination"
      return $?
    fi

    printf '\n  %sUp/Down | Enter | 0-9 | Esc: back | Q: exit%s\n' "$DIM" "$RESET"
    while IFS= read -rsn1 _menu_key; do
      case "$_menu_key" in
        ''|$'\r')
          printf -v "$_menu_destination" '%s' "${_menu_ids[_menu_row]}"
          return 0
          ;;
        q|Q)
          SRV_EXIT_REQUESTED=1
          return 21
          ;;
        b|B|$'\177'|$'\b')
          SRV_BACK_REQUESTED=1
          return 20
          ;;
        $'\033')
          _menu_number=''
          if ! IFS= read -rsn1 -t 0.25 _menu_sequence; then
            SRV_BACK_REQUESTED=1
            return 20
          fi
          case "$_menu_sequence" in
            '['|O)
              # Consume the sequence through its final byte. Cursor keys can
              # carry modifier parameters, such as ESC [ 1 ; 5 A.
              while IFS= read -rsn1 -t 0.25 _menu_sequence; do
                case "$_menu_sequence" in
                  A) _menu_row=$(((_menu_row + _menu_size - 1) % _menu_size)); break 2 ;;
                  B) _menu_row=$(((_menu_row + 1) % _menu_size)); break 2 ;;
                  [a-zA-Z~]) break ;;
                esac
              done
              ;;
          esac
          ;;
        [0-9])
          for _menu_candidate in "${_menu_number}$_menu_key" "$_menu_key"; do
            for ((_menu_index=0; _menu_index<_menu_size; _menu_index++)); do
              if [[ "${_menu_ids[_menu_index]}" == "$_menu_candidate" ]]; then
                _menu_number=$_menu_candidate
                _menu_row=$_menu_index
                break 3
              fi
            done
          done
          ;;
      esac
    done || return 1
  done
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
