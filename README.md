# mars-proxy

Cloudflare Workers proxy for the Mars Maps AI class.
Sits between students' Roo Code and the Anthropic API so the real API key is never exposed.

## How it works

| Key student sends | What proxy does |
|---|---|
| `CLASS_PASSWORD` (e.g. `class2025`) | Injects instructor's real `ANTHROPIC_API_KEY` |
| `sk-ant-...` (student's own key) | Passes straight through |
| Anything else | Returns 401 |

## Deploy (first time)

```bash
npm install
npx wrangler login          # opens browser — log in to Cloudflare
npx wrangler secret put CLASS_PASSWORD      # enter: class2025
npx wrangler secret put ANTHROPIC_API_KEY   # enter: your real sk-ant-... key
npx wrangler deploy
```

Your proxy URL will be:
`https://mars-proxy.YOUR-SUBDOMAIN.workers.dev`

## Update secrets

```bash
npx wrangler secret put CLASS_PASSWORD      # change the class password
npx wrangler secret put ANTHROPIC_API_KEY   # rotate the real key
```

## Watch live logs (during class)

```bash
npm run logs
```

Shows every request in real time — which source (class vs student key) and which endpoint.

## Test

```bash
# Health check
curl https://mars-proxy.YOUR-SUBDOMAIN.workers.dev/health

# Class password (should work)
curl https://mars-proxy.YOUR-SUBDOMAIN.workers.dev/v1/messages \
  -H "x-api-key: class2025" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d '{"model":"claude-haiku-4-5-20251001","max_tokens":20,"messages":[{"role":"user","content":"Say hi"}]}'

# Wrong password (should return 401)
curl https://mars-proxy.YOUR-SUBDOMAIN.workers.dev/v1/messages \
  -H "x-api-key: wrongpassword" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d '{"model":"claude-haiku-4-5-20251001","max_tokens":5,"messages":[{"role":"user","content":"hi"}]}'
```
