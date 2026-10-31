#!/usr/bin/env bash
# Certbot renewal deploy hook. No dependency on the interactive TUI.
set -euo pipefail
umask 077
conf='/etc/srv-helper/deployments.tsv'
[[ ${EUID:-$(id -u)} -eq 0 ]] || exit 1
[[ -r "$conf" ]] || exit 0
[[ -n ${RENEWED_LINEAGE:-} ]] || exit 0
# Only process certbot's actual live directory; reject arbitrary env paths.
case "$RENEWED_LINEAGE" in /etc/letsencrypt/live/*) ;; *) exit 1 ;; esac
certname=${RENEWED_LINEAGE##*/}
[[ "$certname" =~ ^[a-zA-Z0-9._-]+$ ]] || exit 1
[[ -f "$RENEWED_LINEAGE/fullchain.pem" && -f "$RENEWED_LINEAGE/privkey.pem" ]] || exit 1
while IFS=$'\t' read -r name dest group; do
  group=${group:-root}
  [[ "$group" =~ ^[a-z_][a-z0-9_-]*$ ]] && getent group "$group" >/dev/null 2>&1 || exit 1
  [[ "$name" == "$certname" ]] || continue
  [[ "$dest" == /* && "$dest" != '/' && "$dest" != /etc/letsencrypt* && "$dest" != *$'\n'* ]] || exit 1
  # Files are kept in place rather than symlinked; hook updates after every renewal.
  install -d -o root -g "$group" -m 750 -- "$dest"
  for item in cert.pem chain.pem fullchain.pem privkey.pem; do
    [[ -f "$RENEWED_LINEAGE/$item" ]] || continue
    tmp=$(mktemp "$dest/.${item}.XXXXXXXX")
    if [[ "$item" == 'privkey.pem' ]]; then
      if [[ "$group" == root ]]; then mode=600; else mode=640; fi
    else mode=644; fi
    install -o root -g "$group" -m "$mode" -- "$RENEWED_LINEAGE/$item" "$tmp"
    mv -f -- "$tmp" "$dest/$item"
  done
  printf '[SRV Helper] certificate deployed: %s -> %s\n' "$name" "$dest"
done < "$conf"
