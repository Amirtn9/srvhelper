#!/usr/bin/env bash
# Install from local checkout or clone the public GitHub repository.
set -euo pipefail
umask 022
REPO_URL="https://github.com/Amirtn9/Pasarguard-SSL-Helper.git"
if (( EUID != 0 )); then printf 'Baraye install az sudo estefade konid.\n' >&2; exit 1; fi
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
work=''
src=''
cleanup() { [[ -z "$work" ]] || rm -rf -- "$work"; }
trap cleanup EXIT
if [[ -f "$script_dir/srv-helper.sh" && -f "$script_dir/hooks/srv-helper-deploy.sh" ]]; then
  src="$script_dir"
else
  work=$(mktemp -d /tmp/srv-helper-install.XXXXXXXX)
  if command -v git >/dev/null 2>&1; then
    git clone --depth 1 "$REPO_URL" "$work/src"
    src="$work/src"
  else
    command -v curl >/dev/null || { printf 'Git ya curl niaz ast.\n' >&2; exit 1; }
    command -v tar >/dev/null || { printf 'tar niaz ast.\n' >&2; exit 1; }
    curl --proto '=https' --tlsv1.2 -fLsS -o "$work/repo.tar.gz" \
      'https://github.com/Amirtn9/Pasarguard-SSL-Helper/archive/refs/heads/main.tar.gz'
    mkdir -p "$work/unpack"
    tar -xzf "$work/repo.tar.gz" -C "$work/unpack"
    src=$(find "$work/unpack" -mindepth 1 -maxdepth 1 -type d -print -quit)
  fi
  [[ -n "${src:-}" && -f "$src/srv-helper.sh" ]] || { printf 'GitHub branch hanooz SRV Helper nadarad. Aval fileha ra push konid.\n' >&2; exit 1; }
  # When git clones into a known directory, use it as source.
  [[ -d "$work/src" ]] && src="$work/src"
fi
for required in srv-helper.sh lib/ui.sh lib/certs.sh lib/mirrors.sh lib/dns.sh lib/system.sh hooks/srv-helper-deploy.sh; do
  [[ -f "$src/$required" ]] || { printf 'File mojood nist: %s\n' "$required" >&2; exit 1; }
done
for shellfile in "$src/srv-helper.sh" "$src/lib/"*.sh "$src/hooks/"*.sh; do bash -n "$shellfile"; done
stage="/opt/srv-helper.stage.$$"
install -d -m 755 "$stage"
cp -a "$src/srv-helper.sh" "$src/lib" "$src/hooks" "$stage/"
chown -R root:root "$stage"
chmod 755 "$stage" "$stage/lib" "$stage/hooks"
chmod 755 "$stage/srv-helper.sh"; chmod 644 "$stage/lib/"*.sh; chmod 750 "$stage/hooks/"*.sh
if [[ -e /opt/srv-helper ]]; then
  mv /opt/srv-helper "/opt/srv-helper.previous.$(date -u +%Y%m%dT%H%M%SZ).$$"
fi
mv "$stage" /opt/srv-helper
install -d -m 755 /usr/local/bin
cat > /usr/local/bin/srv-helper <<'WRAPPER'
#!/usr/bin/env bash
exec /opt/srv-helper/srv-helper.sh "$@"
WRAPPER
chmod 755 /usr/local/bin/srv-helper
install -d -m 755 /etc/letsencrypt/renewal-hooks/deploy
install -m 750 /opt/srv-helper/hooks/srv-helper-deploy.sh /etc/letsencrypt/renewal-hooks/deploy/srv-helper-deploy
printf 'SRV Helper nasb shod. Ejra: sudo srv-helper\n'
