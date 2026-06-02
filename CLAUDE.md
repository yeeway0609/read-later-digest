# 📙 Read-it-later Digest 稍後閱讀清單摘要 Agent

每隔 **3 天**於 **10:00** 自動從 Notion「Read Later」資料庫挑一篇文章、生成摘要，並寄送到指定信箱。

> 本專案在 **Claude Desktop cowork** 執行，透過兩個 MCP 完成所有外部動作：
> - **Notion MCP**（<https://developers.notion.com/guides/mcp/overview>）：讀取／回寫 Read Later 資料庫。
> - **Mailtrap MCP**（<https://docs.mailtrap.io/>）：寄送 Email。
>
> Notion / Mailtrap 的金鑰一律設定在各自的 MCP server（Claude Desktop 的 MCP 設定）裡，**不放在 `.env`**；`.env` 只保留非機密的識別碼與收／寄件地址。


## 排程設定

排程相關的可調參數集中在此，調整後請重新建立排程任務（見 README「建立排程任務」）。

| 參數 | 值 | 說明 |
|------|-----|------|
| **執行時間** | `10:00` | 每次執行的時間（24 小時制） |
| **排程間隔天數** | `3` | 每隔幾天執行一次；`1` = 每天、`3` = 每三天 |

**對應 cron 表達式**：`0 10 */3 * *`

> 調整間隔天數時，同步修改 cron 的日欄位 `*/N`（例如改回每天為 `0 10 * * *`、每兩天為 `0 10 */2 * *`）。


## Notion 資料庫資訊

- **Database Name**: 📙 Read Later
- **Database URL**: 讀取 `.env` 的 `NOTION_DATABASE_URL`
- **Data Source ID**: 讀取 `.env` 的 `NOTION_DATA_SOURCE_ID`（格式 `collection://<uuid>`，直接交給 Notion MCP 使用）

> 透過 **Notion MCP** 存取資料庫（fetch / search / update-page 等工具）。MCP 的授權在 Claude Desktop 的 MCP 設定完成，本專案不存任何 Notion token。

### Schema

| 欄位 | 類型 | 說明 |
|------|------|------|
| `Read` | checkbox | 是否已發送摘要 |
| `Name` | title | 文章標題 |
| `URL` | url | 原始文章連結 |
| `Claude Note` | text | 執行結果（`✅ 已成功摘要` / `❌ 摘要失敗：{原因}`） |
| `Summarized At` | date | 摘要日期 |
| `Created` | created_time | 建立時間（系統自動，唯讀） |

> Notion MCP 以 SQLite 風格表示這些欄位，更新時的特殊格式見 Step 6。


## Workflow

### Step 1 — 挑選最舊的未讀文章（Notion MCP）

⚠️ **核心要求：必須選出「`Read` 未勾選」中 `Created` 最舊的那一篇。** Notion MCP **沒有** server-side 的 filter+sort 查詢工具，且：

- `notion-fetch` 對 data source（`collection://…`）只回 **schema、不含資料列**。
- `notion-search` 會回頁面清單，但**排序是語意相關度（非時間）、上限 25 筆、且不回傳 `Read`／`Created` 的真實值**。
- 只有 `notion-fetch` **單一頁面** 才會回該頁真實的 `Created`、`Read`、`URL`、`Name`。

因此**絕對不要**用 search 的回傳順序或其 `timestamp` 欄位來判斷「最舊」。一律照下列流程，用每筆**實際的 `Created` property 值**排序：

1. 用 `notion-search` 限定 `data_source_url = <NOTION_DATA_SOURCE_ID>`、`query_type: "internal"`、`page_size: 25`，列出候選頁面（取得每筆的 `id`）。
   - 為求涵蓋完整，可多跑幾個不同的廣義 `query`（例如標題常見字、`"article"`、`"http"`），或用 `filters.created_date_range` 以時間窗逐段列舉，把候選頁面 `id` 去重後合併。
2. 對每個候選頁面呼叫 `notion-fetch`，讀出 `<properties>` 裡的 **真實 `Read` 與 `Created`**。
3. 在本地**自行**過濾出 `Read == "__NO__"`（未讀）者，並用各自的 `Created` 值**升冪排序**，取第一筆 = 最舊的未讀文章。
4. 記下該頁的 `page_id`（`id`）、`URL`（`userDefined:URL` / `url` 欄位）、標題（`Name`）供後續步驟使用。
5. 若沒有任何未讀文章 → 結束，不執行任何動作。

> 這對應 memory「挑最舊/最新紀錄時，用實際 property 值列舉全部候選再排序，別信搜尋列表的時間戳」。寧可多 fetch 幾頁確認，也不要憑 search 排序下結論。

### Step 2 — 取得文章內容（直接讀 Notion 頁面）

> 文章內容**直接從 Notion 頁面**取得，不爬原始 URL。前提：存文章進資料庫前，已用 **Notion Web Clipper** 把整篇正文（含圖片）擷取進該頁面。這樣可避開 cowork 沙箱擋 WebFetch 的問題，也最穩定。

1. 用 `notion-fetch`（帶 Step 1 的 `page_id`）取得該頁的**完整內文**。Step 1 已 fetch 過該頁，可直接沿用其回傳的 `<page>` 內容，不需重抓。
2. 從回傳的 Notion-flavored Markdown 內文中取出：
   - **完整正文**：保留段落順序，不縮寫、不省略；交給 Step 3 摘要。
   - **所有圖片 URL**：內文中的 `![]()` / `<img src>`（Web Clipper 擷取的圖片），連同各圖所在段落位置一起保留，供 Step 4 依原文圖文順序嵌回。
3. `URL` 欄位（`userDefined:URL`）仍要保留，作為 Step 4 email 第一行的「原文連結」。
4. 若該頁 `<blank-page>`／內文為空（未先用 Web Clipper 擷取內容）→ 走 Step 6 的失敗分支，在 `Claude Note` 寫入 `❌ 摘要失敗：Notion 頁面無內容（請先用 Web Clipper 擷取全文）`，結束本次執行。

### Step 3 — 生成摘要

呼叫 `/article-summarizer` skill，將 Step 2 取得的正文（含圖片清單）交給它生成摘要。摘要的所有規則（資訊量比例、語氣、段落結構、專有名詞保留英文等）一律以該 skill 為準，本文件不重複定義。

### Step 4 — 組合 Email HTML

以 `email.template.html` 為範本，填入下列欄位：

| 欄位 | 內容 |
|------|------|
| **主旨** | `[Claude 摘要] {文章標題}` |
| **第一段** | `原文連結：<a href="{URL}">{URL}</a>`（href 與 link text 都填原始 URL，**不可**用「原文連結」等文字代替 link text） |
| **內文** | 摘要內容（見下方格式規則） |

**內文格式規則：**

- 原文為**中文** → 直接輸出繁中摘要段落
- 原文為**英文** → 每段「英文原文 + 深灰色（`#666666`）中文翻譯」交替呈現，達到沉浸式閱讀效果
- 若原文**含圖片**（Step 2 取得的圖片清單非空）→ **必須**保留，依原文圖文順序在對應段落用
  `<img src="{原圖URL}" style="max-width:100%; height:auto; display:block; margin:16px 0; border-radius:4px;">` 嵌入；
  不可省略、不可只用文字描述。若某段落原本就有圖，務必把圖放回該段落附近。

### Step 5 — 寄送 Email（Mailtrap MCP）

呼叫 **`mcp__Mailtrap__send-email`** 工具，傳入下列參數：

| 參數 | 值 |
|------|-----|
| `to` | `.env` 的 `TO_EMAIL`（**純字串**，格式 `email` 或 `name <email>`） |
| `from` | `.env` 的 `MAIL_FROM_EMAIL`（**純字串**，格式 `name <email>`，需為 Mailtrap 已驗證的寄件地址） |
| `subject` | `[Claude 摘要] {文章標題}` |
| `html` | Step 4 組好的完整 HTML |
| `text` | 純文字備用內文（一行摘要即可） |

> ⚠️ **地址格式**：`from` 與 `to` 都必須是**純字串**，例如 `claude-bot <noreply@yeeway.dev>` 或 `yiwei.suuu@gmail.com`。**不可傳 JSON object** `{"email": "...", "name": "..."}` —— Mailtrap API 不接受此格式，會回傳 400 錯誤。

> ⚠️ **Mailtrap MCP 啟動較慢**：有時候 session 初始化時 Mailtrap MCP 尚未就緒，`ToolSearch` 可能找不到 `mcp__Mailtrap__send-email`。遇到此情況**不要立即判斷為「未連接」**，應繼續執行 Step 1–4，在真正要呼叫寄信工具前再次 `ToolSearch("select:mcp__Mailtrap__send-email")`；若仍找不到才走失敗分支。

> Mailtrap 的 API token 由 Mailtrap MCP server（Claude Desktop MCP 設定）持有，**不放在 `.env`**。
> 寄送是對外送出訊息的動作；請依工具回傳判斷成功與否：回傳成功才進 Step 6 的成功分支，否則走失敗分支。

### Step 6 — 更新 Notion（Notion MCP）

用 **Notion MCP 的 `notion-update-page`**（`command: "update_properties"`）更新 Step 1 取得的 `page_id`。Notion MCP 的屬性格式如下：

- `Read`（checkbox）：`"__YES__"` = 勾選
- `Claude Note`（text）：結果文字
- `Summarized At`（date）：用展開欄位 `"date:Summarized At:start"` 填日期（`YYYY-MM-DD`），並設 `"date:Summarized At:is_datetime": 0`

**寄送成功**：

```jsonc
// notion-update-page
{
  "page_id": "{page_id}",
  "command": "update_properties",
  "properties": {
    "Read": "__YES__",
    "Claude Note": "✅ 已成功摘要",
    "date:Summarized At:start": "{今天 YYYY-MM-DD}",
    "date:Summarized At:is_datetime": 0
  }
}
```

**寄送失敗**（不寫 `Summarized At`、不勾 `Read`，只記失敗原因）：

```jsonc
// notion-update-page
{
  "page_id": "{page_id}",
  "command": "update_properties",
  "properties": {
    "Claude Note": "❌ 摘要失敗：{失敗原因}"
  }
}
```
