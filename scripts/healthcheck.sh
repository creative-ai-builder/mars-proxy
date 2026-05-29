#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# healthcheck.sh — Verify mars-proxy is fully set up or fully torn down
#
# Usage:
#   ./scripts/healthcheck.sh up   <CF_TOKEN> <CLASS_PASSWORD>
#   ./scripts/healthcheck.sh down <CF_TOKEN>
#
# Exit codes:
#   0 — state matches expected (fully up, or fully down)
#   1 — state does not match (something is wrong)
#
# Examples:
#   ./scripts/healthcheck.sh up   cfut_abc123 class2025
#   ./scripts/healthcheck.sh down cfut_abc123
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

MODE="${1:?Usage: $0 <up|down> <CF_TOKEN> [CLASS_PASSWORD]}"
CF_TOKEN="${2:?Usage: $0 <up|down> <CF_TOKEN> [CLASS_PASSWORD]}"
CLASS_PASSWORD="${3:-class2025}"

WORKER_NAME="mars-proxy"
PROXY_URL="https://$WORKER_NAME.creative-ai-builder.workers.dev"

# ── Colours ──────────────────────────────────────────────────────────────────
GREEN="\033[92m"; CYAN="\033[96m"; RED="\033[91m"; GOLD="\033[93m"; RESET="\033[0m"; BOLD="\033[1m"
ok()   { echo -e "  ${GREEN}✅ $*${RESET}"; PASS=$((PASS+1)); }
fail() { echo -e "  ${RED}❌ $*${RESET}"; FAIL=$((FAIL+1)); }
info() { echo -e "  ${CYAN}→  $*${RESET}"; }
step() { echo -e "\n${BOLD}${GOLD}$*${RESET}"; }

PASS=0; FAIL=0

[[ "$MODE" != "up" && "$MODE" != "down" ]] && { echo "Mode must be 'up' or 'down'"; exit 1; }

echo -e "\n${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BOLD}${CYAN}  🔍 Mars Proxy Health Check — expecting: $MODE${RESET}"
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

# ── Get account ID ────────────────────────────────────────────────────────────
step "Cloudflare account"
ACCOUNT_RESP=$(curl -sf "https://api.cloudflare.com/client/v4/accounts" \
  -H "Authorization: Bearer $CF_TOKEN") || { fail "Cannot reach Cloudflare API"; echo ""; exit 1; }
ACCOUNT_ID=$(echo "$ACCOUNT_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin)['result'][0]['id'])" 2>/dev/null) \
  || { fail "Token invalid or no accounts found"; exit 1; }
ok "Token valid — account: $ACCOUNT_ID"

# ── Check 1: Worker script exists (or not) ────────────────────────────────────
step "Check 1 — Worker exists in Cloudflare"
HTTP=$(curl -s -o /dev/null -w "%{http_code}" \
  "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/workers/scripts/$WORKER_NAME" \
  -H "Authorization: Bearer $CF_TOKEN")

if [ "$MODE" = "up" ]; then
  [ "$HTTP" = "200" ] && ok "Worker script exists (HTTP $HTTP)" \
    || fail "Worker script NOT found (HTTP $HTTP) — run setup.sh"
else
  [ "$HTTP" = "404" ] && ok "Worker script absent (HTTP $HTTP)" \
    || fail "Worker script still exists (HTTP $HTTP) — run teardown.sh"
fi

# ── Check 2: Secrets are set (or not) ────────────────────────────────────────
step "Check 2 — Secrets"
SECRETS_RESP=$(curl -s \
  "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/workers/scripts/$WORKER_NAME/secrets" \
  -H "Authorization: Bearer $CF_TOKEN")
SECRET_NAMES=$(echo "$SECRETS_RESP" | python3 -c \
  "import sys,json; d=json.load(sys.stdin); print(' '.join(s['name'] for s in d.get('result') or []))" 2>/dev/null || echo "")

if [ "$MODE" = "up" ]; then
  echo "$SECRET_NAMES" | grep -q "CLASS_PASSWORD"    && ok "SECRET CLASS_PASSWORD is set"    || fail "SECRET CLASS_PASSWORD is NOT set"
  echo "$SECRET_NAMES" | grep -q "ANTHROPIC_API_KEY" && ok "SECRET ANTHROPIC_API_KEY is set" || fail "SECRET ANTHROPIC_API_KEY is NOT set"
else
  # After teardown secrets endpoint returns empty or 404
  SECRETS_COUNT=$(echo "$SECRETS_RESP" | python3 -c \
    "import sys,json; d=json.load(sys.stdin); print(len(d.get('result') or []))" 2>/dev/null || echo "0")
  [ "$SECRETS_COUNT" = "0" ] && ok "No secrets present (worker deleted)" \
    || fail "Secrets still present: $SECRET_NAMES"
fi

# ── Check 3: HTTP health endpoint ─────────────────────────────────────────────
step "Check 3 — HTTP health endpoint ($PROXY_URL/health)"
HEALTH_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$PROXY_URL/health" 2>/dev/null || echo "000")
HEALTH_BODY=$(curl -s "$PROXY_URL/health" 2>/dev/null || echo "")

if [ "$MODE" = "up" ]; then
  [ "$HEALTH_STATUS" = "200" ] && ok "Health endpoint: HTTP 200" || fail "Health endpoint: HTTP $HEALTH_STATUS (expected 200)"
  echo "$HEALTH_BODY" | grep -q '"status":"ok"' && ok "Health body: {\"status\":\"ok\"}" \
    || fail "Health body unexpected: $HEALTH_BODY"
else
  [ "$HEALTH_STATUS" = "404" ] || [ "$HEALTH_STATUS" = "000" ] \
    && ok "Health endpoint returns $HEALTH_STATUS (worker gone)" \
    || fail "Health endpoint still returning $HEALTH_STATUS (expected 404 or no response)"
fi

# ── Check 4: Rejection of wrong password ──────────────────────────────────────
step "Check 4 — Wrong password rejected"
if [ "$MODE" = "up" ]; then
  REJECT_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "$PROXY_URL/v1/messages" \
    -H "x-api-key: thisisntright" \
    -H "content-type: application/json" \
    -d '{"model":"claude-haiku-4-5-20251001","max_tokens":5,"messages":[{"role":"user","content":"hi"}]}' 2>/dev/null || echo "000")
  [ "$REJECT_STATUS" = "401" ] && ok "Wrong password rejected: HTTP 401" \
    || fail "Wrong password NOT rejected: HTTP $REJECT_STATUS (expected 401)"
else
  info "Skipped (worker is down)"
fi

# ── Check 5: Class password → real Claude response ────────────────────────────
step "Check 5 — Class password gets real Claude response"
if [ "$MODE" = "up" ]; then
  info "Sending test message with class password '$CLASS_PASSWORD'..."
  CLAUDE_RESP=$(curl -s -X POST "$PROXY_URL/v1/messages" \
    -H "x-api-key: $CLASS_PASSWORD" \
    -H "anthropic-version: 2023-06-01" \
    -H "content-type: application/json" \
    -d '{"model":"claude-haiku-4-5-20251001","max_tokens":10,"messages":[{"role":"user","content":"Reply with just the word READY"}]}' 2>/dev/null || echo "")
  echo "$CLAUDE_RESP" | grep -q '"type":"message"' && ok "Claude responded via class password" \
    || fail "No valid Claude response — check ANTHROPIC_API_KEY secret. Got: $CLAUDE_RESP"
else
  info "Skipped (worker is down)"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo -e "\n${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
TOTAL=$((PASS+FAIL))
if [ "$FAIL" = "0" ]; then
  echo -e "${BOLD}${GREEN}  ✅ All $TOTAL checks passed — proxy is fully $MODE${RESET}"
  echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
  exit 0
else
  echo -e "${BOLD}${RED}  ❌ $FAIL/$TOTAL checks failed${RESET}"
  echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
  exit 1
fi
