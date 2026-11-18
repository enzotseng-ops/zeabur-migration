#!/usr/bin/env bash
# 每日備份範本：新主機上的資料庫 dump → 上傳到 S3 相容儲存（例如 Cloudflare R2）＋ sha256 清單。
# 用 systemd timer 或 cron 每天跑一次；失敗時讓 systemd 的 OnFailure 或 cron 的 MAILTO 通知你。
#
# 先把 DUMPS 改成你的容器與資料庫。需要的環境變數（放在權限 600 的 env 檔，由 systemd EnvironmentFile 載入）：
#   S3_ENDPOINT  例如 https://<account>.r2.cloudflarestorage.com
#   S3_BUCKET    bucket 名稱
#   AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY   只給這個 bucket 寫入權限的金鑰
# 需要：docker、aws CLI。在 Linux 新主機上以 root 執行。任何一個 dump 失敗就整批失敗（set -e），讓你收到通知。
set -euo pipefail
: "${S3_ENDPOINT:?}" "${S3_BUCKET:?}"
export AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION:-auto}   # R2 需要 auto
TS=$(date -u +%Y%m%dT%H%M%SZ); D=$(mktemp -d /var/tmp/backup-XXXX); trap 'rm -rf "$D"' EXIT
umask 077

# 容器名稱|使用者|資料庫|輸出檔名  （PostgreSQL）
DUMPS=(
  "my-postgres-container|app|appdb|appdb.dump"
)
for e in "${DUMPS[@]}"; do
  IFS='|' read -r c u db f <<<"$e"
  docker exec "$c" pg_dump -U "$u" -d "$db" -Fc --lock-wait-timeout=300s > "$D/$f"
done

# MongoDB（範例，不用就刪掉）：帳密從容器自己的環境變數讀，經 --config 檔傳入，不進指令列
# docker exec my-mongo sh -c 'umask 077; printf "password: \"%s\"\n" "$MONGO_INITDB_ROOT_PASSWORD" > /tmp/bk.yml; \
#   mongodump --config=/tmp/bk.yml -u "$MONGO_INITDB_ROOT_USERNAME" --authenticationDatabase=admin --gzip --archive --quiet; \
#   rc=$?; rm -f /tmp/bk.yml; exit $rc' > "$D/mongo.archive.gz"

# 確認每個檔都不是空的
for f in "$D"/*; do [ -s "$f" ] || { echo "empty dump: $f"; exit 1; }; done
( cd "$D" && sha256sum * > manifest.sha256 )
aws s3 cp --recursive --endpoint-url "$S3_ENDPOINT" "$D" "s3://$S3_BUCKET/prod/$TS/" --only-show-errors
# 上傳後核對檔案數
n_local=$(ls "$D" | wc -l); n_remote=$(aws s3 ls --endpoint-url "$S3_ENDPOINT" "s3://$S3_BUCKET/prod/$TS/" | wc -l)
[ "$n_local" -eq "$n_remote" ] || { echo "upload mismatch local=$n_local remote=$n_remote"; exit 1; }
echo "backup ok: prod/$TS ($(du -sh "$D" | cut -f1))"
