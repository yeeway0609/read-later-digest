# 📙 Read-it-later Digest 稍後閱讀清單摘要 Agent

這是一個自動化的 Claude Agent，每隔三天從 Notion 閱讀清單中挑一篇文章、生成摘要，並寄送到你的信箱——讓那些「待讀」的文章真的被讀到。

## 痛點

大多數人的「稍後閱讀」清單都是文章墳場。文章越存越多，卻從來沒時間讀。這個 Agent 解決的就是這個問題：每隔三天自動挑一篇、幫你消化精華、直接送到信箱，你只需要打開來讀。

## 功能

每隔三天的早上 10:00，Agent 會自動：

1. 透過 Notion API 查詢資料庫，找出尚未發送的文章
2. 取最早加入的一篇（`Created` 最舊）
3. 爬取原始文章內容（若網站擋爬蟲，改用 Notion 頁面內容）
4. 生成保留作者語氣與結構的摘要（保留約 50–70% 資訊量）
5. 若原文為英文，以「英文原段 + 深灰色中文翻譯」雙語交替格式排版；原文若有圖片也儘量保留，方便沉浸式閱讀
6. 透過 Resend API 寄出 HTML 信件
7. 在 Notion 中將該篇標記為已發送，並記錄發送日期與執行結果

## 使用情境

- **建立閱讀習慣**：把被動囤積的清單，變成每隔三天主動送到信箱的一篇精華
- **英文技術文章學習**：對照英文原文與中文翻譯，沉浸式閱讀不吃力
- **知識吸收**：摘要格式更好讀，也更容易回顧

## 使用到的工具

| 工具 | 用途 |
|------|------|
| [Claude Code](https://claude.com/claude-code) 或 [Claude Desktop](https://claude.com/download)（cowork） | 排程執行與本地檔案輸出 |
| [Notion](https://notion.so) | 文章資料庫（閱讀清單） |
| [Notion REST API](https://developers.notion.com/) | 以 Personal Access Token 查詢／回寫資料庫（`scripts/notion_query.sh`、`scripts/notion_mark_read.sh`） |
| [Resend](https://resend.com) | Email 寄送 API |

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

### 2. 取得 Notion API Token

本專案**直接打 Notion REST API** 存取資料庫（不使用 Notion MCP connector）。讀取／回寫都透過 repo 內的 `scripts/notion_query.sh` 與 `scripts/notion_mark_read.sh` 兩支腳本，吃 `.env` 的 `NOTION_API_KEY`。

建議使用 **Personal Access Token（PAT）**：

1. 前往 Notion [Developer Portal](https://developers.notion.com/) → **Personal access tokens** → **New personal access token**。
2. 選擇 workspace、capability 勾選 **Notion API**，建立後複製 token。
3. 把 token 填入 `.env` 的 `NOTION_API_KEY`。

> PAT 直接套用「你本人」的權限，**不需要**像 internal integration 那樣手動把資料庫分享給 bot；缺點是一年到期需續。
> 也可改用 internal integration token（[my-integrations](https://www.notion.so/my-integrations)），但需在資料庫 `···` → Connections 把該 integration 加進去。

### 3. 取得 Resend API Key

1. 前往 [resend.com](https://resend.com) 註冊帳號
2. 進入 **API Keys** → **Create API Key**
3. 複製金鑰（格式為 `re_` 開頭）

> **寄件地址說明**：免費方案可直接用 `onboarding@resend.dev` 寄信，無需驗證網域。若要用自己的網域（例如 `digest@yourdomain.com`），在 Resend 後台的 **Domains** 完成驗證即可。
>
> **注意**：若使用 subdomain（例如 `mail.yeeway.dev`），必須在 Resend Domains 頁面明確新增該 subdomain 本身，不會自動繼承父網域的驗證。

### 4. 設定環境變數

複製 `.env.example` 為 `.env`，並填入你的值：

```bash
cp .env.example .env
```

```
RESEND_API_KEY=re_YOUR_API_KEY_HERE
RESEND_FROM_EMAIL=onboarding@resend.dev   # 或你自己的驗證網域
TO_EMAIL=you@youremail.com
NOTION_API_KEY=YOUR_NOTION_TOKEN_HERE     # Personal Access Token（見步驟 2）
NOTION_DATABASE_URL=https://www.notion.so/your-workspace/YOUR_DATABASE_ID
NOTION_DATA_SOURCE_ID=collection://YOUR_DATA_SOURCE_ID
```

Data Source ID 可在資料庫網址或 API 回應中取得；`scripts/notion_query.sh` 會自動去掉 `collection://` 前綴，只用其中的 UUID 呼叫 `data_sources/{id}/query`。

### 5. 建立排程任務

在 **Claude Code** 或 **Claude Desktop cowork** 中告訴 Claude：

> 「幫我依照 CLAUDE.md 的排程設定建立排程任務（每三天早上 10:00 執行，cron：`0 10 */3 * *`）。」

- **Claude Code**：會以本地排程（cron）的方式建立定時任務。
- **Claude Desktop cowork**：在 cowork 中以排程任務（scheduled task）的方式建立。

> 排程任務執行時需要連線 `api.notion.com` 與 `api.resend.com`，並讀寫專案目錄下的暫存檔；請確認沙箱白名單與權限已涵蓋（見 `.claude/settings.json`）。

第一次先手動執行一次，預先授權所需的工具權限，避免之後自動執行時卡在等待確認。

### 6. 新增文章

開始在 Notion 資料庫中儲存文章：將文章網址貼到 `URL` 欄位、填入標題、`Read` 保持未勾選。Agent 每隔三天會自動挑最早加入（`Created` 最舊）的一篇發送。
