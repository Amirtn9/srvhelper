#!/usr/bin/env bash
# SRV Helper - AmirTN9
set -o pipefail
umask 027
SRV_HOME="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
SRV_VERSION="1.0.0"
for module in ui certs mirrors dns system maintenance tunnels automation; do
  # shellcheck source=/dev/null
  source "$SRV_HOME/lib/${module}.sh"
done

network_tools_menu() {
  local choice rc
  while :; do
    [[ ${SRV_EXIT_REQUESTED:-0} == 1 ]] && return
    banner; section 'DNS VA MIRROR'
    menu_line 1 'Modiriat DNS (Iran / Jahani / Finder)'
    menu_line 2 'Modiriat Mirror (Iran / Europe / USA)'
    menu_line 3 'Tanzim Hoshmand (DNS + Mirror + Update + BBR)'
    menu_line 0 'Bargasht'
    prompt 'Entekhab' choice; rc=$?
    if ((rc==20)); then SRV_BACK_REQUESTED=0; return; fi
    ((rc==0)) || return "$rc"
    case "$choice" in
      1) dns_menu ;;
      2) mirror_menu ;;
      3) smart_auto_optimize ;;
      0) return ;;
      *) warn 'Gozine namotabar'; pause ;;
    esac
    [[ ${SRV_EXIT_REQUESTED:-0} == 1 ]] && return
    if [[ ${SRV_BACK_REQUESTED:-0} == 1 ]]; then SRV_BACK_REQUESTED=0; fi
  done
}

main_menu() {
  local opt rc
  while :; do
    [[ ${SRV_EXIT_REQUESTED:-0} == 1 ]] && return 0
    banner
    quick_status
    section 'AMIRTN9 | MENU ASLI'
    menu_line 1 'Modiriat SSL va Certificate'
    menu_line 2 'DNS va Mirror'
    menu_line 3 'Khadamat Server'
    menu_line 4 'Abzar System'
    menu_line 0 'Khorooj'
    printf '\n%b\n' "${DIM}  back = menu ghabli  |  exit = khorooj${RESET}"
    prompt 'Entekhab' opt; rc=$?
    if ((rc==20)); then SRV_BACK_REQUESTED=0; continue; fi
    ((rc==0)) || return 0
    case "$opt" in
      1) ssl_menu ;;
      2) network_tools_menu ;;
      3) server_services_menu ;;
      4) system_menu ;;
      0|exit|quit) return 0 ;;
      *) warn 'Gozine namotabar'; pause ;;
    esac
    [[ ${SRV_EXIT_REQUESTED:-0} == 1 ]] && return 0
    SRV_BACK_REQUESTED=0
  done
}

case "${1:-}" in
  --help|-h)
    printf 'SRV Helper %s\nUsage: sudo srv-helper [--help|--version]\n' "$SRV_VERSION"
    ;;
  --version|-v) printf 'SRV Helper %s\n' "$SRV_VERSION" ;;
  '') main_menu ;;
  *) printf 'Argument namotabar: %s\n' "$1" >&2; exit 2 ;;
esac
