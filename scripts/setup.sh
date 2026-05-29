#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# setup.sh — Deploy mars-proxy to Cloudflare Workers and set secrets
#
# Usage:
#   ./scripts/setup.sh <CF_TOKEN> <ANTHROPIC_KEY> [CLASS_PASSWORD]
#
# Arguments:
#   CF_TOKEN        Cloudflare API token (Workers edit permissions)
#   ANTHROPIC_KEY   Real Anthropic API key (sk-ant-...)
#   CLASS_PASSWORD  Password students use in Roo Code (default: class2025)
#
# Example:
#   ./scripts/setup.sh cfut_abc123 sk-ant-xyz789 class2025
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
ANTHROPIC_KEY="${2:-${ANTHROPIC_KEY:?ANTHROPIC_KEY not set — see ~/.mars-secrets}}"
CLASS_PASSWORD="${3:-${CLASS_PASSWORD:-class2025}}"

WORKER_NAME="mars-proxy"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Colours ──────────────────────────────────────────────────────────────────
GREEN="\033[92m"; CYAN="\033[96m"; RED="\033[91m"; GOLD="\033[93m"; RESET="\033[0m"; BOLD="\033[1m"
ok()   { echo -e "  ${GREEN}✅ $*${RESET}"; }
info() { echo -e "  ${CYAN}→  $*${RESET}"; }
fail() { echo -e "  ${RED}❌ $*${RESET}"; exit 1; }
step() { echo -e "\n${BOLD}${GOLD}$*${RESET}"; }

echo -e "\n${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BOLD}${CYAN}  🚀 Mars Proxy Setup${RESET}"
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

# ── 1. Validate token and discover account ID ─────────────────────────────────
step "Step 1/4 — Validating Cloudflare token"
ACCOUNT_RESP=$(curl -sf "https://api.cloudflare.com/client/v4/accounts" \
  -H "Authorization: Bearer $CF_TOKEN") || fail "Could not reach Cloudflare API — check your token"

SUCCESS=$(echo "$ACCOUNT_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin)['success'])")
[ "$SUCCESS" = "True" ] || fail "Token is invalid or has no account access"

ACCOUNT_ID=$(echo "$ACCOUNT_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin)['result'][0]['id'])")
ok "Token valid — account: $ACCOUNT_ID"

# ── 2. Deploy worker via wrangler ─────────────────────────────────────────────
step "Step 2/4 — Deploying worker code"

# Load nvm if available
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" && nvm use 20 &>/dev/null || true

WRANGLER="$REPO_DIR/node_modules/.bin/wrangler"
[ -x "$WRANGLER" ] || fail "wrangler not found — run 'npm install' in $REPO_DIR first"

cd "$REPO_DIR"
CLOUDFLARE_API_TOKEN="$CF_TOKEN" "$WRANGLER" deploy --quiet 2>&1 | grep -v "WARNING\|update available\|wrangler\|-----" || true
ok "Worker deployed to https://$WORKER_NAME.creative-ai-builder.workers.dev"

# ── 3. Set secrets ────────────────────────────────────────────────────────────
step "Step 3/4 — Setting secrets"
info "Setting CLASS_PASSWORD..."
echo "$CLASS_PASSWORD" | CLOUDFLARE_API_TOKEN="$CF_TOKEN" "$WRANGLER" secret put CLASS_PASSWORD --quiet 2>/dev/null
ok "CLASS_PASSWORD set to: $CLASS_PASSWORD"

info "Setting ANTHROPIC_API_KEY..."
echo "$ANTHROPIC_KEY" | CLOUDFLARE_API_TOKEN="$CF_TOKEN" "$WRANGLER" secret put ANTHROPIC_API_KEY --quiet 2>/dev/null
ok "ANTHROPIC_API_KEY set (value hidden)"

# ── 4. Quick smoke test ───────────────────────────────────────────────────────
step "Step 4/4 — Smoke test"
info "Waiting for deployment to propagate..."
for i in $(seq 1 10); do
  STATUS=$(curl -sf -o /dev/null -w "%{http_code}" \
    https://$WORKER_NAME.creative-ai-builder.workers.dev/health 2>/dev/null || echo "000")
  [ "$STATUS" = "200" ] && break
  sleep 3
done
[ "$STATUS" = "200" ] || fail "Worker not responding after deploy — run healthcheck.sh to investigate"
ok "Health check: HTTP 200"

echo -e "\n${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BOLD}${GREEN}  ✅ Setup complete!${RESET}"
echo -e "  Proxy URL: https://$WORKER_NAME.creative-ai-builder.workers.dev"
echo -e "  Class password: $CLASS_PASSWORD"
echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
