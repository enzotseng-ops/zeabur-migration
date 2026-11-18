# zeabur-migration：從 Zeabur 搬到自管主機的 Claude skill

把 Zeabur 上的網站、服務和 PostgreSQL／MongoDB／Redis，分批搬到自己管理的 VPS（Coolify／Docker）。
內容整理自一次實際完成的搬遷：13 個 app、14 個資料服務，分八次切換，約 37 小時完成。

搬遷紀錄：https://enzotseng.com/works/22

## 安裝

下載 `zeabur-migration.zip`（見 GitHub Releases）。zip 裡已經包含 `zeabur-migration/` 資料夾，解壓到 skills 目錄即可：

- Claude Code：`cd ~/.claude/skills && unzip zeabur-migration.zip`（結果是 `~/.claude/skills/zeabur-migration/SKILL.md`）
- 專案內使用：解壓到 `<你的專案>/.claude/skills/`

然後跟 Claude 說「我想把 Zeabur 上的服務搬到自己的主機」，它就會照這份 skill 的流程進行。

## 內容

| 檔案 | 用途 |
|---|---|
| `SKILL.md` | 流程：盤點 → 測試副本 → 分批手冊 → 切換 → 舊網址處理 → 收尾 |
| `references/runbook-template.md` | 每一批的切換手冊範本 |
| `references/zeabur-api.md` | 用過的 Zeabur GraphQL 操作 |
| `references/lessons.md` | 實際踩過的坑、Redis 的做法 |
| `scripts/pg-move.sh` | PostgreSQL 搬庫＋逐表筆數比對 |
| `scripts/mongo-move.sh` | MongoDB 搬庫＋集合筆數比對 |
| `scripts/pg-count.sql`、`scripts/mongo-count.js` | 筆數比對 |
| `scripts/zeabur.py` | 查環境變數 key、改變數、302 轉址（寫入前要確認） |
| `scripts/webhook-forwarder.Caddyfile` | 舊 zeabur.app 網址原樣轉送到新主機（給 webhook 用） |
| `scripts/daily-backup.sh`、`scripts/health-check.sh` | 每日備份、健康檢查範本 |

## 哪些經過實戰、哪些是範本

- **以實際用過的腳本為底，加上參數與防呆**：`pg-move.sh`（另加了版本檢查、清理；`pg-count.sql` 多了序號比對）、`mongo-move.sh`、`mongo-count.js`、`webhook-forwarder.Caddyfile`，以及 `references/zeabur-api.md` 裡的環境變數、轉址操作。
- **改寫後的冒煙測試**（2026-11-19，本機 Docker 測試容器）：`pg-move.sh` 平行與單檔模式、`mongo-move.sh`（含 TTL 集合）都測過——版本檢查、`CONFIRM_TARGET` 打錯會中止、目標已有資料會中止、加 `ALLOW_OVERWRITE=yes` 才覆蓋、搬完筆數一致回 0；`health-check.sh` 也跑過。「筆數不一致回 3」的分支沒測。
- **依實際做法改寫成通用版，沒有實跑過**：`zeabur.py`（只測了沒有終端機時會停下）、`daily-backup.sh`。請先在測試環境跑一次。
- `setAutoRestart`、`suspendService` 這次有用過，但完整參數沒有留下紀錄；查 `autoRestart` 的欄位寫法也沒有紀錄。使用前先用 GraphQL introspection 確認。

## 注意

- 這些腳本會覆蓋目標資料庫，所以需要 `CONFIRM_TARGET` 才會執行；目標已有資料時還要 `ALLOW_OVERWRITE=yes`。對正式環境的每一步，都應該由你本人確認。
- 只在 Zeabur → 單台 VPS（Coolify）、PostgreSQL／MongoDB／Redis 的組合驗證過。
- 授權：MIT（見 `LICENSE`），可自由使用、修改、再散布；依現況提供，使用風險自負。
