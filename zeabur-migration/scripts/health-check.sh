#!/usr/bin/env bash
# 唯讀健康檢查範本：每行輸出「OK|WARN|FAIL 類別 說明」。不印機密、不寫入任何主機。
# 用 cron 每小時跑；有 FAIL 時再接你習慣的通知（Telegram、Email…）。
set -uo pipefail
SLOW=3   # 秒，超過算 WARN

# 名稱|網址|可接受的 HTTP 狀態碼（regex）
URLS=(
  "main-site|https://www.example.com/|^(200|30[1278])$"
  "api-health|https://api.example.com/health|^200$"
  "old-zeabur-redirect|https://myapp.zeabur.app/|^30[12]$"
)
# 要檢查憑證到期的網域
CERT_HOSTS=(www.example.com api.example.com)
CERT_WARN_DAYS=14

checks() {
for e in "${URLS[@]}"; do
  IFS='|' read -r n u ok <<<"$e"
  r=$(curl -s -o /dev/null -w '%{http_code} %{time_total}' -m 15 "$u" 2>/dev/null); c=${r%% *}; t=${r##* }
  if ! [[ $c =~ $ok ]]; then sleep 5; r=$(curl -s -o /dev/null -w '%{http_code} %{time_total}' -m 15 "$u" 2>/dev/null); c=${r%% *}; t=${r##* }; fi
  if ! [[ $c =~ $ok ]]; then echo "FAIL http $n code=$c (retried)"
  elif awk "BEGIN{exit !($t > $SLOW)}"; then echo "WARN http $n slow ${t}s"
  else echo "OK http $n $c ${t}s"; fi
done

for h in "${CERT_HOSTS[@]}"; do
  end=$(echo | openssl s_client -servername "$h" -connect "$h:443" 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
  if [ -z "$end" ]; then echo "FAIL cert $h unreadable"; continue; fi
  left=$(( ( $(date -d "$end" +%s 2>/dev/null || date -j -f '%b %e %T %Y %Z' "$end" +%s) - $(date +%s) ) / 86400 ))
  [ "$left" -lt "$CERT_WARN_DAYS" ] && echo "WARN cert $h ${left}d left" || echo "OK cert $h ${left}d"
done

# 在新主機本機跑時，可加上磁碟與容器檢查：
if command -v docker >/dev/null 2>&1; then
  use=$(df -P / | awk 'NR==2{gsub("%","",$5); print $5}')
  [ "$use" -ge 85 ] && echo "WARN disk / ${use}%" || echo "OK disk / ${use}%"
  # 只算異常結束（非 0）、重啟中、unhealthy；Coolify 的 helper 容器正常結束不算
  bad=$(docker ps -a --format '{{.Names}} {{.Status}}' | grep -E 'unhealthy|Restarting|Exited \([1-9]' | grep -v 'coolify-helper' || true)
  [ -n "$bad" ] && echo "$bad" | sed 's/^/FAIL container /' || echo "OK containers"
fi
}

# 有任何 FAIL 就以非 0 結束，方便 cron／systemd 接通知
out=$(checks); echo "$out"
! grep -q "^FAIL" <<<"$out"
