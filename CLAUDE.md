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

從 Notion「Read Later」資料庫篩選符合以下條件的文章：

- `Read` = 未勾選（尚未發送）

若**沒有**符合條件的文章 → 結束，不執行任何動作。

從篩選結果中取 **最新建立**（`Created` 欄位最新）的一篇。

### Step 2 — 取得文章內容

1. 從 page 的 `URL` 欄位取得原始文章連結
2. 嘗試用 WebFetch 爬取該 URL，**prompt 必須明確要求**：
   - 回傳可讀正文，**保留原文段落順序**
   - **逐一列出文章中所有圖片的完整 URL（markdown `![]()` 或 `<img src>`），並標明每張圖所在的段落位置（前後文）**

   ⚠️ WebFetch 內部會用小模型依 prompt 濃縮內容，若沒明講要圖片，圖片 URL 會被丟掉。因此抓取時務必把「列出所有圖片 URL + 所在段落」寫進 prompt，並把結果（正文 + 圖片清單）完整保留給 Step 3／Step 4 使用。
3. 若爬取失敗（403、404、已下架等）→ 改讀該 Notion page 的內文
4. 若 page 內文也是空的 → 在 `Claude Note` 欄位寫入 `❌ 摘要失敗：無法取得文章內容`，結束本次執行

### Step 3 — 生成摘要

依 article-summarizer 規則：

- 保留原文約 **50–70%** 的資訊量，維持作者語氣與段落結構
- 專有名詞（技術術語、產品名、套件名等）保留英文原文

### Step 4 — 組合 Email HTML

以 `templates/email.html` 為範本，填入下列欄位：

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

透過 **Resend API**：

```bash
curl -X POST 'https://api.resend.com/emails' \
  -H "Authorization: Bearer $RESEND_API_KEY" \
  -H 'Content-Type: application/json' \
  -d '{
    "from": "'"$RESEND_FROM_EMAIL"'",
    "to": "'"$TO_EMAIL"'",
    "subject": "[Claude 摘要] {文章標題}",
    "html": "{email_html}"
  }'
```

### Step 6 — 更新 Notion（寄送成功後）

- 將該 page 的 `Read` 勾選 ✅
- 將 `Summarized At` 填入今天日期
- 在 `Claude Note` 欄位寫入 `✅ 已成功摘要`

若寄送失敗（API 回傳非 2xx）：
- 在 `Claude Note` 欄位寫入 `❌ 摘要失敗：{失敗原因}`
