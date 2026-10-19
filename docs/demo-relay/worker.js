// Demo relay for the Ace Junk Removal browser demo.
//
// Runs on Cloudflare Workers. It takes the Assistant's request from the demo
// page, adds the Anthropic API key (kept as a Worker secret, never in the page
// or in this file), forces the model and the answer size, and passes
// Anthropic's reply straight back. Only the demo page's own web addresses are
// allowed to call it.
//
// Setup is in README.md next to this file.

const ALLOWED_ORIGINS = [
  /^https:\/\/[a-z0-9-]+\.frame\.claudeusercontent\.com$/, // the demo page inside claude.ai
  /^https:\/\/claude\.ai$/,
];
const MODEL = 'claude-sonnet-5-5';
const MAX_TOKENS = 16000;

export default {
  async fetch(request, env) {
    const origin = request.headers.get('Origin') || '';
    const extra = (env.EXTRA_ORIGIN || '').trim();
    const allowed = ALLOWED_ORIGINS.some(re => re.test(origin)) || (extra && origin === extra);
    const cors = {
      'Access-Control-Allow-Origin': allowed ? origin : 'https://claude.ai',
      'Access-Control-Allow-Methods': 'POST, OPTIONS',
      'Access-Control-Allow-Headers': 'content-type',
      'Access-Control-Max-Age': '600',
      'Vary': 'Origin',
    };
    if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors });
    if (request.method !== 'POST') return new Response('Not found', { status: 404 });
    if (!allowed) return json({ type: 'error', error: { type: 'permission_error', message: 'This relay only serves the demo page.' } }, 403, cors);
    if (!env.ANTHROPIC_API_KEY) return json({ type: 'error', error: { type: 'api_error', message: 'The relay has no API key set.' } }, 500, cors);

    let body;
    try { body = await request.json(); } catch (e) { body = null; }
    if (!body || !Array.isArray(body.messages) || !body.messages.length) {
      return json({ type: 'error', error: { type: 'invalid_request_error', message: 'No request to forward.' } }, 400, cors);
    }

    // Only the parts the demo needs are forwarded; the model and size are fixed here.
    const forwarded = {
      model: MODEL,
      max_tokens: MAX_TOKENS,
      system: typeof body.system === 'string' ? body.system.slice(0, 20000) : undefined,
      messages: body.messages.slice(-2),
      output_config: body.output_config,
    };

    const upstream = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-api-key': env.ANTHROPIC_API_KEY,
        'anthropic-version': '2023-06-01',
      },
      body: JSON.stringify(forwarded),
    });
    const text = await upstream.text();
    return new Response(text, { status: upstream.status, headers: { ...cors, 'content-type': 'application/json' } });
  },
};

function json(value, status, headers) {
  return new Response(JSON.stringify(value), { status, headers: { ...headers, 'content-type': 'application/json' } });
}
