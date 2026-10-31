#!/usr/bin/env bash
# SRV Helper - AmirTN9 server control center
set -o pipefail
umask 027
SRV_HOME="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
SRV_VERSION="1.0.0"
for module in ui certs mirrors dns system netoptix paqet automation; do
  # shellcheck source=/dev/null
  source "$SRV_HOME/lib/${module}.sh"
done

main_menu() {
  local opt rc
  while :; do
    [[ ${SRV_EXIT_REQUESTED:-0} == 1 ]] && return 0
    banner
    quick_status
    section 'AMIRTN9 | MAIN MENU'
    menu_line 1 'SSL Dasti       | Yek domain, ravesh sade'
    menu_line 2 'SSL Hoshmand    | SAN + Batch + path manager'
    menu_line 3 'Smart Auto      | DNS + Mirror + APT update + BBR'
    menu_line 4 'DNS Finder      | Iran DNS / TIC / ISP / Global'
    menu_line 5 'Mirror Manager  | Iran / Europe / USA (Ubuntu/Debian)'
    menu_line 6 'Paqet Manager   | Official Behzad manager + services'
    menu_line 7 'SysHelper       | Server dashboard + network + TCP'
    menu_line 8 'NetOptix Tools  | Swap / ZRAM / MTU / Security / Cockpit'
    menu_line 9 'SSL Dashboard   | Certificates / renewal / deploy'
    menu_line 10 'Diagnostics     | System + network report'
    menu_line 0 'Exit'
    printf '\n%b\n' "${DIM}  Tip: dar har marhale back = bargasht | exit = khorooj${RESET}"
    prompt 'Entekhab' opt; rc=$?
    case "$rc" in
      20) continue ;;
      21) return 0 ;;
      0) ;;
      *) return 1 ;;
    esac
    case "$opt" in
      1) manual_ssl ;;
      2) smart_ssl_menu ;;
      3) smart_auto_optimize ;;
      4) dns_menu ;;
      5) mirror_menu ;;
      6) paqet_menu ;;
      7) system_menu ;;
      8) netoptix_menu ;;
      9) certificate_dashboard ;;
      10) system_overview; network_status; pause ;;
      0|q|Q|exit|quit) return 0 ;;
      *) warn 'Gozine namotabar ast'; pause ;;
    esac
    [[ ${SRV_EXIT_REQUESTED:-0} == 1 ]] && return 0
  done
}

case "${1:-}" in
  --help|-h)
    printf 'SRV Helper %s by AmirTN9\nUsage: sudo srv-helper [--help|--version]\nInteractive: SSL, DNS Finder, APT Mirror, Paqet, SysHelper, NetOptix.\n'
    ;;
  --version|-v) printf 'SRV Helper %s\n' "$SRV_VERSION" ;;
  '') main_menu ;;
  *) printf 'Argument namotabar: %s\n' "$1" >&2; exit 2 ;;
esac
