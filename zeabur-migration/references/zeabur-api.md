# Zeabur API 筆記

以下是 2026 年 11 月搬遷時用過的 GraphQL 操作；有標「未驗證」的是當時有用、但寫法沒有留下完整紀錄的部分。Zeabur 的 API 可能改版，**使用前先用 introspection 或官方文件確認欄位還在**。

## 連線

- 端點：`https://api.zeabur.com/graphql`
- 驗證：`Authorization: Bearer <token>`。token 在 Zeabur 後台的帳號設定中建立。
- token 放在權限 600 的檔案或環境變數 `ZEABUR_TOKEN`，不要寫進程式或 log。

`scripts/zeabur.py` 是一支小工具，包好了查 key／網域／自動重啟、改環境變數、重啟、302 轉址這幾項，只印 key 和狀態；暫停服務、關自動重啟、關自動部署請照下面的寫法自己送。

## 盤點（唯讀）

```graphql
# 服務的環境變數 key（不要取 value）
{ service(_id:"<SERVICE_ID>") { variables(environmentID:"<ENV_ID>") { key } } }

# 服務的網域
{ service(_id:"<SERVICE_ID>") { domains(environmentID:"<ENV_ID>") { domain redirectTo status } } }

# 自動重啟設定（restartHour 是 UTC）——未驗證：欄位名稱依當時紀錄推得，先用 introspection 確認
{ service(_id:"<SERVICE_ID>") { autoRestart(environmentID:"<ENV_ID>") { enabled restartHour } } }
```

SERVICE_ID、ENV_ID 可以從 Zeabur 後台網址找到，也可以查專案底下的服務清單（欄位名稱以當時的 schema 為準）。

## 改環境變數（寫入，要先問）

```graphql
mutation { createEnvironmentVariable(serviceID:"<SID>", environmentID:"<EID>", key:"K", value:"V") { key } }
mutation { updateSingleEnvironmentVariable(serviceID:"<SID>", environmentID:"<EID>", oldKey:"K", newKey:"K", value:"V") { key } }
mutation { deleteSingleEnvironmentVariable(serviceID:"<SID>", environmentID:"<EID>", key:"K") { key } }
mutation { restartService(serviceID:"<SID>", environmentID:"<EID>") }
```

改完要 `restartService` 才會生效。常見用途：切換時把舊站設成維護模式、關掉舊站的排程。

## 舊網址改 302（寫入，要先問）

先移除舊的 generated 網域，再用同一個子網域加回來，並帶上 `redirectTo`：

```graphql
mutation { removeDomain(domain:"myapp.zeabur.app") }
mutation { addDomain(serviceID:"<SID>", environmentID:"<EID>", domain:"myapp", isGenerated:true, redirectTo:"myapp.example.com") { domain redirectTo status } }
```

- 移除到加回之間，舊網址約有 20 秒會失效。
- 退回：同樣兩步，加回時不帶 `redirectTo`。
- POST 的 webhook 不要用這個方法，改用 `scripts/webhook-forwarder.Caddyfile`。

## 凍結舊服務（寫入，要先問）

```graphql
# 先關自動重啟，再暫停；順序反過來，每日排程會把服務拉起來
mutation { setAutoRestart(serviceID:"<SID>", environmentID:"<EID>", enabled:false) }
mutation { suspendService(serviceID:"<SID>", environmentID:"<EID>") }

# 關自動部署：把 watchPaths 改成不存在的路徑；改回 ["*"] 即可恢復
mutation { updateWatchPaths(serviceID:"<SID>", watchPaths:["__auto_deploy_disabled__/**"]) { _id } }
```

`setAutoRestart`、`suspendService` 的完整參數與回傳型別，這次的紀錄裡沒有完整寫下，**使用前先用 introspection 確認**。
