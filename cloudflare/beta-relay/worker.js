// Ace beta relay (Oct 20, 2026). The beta app sends its Assistant notes
// here instead of straight to Anthropic, so the API key never ships inside
// the app. The key lives only in this Worker's secret ANTHROPIC_API_KEY,
// which Kyle sets in the Cloudflare dashboard.
//
// It forwards one kind of request only: a Messages call on the two models
// the app uses, with the same token cap the app sends. Anything else is
// refused. Delete or pause the Worker to switch the beta's Assistant off.

const ANTHROPIC_URL = "https://api.anthropic.com/v1/messages";
const ALLOWED_MODELS = ["claude-haiku-5-5", "claude-sonnet-5-5"];
const MAX_TOKENS = 16000;
const MAX_BODY_BYTES = 1_000_000;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method !== "POST" || url.pathname !== "/v1/messages") {
      return refuse(404, "Not found.");
    }
    if (!env.ANTHROPIC_API_KEY) {
      return refuse(500, "The relay has no API key set.");
    }

    const text = await request.text();
    if (text.length > MAX_BODY_BYTES) {
      return refuse(413, "The note is too large.");
    }
    let body;
    try {
      body = JSON.parse(text);
    } catch {
      return refuse(400, "The request could not be read.");
    }
    if (!ALLOWED_MODELS.includes(body.model)) {
      return refuse(400, "That model is not allowed on this relay.");
    }
    if (typeof body.max_tokens !== "number" || body.max_tokens > MAX_TOKENS) {
      body.max_tokens = MAX_TOKENS;
    }

    const upstream = await fetch(ANTHROPIC_URL, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "anthropic-version": request.headers.get("anthropic-version") || "2023-06-01",
        "x-api-key": env.ANTHROPIC_API_KEY,
      },
      body: JSON.stringify(body),
    });

    return new Response(upstream.body, {
      status: upstream.status,
      headers: { "content-type": upstream.headers.get("content-type") || "application/json" },
    });
  },
};

function refuse(status, message) {
  return new Response(JSON.stringify({ type: "error", error: { type: "relay_error", message } }), {
    status,
    headers: { "content-type": "application/json" },
  });
}
