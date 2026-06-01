#!/bin/bash
# 用法：./send_email.sh "<subject>" <html_file>
# 範例：./send_email.sh "[Claude 摘要] 文章標題" /tmp/email.html
set -euo pipefail

SUBJECT="${1:?請提供信件主旨作為第一個參數}"
HTML_FILE="${2:?請提供 HTML 檔案路徑作為第二個參數}"

if [[ ! -f "$HTML_FILE" ]]; then
  echo "錯誤：找不到檔案 $HTML_FILE" >&2
  exit 1
fi

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

: "${RESEND_API_KEY:?.env 缺少 RESEND_API_KEY}"
: "${RESEND_FROM_EMAIL:?.env 缺少 RESEND_FROM_EMAIL}"
: "${TO_EMAIL:?.env 缺少 TO_EMAIL}"

HTML_CONTENT=$(cat "$HTML_FILE")
BODY_FILE=$(mktemp)

HTTP_CODE=$(curl -s \
  -o "$BODY_FILE" \
  -w "%{http_code}" \
  -X POST 'https://api.resend.com/emails' \
  -H "Authorization: Bearer ${RESEND_API_KEY}" \
  -H 'Content-Type: application/json' \
  -d "$(jq -n \
    --arg from "$RESEND_FROM_EMAIL" \
    --arg to "$TO_EMAIL" \
    --arg subject "$SUBJECT" \
    --arg html "$HTML_CONTENT" \
    '{from: $from, to: $to, subject: $subject, html: $html}')")

BODY=$(cat "$BODY_FILE")
rm -f "$BODY_FILE"

if [[ "${HTTP_CODE}" =~ ^2 ]]; then
  echo "OK ${HTTP_CODE}: ${BODY}"
else
  echo "FAIL ${HTTP_CODE}: ${BODY}" >&2
  exit 1
fi
