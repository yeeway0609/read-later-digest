# 📙 Read-it-later Digest 稍後閱讀清單摘要 Agent

每隔 **3 天**於 **10:00** 自動從 Notion「Read Later」資料庫挑一篇文章、生成摘要，並寄送到指定信箱。


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
- **Database URL**: `$NOTION_DATABASE_URL`
- **Data Source ID**: `$NOTION_DATA_SOURCE_ID`

> 本專案**直接打 Notion REST API**（透過 `.env` 的 `NOTION_API_KEY`，建議用 Personal Access Token），不使用 Notion MCP connector。讀取／回寫資料庫一律透過下方的 `scripts/notion_query.sh` 與 `scripts/notion_mark_read.sh` 兩支腳本。

### Schema

| 欄位 | 類型 | 說明 |
|------|------|------|
| `Read` | checkbox | 是否已發送摘要 |
| `Name` | title | 文章標題 |
| `URL` | url | 原始文章連結 |
| `Claude Note` | text | 執行結果（`✅ 已成功摘要` / `❌ 摘要失敗：{原因}`） |
| `Summarized At` | date | 摘要日期 |
| `Created` | created_time | 建立時間 |


## Workflow

### Step 1 — 挑選資料庫文章

執行 `scripts/notion_query.sh`，它會直接打 Notion REST API 的 Query a data source 端點，做 server-side 過濾與排序：

- 過濾：`Read` = 未勾選（`checkbox = false`）
- 排序：`Created` 升冪（最舊的在前）
- 只取 1 筆

```bash
bash scripts/notion_query.sh
```

- 輸出單行 JSON：`{"id":"<page_id>","name":"<標題>","url":"<原文連結>"}`，即「最早建立的未讀」那一篇。
- 若輸出 `{}`（沒有符合條件的文章）→ 結束，不執行任何動作。

> ⚠️ 不要用語意搜尋或頁面列表的顯示時間戳來判斷「最舊」——一律以本腳本的 server-side `filter + sort` 結果為準。後續步驟用到的 `page_id` / `URL` / 標題都取自這筆 JSON。

### Step 2 — 取得文章內容

1. 從 page 的 `URL` 欄位取得原始文章連結
2. 嘗試用 WebFetch 爬取該 URL，**prompt 必須明確要求**：
   - **回傳完整正文，不得縮寫、摘要或省略任何段落**，只做去廣告／導航列等非正文元素的格式清理，保留原文段落順序
   - **逐一列出文章中所有圖片的完整 URL（markdown `![]()` 或 `<img src>`），並標明每張圖所在的段落位置（前後文）**

   ⚠️ WebFetch 內部會用小模型依 prompt 濃縮內容，若沒明講要完整正文，內容會被大幅壓縮；若沒明講要圖片，圖片 URL 會被丟掉。因此抓取時務必把「完整正文（不摘要）+ 列出所有圖片 URL + 所在段落」寫進 prompt，並把結果（完整正文 + 圖片清單）完整保留給 Step 3／Step 4 使用。
3. 若爬取失敗（403、404、已下架等）→ 改讀該 Notion page 的內文
4. 若 page 內文也是空的 → 在 `Claude Note` 欄位寫入 `❌ 摘要失敗：無法取得文章內容`，結束本次執行

### Step 3 — 生成摘要

呼叫 `/article-summarizer` skill，將 Step 2 取得的正文（含圖片清單）交給它生成摘要。摘要的所有規則（資訊量比例、語氣、段落結構、專有名詞保留英文等）一律以該 skill 為準，本文件不重複定義。

### Step 4 — 組合 Email HTML

以 `email.template.html` 為範本，填入下列欄位：

| 欄位 | 內容 |
|------|------|
| **主旨** | `[Claude 摘要] {文章標題}` |
| **第一段** | `原文連結：{URL}` |
| **內文** | 摘要內容（見下方格式規則） |

**內文格式規則：**

- 原文為**中文** → 直接輸出繁中摘要段落
- 原文為**英文** → 每段「英文原文 + 深灰色（`#666666`）中文翻譯」交替呈現，達到沉浸式閱讀效果
- 若原文**含圖片**（Step 2 取得的圖片清單非空）→ **必須**保留，依原文圖文順序在對應段落用
  `<img src="{原圖URL}" style="max-width:100%; height:auto; display:block; margin:16px 0; border-radius:4px;">` 嵌入；
  不可省略、不可只用文字描述。若某段落原本就有圖，務必把圖放回該段落附近。

### Step 5 — 寄送 Email

先將組好的 Email HTML 寫入暫存檔，再呼叫 `scripts/send_email.sh`：

```bash
# 將 Step 4 組好的 HTML 寫到專案目錄下的暫存檔（沙箱可寫；寄完可刪）
cat > digest_email.html << 'EOF'
{email_html}
EOF

# 呼叫腳本寄送（腳本自動讀取 .env 中的金鑰與寄件設定）
bash scripts/send_email.sh "[Claude 摘要] {文章標題}" digest_email.html
```

腳本回傳非零 exit code 表示寄送失敗，錯誤訊息會輸出到 stderr。寄送完成後可刪除 `digest_email.html`。

### Step 6 — 更新 Notion（寄送成功後）

呼叫 `scripts/notion_mark_read.sh`（直接打 Notion REST API 的 Update page 端點），把該 page 的 `Read` 勾選 ✅、`Summarized At` 填今天日期、`Claude Note` 寫入結果：

```bash
# 用法：bash scripts/notion_mark_read.sh <page_id> "<claude_note>" [summarized_date]
# page_id 取自 Step 1 的 JSON；日期省略時預設今天
bash scripts/notion_mark_read.sh "{page_id}" "✅ 已成功摘要"
```

若寄送失敗（Resend 回傳非 2xx）：
- 不傳日期、改寫失敗原因（第三個參數傳空字串略過 `Summarized At`）：

```bash
bash scripts/notion_mark_read.sh "{page_id}" "❌ 摘要失敗：{失敗原因}" ""
```

腳本回傳非零 exit code 表示更新失敗，錯誤訊息會輸出到 stderr。
