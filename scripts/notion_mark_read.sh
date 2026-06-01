#!/bin/bash
# 更新 Notion「Read Later」頁面：勾選 Read、填 Summarized At、寫 Claude Note。
# 用法：bash notion_mark_read.sh <page_id> "<claude_note>" [summarized_date]
#   page_id          : 要更新的頁面 ID（notion_query.sh 回傳的 .id）
#   claude_note      : 寫入 Claude Note 欄位的文字（如「✅ 已成功摘要」或「❌ 摘要失敗：...」）
#   summarized_date  : 選填，ISO 日期（預設今天）；寄送失敗時可傳空字串 "" 略過日期
# 失敗時錯誤訊息輸出到 stderr 並回傳非零 exit code。
#
# 直接打 Notion REST API 的 Update page properties 端點，取代原本 MCP 的 update-page。
set -euo pipefail

PAGE_ID="${1:?請提供 page_id 作為第一個參數}"
CLAUDE_NOTE="${2:?請提供 Claude Note 文字作為第二個參數}"
SUMMARIZED_DATE="${3-$(date +%F)}"

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

: "${NOTION_API_KEY:?.env 缺少 NOTION_API_KEY}"
NOTION_VERSION="${NOTION_VERSION:-2025-09-03}"
READ_PROP="${NOTION_READ_PROP:-Read}"
CREATED_PROP="${NOTION_SUMMARIZED_PROP:-Summarized At}"
NOTE_PROP="${NOTION_NOTE_PROP:-Claude Note}"

# 組 properties：勾選 Read + 寫 Claude Note；有日期才寫 Summarized At
REQ_BODY=$(jq -n \
  --arg readp "$READ_PROP" \
  --arg notep "$NOTE_PROP" \
  --arg datep "$CREATED_PROP" \
  --arg note "$CLAUDE_NOTE" \
  --arg date "$SUMMARIZED_DATE" \
  '{
     properties: (
       {
         ($readp): { checkbox: true },
         ($notep): { rich_text: [ { text: { content: $note } } ] }
       }
       + (if $date == "" then {} else { ($datep): { date: { start: $date } } } end)
     )
   }')

BODY_FILE=$(mktemp)
HTTP_CODE=$(curl -s \
  -o "$BODY_FILE" \
  -w "%{http_code}" \
  -X PATCH "https://api.notion.com/v1/pages/${PAGE_ID}" \
  -H "Authorization: Bearer ${NOTION_API_KEY}" \
  -H "Notion-Version: ${NOTION_VERSION}" \
  -H 'Content-Type: application/json' \
  -d "$REQ_BODY")

BODY=$(cat "$BODY_FILE")
rm -f "$BODY_FILE"

if [[ "${HTTP_CODE}" =~ ^2 ]]; then
  echo "OK ${HTTP_CODE}"
else
  echo "Notion update 失敗 ${HTTP_CODE}: ${BODY}" >&2
  exit 1
fi
