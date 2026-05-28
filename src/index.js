/**
 * Mars Maps Class — Anthropic API Proxy
 * Cloudflare Workers
 *
 * Accepts two kinds of keys in the x-api-key header:
 *   1. CLASS_PASSWORD env var  → injects instructor's real ANTHROPIC_API_KEY
 *   2. Anything starting sk-ant-  → passes through as-is (student's own key)
 *   3. Anything else            → 401 Unauthorized
 *
 * Deploy:
 *   wrangler secret put ANTHROPIC_API_KEY   (real Anthropic key - never visible to students)
 *   wrangler secret put CLASS_PASSWORD      (e.g. "class2025" - safe to share)
 *   wrangler deploy
 */

const ANTHROPIC_BASE = 'https://api.anthropic.com';

export default {
  async fetch(request, env) {

    // ── CORS preflight ────────────────────────────────────────────────────
    if (request.method === 'OPTIONS') {
      return corsResponse(null, 204);
    }

    const url = new URL(request.url);

    // ── Health check ──────────────────────────────────────────────────────
    if (url.pathname === '/health') {
      return corsResponse(JSON.stringify({ status: 'ok', service: 'mars-proxy' }), 200);
    }

    // ── Resolve the key ───────────────────────────────────────────────────
    // Roo Code sends x-api-key for Anthropic provider.
    // Some OpenAI-compat clients send Authorization: Bearer instead.
    const providedKey =
      request.headers.get('x-api-key') ||
      (request.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '').trim();

    let anthropicKey;
    let keySource;

    if (providedKey === env.CLASS_PASSWORD) {
      // Class password — use instructor's key (never revealed to students)
      anthropicKey = env.ANTHROPIC_API_KEY;
      keySource = 'class';
    } else if (providedKey.startsWith('sk-ant-')) {
      // Student's own real Anthropic key — pass straight through
      anthropicKey = providedKey;
      keySource = 'student';
    } else {
      console.log(`[mars-proxy] REJECTED key="${providedKey?.slice(0, 8)}..." path=${url.pathname}`);
      return corsResponse(
        JSON.stringify({ error: { type: 'authentication_error', message: 'Invalid API key. Use the class password or your own Anthropic key.' } }),
        401
      );
    }

    // ── Build forwarded request ───────────────────────────────────────────
    const forwardHeaders = new Headers(request.headers);
    forwardHeaders.set('x-api-key', anthropicKey);
    forwardHeaders.delete('Authorization'); // Anthropic uses x-api-key, not Bearer
    // Strip Cloudflare-added headers that Anthropic doesn't need
    for (const h of ['cf-ray', 'cf-connecting-ip', 'cf-visitor', 'cf-ipcountry']) {
      forwardHeaders.delete(h);
    }

    const targetUrl = ANTHROPIC_BASE + url.pathname + url.search;

    // ── Log for instructor visibility (Cloudflare dashboard) ─────────────
    console.log(`[mars-proxy] ${keySource} → ${request.method} ${url.pathname}`);

    // ── Forward and stream back ───────────────────────────────────────────
    let upstream;
    try {
      upstream = await fetch(targetUrl, {
        method: request.method,
        headers: forwardHeaders,
        body: request.body,
      });
    } catch (err) {
      console.error(`[mars-proxy] Upstream fetch failed: ${err.message}`);
      return corsResponse(
        JSON.stringify({ error: { type: 'proxy_error', message: 'Could not reach Anthropic API.' } }),
        502
      );
    }

    // Pass through response — including streaming SSE — with CORS headers
    const responseHeaders = new Headers(upstream.headers);
    responseHeaders.set('Access-Control-Allow-Origin', '*');

    return new Response(upstream.body, {
      status: upstream.status,
      statusText: upstream.statusText,
      headers: responseHeaders,
    });
  },
};

// ── Helpers ───────────────────────────────────────────────────────────────
function corsResponse(body, status) {
  return new Response(body, {
    status,
    headers: {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': '*',
    },
  });
}
