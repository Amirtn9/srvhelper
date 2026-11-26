#!/usr/bin/env bash
# Certbot renewal deploy hook. No dependency on the interactive TUI.
set -euo pipefail
umask 077
conf='/etc/srv-helper/deployments.tsv'
((EUID == 0)) || exit 1
[[ -r "$conf" && -n ${RENEWED_LINEAGE:-} ]] || exit 0
certname=${RENEWED_LINEAGE##*/}
[[ "$RENEWED_LINEAGE" == "/etc/letsencrypt/live/$certname" ]] || exit 1
[[ "$certname" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]] || exit 1
exec 9>/etc/srv-helper/deploy.lock
flock 9

deploy() (
  local dest=$1 group=$2 stage item mode pub cert_pub
  local -a items=(cert.pem chain.pem fullchain.pem privkey.pem) replaced=()
  local committed=0
  [[ "$group" =~ ^[a-z_][a-z0-9_-]*$ ]] && getent group "$group" >/dev/null || return 1
  [[ "$dest" == /* && "$dest" != '/' && "$dest" != *$'\n'* && ! -L "$dest" ]] || return 1
  dest=$(realpath -m -- "$dest") || return 1
  [[ "$dest" != / && "$dest" != /etc/letsencrypt && "$dest" != /etc/letsencrypt/* ]] || return 1
  install -d -o root -g "$group" -m 750 -- "$dest" || return 1
  stage=$(mktemp -d "$dest/.srv-helper.XXXXXXXX") || return 1
  cleanup() {
    local rc=$? failed=0 file
    if ((!committed)); then
      for file in "${replaced[@]}"; do
        if [[ -e "$stage/previous/$file" || -L "$stage/previous/$file" ]]; then
          mv -fT -- "$stage/previous/$file" "$dest/$file" || failed=1
        else
          rm -f -- "$dest/$file" || failed=1
        fi
      done
    fi
    if ((failed)); then printf 'Certificate rollback incomplete: %s\n' "$stage" >&2
    else rm -rf -- "$stage"; fi
    exit "$rc"
  }
  trap cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  mkdir "$stage/previous" || return 1
  for item in "${items[@]}"; do
    [[ -f "$RENEWED_LINEAGE/$item" && ! -d "$dest/$item" ]] || return 1
    mode=644
    if [[ "$item" == privkey.pem ]]; then
      if [[ "$group" == root ]]; then mode=600; else mode=640; fi
    fi
    install -o root -g "$group" -m "$mode" -- "$RENEWED_LINEAGE/$item" "$stage/$item" || return 1
    if [[ -e "$dest/$item" || -L "$dest/$item" ]]; then
      cp -aT -- "$dest/$item" "$stage/previous/$item" || return 1
    fi
  done
  pub=$(openssl pkey -in "$stage/privkey.pem" -pubout) || return 1
  cert_pub=$(openssl x509 -in "$stage/fullchain.pem" -pubkey -noout) || return 1
  [[ "$pub" == "$cert_pub" ]] || return 1
  for item in "${items[@]}"; do
    replaced+=("$item")
    mv -fT -- "$stage/$item" "$dest/$item" || return 1
  done
  committed=1
  printf '[SRV Helper] certificate deployed: %s -> %s\n' "$certname" "$dest"
)

failed=0
while IFS=$'\t' read -r name dest group; do
  [[ "$name" == "$certname" ]] || continue
  if ! deploy "$dest" "${group:-root}"; then
    printf '[SRV Helper] certificate deployment failed: %s\n' "$certname" >&2
    failed=1
  fi
done < "$conf"
exit "$failed"
