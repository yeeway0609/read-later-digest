#!/bin/bash
# 查詢 Notion「Read Later」資料庫中「未讀（Read 未勾選）且 Created 最舊」的一筆文章。
# 用法：bash notion_query.sh
# 輸出（stdout，單行 JSON）：{"id":"<page_id>","name":"<title>","url":"<article_url>"}
#   無符合文章時輸出：{}（exit 0）
# 失敗時錯誤訊息輸出到 stderr 並回傳非零 exit code。
#
# 直接打 Notion REST API 的 Query a data source 端點，做 server-side
# filter（Read=false）+ sort（Created ascending）+ page_size=1，
# 取代 MCP 只有語意 search（25 筆上限、無法過濾/排序）的限制。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "錯誤：找不到 .env 檔案（$ENV_FILE）" >&2
  exit 1
fi

# 讀取 .env（跳過空行與註解）
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
  key="${line%%=*}"
  value="${line#*=}"
  [[ -z "${!key+x}" ]] && export "$key"="$value"
done < "$ENV_FILE"

: "${NOTION_API_KEY:?.env 缺少 NOTION_API_KEY（建議用 Personal Access Token：Notion Developer Portal → Personal access tokens → New；或用 internal integration 並把資料庫分享給它）}"
: "${NOTION_DATA_SOURCE_ID:?.env 缺少 NOTION_DATA_SOURCE_ID}"

# 可調：Notion API 版本（data sources 端點需 2025-09-03 以上）與排序/過濾欄位
NOTION_VERSION="${NOTION_VERSION:-2025-09-03}"
READ_PROP="${NOTION_READ_PROP:-Read}"
CREATED_PROP="${NOTION_CREATED_PROP:-Created}"

# 去掉可能的 collection:// 前綴，取出純 data source UUID
DS_ID="${NOTION_DATA_SOURCE_ID#collection://}"

REQ_BODY=$(jq -n \
  --arg read "$READ_PROP" \
  --arg created "$CREATED_PROP" \
  '{
     filter: { property: $read, checkbox: { equals: false } },
     sorts: [ { property: $created, direction: "ascending" } ],
     page_size: 1
   }')

BODY_FILE=$(mktemp)
HTTP_CODE=$(curl -s \
  -o "$BODY_FILE" \
  -w "%{http_code}" \
  -X POST "https://api.notion.com/v1/data_sources/${DS_ID}/query" \
  -H "Authorization: Bearer ${NOTION_API_KEY}" \
  -H "Notion-Version: ${NOTION_VERSION}" \
  -H 'Content-Type: application/json' \
  -d "$REQ_BODY")

BODY=$(cat "$BODY_FILE")
rm -f "$BODY_FILE"

if [[ ! "${HTTP_CODE}" =~ ^2 ]]; then
  echo "Notion query 失敗 ${HTTP_CODE}: ${BODY}" >&2
  exit 1
fi

# 無符合文章 → 輸出 {}
COUNT=$(echo "$BODY" | jq '.results | length')
if [[ "$COUNT" -eq 0 ]]; then
  echo '{}'
  exit 0
fi

# 取出 page id / 標題 / URL 欄位。title 與 url 的 property 名稱依 schema 為 "Name" / "URL"。
echo "$BODY" | jq -c '
  .results[0] as $p
  | {
      id:   $p.id,
      name: ([ $p.properties.Name.title[]?.plain_text ] | join("")),
      url:  ($p.properties.URL.url // "")
    }'
