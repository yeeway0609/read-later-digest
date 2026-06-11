# 📙 Read-it-later Digest 稍後閱讀清單摘要 Agent

這是一個自動化的 Claude Agent，每隔三天從 Notion 閱讀清單中挑一篇文章、生成摘要，並寄送到你的信箱——讓那些「待讀」的文章真的被讀到。

## 痛點

大多數人的「稍後閱讀」清單都是文章墳場。文章越存越多，卻從來沒時間讀。這個 Agent 解決的就是這個問題：每隔三天自動挑一篇、幫你消化精華、直接送到信箱，你只需要打開來讀。

> 本專案在 **Claude Cowork** 執行，透過 **Notion MCP** 與 **Mailtrap MCP** 完成所有外部動作。

## 功能

每隔三天的早上 10:00，Agent 會自動：

1. 透過 **Notion MCP** 列舉資料庫文章，逐頁讀取真實屬性、找出尚未發送（`Read` 未勾選）的文章
2. 取最早加入的一篇（依各筆真實的 `Created` 升冪排序，取最舊）
3. **直接讀該篇 Notion 頁面的內文**（含圖片）作為原文，不爬原始 URL
4. 生成保留作者語氣與結構的摘要（保留約 70–80% 資訊量）
5. 若原文為英文，以「英文原段 + 深灰色中文翻譯」雙語交替格式排版；原文若有圖片也儘量保留，方便沉浸式閱讀
6. 透過 **Mailtrap MCP** 寄出 HTML 信件
7. 透過 **Notion MCP** 將該篇標記為已發送，並記錄發送日期與執行結果

> ⚠️ **關於「最舊」的取法**：Notion MCP 沒有 server-side 的 filter+sort 查詢工具，`search` 的回傳順序與 `timestamp` 並非可靠的時間排序。因此挑選時一律「列舉候選 → 逐頁 `fetch` 取真實 `Created`／`Read` → 自行過濾未讀並升冪排序」，細節見 `CLAUDE.md` 的 Step 1。

## 使用情境

- **建立閱讀習慣**：把被動囤積的清單，變成每隔三天主動送到信箱的一篇精華
- **英文技術文章學習**：對照英文原文與中文翻譯，沉浸式閱讀不吃力
- **知識吸收**：摘要格式更好讀，也更容易回顧

## 使用到的工具

| 工具 | 用途 |
|------|------|
| [Claude Desktop](https://claude.com/download)（cowork） | 排程執行與本地檔案輸出 |
| [Notion](https://notion.so) | 文章資料庫（閱讀清單） |
| [Notion MCP](https://developers.notion.com/guides/mcp/overview) | 透過 MCP 查詢／回寫資料庫（fetch / search / update-page） |
| [Mailtrap MCP](https://docs.mailtrap.io/) | 透過 MCP 寄送 Email |

## Notion 資料庫欄位

| 欄位 | 類型 | 說明 |
|------|------|------|
| `Name` | 標題 | 文章標題 |
| `URL` | URL | 原始文章連結 |
| `Read` | 勾選框 | 是否已發送摘要 |
| `Summarized At` | 日期 | 摘要寄出的日期 |
| `Claude Note` | 文字 | 執行結果（`✅ 已成功摘要` / `❌ 摘要失敗：{原因}`） |

## 安裝與設定

### 1. 建立 Notion 資料庫

建立一個包含以下欄位的資料庫：

| 欄位 | 類型 |
|------|------|
| `Name` | 標題 |
| `URL` | URL |
| `Read` | 勾選框 |
| `Summarized At` | 日期 |
| `Claude Note` | 文字 |

建立後，從資料庫網址複製 Database ID：
```
https://notion.so/your-workspace/<DATABASE_ID>?v=...
```

### 2. 連接 Notion MCP

在 **Claude Desktop** 的 MCP 設定中加入並授權 **Notion MCP**（見 [Notion MCP 指南](https://developers.notion.com/guides/mcp/overview)）。授權的帳號需能存取上面建立的「📙 Read Later」資料庫。

> Notion 的授權／token 由 Notion MCP server 持有，**不放在本專案的 `.env`**。

### 3. 連接 Mailtrap MCP

在 **Claude Desktop** 的 MCP 設定中加入並授權 **Mailtrap MCP**（見 [Mailtrap 文件](https://docs.mailtrap.io/)），並設定其 API token 與寄件網域。

> **寄件地址說明**：寄件地址需為 Mailtrap 已驗證的網域／地址。Mailtrap 的 API token 由 Mailtrap MCP server 持有，**不放在本專案的 `.env`**。

### 4. 設定環境變數

`.env` 只保留**非機密**的識別碼與收／寄件地址（金鑰都在各 MCP server 設定裡）。複製 `.env.example` 為 `.env`，並填入你的值：

```bash
cp .env.example .env
```

```
TO_EMAIL=you@youremail.com                  # 摘要寄到這裡
MAIL_FROM_EMAIL=digest@yourdomain.com       # Mailtrap 已驗證的寄件地址（若 MCP 已設定預設寄件者可省略）
NOTION_DATABASE_URL=https://www.notion.so/your-workspace/YOUR_DATABASE_ID
NOTION_DATA_SOURCE_ID=collection://YOUR_DATA_SOURCE_ID
```

Data Source ID（`collection://<uuid>`）可在 Notion MCP `fetch` 資料庫時，從回傳的 `<data-source url="collection://…">` 取得，直接整串交給 Notion MCP 使用即可。

### 5. 建立排程任務

在 **Claude Desktop cowork** 中告訴 Claude：

> 「幫我依照 CLAUDE.md 的排程設定建立排程任務（每三天早上 10:00 執行，cron：`0 10 */3 * *`）。」

在 cowork 中會以排程任務（scheduled task）的方式建立。

> 排程任務執行時需要 **Notion MCP** 與 **Mailtrap MCP** 已連線授權即可（文章內容直接讀 Notion 頁面，不需要 WebFetch／對外爬網）。

第一次先手動執行一次，預先授權所需的 MCP 工具權限，避免之後自動執行時卡在等待確認。

### 6. 新增文章（用 Web Clipper 連內容一起存）

用 **[Notion Web Clipper](https://www.notion.com/web-clipper)**（瀏覽器擴充或分享選單）把文章存進「📙 Read Later」資料庫，**讓整篇正文與圖片一起被擷取進頁面內文**，並確認 `URL` 欄位有原文連結、`Read` 保持未勾選。

> ⚠️ **重要前提**：Agent 直接讀 Notion **頁面內文**作為原文（不爬原始 URL），所以存文章時務必讓 Web Clipper 把全文擷取進頁面。若頁面只有標題、內文是空的，該篇會被標記為 `❌ 摘要失敗：Notion 頁面無內容`。

Agent 每隔三天會自動挑最早加入（`Created` 最舊）的一篇發送。

## References

- [Notion Developers Docs](https://developers.notion.com/guides/mcp/get-started-with-mcp)
- [Mailtrap Docs](https://docs.mailtrap.io/guides/ai-powered-integrations/claude)
