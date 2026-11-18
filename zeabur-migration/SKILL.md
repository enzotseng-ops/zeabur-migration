---
name: zeabur-migration
description: >-
  Move apps and their PostgreSQL / MongoDB / Redis databases off Zeabur onto a
  self-managed VPS (Coolify, Docker), batch by batch, with rehearsals, row-count
  verification, written rollback, old-URL redirects and a daily backup.
  把 Zeabur 上的網站、服務和資料庫分批搬到自己管理的主機（VPS＋Coolify）。
  Use this skill whenever the user wants to leave Zeabur, 搬離 Zeabur, 從 Zeabur 搬家,
  move a Zeabur project to a VPS / Hetzner / 騰訊雲 / AWS Lightsail / their own server,
  migrate a Zeabur PostgreSQL or MongoDB, keep old *.zeabur.app URLs working after a move,
  or plan a cutover / 切換 / 停機搬遷 of anything currently hosted on Zeabur —
  even if they only describe the goal ("Zeabur 太貴了想自己架", "把服務收到一台主機").
---

# 從 Zeabur 搬到自管主機

這份 skill 整理自一次實際完成的搬遷（2026 年 11 月）：13 個 app、10 個 PostgreSQL、1 個 MongoDB、3 個 Redis，
從 Zeabur 兩台專用主機＋一台辦公室電腦，分八次搬到一台裝了 Coolify 的 VPS，約 37 小時切完，有比對的資料表筆數全部一致。

它適用的範圍就是那次做過的事：**Zeabur → 單台 VPS（Coolify／Docker）**，資料庫是 **PostgreSQL、MongoDB、Redis**。
MySQL、物件儲存、Zeabur 共享叢集上的 volume 等沒有實測過；遇到時照同樣的原則做，但要明白告訴使用者那部分沒有驗證過。

## 先講好的規矩（為什麼重要）

搬家會碰到別人的正式環境和客人的資料，出錯的代價很高，所以：

1. **正式環境的每一個寫入動作，都要先得到使用者在對話裡的同意**：改 DNS、改 Zeabur 環境變數、停或暫停服務、dump 正式庫、restore、改轉址。唯讀查詢可以直接做。把「要做什麼、影響誰、怎麼退回」講清楚再問。
2. **不要印出任何機密**：連線字串、密碼、token 只放在權限 600 的檔案裡，用腳本讀檔；列環境變數時只印 key 或主機名。篩選條件要窄，例如 `ADS_*` 這種前綴可能順帶比對到 `*_SECRET`。
3. **舊的先凍結，不要刪**：舊服務設唯讀或暫停，保留到回滾期結束，再由使用者決定何時刪。
4. **每一批都要有能執行的回滾步驟**，而且在動手前寫下來。
5. **預估和實測都記下來**：停機時間、筆數、指令結果寫進手冊，之後才有辦法判斷做得好不好。

## 工作流程

### 1. 唯讀盤點

目標是一張完整的清單，漏掉的東西會在切換後變成事故。

- Zeabur：每個專案、服務、網域（含 `*.zeabur.app`）、環境變數的 **key**、資料庫的種類和大小。
  - 每個服務的 **自動重啟（autoRestart）設定** 也要查。Zeabur 的每日自動重啟會把已暫停的服務拉起來，詳見 `references/lessons.md`。
  - 怎麼查見 `references/zeabur-api.md`。
- 誰會連進來：webhook 呼叫端（LINE、Meta、金流）、OAuth 回呼網址、其他系統直連的資料庫，以及 **預備／staging 環境**。這幾類最容易漏。
- DNS：網域在哪裡管、TTL、走不走 Cloudflare 代理。
- 備份現況：哪些資料庫有開自動備份。
- 流量低峰：用 log 或資料庫寫入量找出一天裡最安靜的時段。

把結果寫成 `inventory.md`。

### 2. 新主機與測試副本

- 開機器，裝 Coolify（或純 Docker），建一個「測試」環境。
- 把每個 app 部署上去，版本要跟 Zeabur 上的正式版一模一樣：**切換時不要夾帶功能變更**，出問題才分得出是搬家造成的還是新程式造成的。
- 每個資料庫各還原一份測試副本，確認 app 能開、能讀寫。
- 量一次 dump／restore 的時間。**從新主機 dump 正式庫會拖慢正式站**，量的時候要盯著正式站的延遲，必要時中止。

### 3. 分批與手冊

從風險低、回滾簡單的開始，例如只要改一筆 DNS 的個人網站。最大、最重要或有金流的排後面，在低峰時段做。

**彼此直連的服務要一起搬。** 跨區連資料庫一次往返可能就要幾十到上百毫秒，app 和它的資料庫分開，會讓每個請求變慢好幾秒。

每一批用 `references/runbook-template.md` 寫一份手冊，至少包含：

- 停寫入的方式：維護模式、把資料庫設成唯讀，或對 Mongo 下 `fsyncLock`。
- 搬庫指令和預估時間。
- 驗收清單。
- 回滾 A：DNS 指回舊站、解鎖舊庫。
- 回滾 B：資料庫有新寫入時，把新庫反向搬回舊處。附的腳本只做單向，反向指令要自己寫並預演。
- 公告時間，以及硬性上限（超過就回滾）。

寫好後交給另一個模型或另一個人審，再預演一次。

### 4. 切換

照手冊做，每一步都記下時間和結果。典型順序：

1. 停寫入，然後確認舊庫寫入量已經不再變動。
2. 搬庫：PostgreSQL 用 `scripts/pg-move.sh`，MongoDB 用 `scripts/mongo-move.sh`。Redis 的做法見 `references/lessons.md`。
3. 比對：`scripts/pg-count.sql`、`scripts/mongo-count.js` 要兩邊一致；PostgreSQL 的序號也要一致。
4. 新 app 改連新庫並啟動，用直連的方式驗收，例如帶 Host header 打新主機。
5. 改 DNS，從外部驗收。
6. 舊庫維持唯讀或拒絕連線，留著當回滾來源。

### 5. 舊網址怎麼辦

`*.zeabur.app` 網址無法靠 DNS 搬走：

- **一般網頁**：在 Zeabur 把網域改成 302 轉到新網址，做法見 `references/zeabur-api.md`。
- **webhook 和 OAuth 回呼**：這類請求多半是 POST，302 會讓 POST 變成 GET 或直接失敗。在 Zeabur 留一個 Caddy 轉送服務，把舊網址綁上去，原樣轉進新主機，見 `scripts/webhook-forwarder.Caddyfile`。等所有呼叫端都改成新網址後再關掉。
- 轉址生效時，舊網址會中斷約 20 秒。

### 6. 收尾

- 暫停舊服務時，**同時關掉它的 autoRestart**，也關掉自動部署（例如把 watchPaths 改成不存在的路徑），以免 git push 又部署到舊站。
- 每日備份：`scripts/daily-backup.sh` 是範本，把 dump 傳到異地（例如 S3／R2），附 sha256，失敗要通知。
- 至少做一次 **計時的還原演練**：從異地備份還原到另一台機器，記下花了幾分鐘。
- 健康檢查：`scripts/health-check.sh` 是範本，每小時檢查網址、憑證、磁碟、容器。
- 回滾期過後，列出 Zeabur 上可以關的東西，由使用者決定。

## 回報方式

每一批結束後，給使用者一段簡短報告：做了什麼、實測停機時間（和預估比較）、筆數比對結果、留下了哪些回滾來源和暫存檔（含個資的 dump 要排定刪除時間）、還有什麼沒做。

## 參考檔

- `references/runbook-template.md`：每批的手冊範本
- `references/zeabur-api.md`：本次用過的 Zeabur GraphQL 操作（盤點、改環境變數、轉址、暫停、關自動重啟）
- `references/lessons.md`：這次踩過的坑，以及 Redis 的做法
- `scripts/`：搬庫、比對、轉送、備份、健康檢查的腳本。每支檔頭都寫了用法和需要的環境變數。`.sh` 腳本是給 Linux 新主機以 root 執行的；`zeabur.py` 可在任何有 Python 3 的電腦上跑。
