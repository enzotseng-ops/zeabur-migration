#!/usr/bin/env bash
# PostgreSQL：舊庫（例如 Zeabur）→ 新主機上的 PostgreSQL 容器，搬完逐表比對筆數與序號。
# 在 Linux 新主機上以 root 執行。需要 docker。
#
# 用法：
#   CONFIRM_TARGET=<dst-container>/<dst-db> pg-move.sh <name> <dst-container> <dst-user> <dst-db> [jobs]
#
#   name           代號；來源連線字串放在 $WORKDIR/<name>-src.url（權限 600，內容是 postgres://...）
#   dst-container  新主機上目標 PostgreSQL 的 docker 容器名稱
#   dst-user/db    目標資料庫的使用者與資料庫名稱
#   jobs           選填。給數字（例如 4）就用 -Fd 平行 dump/restore（會先 DROP 再 CREATE 目標庫），適合大庫；
#                  不給就用單檔 -Fc，在單一交易內 --clean 還原
#   CONFIRM_TARGET 必填，要等於「容器/資料庫」。因為會清空目標庫，用來防止打錯參數。
#
# 環境變數：WORKDIR（預設 /root/migr）、PG_IMAGE（預設 postgres:18）。
#   dump 用 PG_IMAGE 的 pg_dump，還原用目標容器自己的 pg_restore，所以 PG_IMAGE 的主版本
#   必須和目標容器相同，且不低於來源。腳本會先檢查，不符就中止。
#
# 不會印出連線字串或密碼。dump 檔留在 $WORKDIR（0700），含正式資料，回滾期過後要自己刪。
# 在停寫入（維護模式／唯讀）之後才對正式庫執行，否則 dump 會拖慢正式站，搬完的資料也不是最終版。
# 結束碼：0 一致；1 失敗；2 參數錯；3 筆數不一致。
set -euo pipefail
N=${1:?name}; C=${2:?dst-container}; U=${3:?dst-user}; DB=${4:?dst-db}; J=${5:-}
WORKDIR=${WORKDIR:-/root/migr}; IMG=${PG_IMAGE:-postgres:18}
HERE=$(cd "$(dirname "$0")" && pwd)
[ "${CONFIRM_TARGET:-}" = "$C/$DB" ] || { echo "ABORT: set CONFIRM_TARGET=$C/$DB to confirm the target database will be overwritten"; exit 2; }
[ -z "$J" ] || [[ $J =~ ^[1-9][0-9]?$ ]] || { echo "ABORT: jobs must be a number"; exit 2; }
[ -s "$WORKDIR/$N-src.url" ] || { echo "ABORT: $WORKDIR/$N-src.url missing"; exit 2; }
umask 077; chmod 700 "$WORKDIR"
cleanup() { docker exec "$C" rm -rf /tmp/pgm-r.dir /tmp/pgm-r.dump /tmp/pgm-count.sql >/dev/null 2>&1 || true; }
trap cleanup EXIT
cleanup

# 版本檢查：工具映像 vs 目標 vs 來源
tool=$(docker run --rm "$IMG" pg_dump --version | grep -oE '[0-9]+' | head -1)
dst=$(docker exec "$C" pg_restore --version | grep -oE '[0-9]+' | head -1)
src=$(docker run --rm -v "$WORKDIR":/m "$IMG" sh -c "psql -tA -d \"\$(cat /m/$N-src.url)\" -c 'SHOW server_version_num'" | cut -c1-2)
echo "versions: source=$src tool=$tool target=$dst"
[ "$tool" = "$dst" ] || { echo "ABORT: PG_IMAGE major ($tool) must equal target major ($dst)"; exit 2; }
[ "$tool" -ge "$src" ] || { echo "ABORT: target major ($dst) is older than source ($src)"; exit 2; }

cp "$HERE/pg-count.sql" "$WORKDIR/pg-count.sql"
T=$(date +%Y%m%dT%H%M%S); t0=$(date +%s)
if [ -n "$J" ]; then
  OUT=$N-final-$T.dir
  docker run --rm -v "$WORKDIR":/m "$IMG" sh -c "umask 077; pg_dump --no-owner --no-acl -Fd -j $J -d \"\$(cat /m/$N-src.url)\" -f /m/$OUT"
  echo "dump $(( $(date +%s)-t0 ))s size=$(du -sh "$WORKDIR/$OUT" | cut -f1)"
  docker cp "$WORKDIR/$OUT" "$C":/tmp/pgm-r.dir
  t1=$(date +%s)
  docker exec "$C" psql -q -U "$U" -d postgres -c "DROP DATABASE IF EXISTS \"$DB\" WITH (FORCE);" -c "CREATE DATABASE \"$DB\" OWNER \"$U\";"
  docker exec "$C" pg_restore -U "$U" -d "$DB" --no-owner --no-acl -j "$J" --exit-on-error /tmp/pgm-r.dir
else
  OUT=$N-final-$T.dump
  docker run --rm -v "$WORKDIR":/m "$IMG" sh -c "umask 077; pg_dump --no-owner --no-acl -Fc -d \"\$(cat /m/$N-src.url)\" -f /m/$OUT"
  echo "dump $(( $(date +%s)-t0 ))s bytes=$(stat -c %s "$WORKDIR/$OUT") sha256=$(sha256sum "$WORKDIR/$OUT" | cut -c1-16)"
  docker cp "$WORKDIR/$OUT" "$C":/tmp/pgm-r.dump
  t1=$(date +%s)
  docker exec "$C" pg_restore -U "$U" -d "$DB" --clean --if-exists --no-owner --no-acl --single-transaction --exit-on-error /tmp/pgm-r.dump
fi
echo "restore $(( $(date +%s)-t1 ))s"

# 逐表比對筆數與序號（來源 vs 目標）
docker run --rm -v "$WORKDIR":/m "$IMG" sh -c "psql -q -d \"\$(cat /m/$N-src.url)\" -f /m/pg-count.sql 2>&1" | sed 's/.*NOTICE:  //' > "$WORKDIR/$N-src.cnt"
docker cp "$WORKDIR/pg-count.sql" "$C":/tmp/pgm-count.sql
docker exec "$C" psql -q -U "$U" -d "$DB" -f /tmp/pgm-count.sql 2>&1 | sed 's/.*NOTICE:  //' > "$WORKDIR/$N-dst.cnt"
echo "dump kept: $WORKDIR/$OUT (contains production data; delete after the rollback window)"
if cmp -s "$WORKDIR/$N-src.cnt" "$WORKDIR/$N-dst.cnt"; then
  echo "lines=$(wc -l < "$WORKDIR/$N-dst.cnt") COUNTS_IDENTICAL"; exit 0
fi
echo "COUNTS_DIFFERENT"; diff "$WORKDIR/$N-src.cnt" "$WORKDIR/$N-dst.cnt" | head -10 || true
exit 3
