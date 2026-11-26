#!/usr/bin/env bash
# Executed through an authenticated SSH channel on the source.
set -euo pipefail
export LC_ALL=C
((EUID == 0)) || exit 1
mode=${1:-}
case "$mode" in
  inventory)
    . /etc/os-release
    printf 'OS=%s\nVERSION=%s\nARCH=%s\nMACHINE=%s\n' "$ID" "$VERSION_ID" "$(dpkg --print-architecture)" "$(cat /etc/machine-id)"
    printf 'BYTES=%s\n' "$(timeout 120 du -sx -B1 / 2>/dev/null | awk '{print $1}')"
    for path in /srv /var/www; do
      if [[ -d "$path" && ! -L "$path" ]] && [[ -n $(find "$path" -mindepth 1 -maxdepth 1 -print -quit) ]]; then
        printf 'DATA=%s\n' "$path"
        data_bytes=$(du -sx -B1 "$path" | awk '{print $1}')
        printf 'DATA_BYTES=%s:%s\n' "$path" "$data_bytes"
        find "$path" -xdev -printf '%U:%G\n' | sort -u | while IFS=: read -r uid gid; do
          user=$(getent passwd "$uid" | cut -d: -f1) || user=''
          group=$(getent group "$gid" | cut -d: -f1) || group=''
          printf 'USER_ID=%s:%s\nGROUP_ID=%s:%s\n' "$uid" "$user" "$gid" "$group"
        done
      fi
    done
    if command -v pg_lsclusters >/dev/null; then
      clusters=$(pg_lsclusters -h)
      awk 'NF {print "POSTGRES="$1":"$2":"$3":"$4}' <<< "$clusters"
      if [[ -n "$clusters" && "$clusters" != *$'\n'* ]]; then
        read -r _ _ port status _ <<< "$clusters"
        if [[ "$status" == online ]]; then
          dbs=$(runuser -u postgres -- psql -X -At --port "$port" --dbname postgres -v ON_ERROR_STOP=1 \
            -c "SELECT datname FROM pg_database WHERE datname NOT IN ('postgres','template0','template1') ORDER BY datname")
          if [[ -n "$dbs" ]]; then printf '%s\n' "$dbs" | sed 's/^/PG_DATABASE=/'; fi
          tablespaces=$(runuser -u postgres -- psql -X -At --port "$port" --dbname postgres -v ON_ERROR_STOP=1 \
            -c "SELECT spcname FROM pg_tablespace WHERE spcname NOT IN ('pg_default','pg_global')")
          if [[ -n "$tablespaces" ]]; then printf '%s\n' "$tablespaces" | sed 's/^/PG_TABLESPACE=/'; fi
        fi
      fi
    fi
    for client in mariadb mysql; do
      if command -v "$client" >/dev/null &&
         version=$("$client" --batch --skip-column-names -e 'SELECT VERSION()' 2>/dev/null); then
        printf 'MYSQL=%s\nMYSQL_VERSION=%s\n' "$client" "$version"
        dbs=$("$client" --batch --skip-column-names -e "SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME NOT IN ('mysql','sys','performance_schema','information_schema') ORDER BY SCHEMA_NAME")
        if [[ -n "$dbs" ]]; then printf '%s\n' "$dbs" | sed 's/^/MYSQL_DATABASE=/'; fi
        break
      fi
    done
    for service in mysql.service mariadb.service postgresql.service docker.service; do
      if systemctl is-active --quiet "$service" 2>/dev/null; then printf 'ACTIVE=%s\n' "$service"; fi
    done
    findmnt -rn -o TARGET,FSTYPE | while read -r mount fs; do
      case "$fs" in ext[234]|xfs|btrfs|zfs|nfs|nfs4|cifs|ceph|fuseblk|vfat) ;; *) continue ;; esac
      [[ "$mount" != / ]] || continue
      mount=$(printf '%b' "$mount")
      [[ -d "$mount" && "$mount" != *$'\n'* ]] || continue
      printf 'VOLUME=%s\n' "$mount"
    done
    ;;
  packages) dpkg-query -W -f='${db:Status-Abbrev}\t${binary:Package}\t${Version}\n' ;;
  services) SYSTEMD_COLORS=0 systemctl list-unit-files --type=service --no-pager --no-legend ;;
  mounts) findmnt -rn -o TARGET,FSTYPE ;;
  filesystem)
    tar --create --file=- --numeric-owner --acls --xattrs --sparse --one-file-system \
      --exclude='./proc' --exclude='./sys' --exclude='./dev' --exclude='./run' \
      --exclude='./tmp' --exclude='./var/tmp' --exclude='./swapfile*' --exclude='./swap.img' \
      --exclude='./var/backups/srv-helper' --directory=/ . | gzip -1
    ;;
  postgres)
    version=$2 cluster=$3 port=$4
    [[ "$version" =~ ^[0-9]+$ && "$cluster" =~ ^[A-Za-z0-9_-]+$ && "$port" =~ ^[0-9]+$ ]] || exit 2
    runuser -u postgres -- "/usr/lib/postgresql/$version/bin/pg_dumpall" --port "$port" |
      sed -E '/^CREATE ROLE postgres;$/d; /^ALTER ROLE postgres /d'
    ;;
  mysql-accounts)
    client=$2
    [[ "$client" == mysql || "$client" == mariadb ]] || exit 2
    accounts=$("$client" --batch --skip-column-names -e "SELECT CONCAT(QUOTE(User),'@',QUOTE(Host)) FROM mysql.user WHERE User NOT IN ('root','mysql.session','mysql.sys','mysql.infoschema','mariadb.sys','debian-sys-maint') ORDER BY User,Host")
    if [[ -z "$accounts" ]]; then exit 0; fi
    while IFS= read -r account; do
      definition=$("$client" --batch --raw --skip-column-names -e "SHOW CREATE USER $account")
      [[ "$definition" == *$'\t'* ]] || exit 2
      printf '%s;\n' "${definition#*$'\t'}"
      "$client" --batch --raw --skip-column-names -e "SHOW GRANTS FOR $account" | sed 's/$/;/'
    done <<< "$accounts"
    ;;
  mysql)
    client=$2
    case "$client" in
      mariadb) dump=mariadb-dump ;;
      mysql) dump=mysqldump ;;
      *) exit 2 ;;
    esac
    schemas=$("$client" --batch --skip-column-names -e "SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME NOT IN ('mysql','sys','performance_schema','information_schema')")
    [[ -n "$schemas" ]] || exit 0
    mapfile -t databases <<< "$schemas"
    for schema in "${databases[@]}"; do [[ "$schema" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]*$ ]] || exit 2; done
    options=(--lock-all-tables --routines --events --triggers --hex-blob)
    if [[ "$client" == mysql ]]; then options+=(--set-gtid-purged=OFF); fi
    "$dump" "${options[@]}" --databases "${databases[@]}"
    ;;
  *) exit 2 ;;
esac
