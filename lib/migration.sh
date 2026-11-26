#!/usr/bin/env bash

migration_remote() {
  local arg request='bash -s --'
  for arg; do
    [[ "$arg" =~ ^[A-Za-z0-9_-]+$ ]] || return 2
    request+=" $arg"
  done
  ssh -F /dev/null -T -p "$migration_port" -S "$migration_work/ssh" -o ControlMaster=no \
    -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$migration_work/known_hosts" \
    -o GlobalKnownHostsFile=/dev/null -o BatchMode=yes -o ConnectTimeout=10 \
    -o ServerAliveInterval=15 -o ServerAliveCountMax=3 -l "$migration_user" "$migration_host" \
    "$migration_priv $request" < "$SRV_HOME/lib/migration-remote.sh"
}

migration_value() {
  local file=$1 key=$2
  awk -F= -v key="$key" '$1==key {print substr($0,length(key)+2); exit}' "$file"
}

migration_checklist() {
  local index
  for index in "${!migration_labels[@]}"; do
    case "${migration_status[index]}" in
      ok) success "${migration_labels[index]}" ;;
      failed) fail "${migration_labels[index]}" ;;
      pending) info "${migration_labels[index]} (dar entezar)" ;;
      skipped) info "${migration_labels[index]} (anjam nashod)" ;;
    esac
  done
}

migration_phase() {
  migration_step=$1
  step "$((migration_step+1))" "${#migration_labels[@]}" "${migration_labels[migration_step]}"
}

migration_finish() {
  local rc=$?
  trap - EXIT INT TERM
  case "$rc" in
    20|21) migration_status[migration_step]=skipped ;;
    0) ;;
    *) migration_status[migration_step]=failed ;;
  esac
  section 'GOZARESH ENTEGHAL'
  migration_checklist
  if [[ -n ${migration_bundle:-} && -f "$migration_bundle" ]]; then
    info "Backup ramznegari-shode: $migration_bundle"
    if [[ ${migration_status[5]} == ok ]]; then
      sed -n 's/^DATA=/  File-ha restore shod: /p; s/^PG_DATABASE=/  Database PostgreSQL restore shod: /p; s/^MYSQL_DATABASE=/  Schema MySQL\/MariaDB restore shod: /p' "$migration_work/inventory"
    fi
  fi
  if [[ -n ${migration_work:-} ]]; then
    ssh -F /dev/null -p "$migration_port" -S "$migration_work/ssh" -O exit -l "$migration_user" "$migration_host" >/dev/null 2>&1 || :
    rm -rf -- "$migration_work"
  fi
  case "$rc" in
    0) success 'Marhalehaye entekhab-shode ba movafaghiat tamam shod.' ;;
    20|21) warn 'Amaliat laghv shod.' ;;
    *) fail 'Amaliat kamel nashod. Gozaresh bala ra barrasi konid.' ;;
  esac
  exit "$rc"
}

migration_wizard() (
  local mode=$1 migration_host migration_user migration_port pin key actual
  local migration_step=0 migration_work='' migration_bundle='' migration_priv=''
  local path manifest platform local_version local_arch bytes free value space_factor=2
  local pg='' mysql='' index db_version volumes
  local -a migration_labels=('Ettezaal SSH va tasdiq kelid' 'Barrasi Ubuntu, disk va service-ha' 'Backup database-ha' 'Enteghal file-ha' 'Ramznegari va barresi backup' 'Bazsazi va barresi maghsad')
  local -a migration_status=(pending pending pending pending pending pending)
  need_root || return 1
  for value in ssh ssh-keyscan ssh-keygen gpg tar sha256sum flock timeout gzip dd mountpoint; do
    need_cmd "$value" || { warn 'Baraye in bakhsh OpenSSH client, GnuPG va GNU tar ra nasb konid.'; return 1; }
  done
  [[ -t 0 && -t 1 ]] || { fail 'In amaliat be terminal taamoli niaz darad.'; return 1; }
  . /etc/os-release
  [[ "$ID" == ubuntu && -n ${VERSION_ID:-} ]] || { fail 'Maghsad bayad Ubuntu bashad.'; return 1; }
  local_version=$VERSION_ID
  local_arch=$(dpkg --print-architecture) || return 1
  info 'Ubuntu va architecture dar har do server bayad yeksan bashad.'
  info 'Baraye backup sazgar, neveshtan app-ha ra dar mabda motavaqef konid. Database dumps az engine gerefte mishavand.'
  prompt 'IP ya hostname server ghadimi' migration_host || return $?
  prompt 'User SSH (root ya karbar ba sudo -n)' migration_user || return $?
  prompt 'Port SSH (khali = 22)' migration_port || return $?
  migration_port=${migration_port:-22}
  [[ "$migration_host" =~ ^[A-Za-z0-9][A-Za-z0-9.:-]*$ && ${#migration_host} -le 253 &&
     "$migration_user" =~ ^[a-z_][a-z0-9_-]*$ && "$migration_port" =~ ^[0-9]{1,5}$ ]] &&
    ((10#$migration_port >= 1 && 10#$migration_port <= 65535)) ||
    { fail 'Moshakhasat SSH namotabar ast.'; return 1; }
  migration_port=$((10#$migration_port))
  info 'Fingerprint SHA256 kelid SSH mabda ra az console motmaen begirid.'
  prompt 'Fingerprint kelid ED25519 mabda (SHA256:...)' pin || return $?
  [[ "$pin" =~ ^SHA256:[A-Za-z0-9+/]{43}$ ]] || { fail 'Fingerprint namotabar ast.'; return 1; }
  path="$(backup_dir)/migration"
  install -d -m 700 "$path" || return 1
  exec 9>"$path/.lock" || return 1
  flock -n 9 || { fail 'Yek enteghal digar dar hale ejra ast.'; return 1; }
  migration_work=$(mktemp -d "$path/.work.XXXXXXXX") || return 1
  trap migration_finish EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  migration_phase 0
  ssh-keyscan -T 8 -p "$migration_port" -t ed25519 "$migration_host" > "$migration_work/keys" 2>/dev/null || return 1
  while IFS= read -r key; do
    actual=$(ssh-keygen -lf /dev/stdin <<< "$key" | awk '{print $2}')
    if [[ "$actual" == "$pin" ]]; then printf '%s\n' "$key" > "$migration_work/known_hosts"; break; fi
  done < "$migration_work/keys"
  [[ -s "$migration_work/known_hosts" ]] || { fail 'Fingerprint mabda match nashod.'; return 1; }
  ssh -F /dev/null -M -N -f -p "$migration_port" -S "$migration_work/ssh" -o StrictHostKeyChecking=yes \
    -o UserKnownHostsFile="$migration_work/known_hosts" -o GlobalKnownHostsFile=/dev/null \
    -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=3 \
    -l "$migration_user" "$migration_host" 9>&- || return 1
  if [[ "$migration_user" != root ]]; then migration_priv='sudo -n'; fi
  migration_status[0]=ok
  migration_phase 1
  manifest="$migration_work/inventory"
  migration_remote inventory > "$manifest" || { fail 'Dastresi root ya sudo -n va inventory mabda ra barrasi konid.'; return 1; }
  platform=$(migration_value "$manifest" OS)
  [[ "$platform" == ubuntu && $(migration_value "$manifest" VERSION) == "$local_version" &&
     $(migration_value "$manifest" ARCH) == "$local_arch" ]] || { fail 'Ubuntu version ya architecture yeksan nist.'; return 1; }
  value=$(migration_value "$manifest" MACHINE)
  [[ "$value" =~ ^[a-f0-9]{32}$ && "$value" != "$(cat /etc/machine-id)" ]] || { fail 'Mabda va maghsad bayad ID motefavet dashte bashand.'; return 1; }
  bytes=$(migration_value "$manifest" BYTES)
  free=$(df -PB1 "$path" | awk 'NR==2 {print $4}')
  if [[ "$mode" == restore ]]; then space_factor=4; fi
  [[ "$bytes" =~ ^[0-9]{1,16}$ && "$free" =~ ^[0-9]{1,16}$ ]] && ((free > bytes * space_factor + 268435456)) ||
    { fail 'Fazaye disk kafi nist  (backup va staging).'; return 1; }
  migration_remote packages > "$migration_work/packages.tsv" || return 1
  migration_remote services > "$migration_work/services.txt" || return 1
  migration_remote mounts > "$migration_work/mounts.txt" || return 1
  volumes=$(migration_value "$manifest" VOLUME)
  if [[ -n "$volumes" ]]; then
    warn 'Volume joda dar mabda vojood darad. Backup root filesystem in volume-ha ra cover nemikonad.'
    sed -n 's/^VOLUME=/  /p' "$manifest"
    if [[ "$mode" == restore ]]; then
      local mount
      while IFS= read -r mount; do
        case "$mount" in
          /srv|/srv/*|/var|/var/www|/var/www/*)
            fail "Volume app joda ast; restore khodkar motavaqef shod: $mount"
            return 1 ;;
        esac
      done < <(sed -n 's/^VOLUME=//p' "$manifest")
    fi
  fi
  pg=$(migration_value "$manifest" POSTGRES)
  mysql=$(migration_value "$manifest" MYSQL)
  if grep -qx 'ACTIVE=postgresql.service' "$manifest" && [[ -z "$pg" ]]; then fail 'PostgreSQL faal ast vali cluster peyda nashod.'; return 1; fi
  if grep -Eq '^ACTIVE=(mysql|mariadb)\.service$' "$manifest" && [[ -z "$mysql" ]]; then fail 'Database MySQL-compatible faal ast vali login local momken nist.'; return 1; fi
  if [[ -n "$pg" ]] && [[ $(grep -c '^POSTGRES=' "$manifest") != 1 || "$pg" != *:online* ]]; then
    fail 'In wizard baraye dump PostgreSQL be yek cluster online niaz darad.'
    return 1
  fi
  section 'PISHNAMAYESH'
  info "Ubuntu $local_version | $local_arch"
  info "Hajm takhmini root filesystem: $((bytes/1048576)) MiB"
  info "Package-ha: $(awk '$1=="ii" {count++} END {print count+0}' "$migration_work/packages.tsv")"
  info "Service-haye enabled: $(awk '$2=="enabled" {count++} END {print count+0}' "$migration_work/services.txt")"
  sed -n 's/^ACTIVE=/  Service faal: /p; s/^DATA=/  Masir app: /p; s/^PG_DATABASE=/  PostgreSQL: /p; s/^MYSQL_DATABASE=/  MySQL\/MariaDB: /p' "$manifest"
  info 'Backup: root filesystem, package list, service list, logical database dumps.'
  warn 'File-haye live snapshot block-level nistand. Disk-haye joda va bootloader joda modiriat mishavand.'
  if [[ "$mode" == restore ]]; then
    info 'Restore khodkar: /srv, /var/www va database-haye poshtibani-shode dar maghsad khali.'
    warn 'Package inventory, user-ha, Docker, SSH, network va config-haye digar baraye restore dasti dar backup mimanand.'
    migration_preflight_restore "$manifest" --plan || return 1
  fi
  if [[ -n "$mysql" ]]; then warn 'MySQL/MariaDB dump neveshtan ra movaghatian lock mikonad.'; fi
  confirm 'Backup va amaliat entekhab-shode shoroo shavad?' || return $?
  migration_status[1]=ok
  migration_phase 2
  if [[ -n "$pg" ]]; then
    IFS=: read -r db_version value index _ <<< "$pg"
    [[ "$db_version" =~ ^[0-9]+$ && "$value" =~ ^[A-Za-z0-9_-]+$ && "$index" =~ ^[0-9]+$ ]] || return 1
    migration_remote postgres "$db_version" "$value" "$index" > "$migration_work/postgres.sql" || return 1
  fi
  if [[ -n "$mysql" ]]; then
    [[ "$mysql" == mysql || "$mysql" == mariadb ]] || return 1
    migration_remote mysql "$mysql" > "$migration_work/mysql.sql" || return 1
    migration_remote mysql-accounts "$mysql" > "$migration_work/mysql-accounts.sql" || return 1
  fi
  if [[ -n "$pg$mysql" ]]; then migration_status[2]=ok; else migration_status[2]=skipped; fi
  migration_phase 3
  info 'Archive az SSH dar hale enteghal ast. In marhale momken ast tol bekeshad.'
  if ! migration_remote filesystem | dd status=progress of="$migration_work/root.tar.gz"; then
    fail 'Copy root filesystem fail shod (momken ast file-i dar mabda taghir karde bashad).'
    return 1
  fi
  gzip -t "$migration_work/root.tar.gz" && tar -tzf "$migration_work/root.tar.gz" >/dev/null || return 1
  migration_status[3]=ok
  migration_phase 4
  local -a files=(inventory packages.tsv services.txt mounts.txt root.tar.gz)
  [[ ! -f "$migration_work/postgres.sql" ]] || files+=(postgres.sql)
  [[ ! -f "$migration_work/mysql.sql" ]] || files+=(mysql.sql mysql-accounts.sql)
  (cd "$migration_work" && sha256sum -- "${files[@]}" > SHA256SUMS && sha256sum -c SHA256SUMS) || return 1
  info 'Passphrase backup ra dar prompt GnuPG vared konid va dar jay amn negah darid.'
  export GPG_TTY
  GPG_TTY=$(tty) || return 1
  if ! tar -C "$migration_work" -cf - -- "${files[@]}" SHA256SUMS |
       gpg --symmetric --cipher-algo AES256 --no-symkey-cache --output "$migration_work/backup.tar.gpg"; then return 1; fi
  [[ -s "$migration_work/backup.tar.gpg" ]] || return 1
  info 'Baraye tasdiq salamat archive, passphrase ra dobare vared konid.'
  if ! gpg --decrypt --no-symkey-cache "$migration_work/backup.tar.gpg" | tar -tf - >/dev/null; then
    fail 'Archive ramznegari-shode validate nashod.'
    return 1
  fi
  migration_bundle="$path/backup-$(date -u +%Y%m%dT%H%M%SZ)-${migration_work##*.}.tar.gpg"
  mv -T -- "$migration_work/backup.tar.gpg" "$migration_bundle" || return 1
  migration_status[4]=ok
  migration_phase 5
  if [[ "$mode" == restore ]] && grep -Eq '^(DATA|POSTGRES|MYSQL_DATABASE)=' "$manifest"; then
    migration_restore "$manifest" "$migration_work" || return 1
    migration_status[5]=ok
  else
    migration_status[5]=skipped
  fi
)

migration_pg_port() {
  local inventory=$1 source_cluster source_version target
  source_cluster=$(migration_value "$inventory" POSTGRES)
  source_version=${source_cluster%%:*}
  [[ "$source_version" =~ ^[0-9]+$ ]] || return 1
  command -v pg_lsclusters >/dev/null || return 1
  target=$(pg_lsclusters -h) || return 1
  [[ "$target" != *$'\n'* ]] || return 1
  awk -v version="$source_version" '$1==version && $4=="online" {print $3; found=1} END {exit !found}' <<< "$target"
}

migration_preflight_restore() {
  local inventory=$1 mode=${2:-} item pg port engine version current package available required parent kind id expected actual
  while IFS= read -r item; do
    case "$item" in /srv|/var/www) ;; *) return 1 ;; esac
    [[ "$(realpath -m -- "$item")" == "$item" ]] || { fail "Masir maghsad symlink darad: $item"; return 1; }
    parent=${item%/*}; parent=${parent:-/}
    required=$(awk -F= -v prefix="$item:" '$1=="DATA_BYTES" && index($2,prefix)==1 {print substr($2,length(prefix)+1); exit}' "$inventory")
    available=$(df -PB1 "$parent" | awk 'NR==2 {print $4}')
    [[ "$required" =~ ^[0-9]{1,16}$ && "$available" =~ ^[0-9]{1,16}$ ]] && ((available > required)) ||
      { fail "Fazaye disk maghsad kafi nist: $item"; return 1; }
    if [[ -L "$item" || ( -e "$item" && ! -d "$item" ) ||
          ( -d "$item" && -n $(find "$item" -mindepth 1 -maxdepth 1 -print -quit) ) ]]; then
      fail "Maghsad khali nist: $item"
      return 1
    fi
    if mountpoint -q -- "$item"; then fail "Maghsad mount jodagane ast: $item"; return 1; fi
  done < <(sed -n 's/^DATA=//p' "$inventory")
  while IFS=: read -r kind id expected; do
    [[ "$id" =~ ^[0-9]+$ && -n "$expected" ]] ||
      { fail "Owner ya group mabda namaloom ast: $id"; return 1; }
    actual=$(getent "$kind" "$id" | cut -d: -f1) || actual=''
    [[ "$actual" == "$expected" ]] ||
      { fail "$kind $id ($expected) dar maghsad yeksan nist."; return 1; }
  done < <(sed -n 's/^USER_ID=/passwd:/p; s/^GROUP_ID=/group:/p' "$inventory" | LC_ALL=C sort -u)
  if grep -q '^PG_TABLESPACE=' "$inventory"; then
    fail 'PostgreSQL tablespace joda darad. Restore dasti niaz ast.'
    return 1
  fi
  pg=$(migration_value "$inventory" POSTGRES)
  if [[ -n "$pg" ]]; then
    package="postgresql-${pg%%:*}"
    if port=$(migration_pg_port "$inventory"); then
      current=$(runuser -u postgres -- psql -X -At --port "$port" --dbname postgres -v ON_ERROR_STOP=1 -c \
        "SELECT datname FROM pg_database WHERE datname NOT IN ('postgres','template0','template1') UNION ALL SELECT rolname FROM pg_roles WHERE rolname <> 'postgres' AND rolname !~ '^pg_' UNION ALL SELECT relname FROM pg_class c JOIN pg_namespace n ON c.relnamespace=n.oid WHERE n.nspname NOT LIKE 'pg_%' AND n.nspname <> 'information_schema' AND c.relkind IN ('r','p','S','v','m','f');") || return 1
      [[ -z "$current" ]] || { fail 'PostgreSQL maghsad database ya role karbari darad.'; return 1; }
    elif [[ "$mode" == --plan ]] && ! command -v pg_lsclusters >/dev/null &&
         LC_ALL=C apt-cache show "$package" >/dev/null 2>&1; then
      info "Package $package bad az backup az APT nasb mishavad."
    else
      fail "PostgreSQL ${pg%%:*} online dar maghsad niaz ast."
      return 1
    fi
  fi
  engine=$(migration_value "$inventory" MYSQL)
  if [[ -n "$engine" ]]; then
    [[ "$engine" == mysql || "$engine" == mariadb ]] || return 1
    need_cmd "$engine" || return 1
    version=$(migration_value "$inventory" MYSQL_VERSION)
    current=$("$engine" --batch --skip-column-names -e 'SELECT VERSION()') || return 1
    [[ -n "$version" && "$current" == "$version" ]] || { fail 'Version database MySQL/MariaDB yeksan nist.'; return 1; }
    current=$("$engine" --batch --skip-column-names -e \
      "SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME NOT IN ('mysql','sys','performance_schema','information_schema')") || return 1
    [[ -z "$current" ]] || { fail 'MySQL/MariaDB maghsad schema karbari darad.'; return 1; }
    warn 'MySQL/MariaDB: schema, data, routine va trigger restore mishavand. Account va grant dasti set mishavand.'
  fi
}

migration_restore() {
  local inventory=$1 work=$2 item port engine names target_data old_data parent staged pg
  info 'Maghsad dobare barresi mishavad.'
  migration_preflight_restore "$inventory" --plan || return 1
  pg=$(migration_value "$inventory" POSTGRES)
  if [[ -n "$pg" ]] && ! command -v pg_lsclusters >/dev/null; then
    [[ "${pg%%:*}" =~ ^[0-9]+$ ]] || return 1
    info "Nasb package PostgreSQL ${pg%%:*} az APT..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y "postgresql-${pg%%:*}" || return 1
  fi
  migration_preflight_restore "$inventory" || return 1
  local -a items=()
  mapfile -t items < <(sed -n 's/^DATA=//p' "$inventory")
  if (("${#items[@]}")); then
    mkdir "$work/restore" || return 1
    for item in "${items[@]}"; do
      info "Amade sazi file-ha: $item"
      tar --extract --gzip --file="$work/root.tar.gz" --directory="$work/restore" \
        --numeric-owner --same-owner --same-permissions --acls --xattrs -- "./${item#/}" || return 1
      [[ -d "$work/restore$item" && ! -L "$work/restore$item" ]] || return 1
    done
  fi
  if [[ -s "$work/postgres.sql" ]]; then
    info 'Import PostgreSQL dar hale ejra ast.'
    port=$(migration_pg_port "$inventory") || return 1
    if ! runuser -u postgres -- psql -X --port "$port" --dbname postgres -v ON_ERROR_STOP=1 \
      < "$work/postgres.sql" > "$work/postgres-import.log" 2>&1; then
      fail 'Import PostgreSQL kamel nashod. Maghsad momken ast nimesaze bashad.'
      return 1
    fi
    names=$(runuser -u postgres -- psql -X -At --port "$port" --dbname postgres -v ON_ERROR_STOP=1 \
      -c "SELECT datname FROM pg_database WHERE datname NOT IN ('postgres','template0','template1') ORDER BY datname") || return 1
    [[ "$names" == "$(sed -n 's/^PG_DATABASE=//p' "$inventory")" ]] || { fail 'List database PostgreSQL yeksan nist.'; return 1; }
    success 'PostgreSQL import va list database-ha barrasi shod.'
  fi
  if [[ -s "$work/mysql.sql" ]]; then
    engine=$(migration_value "$inventory" MYSQL)
    [[ "$engine" == mysql || "$engine" == mariadb ]] || return 1
    info "Import $engine dar hale ejra ast."
    if ! "$engine" < "$work/mysql.sql" > "$work/mysql-import.log" 2>&1; then
      fail 'Import MySQL/MariaDB kamel nashod. Maghsad momken ast nimesaze bashad.'
      return 1
    fi
    names=$("$engine" --batch --skip-column-names -e \
      "SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME NOT IN ('mysql','sys','performance_schema','information_schema') ORDER BY SCHEMA_NAME") || return 1
    [[ "$names" == "$(sed -n 's/^MYSQL_DATABASE=//p' "$inventory")" ]] || { fail 'List schema MySQL/MariaDB yeksan nist.'; return 1; }
    success 'MySQL/MariaDB import va list schema-ha barrasi shod.'
  fi
  for item in "${items[@]}"; do
    info "Nasb file-ha: $item"
    parent=${item%/*}; parent=${parent:-/}
    staged=$(mktemp -d "$parent/.srv-helper-migration.XXXXXXXX") || return 1
    target_data="$staged/new"
    old_data="$staged/old"
    if ! cp -aT -- "$work/restore$item" "$target_data"; then rm -rf -- "$staged"; return 1; fi
    if [[ -d "$item" && ! -L "$item" && -z $(find "$item" -mindepth 1 -maxdepth 1 -print -quit) ]]; then
      mv -T -- "$item" "$old_data" || { rm -rf -- "$staged"; return 1; }
    fi
    if ! mv -nT -- "$target_data" "$item" || [[ -e "$target_data" ]]; then
      if [[ -d "$old_data" && ! -e "$item" ]]; then mv -T -- "$old_data" "$item" || :; fi
      fail "Nasb file kamel nashod: $item. Staging: $staged"
      return 1
    fi
    rm -rf -- "$staged"
    success "File-ha dar $item nasb shodand."
  done
  info 'Service va config-haye digar baraye restore dasti dar archive hastand.'
}

migration_menu() {
  local choice rc
  choose_menu choice 'BACKUP VA ENTEGHAL SERVER' 'In menu ra rooye Ubuntu maghsad ejra konid.' \
    1 'Backup ramznegari-shode az server ghadimi' \
    2 'Backup va restore file/database-haye poshtibani-shode' \
    0 'Bargasht' || return $?
  case "$choice" in
    1) migration_wizard backup; rc=$? ;;
    2) migration_wizard restore; rc=$? ;;
    0) return 0 ;;
    *) warn 'Gozine namotabar.'; return 1 ;;
  esac
  case "$rc" in
    20) SRV_BACK_REQUESTED=1 ;;
    21) SRV_EXIT_REQUESTED=1 ;;
  esac
  pause
  return "$rc"
}
