#!/usr/bin/env bash
# Ubuntu/Debian mirror switching with Release validation, backup and rollback.
debian_mirror_candidates() {
  case "$1" in
    iran) printf '%s\n' \
      'https://mirror.iranserver.com/debian' \
      'https://mirror.arvancloud.ir/debian' \
      'https://mirror.pishgaman.net/debian' \
      'https://mirror.aminidc.com/debian' \
      'https://mirror.famaserver.com/debian' \
      'https://ftp.ir.debian.org/debian' \
      'https://deb.debian.org/debian' ;;
    europe) printf '%s\n' \
      'https://deb.debian.org/debian' \
      'https://ftp.de.debian.org/debian' \
      'https://ftp.nl.debian.org/debian' \
      'https://ftp.fr.debian.org/debian' \
      'https://ftp.uk.debian.org/debian' ;;
    usa) printf '%s\n' \
      'https://deb.debian.org/debian' \
      'https://ftp.us.debian.org/debian' \
      'https://mirror.math.princeton.edu/pub/debian' ;;
  esac
}
mirror_candidates() {
  local family=${2:-ubuntu}
  [[ "$family" == debian ]] && { debian_mirror_candidates "$1"; return; }
  # Ubuntu publishes non-x86 packages in the ports archive.
  local architecture
  architecture=$(dpkg --print-architecture) || return 1
  case "$architecture" in
    amd64|i386) ;;
    *) printf '%s\n' 'https://ports.ubuntu.com/ubuntu-ports'; return ;;
  esac
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
        'https://repo.linuxmirrors.ir/ubuntu' \
        'https://mirror.famaserver.com/archive' \
        'https://ubuntu.parsvds.com/ubuntu' \
        'https://mirror.faraso.org/ubuntu' \
        'https://mirrors.ubuntu.dimit.cloud/ubuntu' \
        'http://repo.iut.ac.ir/repo/Ubuntu' \
        'https://ir.archive.ubuntu.com/ubuntu' \
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
mirror_probe() (
  local url=$1 codename=$2 architecture file seconds rate transfer
  [[ "$codename" =~ ^[a-z0-9-]+$ ]] || return 1
  architecture=$(dpkg --print-architecture) || return 1
  file=$(mktemp) || return 1
  trap 'rm -f -- "$file"' EXIT
  transfer=$(curl --fail --silent --show-error --location --proto '=http,https' \
    --proto-redir '=http,https' --connect-timeout 3 --max-time 10 --max-filesize 2097152 \
    -o "$file" -w '%{time_total} %{speed_download}' "${url%/}/dists/$codename/Release" 2>/dev/null) || return 1
  read -r seconds rate <<< "$transfer"
  LC_ALL=C awk -v code="$codename" -v arch="$architecture" '
    $1 == "Codename:" && $2 == code { codename = 1 }
    $1 == "Suite:" && $2 == code { suite = 1 }
    $1 == "Architectures:" {
      for (i = 2; i <= NF; i++) if ($i == arch) architecture = 1
    }
    END { exit !((codename || suite) && architecture) }
  ' "$file" || return 1
  printf '%s' "$seconds"
  if [[ ${3:-} == --details ]]; then printf '|%s' "$rate"; fi
)
rank_mirrors() {
  local region=$1 codename=$2 family=${3:-ubuntu} url seconds probe rate i=0 jobfile
  local tmp required suite
  required=$(apt_archive_plan "$family" --suites) || return 1
  [[ -n "$required" ]] || required=$codename
  tmp=$(mktemp -d /tmp/srv-helper-mirrors.XXXXXXXX) || return 1
  section "TEST SORAT MIRROR | ${region^^}" >&2
  info 'Mirror ha ba 6 worker be surat parallel check mishavand...' >&2
  local -a mirrors=()
  mapfile -t mirrors < <(mirror_candidates "$region" "$family")
  for url in "${mirrors[@]}"; do
    # Each child writes to its own file, so output cannot interleave.
    (
      if probe=$(mirror_probe "$url" "$codename" --details); then
        IFS='|' read -r seconds rate <<< "$probe"
        while IFS= read -r suite; do
          [[ "$suite" == "$codename" ]] && continue
          mirror_probe "$url" "$suite" >/dev/null || exit 1
        done <<< "$required"
        printf '%s|%s%s\n' "$seconds" "$url" "${rate:+|$rate}" > "$tmp/$i.ok"
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
  printf '%s\n' "${results[@]}" | LC_ALL=C sort -n -t '|' -k1,1
}

select_ranked_mirror() {
  local destination=$1 region=$2 code=$3 family=$4 ranking
  local seconds url rate label index choice
  local -a entries=() options=()
  ranking=$(rank_mirrors "$region" "$code" "$family") || return 1
  while IFS='|' read -r seconds url rate; do
    index=$((${#entries[@]} + 1))
    label=$(LC_ALL=C awk -v seconds="$seconds" 'BEGIN {printf "%5.0f ms", seconds * 1000}')
    entries+=("$url")
    if [[ "$rate" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
      rate=$(LC_ALL=C awk -v rate="$rate" 'BEGIN {printf " | %5.0f KiB/s", rate / 1024}')
    else
      rate=''
    fi
    options+=("$index" "$label$rate  |  $url")
    ((index < 10)) || break
  done <<< "$ranking"
  local heading
  printf -v heading '\n  %s%s / %s / %s%s\n         %sRELEASE SAMPLE (TIME / RATE) | MIRROR%s' "$DIM" "${region^^}" "$family" "$code" "$RESET" "$C1" "$RESET"
  choose_menu choice 'SELECT AN APT MIRROR' "$heading" \
    "${options[@]}" 0 'Skip mirror change' || return $?
  if [[ ! "$choice" =~ ^([1-9]|10)$ ]] || ((choice > ${#entries[@]})); then
    [[ "$choice" == 0 ]] || warn 'Invalid mirror number.'
    return 1
  fi
  printf -v "$destination" '%s' "${entries[choice-1]}"
}
apt_source_files() (
  shopt -s nullglob
  local file
  for file in /etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
    [[ -f "$file" && ! -L "$file" ]] && printf '%s\n' "$file"
  done
  return 0
)

apt_archive_plan() {
  local family=$1 mode=$2 new=${3:-} old='' known
  local -a files=()
  [[ ! -r "$(state_dir)/last-mirror" ]] || IFS= read -r old < "$(state_dir)/last-mirror"
  known=$(mirror_candidates iran "$family") || return 1
  mapfile -t files < <(apt_source_files)
  python3 - "$mode" "$new" "$old" "$family" "$known" "${files[@]}" <<'PYCODE'
import os, pathlib, re, sys, tempfile
mode, new, old, family, known, *files = sys.argv[1:]
# Exclude dedicated security archives and unrelated third-party repositories.
if family == "ubuntu":
    base = r'https?://(?:[a-z0-9-]+\.)*archive\.ubuntu\.com/ubuntu/?|https?://ports\.ubuntu\.com/ubuntu-ports/?'
else:
    base = r'https?://(?:deb\.debian\.org/debian|ftp\.[a-z0-9.-]+\.debian\.org/debian)/?(?=/|[\s]|$)'
for url in [*known.splitlines(), old]:
    if url.startswith(("http://", "https://")):
        base += r"|https?://" + re.escape(url.split("://", 1)[1].rstrip("/")) + r"/?"
pattern = re.compile(r"(?:" + base + r")(?=\s|$)", re.I)
def transform(original, deb822):
    suites = set()
    archives = set()
    if not deb822:
        result = []
        for line in original.splitlines(keepends=True):
            source, comment, trailing = line.partition("#")
            fields = re.match(r"^\s*deb(?:-src)?\s+(?:\[[^]]*\]\s+)?(\S+)\s+(\S+)", source)
            if fields and pattern.fullmatch(fields[1]):
                suites.add(fields[2])
                archives.add(fields[1])
                source = source[:fields.start(1)] + new + source[fields.end(1):]
            result.append(source + comment + trailing)
        return "".join(result), suites, archives

    result = []
    for stanza in re.split(r"(\r?\n[ \t]*\r?\n)", original):
        fields = {}
        for field in re.finditer(r"^([\w-]+):[ \t]*(.*(?:\n[ \t]+[^\n]+)*)", stanza, re.M):
            fields[field[1].lower()] = field
        uris = fields.get("uris")
        enabled = fields.get("enabled")
        if uris and "suites" in fields and not (enabled and enabled[2].strip().lower() == "no"):
            matches = [uri for uri in uris[2].split() if pattern.fullmatch(uri)]
            if matches:
                suites.update(fields["suites"][2].split())
                archives.update(matches)
                replacement = re.sub(r"\S+", lambda token: new if pattern.fullmatch(token[0]) else token[0], uris[2])
                stanza = stanza[:uris.start(2)] + replacement + stanza[uris.end(2):]
        result.append(stanza)
    return "".join(result), suites, archives

all_suites = set()
all_archives = set()
matched = False
for name in files:
    path = pathlib.Path(name)
    original = path.read_text()
    updated, suites, archives = transform(original, path.suffix == ".sources")
    if not suites:
        continue
    matched = True
    all_suites.update(suites)
    all_archives.update(archives)
    if mode == "--files":
        print(name)
    elif mode == "--apply" and updated != original:
        info = path.stat()
        temporary = None
        try:
            with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, prefix=".srv-helper-", delete=False) as handle:
                temporary = pathlib.Path(handle.name)
                os.fchown(handle.fileno(), info.st_uid, info.st_gid)
                os.fchmod(handle.fileno(), info.st_mode & 0o7777)
                handle.write(updated)
                handle.flush()
                os.fsync(handle.fileno())
            temporary.replace(path)
        finally:
            if temporary is not None:
                temporary.unlink(missing_ok=True)
if mode == "--suites":
    print("\n".join(sorted(all_suites)), end="\n" if all_suites else "")
elif mode == "--archives":
    print(", ".join(sorted(all_archives)))
elif mode == "--apply" and not matched:
    sys.exit("No matching APT archives")
PYCODE
}

restore_apt_files() {
  local backup=$1 saved target failed=0
  shift
  if (($#)); then
    for target; do cp -aT -- "$backup$target" "$target" || failed=1; done
  else
    while IFS= read -r -d '' saved; do
      target=${saved#"$backup"}
      cp -aT -- "$saved" "$target" || failed=1
    done < <(find "$backup/etc/apt" -type f -print0)
  fi
  ((failed == 0))
}

apply_mirror() (
  local new=$1 bdir os_id family paths required suite file state_staged current
  need_root && need_cmd python3 && need_cmd apt-get || return 1
  os_id=$(. /etc/os-release; printf '%s' "${ID:-}")
  case "$os_id" in ubuntu|debian) family=$os_id ;; *) fail 'Only Ubuntu and Debian are supported.'; return 1 ;; esac
  [[ "$new" =~ ^https?://[a-zA-Z0-9.-]+(/[a-zA-Z0-9._/-]+)?$ ]] || return 1
  install -d -m 700 "$(state_dir)" "$(backup_dir)" || return 1
  exec 9>"$(state_dir)/apt.lock" || return 1
  flock -n 9 || { fail 'Another APT change is in progress.'; return 1; }
  paths=$(apt_archive_plan "$family" --files) || return 1
  required=$(apt_archive_plan "$family" --suites) || return 1
  [[ -n "$paths" && -n "$required" ]] || { fail 'No supported active APT archive found.'; return 1; }
  while IFS= read -r suite; do
    mirror_probe "$new" "$suite" >/dev/null || { fail "Missing compatible suite: $suite"; return 1; }
  done <<< "$required"
  section 'APT CHANGE PREVIEW'
  printf '  %s\n' "$paths"
  current=$(apt_archive_plan "$family" --archives) || return 1
  info "Current archives: $current"
  info "New archive: $new"
  info "Verified suites: ${required//$'\n'/, }"
  confirm 'Apply this APT mirror?' || return 1
  bdir=$(mktemp -d "$(backup_dir)/apt-$(date -u +%Y%m%dT%H%M%SZ).XXXXXXXX") || return 1
  local -a files=()
  mapfile -t files <<< "$paths"
  for file in "${files[@]}"; do cp -a --parents -- "$file" "$bdir" || return 1; done
  [[ ! -f "$(state_dir)/last-mirror" ]] || cp -a "$(state_dir)/last-mirror" "$bdir/previous-mirror" || return 1
  state_staged=$(mktemp "$(state_dir)/.last-mirror.XXXXXXXX") || return 1
  apt_rollback() {
    local rc=$?
    trap - EXIT
    rm -f -- "$state_staged"
    if restore_apt_files "$bdir" "${files[@]}"; then
      fail 'APT change failed. Source files restored.'
    else
      fail "APT rollback incomplete: $bdir"
    fi
    exit "$rc"
  }
  trap apt_rollback EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  printf '%s\n' "$new" > "$state_staged" || return 1
  apt_archive_plan "$family" --apply "$new" || return 1
  info 'Running APT update with signature verification...'
  DEBIAN_FRONTEND=noninteractive apt-get -o APT::Update::Error-Mode=any update || return 1
  mv -fT -- "$state_staged" "$(state_dir)/last-mirror" || return 1
  trap - EXIT INT TERM
  success "Mirror: $new"
  success "Backup: $bdir"
)

restore_mirror() (
  need_root || return 1
  local backup selected name pointer="$(state_dir)/last-apt-backup"
  local -a options=() backups=()
  local index=0
  [[ -d "$(state_dir)" ]] || { fail 'No APT backup found.'; return 1; }
  exec 9>"$(state_dir)/apt.lock" || return 1
  flock -n 9 || { fail 'Another APT change is in progress.'; return 1; }
  while IFS= read -r backup; do
    [[ -d "$backup/etc/apt" ]] || continue
    index=$((index+1))
    backups+=("$backup")
    options+=("$index" "${backup##*/}")
    ((index < 10)) || break
  done < <(find "$(backup_dir)" -maxdepth 1 -type d -name 'apt-*' 2>/dev/null | LC_ALL=C sort -r)
  if [[ -r "$pointer" ]] && IFS= read -r backup < "$pointer" &&
     [[ "$backup" == "$(backup_dir)"/apt-* && -d "$backup" && ! -d "$backup/etc/apt" ]]; then
    index=$((index+1))
    backups+=("$backup")
    options+=("$index" 'Legacy APT backup')
  fi
  (("${#backups[@]}")) || { fail 'No APT backup found.'; return 1; }
  choose_menu selected 'RESTORE APT SOURCES' '' "${options[@]}" 0 'Cancel' || return
  [[ "$selected" =~ ^[1-9][0-9]?$ ]] && ((selected <= index)) || return 1
  backup=${backups[selected-1]}
  confirm "Restore APT sources from ${backup##*/}?" || return 1
  if [[ -d "$backup/etc/apt" ]]; then
    restore_apt_files "$backup" || { fail "APT restore incomplete: $backup"; return 1; }
  else
    for name in /etc/apt/sources.list /etc/apt/sources.list.d/{ubuntu,debian}.sources; do
      if [[ -f "$backup/${name##*/}" ]]; then cp -aT -- "$backup/${name##*/}" "$name" || return 1; fi
    done
  fi
  if [[ -f "$backup/previous-mirror" ]]; then
    cp -a "$backup/previous-mirror" "$(state_dir)/last-mirror" || return 1
  else
    rm -f -- "$(state_dir)/last-mirror" || return 1
  fi
  DEBIAN_FRONTEND=noninteractive apt-get -o APT::Update::Error-Mode=any update ||
    { fail 'APT sources restored, but APT update failed.'; return 1; }
  success 'APT sources restored and package indexes refreshed.'
)

mirror_menu() {
  local choice region code selected validated family os_id
  os_id=$(. /etc/os-release; printf '%s' "${ID:-unknown}")
  case "$os_id" in
    ubuntu) family=ubuntu ;;
    debian) family=debian ;;
    *) warn 'Mirror auto faghat Ubuntu/Debian ra poshtibani mikonad.'; pause; return ;;
  esac
  code=$(. /etc/os-release; printf '%s' "${VERSION_CODENAME:-}")
  [[ -n "$code" ]] || { fail 'Codename system tashkhis dade nashod'; pause; return; }
  choose_menu choice 'MODIRIAT MIRROR HAYE APT' '' \
    1 'Iran: test and choose a mirror' \
    2 'Europe: DE / NL / FR / UK' \
    3 'USA: US / Princeton' \
    4 'URL mirror delkhah (ba test)' \
    5 'Bargardandan APT ghabli' \
    0 'Bargasht' || return
  case "$choice" in
    1) region='iran' ;;
    2) region='europe' ;;
    3) region='usa' ;;
    4)
      prompt 'URL mirror (Ubuntu: /ubuntu, Debian: /debian)' selected || return
      [[ "$selected" =~ ^https?://[a-zA-Z0-9.-]+(/[a-zA-Z0-9._/-]+)?$ ]] || { fail 'URL namotabar'; pause; return; }
      if ! validated=$(mirror_probe "${selected%/}" "$code"); then fail 'Mirror Release peyda nashod'; pause; return; fi
      selected=${selected%/}
      info "Zaman pasokh: ${validated}s"
      ;;
    5) restore_mirror; pause; return ;;
    0) return ;;
    *) warn 'Gozine namotabar'; pause; return ;;
  esac
  if [[ -n "${region:-}" ]]; then
    select_ranked_mirror selected "$region" "$code" "$family" || return
  fi
  warn 'Source haye APT taghir mikonand. Backup khodkar gerefte mishavad.'
  apply_mirror "$selected"
  pause
}
