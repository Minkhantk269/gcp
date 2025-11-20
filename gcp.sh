#!/usr/bin/env bash
set -euo pipefail

# =================== Color & UI ===================
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  RESET=$'\e[0m'; BOLD=$'\e[1m'; DIM=$'\e[2m'
  C_CYAN=$'\e[38;5;44m'; C_BLUE=$'\e[38;5;33m'
  C_GREEN=$'\e[38;5;46m'; C_YEL=$'\e[38;5;226m'
  C_ORG=$'\e[38;5;214m'; C_PINK=$'\e[38;5;205m'
  C_GREY=$'\e[38;5;245m'; C_RED=$'\e[38;5;196m'
else
  RESET= BOLD= DIM= C_CYAN= C_BLUE= C_GREEN= C_YEL= C_ORG= C_PINK= C_GREY= C_RED=
fi

hr(){ printf "${C_GREY}%s${RESET}\n" "──────────────────────────────────────────────"; }
sec(){ printf "\n${C_BLUE}📦 ${BOLD}%s${RESET}\n" "$1"; hr; }
ok(){ printf "${C_GREEN}✔${RESET} %s\n" "$1"; }
warn(){ printf "${C_ORG}⚠${RESET} %s\n" "$1"; }
err(){ printf "${C_RED}✘${RESET} %s\n" "$1"; }
kv(){ printf "   ${C_GREY}%s${RESET}  %s\n" "$1" "$2"; }

printf "\n${C_CYAN}${BOLD}🚀 N4 Cloud Run — One-Click Deploy${RESET} ${C_GREY}(Trojan / VLESS / gRPC)${RESET}\n"
hr

# =================== Secrets via ENV / .env ===================
# Load .env if present (TELEGRAM_TOKEN / TELEGRAM_CHAT_ID)
if [[ -f .env ]]; then
  # export-all temporarily to import keys; avoid echoing secrets
  set -a; source ./.env; set +a
  ok ".env loaded"
fi
# Never hardcode; only read from ENV
TELEGRAM_TOKEN="${TELEGRAM_TOKEN:-}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"

# =================== Project ===================
sec "Project"
PROJECT="$(gcloud config get-value project 2>/dev/null || true)"
if [[ -z "$PROJECT" ]]; then
  err "No active GCP project."
  echo "    👉 gcloud config set project <YOUR_PROJECT_ID>"
  exit 1
fi
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')"
ok "Loaded Project"
kv "Project:" "${BOLD}${PROJECT}${RESET}"
kv "Project No.:" "${PROJECT_NUMBER}"

# =================== Protocol ===================
sec "Protocol"
printf "   ${C_PINK}1) Trojan (WS)    2) VLESS (WS)    3) VLESS (gRPC)${RESET}\n"
read -rp "   Choose [default 1]: " _opt || true
case "${_opt:-1}" in
  2) PROTO="vless"     ; IMAGE="docker.io/n4vip/vless:latest"     ;;
  3) PROTO="vlessgrpc" ; IMAGE="docker.io/n4vip/vlessgrpc:latest" ;;
  *) PROTO="trojan"    ; IMAGE="docker.io/n4vip/trojan:latest"    ;;
esac
ok "Selected ${PROTO^^}"

# =================== Defaults ===================
SERVICE="${SERVICE:-homevpn}"
REGION="${REGION:-us-central1}"
MEMORY="${MEMORY:-16Gi}"
CPU="${CPU:-4}"
TIMEOUT="${TIMEOUT:-3600}"
PORT="${PORT:-8080}"

sec "Deploy Config"
kv "Service:" "${BOLD}${SERVICE}${RESET}"
kv "Region:" "${REGION}"
kv "CPU/Mem:" "${CPU} vCPU / ${MEMORY}"
kv "Timeout/Port:" "${TIMEOUT}s / ${PORT}"
# (image link intentionally hidden in summary)

# =================== Keys ===================
TROJAN_PASS="Home"
TROJAN_TAG="Home%20GCP%20Hour%20Key"
TROJAN_PATH="%2F%40n4vpn"

VLESS_UUID="0c890000-4733-b20e-067f-fc341bd20000"
VLESS_PATH="%2FN4VPN"
VLESS_TAG="HOME%20GCP%20VLESS"

VLESSGRPC_UUID="0c890000-4733-b20e-067f-fc341bd20000"
VLESSGRPC_SVC="homegcp-grpc"
VLESSGRPC_TAG="GCP-VLESS-GRPC"

# =================== Service name ===================
read -rp "   Service name [default: ${SERVICE}]: " _svc || true
SERVICE="${_svc:-$SERVICE}"
# =================== Timezone Setup ===================
export TZ="Asia/Yangon"
START_EPOCH="$(date +%s)"
END_EPOCH="$(( START_EPOCH + 5*3600 ))"
fmt_dt(){ date -d @"$1" "+%d.%m.%Y %I:%M %p"; }
START_LOCAL="$(fmt_dt "$START_EPOCH")"
END_LOCAL="$(fmt_dt "$END_EPOCH")"
kv "Start:" "${START_LOCAL}"
kv "End:"   "${END_LOCAL}"
# =================== Enable APIs & Deploy ===================
sec "Enable APIs"
gcloud services enable run.googleapis.com cloudbuild.googleapis.com --quiet
ok "APIs Enabled"

sec "Deploying"
gcloud run deploy "$SERVICE" \
  --image="$IMAGE" \
  --platform=managed \
  --region="$REGION" \
  --memory="$MEMORY" \
  --cpu="$CPU" \
  --timeout="$TIMEOUT" \
  --allow-unauthenticated \
  --port="$PORT" \
  --quiet
ok "Deployed Successfully"

# =================== Canonical URL ===================
CANONICAL_HOST="${SERVICE}-${PROJECT_NUMBER}.${REGION}.run.app"
URL_CANONICAL="https://${CANONICAL_HOST}"

sec "Result"
ok "Service Ready"
kv "URL:" "${C_CYAN}${BOLD}${URL_CANONICAL}${RESET}"

# =================== Build Client URL ===================
LABEL=""; URI=""
case "$PROTO" in
  trojan)
    URI="trojan://${TROJAN_PASS}@m.googleapis.com:443?path=${TROJAN_PATH}&security=tls&alpn=http%2F1.1&host=${CANONICAL_HOST}&fp=randomized&type=ws&sni=m.googleapis.com#${TROJAN_TAG}"
    LABEL="TROJAN URL"
    ;;
  vless)
    URI="vless://${VLESS_UUID}@m.googleapis.com:443?path=${VLESS_PATH}&security=tls&alpn=http%2F1.1&encryption=none&host=${CANONICAL_HOST}&fp=randomized&type=ws&sni=m.googleapis.com#${VLESS_TAG}"
    LABEL="VLESS URL (WS)"
    ;;
  vlessgrpc)
    URI="vless://${VLESSGRPC_UUID}@m.googleapis.com:443?mode=gun&security=tls&alpn=http%2F1.1&encryption=none&fp=randomized&type=grpc&serviceName=${VLESSGRPC_SVC}&sni=${CANONICAL_HOST}#${VLESSGRPC_TAG}"
    LABEL="VLESS-gRPC URL"
    ;;
esac

sec "Client Key"
printf "   ${C_YEL}${BOLD}%s${RESET}\n" "${LABEL}"
printf "   ${C_ORG}👉 %s${RESET}\n" "${URI}"
hr

# =================== Telegram Push (only if both envs exist) ===================
if [[ -n "${TELEGRAM_TOKEN}" && -n "${TELEGRAM_CHAT_ID}" ]]; then
  sec "Telegram"
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
  # never echo secrets
  curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
       -d "chat_id=${TELEGRAM_CHAT_ID}" \
       --data-urlencode "text=${HTML_MSG}" \
       -d "parse_mode=HTML" >/dev/null \
    && ok "Telegram message sent"
else
  warn "Telegram not configured (set TELEGRAM_TOKEN & TELEGRAM_CHAT_ID via ENV or .env)"
fi

printf "\n${C_GREEN}${BOLD}✨ All done. Enjoy!${RESET}\n"
