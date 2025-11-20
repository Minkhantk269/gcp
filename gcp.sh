#!/usr/bin/env bash
set -euo pipefail

# =================== Colors ===================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

ok() { echo -e "${GREEN}[OK]${NC} $1"; }
err() { echo -e "${RED}[ERROR]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
sec() { echo -e "\n${CYAN}========== $1 ==========${NC}"; }

# =================== Time ===================
START_TS=$(date +%s)
START_LOCAL=$(date +"%Y-%m-%d %H:%M:%S")

# =================== Required ENVs ===================
SERVICE="homecloudrun"
REGION="asia-southeast1"
IMAGE="gcr.io/cloudrun-service/${SERVICE}:latest"

sec "Building Docker Image"
docker build -t "$IMAGE" .

sec "Pushing to Container Registry"
docker push "$IMAGE"

sec "Deploying to Cloud Run"
gcloud run deploy "$SERVICE" \
  --image="$IMAGE" \
  --platform=managed \
  --region="$REGION" \
  --allow-unauthenticated

# =================== Fetch Deploy URL ===================
URL_CANONICAL=$(gcloud run services describe "$SERVICE" --platform managed --region "$REGION" --format 'value(status.url)')
URI="$URL_CANONICAL"

ok "Cloud Run URL → $URI"

END_TS=$(date +%s)
END_LOCAL=$(date +"%Y-%m-%d %H:%M:%S")

# =================== Telegram Push (multi accounts) ===================
if [[ -n "${TELEGRAM_TOKEN:-}" ]]; then
  sec "Telegram Notification"

  # Accept 3 possible variables:
  # TELEGRAM_CHAT_ID
  # TELEGRAM_CHAT_ID1
  # TELEGRAM_CHAT_ID2
  CHAT_IDS=()

  [[ -n "${TELEGRAM_CHAT_ID:-}" ]]  && CHAT_IDS+=("$TELEGRAM_CHAT_ID")
  [[ -n "${TELEGRAM_CHAT_ID1:-}" ]] && CHAT_IDS+=("$TELEGRAM_CHAT_ID1")
  [[ -n "${TELEGRAM_CHAT_ID2:-}" ]] && CHAT_IDS+=("$TELEGRAM_CHAT_ID2")

  if [[ ${#CHAT_IDS[@]} -eq 0 ]]; then
      warn "⚠ No Telegram chat IDs were provided"
  else
      HTML_MSG=$(
        cat <<EOF
<b>✅ Cloud Run Deploy Success</b>
━━━━━━━━━━━━━━━━━━
<blockquote><b>Service:</b> ${SERVICE}
<b>Region:</b> ${REGION}
<b>URL:</b> ${URL_CANONICAL}</blockquote>
<b>🔑 MYTEL လိုင်းဖြတ် GCP</b>
<pre><code>${URI}</code></pre>
<blockquote>🕒 <b>Start:</b> ${START_LOCAL}
⏳ <b>End:</b> ${END_LOCAL}</blockquote>
━━━━━━━━━━━━━━━━━━
EOF
      )

      for CID in "${CHAT_IDS[@]}"; do
        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
          -d "chat_id=${CID}" \
          --data-urlencode "text=${HTML_MSG}" \
          -d "parse_mode=HTML" >/dev/null && \
          ok "Telegram sent → ${CID}"
      done
  fi
else
  warn "Telegram not configured (missing TELEGRAM_TOKEN)"
fi

echo ""
ok "Deploy finished!"
