# 📙 Read-it-later Digest 稍後閱讀清單摘要 Agent

這是一個自動化的 Claude Agent，每隔三天從 Notion 閱讀清單中挑一篇文章、生成摘要，並寄送到你的信箱——讓那些「待讀」的文章真的被讀到。

---

## 痛點

大多數人的「稍後閱讀」清單都是文章墳場。文章越存越多，卻從來沒時間讀。這個 Agent 解決的就是這個問題：每隔三天自動挑一篇、幫你消化精華、直接送到信箱，你只需要打開來讀。

---

## 功能

每隔三天的早上 10:00，Agent 會自動：

1. 查詢 Notion 資料庫，找出尚未發送的文章
2. 取最新加入的一篇
3. 爬取原始文章內容（若網站擋爬蟲，改用 Notion 頁面內容）
4. 生成保留作者語氣與結構的摘要（保留約 50–70% 資訊量）
5. 若原文為英文，以「英文原段 + 深灰色中文翻譯」雙語交替格式排版；原文若有圖片也儘量保留，方便沉浸式閱讀
6. 透過 Resend API 寄出 HTML 信件
7. 在 Notion 中將該篇標記為已發送，並記錄發送日期與執行結果

---

## 使用情境

- **建立閱讀習慣**：把被動囤積的清單，變成每隔三天主動送到信箱的一篇精華
- **英文技術文章學習**：對照英文原文與中文翻譯，沉浸式閱讀不吃力
- **知識吸收**：摘要格式更好讀，也更容易回顧

---

## 使用到的工具

| 工具 | 用途 |
|------|------|
| [Notion](https://notion.so) | 文章資料庫（閱讀清單） |
| [Notion MCP](https://github.com/makenotion/notion-mcp-server) | Claude 連接 Notion 的插件 |
| [Resend](https://resend.com) | Email 寄送 API |
| [Claude Code](https://claude.com/claude-code) | 排程執行與本地檔案輸出 |

---

## Notion 資料庫欄位

| 欄位 | 類型 | 說明 |
|------|------|------|
| `Name` | 標題 | 文章標題 |
| `URL` | URL | 原始文章連結 |
| `Read` | 勾選框 | 是否已發送摘要 |
| `Summarized At` | 日期 | 摘要寄出的日期 |
| `Claude Note` | 文字 | 執行結果（`✅ 已成功摘要` / `❌ 摘要失敗：{原因}`） |

---

## 輸出

- **Email**：每隔三天 10:00 透過 Resend 寄出

---

## 安裝與設定

### 前置準備

- 安裝 [Claude Code](https://claude.com/claude-code)
- 擁有 [Notion](https://notion.so) 帳號
- 擁有 [Resend](https://resend.com) 帳號（免費方案即可）

---

### 1. 建立 Notion 資料庫

複製 [此 Notion 模板](#)，或手動建立一個包含以下欄位的資料庫：

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

---

### 2. 連接 Notion MCP

本專案透過 Claude 內建的 **Notion MCP connector** 存取資料庫，不需在 repo 內放任何 Notion server 設定或 token。

設定步驟：

1. 在 Claude（Desktop／cowork）的 **Settings → Connectors** 中加入並授權 **Notion** connector。
2. 授權時把存取範圍給到步驟 1 建立的 Read Later 資料庫（或允許整個 workspace）。
3. 在 Claude 中執行 `/mcp` 確認 Notion connector 已連線。

> connector 的驗證走 Claude 帳號的 OAuth，與本專案 `.env` 無關；排程／cowork 任務會沿用同一組已授權的 connector。

---

### 3. 取得 Resend API Key

1. 前往 [resend.com](https://resend.com) 註冊帳號
2. 進入 **API Keys** → **Create API Key**
3. 複製金鑰（格式為 `re_` 開頭）

> **寄件地址說明**：免費方案可直接用 `onboarding@resend.dev` 寄信，無需驗證網域。若要用自己的網域（例如 `digest@yourdomain.com`），在 Resend 後台的 **Domains** 完成驗證即可。

---

### 4. 設定環境變數

複製 `.env.example` 為 `.env`，並填入你的值：

```bash
cp .env.example .env
```

```
RESEND_API_KEY=re_YOUR_API_KEY_HERE
RESEND_FROM_EMAIL=onboarding@resend.dev   # 或你自己的驗證網域
TO_EMAIL=you@youremail.com
NOTION_DATABASE_URL=https://www.notion.so/your-workspace/YOUR_DATABASE_ID
NOTION_DATA_SOURCE_ID=collection://YOUR_DATA_SOURCE_ID
```

找不到 Notion Data Source ID 的話，可以問 Claude：「幫我 fetch 這個 Notion 資料庫：[你的資料庫網址]，告訴我 data source ID 是什麼。」

---

### 5. 建立排程任務

在 Claude Code 中告訴 Claude：

> 「幫我依照 CLAUDE.md 的排程設定建立排程任務（每三天早上 10:00 執行，cron：`0 10 */3 * *`）。」

第一次先手動執行一次，預先授權所需的工具權限，避免之後自動執行時卡在等待確認。

---

### 6. 新增文章

開始在 Notion 資料庫中儲存文章：將文章網址貼到 `URL` 欄位、填入標題、`Read` 保持未勾選。Agent 每隔三天會自動挑最新的一篇發送。
