# mars-proxy — Claude Context

Cloudflare Workers proxy for the Mars Maps AI class.
Sits between students' Roo Code and the Anthropic API so the real key is never exposed.

---

## Secrets File

All scripts require a `~/.mars-secrets` file with credentials.
**This file is never committed to git.**

### Create it (run once)

```bash
cat > ~/.mars-secrets << 'EOF'
CF_TOKEN=cfut_your_cloudflare_token_here
ANTHROPIC_KEY=sk-ant-your_anthropic_key_here
CLASS_PASSWORD=class2025
EOF
chmod 600 ~/.mars-secrets
```

Replace the placeholder values with real credentials:
- `CF_TOKEN` — Cloudflare API token with Workers edit permissions (dash.cloudflare.com/profile/api-tokens)
- `ANTHROPIC_KEY` — Real Anthropic API key (console.anthropic.com)
- `CLASS_PASSWORD` — Password students enter in Roo Code (default: `class2025`)

### Check it exists before running any script

```bash
[ -f ~/.mars-secrets ] || { echo "❌ ~/.mars-secrets not found — see CLAUDE.md to create it"; exit 1; }
```

### Source it in every bash command

```bash
set -a && source ~/.mars-secrets && set +a
```

---

## Scripts

All scripts are in `scripts/` and read credentials from `~/.mars-secrets`.

### Deploy proxy (or redeploy after code changes)

```bash
set -a && source ~/.mars-secrets && set +a
./scripts/setup.sh "$CF_TOKEN" "$ANTHROPIC_KEY" "$CLASS_PASSWORD"
```

### Remove proxy from Cloudflare

```bash
set -a && source ~/.mars-secrets && set +a
./scripts/teardown.sh "$CF_TOKEN"
```

### Verify proxy is fully up

```bash
set -a && source ~/.mars-secrets && set +a
./scripts/healthcheck.sh up "$CF_TOKEN" "$CLASS_PASSWORD"
```

### Verify proxy is fully down

```bash
set -a && source ~/.mars-secrets && set +a
./scripts/healthcheck.sh down "$CF_TOKEN"
```

---

## Architecture

```
Student Roo Code
    │  x-api-key: class2025  (or sk-ant-... for post-class students)
    ▼
Cloudflare Workers  (mars-proxy.creative-ai-builder.workers.dev)
    │  Checks key:
    │    "class2025"   → injects ANTHROPIC_API_KEY secret
    │    "sk-ant-..."  → passes through unchanged
    │    anything else → 401
    ▼
Anthropic API  (api.anthropic.com)
```

---

## Proxy URL

```
https://mars-proxy.creative-ai-builder.workers.dev
```

---

## Cloudflare Account

- **Account:** creative.ai.builder@gmail.com
- **Account ID:** e62742a14605dcb044b929d61cc49b6e
- **Worker name:** mars-proxy
- **Subdomain:** creative-ai-builder.workers.dev

---

## Student Template Repo

`github.com/creative-ai-builder/mars-maps-starter`

Students enter in Roo Code on Day 1:
- API Base URL: `https://mars-proxy.creative-ai-builder.workers.dev`
- API Key: `class2025`
