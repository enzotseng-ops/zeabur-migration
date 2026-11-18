#!/usr/bin/env bash
# MongoDB：舊庫 → 新主機上的 MongoDB 容器（mongodump/mongorestore），搬完比對集合筆數。
# 在 Linux 新主機上以 root 執行。需要 docker。
#
# 用法：
#   CONFIRM_TARGET=<dst-container> mongo-move.sh <name> <dst-container> "<db1> <db2> ..."
#
#   來源 URI：$WORKDIR/<name>-src.url（權限 600）
#   目標 URI：$WORKDIR/<name>-dst.url（權限 600，從目標容器內部連，例如
#            mongodb://root:<url-encoded-pw>@localhost:27017/?authSource=admin）
#   會用 --drop 覆蓋目標上同名的集合，所以要 CONFIRM_TARGET 等於目標容器名稱。
#   ALLOW_DIFF_COLLECTIONS="db.coll db.coll2"：這些集合只比名稱與索引數（例如切換前仍有寫入的集合）。
#
# 環境變數：WORKDIR（預設 /root/migr）、MONGO_IMAGE（預設 mongo:7.0，主版本要和目標相同）
# URI 只寫進 0600 的暫存檔（--config 與 connect() 包裝檔），不會出現在指令列或輸出。URI 裡不能有 " 或 \。
# TTL 集合（有過期索引）筆數會浮動，只比名稱、索引數、ttl 旗標。
# 結束碼：0 一致；1 中止；2 參數錯；3 筆數不一致。
set -uo pipefail
N=${1:?name}; C=${2:?dst-container}; DBS=${3:?"db list"}
WORKDIR=${WORKDIR:-/root/migr}; IMG=${MONGO_IMAGE:-mongo:7.0}; ALLOW=${ALLOW_DIFF_COLLECTIONS:-}
HERE=$(cd "$(dirname "$0")" && pwd)
[ "${CONFIRM_TARGET:-}" = "$C" ] || { echo "ABORT: set CONFIRM_TARGET=$C to confirm collections on the target will be dropped"; exit 2; }
for f in "$WORKDIR/$N-src.url" "$WORKDIR/$N-dst.url"; do
  [ -s "$f" ] || { echo "ABORT: $f missing"; exit 2; }
  if grep -q '["\\]' "$f"; then echo "ABORT: $f contains \" or \\"; exit 2; fi
done
umask 077; chmod 700 "$WORKDIR"
T=$(date +%Y%m%dT%H%M%S); A=$WORKDIR/$N-mongo-$T; mkdir -p "$A"; TMPD=$(mktemp -d)
cleanup() { rm -rf "${TMPD:?}"; docker exec "$C" rm -f /tmp/mm-r.yml /tmp/mm-w.js >/dev/null 2>&1 || true; }
trap cleanup EXIT

printf 'uri: "%s"\n' "$(tr -d '\n' < "$WORKDIR/$N-dst.url")" > "$TMPD/r.yml"
docker cp "$TMPD/r.yml" "$C":/tmp/mm-r.yml || { echo ABORT_RESTORE; exit 1; }

T0=$(date +%s)
for DB in $DBS; do
  t=$(date +%s)
  docker run --rm -e DB="$DB" -v "$WORKDIR/$N-src.url":/s/url:ro -v "$A":/m "$IMG" sh -c \
    'umask 077; printf "uri: \"%s\"\n" "$(tr -d "\n" < /s/url)" > /tmp/c.yml; exec mongodump --config=/tmp/c.yml --gzip --archive=/m/$DB.archive.gz --db=$DB --quiet' \
    || { echo "dump failed db=$DB"; echo ABORT_DUMP; exit 1; }
  echo "dump db=$DB $(( $(date +%s)-t ))s"
  t=$(date +%s); LOG=$A/restore-$DB.log
  docker exec -i "$C" mongorestore --config=/tmp/mm-r.yml --drop --stopOnError --gzip --archive < "$A/$DB.archive.gz" >/dev/null 2>"$LOG" \
    || { echo "restore failed db=$DB"; tail -5 "$LOG"; echo ABORT_RESTORE; exit 1; }
  echo "restore db=$DB $(( $(date +%s)-t ))s"
done
echo "total $(( $(date +%s)-T0 ))s"

# 筆數比對：mongo-count.js 用全域 db，外面包一層 db = connect(...)，連線字串只存在 0600 檔
docker run --rm -v "$WORKDIR/$N-src.url":/s/url:ro -v "$HERE/mongo-count.js":/s/cnt.js:ro "$IMG" sh -c \
  'umask 077; printf "db = connect(\"%s\");\n" "$(tr -d "\n" < /s/url)" > /tmp/w.js; cat /s/cnt.js >> /tmp/w.js; mongosh --nodb --quiet --file /tmp/w.js' \
  > "$TMPD/src.all" 2>/dev/null
printf 'db = connect("%s");\n' "$(tr -d '\n' < "$WORKDIR/$N-dst.url")" > "$TMPD/w.js"; cat "$HERE/mongo-count.js" >> "$TMPD/w.js"
docker cp "$TMPD/w.js" "$C":/tmp/mm-w.js
docker exec "$C" mongosh --nodb --quiet --file /tmp/mm-w.js > "$TMPD/dst.all" 2>/dev/null
pick() { for DB in $DBS; do grep "^$DB\." "$1" || true; done; }
norm() { awk -v allow=" $ALLOW " '{ if (index(allow, " " $1 " ")) print $1, $3; else if ($4 == "ttl=yes") print $1, $3, $4; else print $0 }' | LC_ALL=C sort; }
pick "$TMPD/src.all" | norm > "$TMPD/s"; pick "$TMPD/dst.all" | norm > "$TMPD/d"
echo "archives kept: $A (contains production data; delete after the rollback window)"
if [ -s "$TMPD/s" ] && cmp -s "$TMPD/s" "$TMPD/d"; then echo "collections=$(wc -l < "$TMPD/d") MONGO_COUNTS_OK"; exit 0; fi
echo "collections src=$(wc -l < "$TMPD/s") dst=$(wc -l < "$TMPD/d") MONGO_COUNTS_DIFFERENT"
diff "$TMPD/s" "$TMPD/d" | head -20
exit 3
