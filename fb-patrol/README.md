# FB Patrol Skill (Facebook 自動巡邏與回覆工具)

這是一個用於 Facebook 粉絲專頁的自動化巡邏與回覆工具，旨在協助管理員自動監控貼文並回覆留言。

## 🌟 主要功能
- **自動巡邏 (Patrol)**：掃描粉專最近的貼文，找出尚未回覆的留言。
- **AI 自動回覆**：根據設定的「無毒龍蝦」人設（或其他自定義人設）自動產生回覆內容。
- **歷史紀錄追蹤**：自動記錄已回覆的留言 ID，避免重複回覆，確保運作效率。

## 📁 檔案說明
- `fb_reply.py`：核心巡邏與回覆邏輯。
- `fb_post.py`：底層 Facebook API 串接工具，支援發文與讀取。
- `requirements.txt`：Python 依賴套件清單。
- `fb_reply_history.json`：已回覆留言的紀錄，第一次執行時在本機自動建立，已列入 `.gitignore`，不會上傳。

## 🚀 使用方式

### 1. 安裝依賴
```bash
pip install -r requirements.txt
```

### 2. 配置環境變數
為了安全起見，請將您的憑證設置為環境變數：
- `FB_ACCESS_TOKEN`：您的 Facebook Page Access Token。
- `FB_PAGE_ID`：您的粉絲專頁 ID。
- `FB_APP_ID`：您的 Facebook App ID。
- `MCP_API_KEY`：（選用）MCP 服務的 API Key。
- `FB_LOG_FILE`：（選用）互動紀錄檔路徑，預設為本資料夾的 `fb_interactions_log.jsonl`。
- `FB_QA_LIBRARY`：（選用）問答庫檔案路徑，預設為本資料夾的 `qa_library.md`。

### 3. 執行巡邏
```bash
python3 fb_reply.py
```

## ⚠️ 安全提醒
本專案已移除所有硬編碼的敏感資訊。在使用前，請確保正確配置您的環境變數，切勿將包含 Token 的程式碼再次上傳至公開倉庫。

---

This skill provides automated patrolling and replying capabilities for Facebook Pages.
- **Patrol**: Scans recent posts for new comments.
- **Auto-Reply**: Uses AI logic to reply to comments based on predefined personas.
- **History Tracking**: Keeps track of replied comments to avoid duplicates.
