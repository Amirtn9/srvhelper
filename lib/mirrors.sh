#!/usr/bin/env bash
# Ubuntu mirror switching with release validation, backup, rollback.
# Debian is intentionally not rewritten; unsupported APT layouts are preserved.
mirror_candidates() {
  case "$1" in
    iran)
      # All candidates are runtime-verified: entries can disappear or be stale.
      printf '%s\n' \
        'https://mirror.iranserver.com/ubuntu' \
        'https://mirror.arvancloud.ir/ubuntu' \
        'https://ubuntu.pishgaman.net/ubuntu' \
        'https://ubuntu.pars.host/ubuntu' \
        'https://archive.ubuntu.mirrors.zagrio.net/ubuntu' \
        'https://ubuntu-mirror.kimiahost.com/ubuntu' \
        'https://ubuntu.avinahost.com/ubuntu' \
        'https://ubuntu.mobinhost.com/ubuntu' \
        'https://ir.ubuntu.sindad.cloud/ubuntu' \
        'https://mirror.aminidc.com/ubuntu' \
        'https://mirrors.pardisco.co/ubuntu' \
        'https://archive.ubuntu.petiak.ir/ubuntu' \
        'https://linuxmirrors.ir/ubuntu' \
        'https://ubuntu.parsvds.com/ubuntu' \
        'https://mirror.faraso.org/ubuntu' \
        'https://mirrors.ubuntu.dimit.cloud/ubuntu' \
        'https://repo.iut.ac.ir/ubuntu' \
        'http://ir.archive.ubuntu.com/ubuntu' \
        'http://archive.ubuntu.com/ubuntu' ;;
    europe)
      printf '%s\n' \
        'http://de.archive.ubuntu.com/ubuntu' \
        'http://nl.archive.ubuntu.com/ubuntu' \
        'http://fr.archive.ubuntu.com/ubuntu' \
        'http://gb.archive.ubuntu.com/ubuntu' \
        'http://archive.ubuntu.com/ubuntu' ;;
    usa)
      printf '%s\n' \
        'http://us.archive.ubuntu.com/ubuntu' \
        'https://mirror.math.princeton.edu/pub/ubuntu' \
        'http://archive.ubuntu.com/ubuntu' ;;
  esac
}
mirror_probe() {
  local url=$1 codename=$2 result code secs
  result=$(curl -L -sS --connect-timeout 3 --max-time 10 -o /dev/null -w '%{http_code} %{time_total}' "$url/dists/$codename/Release" 2>/dev/null) || return 1
  read -r code secs <<< "$result"
  [[ "$code" == 200 ]] || return 1
  # Must be a valid Release path for this codename. HEAD may be blocked; use GET.
  printf '%s' "$secs"
}
rank_mirrors() {
  local region=$1 codename=$2 url seconds i=0 jobfile
  local tmp
  tmp=$(mktemp -d /tmp/srv-helper-mirrors.XXXXXXXX) || return 1
  section "TEST SORAT MIRROR | ${region^^}" >&2
  info 'Mirror ha ba 6 worker be surat parallel check mishavand...' >&2
  local -a mirrors=()
  mapfile -t mirrors < <(mirror_candidates "$region")
  for url in "${mirrors[@]}"; do
    # Each child writes to its own file, so output cannot interleave.
    (
      if seconds=$(mirror_probe "$url" "$codename"); then
        printf '%s|%s\n' "$seconds" "$url" > "$tmp/$i.ok"
      else
        printf '%s\n' "$url" > "$tmp/$i.fail"
      fi
    ) &
    ((i+=1))
    if ((i % 6 == 0)); then wait || :; fi
  done
  wait || :
  local -a results=()
  for ((i=0;i<${#mirrors[@]};i++)); do
    if [[ -f "$tmp/$i.ok" ]]; then
      IFS= read -r jobfile < "$tmp/$i.ok"
      results+=("$jobfile")
      printf '  [OK]   %s\n' "$jobfile" >&2
    else
      printf '  [FAIL] %s\n' "${mirrors[$i]}" >&2
    fi
  done
  rm -rf -- "$tmp"
  if ((${#results[@]} == 0)); then
    fail 'Hich mirror motabari peyda nashod' >&2; return 1
  fi
  printf '%s\n' "${results[@]}" | LC_ALL=C sort -n -t '|' -k1,1 | cut -d '|' -f2-
}
ubuntu_sources() {
  [[ -f /etc/apt/sources.list ]] && printf '%s\n' /etc/apt/sources.list
  [[ -f /etc/apt/sources.list.d/ubuntu.sources ]] && printf '%s\n' /etc/apt/sources.list.d/ubuntu.sources
}
apply_mirror() {
  local new=$1 old='' bdir timestamp file changed
  need_root && need_cmd python3 && need_cmd apt-get || return 1
  [[ "$new" =~ ^https?://[a-zA-Z0-9.-]+(/[a-zA-Z0-9._/-]+)?$ ]] || { fail 'URL namotabar'; return 1; }
  local state='/var/lib/srv-helper/last-mirror'
  [[ -r "$state" ]] && IFS= read -r old < "$state"
  timestamp=$(date -u +'%Y%m%dT%H%M%SZ')
  bdir="$(backup_dir)/apt-$timestamp-$$"
  install -d -m 700 "$bdir"
  local -a files=()
  while IFS= read -r file; do
    files+=("$file")
    cp -a -- "$file" "$bdir/$(basename "$file")"
  done < <(ubuntu_sources)
  if ((${#files[@]} == 0)); then fail 'Ubuntu APT source peyda nashod'; return 1; fi
  # Modify only the existing Ubuntu archive URLs; no third-party repos or security URLs.
  if ! python3 - "$new" "$old" "${files[@]}" <<'PY'
import pathlib, re, sys
new, old, *files = sys.argv[1:]
# Match only official Ubuntu archive hosts or the previously applied SRV Helper mirror.
base = r'https?://(?:[a-z0-9-]+\.)*archive\.ubuntu\.com/ubuntu/?'
pattern = re.compile(base + (r'|' + re.escape(old.rstrip('/')) + r'/?' if old.startswith(('http://','https://')) else ''), re.I)
changes = 0
for name in files:
    path = pathlib.Path(name)
    original = path.read_text()
    updated = pattern.sub(new, original)
    if updated != original:
        path.write_text(updated)
        changes += 1
if not changes:
    print('Archive URL dar sources.list/ubuntu.sources peyda nashod; changes=0', file=sys.stderr)
    sys.exit(3)
PY
  then
    for file in "${files[@]}"; do cp -a -- "$bdir/$(basename "$file")" "$file"; done
    fail 'Mirror taghir nakard; config ghabli hefz shod'; return 1
  fi
  info 'APT update test dar hale ejra ...'
  if DEBIAN_FRONTEND=noninteractive apt-get update; then
    install -d -m 700 /var/lib/srv-helper
    printf '%s\n' "$new" > "$state"
    chmod 600 "$state"
    printf '%s\n' "$bdir" > /var/lib/srv-helper/last-apt-backup
    success "Mirror set shod: $new"
    success "Backup: $bdir"
  else
    for file in "${files[@]}"; do cp -a -- "$bdir/$(basename "$file")" "$file"; done
    fail 'APT update fail shod; source ha automatic restore shodand'
    return 1
  fi
}
restore_mirror() {
  need_root || return 1
  local pointer='/var/lib/srv-helper/last-apt-backup' backup file original
  if [[ ! -r "$pointer" ]]; then fail 'Backup sabt nashode'; return 1; fi
  IFS= read -r backup < "$pointer"
  [[ "$backup" == /var/backups/srv-helper/apt-* && -d "$backup" ]] || { fail 'Backup namotabar'; return 1; }
  confirm "APT source ha az $backup restore shavand?" || return 1
  for original in /etc/apt/sources.list /etc/apt/sources.list.d/ubuntu.sources; do
    file="$backup/$(basename "$original")"
    [[ -f "$file" ]] && cp -a -- "$file" "$original"
  done
  rm -f /var/lib/srv-helper/last-mirror /var/lib/srv-helper/last-apt-backup
  DEBIAN_FRONTEND=noninteractive apt-get update || warn 'APT update bad az restore error dad'
  success 'Mirror restore shod'
}
mirror_menu() {
  local choice region code selected validated
  banner; section 'MODIRIAT APT MIRROR HA'
  if [[ "$(. /etc/os-release; echo "$ID")" != ubuntu ]]; then
    warn 'Mirror auto-apply faqat Ubuntu ra support mikonad; Debian/system haye digar taghir nemikonand.'
    pause; return
  fi
  code=$(. /etc/os-release; printf '%s' "${VERSION_CODENAME:-}")
  [[ -n "$code" ]] || { fail 'Ubuntu codename unknown'; pause; return; }
  menu_line 1 'Iran: test + entekhab behtarin'
  menu_line 2 'Europe: DE / NL / FR / UK'
  menu_line 3 'USA: US / Princeton'
  menu_line 4 'URL mirror delkhah (ba test)'
  menu_line 5 'Bargardandan APT ghabli'
  menu_line 0 'Bargasht'
  prompt 'Entekhab' choice || return
  case "$choice" in
    1) region='iran' ;;
    2) region='europe' ;;
    3) region='usa' ;;
    4)
      prompt 'URL (mesal: https://host.tld/ubuntu)' selected || return
      [[ "$selected" =~ ^https?://[a-zA-Z0-9.-]+(/[a-zA-Z0-9._/-]+)?$ ]] || { fail 'URL namotabar'; pause; return; }
      if ! validated=$(mirror_probe "${selected%/}" "$code"); then fail 'Mirror Release peyda nashod'; pause; return; fi
      selected=${selected%/}
      info "Response: ${validated}s"
      ;;
    5) restore_mirror; pause; return ;;
    0) return ;;
    *) warn 'Gozine namotabar'; pause; return ;;
  esac
  if [[ -n "${region:-}" ]]; then
    local -a ranked=()
    mapfile -t ranked < <(rank_mirrors "$region" "$code")
    if ((${#ranked[@]} == 0)); then fail 'Mirror motabar nist'; pause; return; fi
    selected=${ranked[0]}
    info "Fastest verified: $selected"
    info 'Note: Mirror test masir Release ra check mikonad; download speed vaghei momken ast fargh konad.'
  fi
  warn 'APT sources system taghir mikonand. Backup automatic ast.'
  if confirm "Mirror $selected apply shavad?"; then apply_mirror "$selected"; fi
  pause
}
