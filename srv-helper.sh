#!/usr/bin/env bash
# SRV Helper - Modular SSL & VPS manager
set -o pipefail
umask 027
SRV_HOME="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
SRV_VERSION="1.0.0"
# All interactive output is Finglish (ASCII).
for module in ui certs mirrors dns system; do
  # shellcheck source=/dev/null
  source "$SRV_HOME/lib/${module}.sh"
done

main_menu() {
  while :; do
    banner
    printf '%b\n' "${DIM}  System: $(os_label)  |  Karbar: $(id -un)  |  SSL: $(command -v certbot >/dev/null && echo ready || echo missing)${RESET}"
    section "MENU ASLI"
    menu_line 1 'SSL Dasti       | Yek domain, mesle ravesh ghabli'
    menu_line 2 'SSL Hoshmand    | SAN + Batch + modiriat masir'
    menu_line 3 'Modiriat Mirror | Iran / Europe / USA'
    menu_line 4 'Modiriat DNS    | Iran / Global + restore'
    menu_line 5 'Abzar System    | Vaziat + shabake + abzar'
    menu_line 6 'Vaziat SSL      | List / check / renewal'
    menu_line 0 'Khorooj'
    prompt 'Entekhab' opt
    case "$opt" in
      1) manual_ssl ;;
      2) smart_ssl_menu ;;
      3) mirror_menu ;;
      4) dns_menu ;;
      5) system_menu ;;
      6) certificate_dashboard ;;
      0|q|Q) printf '\nKhodafez!\n'; return ;;
      *) warn 'Gozine namotabar ast'; pause ;;
    esac
  done
}

case "${1:-}" in
  --help|-h)
    printf 'SRV Helper %s\nUsage: sudo ./srv-helper.sh [--help|--version]\nInteractive: SSL, Mirror, DNS, Sys Tools.\n' "$SRV_VERSION"
    ;;
  --version|-v) printf 'SRV Helper %s\n' "$SRV_VERSION" ;;
  '') main_menu ;;
  *) printf 'Argument namotabar: %s\n' "$1" >&2; exit 2 ;;
esac
