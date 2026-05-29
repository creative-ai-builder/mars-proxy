#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# teardown.sh — Remove mars-proxy from Cloudflare Workers
#
# Usage:
#   ./scripts/teardown.sh <CF_TOKEN>
#
# What it does:
#   - Deletes the Worker script (stops all traffic immediately)
#   - Does NOT delete the workers.dev subdomain registration
#   - Does NOT touch GitHub repos or local files
#
# Example:
#   ./scripts/teardown.sh cfut_abc123
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# ── Load ~/.mars-secrets if no arguments supplied ─────────────────────────────
if [ $# -eq 0 ]; then
  [ -f ~/.mars-secrets ] || {
    echo "❌ No arguments given and ~/.mars-secrets not found."
    echo ""
    echo "Create it with:"
    echo "  cat > ~/.mars-secrets << 'EOF'"
    echo "  CF_TOKEN=cfut_your_cloudflare_token_here"
    echo "  ANTHROPIC_KEY=sk-ant-your_anthropic_key_here"
    echo "  CLASS_PASSWORD=class2025"
    echo "  EOF"
    echo "  chmod 600 ~/.mars-secrets"
    exit 1
  }
  set -a && source ~/.mars-secrets && set +a
fi

CF_TOKEN="${1:-${CF_TOKEN:?CF_TOKEN not set — see ~/.mars-secrets}}"
WORKER_NAME="mars-proxy"

# ── Colours ──────────────────────────────────────────────────────────────────
GREEN="\033[92m"; CYAN="\033[96m"; RED="\033[91m"; GOLD="\033[93m"; RESET="\033[0m"; BOLD="\033[1m"
ok()   { echo -e "  ${GREEN}✅ $*${RESET}"; }
info() { echo -e "  ${CYAN}→  $*${RESET}"; }
fail() { echo -e "  ${RED}❌ $*${RESET}"; exit 1; }
step() { echo -e "\n${BOLD}${GOLD}$*${RESET}"; }

echo -e "\n${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BOLD}${CYAN}  🔻 Mars Proxy Teardown${RESET}"
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

# ── 1. Validate token and get account ID ─────────────────────────────────────
step "Step 1/2 — Validating token"
ACCOUNT_RESP=$(curl -sf "https://api.cloudflare.com/client/v4/accounts" \
  -H "Authorization: Bearer $CF_TOKEN") || fail "Could not reach Cloudflare API"

SUCCESS=$(echo "$ACCOUNT_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin)['success'])")
[ "$SUCCESS" = "True" ] || fail "Token invalid"

ACCOUNT_ID=$(echo "$ACCOUNT_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin)['result'][0]['id'])")
ok "Token valid — account: $ACCOUNT_ID"

# ── 2. Check worker exists before deleting ────────────────────────────────────
step "Step 2/2 — Deleting worker"
info "Checking if worker '$WORKER_NAME' exists..."
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/workers/scripts/$WORKER_NAME" \
  -H "Authorization: Bearer $CF_TOKEN")

if [ "$HTTP_STATUS" = "404" ]; then
  echo -e "  ${GOLD}⚠️  Worker '$WORKER_NAME' not found — already torn down?${RESET}"
  exit 0
fi

[ "$HTTP_STATUS" = "200" ] || fail "Unexpected status $HTTP_STATUS checking worker — aborting"
info "Worker found. Deleting..."

RESP=$(curl -s -X DELETE \
  "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/workers/scripts/$WORKER_NAME" \
  -H "Authorization: Bearer $CF_TOKEN")

SUCCESS=$(echo "$RESP" | python3 -c "import sys,json; print(json.load(sys.stdin)['success'])")
[ "$SUCCESS" = "True" ] || fail "Delete failed: $(echo "$RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('errors','unknown'))")"
ok "Worker deleted"

echo -e "\n${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BOLD}${GREEN}  ✅ Teardown complete${RESET}"
echo -e "  Requests to mars-proxy.creative-ai-builder.workers.dev will now 404"
echo -e "  Re-deploy anytime with: ./scripts/setup.sh <CF_TOKEN> <ANTHROPIC_KEY>"
echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
