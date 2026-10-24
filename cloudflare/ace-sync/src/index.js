// Ace's sync server: keeps every iPhone and Mac in step.
// Design: docs/device-sync.md.
//
// POST /v1/sync
//   { device: "uuid", since: 0, changes: [{ type, id, updatedAt, deleted, data }] }
// → { changes: [{ type, id, updatedAt, deleted, data, seq }], latest: 12, more: false }
//
// An incoming record replaces the stored one only when it is newer. Every
// accepted change gets the next running number (seq).

import { disconnect, finishConnect, resume, runSheetSync, startConnect, status } from "./google.js";

const TYPES = new Set(["customer", "job", "dumpster", "rental", "quote", "worker", "labor", "setting"]);
// The free plan allows 50 database queries per request and 10 ms of CPU,
// so a device sends at most 40 changes and gets at most 200 back at a time.
const PAGE = 200;
const MAX_CHANGES = 40;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname === "/v1/health") return json({ ok: true });
    // The two public pages Google's sign-in screen links to (its Branding
    // page requires a homepage and a privacy policy on this domain).
    if (url.pathname === "/" || url.pathname === "/privacy") return publicPage(url.pathname);
    // Google sends the browser back here after the sign-in (no sync code:
    // it is checked against the sign-in Ace started).
    if (url.pathname === "/google/callback") return finishConnect(request, env);
    if (request.method !== "POST") return json({ error: "Use POST." }, 405);
    if (!env.SYNC_KEY || request.headers.get("Authorization") !== `Bearer ${env.SYNC_KEY}`) {
      return json({ error: "Wrong sync code." }, 401);
    }
    switch (url.pathname) {
      case "/v1/google/start": return json(await startConnect(env));
      case "/v1/google/status": return json(await status(env));
      case "/v1/google/disconnect": return json(await disconnect(env));
      case "/v1/google/resume": return json(await resume(env));
      case "/v1/google/run":
        await runSheetSync(env);
        return json(await status(env));
      case "/v1/claude": return claude(request, env);
      case "/v1/sync": break;
      default: return json({ error: "Not found." }, 404);
    }

    let body;
    try {
      body = await request.json();
    } catch {
      return json({ error: "Not JSON." }, 400);
    }
    const device = typeof body.device === "string" ? body.device.slice(0, 64) : "";
    const since = Number.isInteger(body.since) && body.since >= 0 ? body.since : 0;
    const changes = Array.isArray(body.changes) ? body.changes : [];
    if (changes.length > MAX_CHANGES) return json({ error: `At most ${MAX_CHANGES} changes per request.` }, 413);

    const statements = [];
    for (const change of changes) {
      const problem = check(change);
      if (problem) return json({ error: problem }, 400);
      statements.push(
        env.DB.prepare(
          `INSERT INTO records (type, id, updated_at, deleted, data, seq, device)
           VALUES (?1, ?2, ?3, ?4, ?5, (SELECT COALESCE(MAX(seq), 0) + 1 FROM records), ?6)
           ON CONFLICT (type, id) DO UPDATE SET
             updated_at = excluded.updated_at, deleted = excluded.deleted,
             data = excluded.data, seq = excluded.seq, device = excluded.device
           WHERE excluded.updated_at > records.updated_at`
        ).bind(change.type, change.id, change.updatedAt, change.deleted ? 1 : 0,
               JSON.stringify(change.data ?? {}), device)
      );
    }
    // A batch runs as one transaction, so two devices syncing at once never
    // get the same running number.
    if (statements.length) await env.DB.batch(statements);

    // A device that is further along than this server has ever been is
    // talking to a reset or replaced server: tell it to start afresh.
    const top = await env.DB.prepare("SELECT COALESCE(MAX(seq), 0) AS top, (SELECT value FROM meta WHERE key = 'server_id') AS server FROM records").first();
    if (since > top.top) return json({ changes: [], latest: 0, more: false, reset: true, server: top.server });

    const { results } = await env.DB.prepare(
      `SELECT type, id, updated_at, deleted, data, seq FROM records
       WHERE seq > ?1 ORDER BY seq LIMIT ?2`
    ).bind(since, PAGE + 1).all();
    const more = results.length > PAGE;
    const page = more ? results.slice(0, PAGE) : results;

    return json({
      changes: page.map((row) => ({
        type: row.type,
        id: row.id,
        updatedAt: row.updated_at,
        deleted: row.deleted === 1,
        data: JSON.parse(row.data),
        seq: row.seq,
      })),
      // Only as far as what was actually sent: a save landing between the
      // page query and a separate "highest number" query would otherwise be
      // counted as seen and never sent (audit Oct 21, M6).
      latest: page.length ? page[page.length - 1].seq : since,
      more,
      server: top.server,
    });
  },

  // Every minute: the Google Sheet check.
  async scheduled(event, env, ctx) {
    ctx.waitUntil(runSheetSync(env));
  },
};

function check(change) {
  if (!change || typeof change !== "object") return "A change is not an object.";
  if (!TYPES.has(change.type)) return `Unknown record type: ${String(change.type).slice(0, 20)}.`;
  if (typeof change.id !== "string" || !/^[0-9A-Fa-f-]{36}$/.test(change.id)) return "A record ID is not a UUID.";
  if (typeof change.updatedAt !== "number" || !Number.isFinite(change.updatedAt)) return "A record has no time.";
  if (change.data !== undefined && (typeof change.data !== "object" || change.data === null)) return "A record's data is not an object.";
  return null;
}

// The Assistant's notes (Oct 24): the app sends Anthropic Messages calls
// here with the sync code, and they go on to the ace-beta-relay Worker over
// a service binding (CLAUDE in wrangler.jsonc), which holds the API key.
// Nobody types a key on a phone, and the key is in one place only.
const CLAUDE_MODELS = ["claude-haiku-5-5", "claude-sonnet-5-5"];
const CLAUDE_MAX_TOKENS = 16000;
const CLAUDE_MAX_BYTES = 1_000_000;

async function claude(request, env) {
  const refuse = (status, message) => json({ type: "error", error: { type: "ace_error", message } }, status);
  if (!env.CLAUDE) return refuse(503, "The Assistant is not set up on the server.");
  const text = await request.text();
  if (text.length > CLAUDE_MAX_BYTES) return refuse(413, "The note is too large.");
  let body;
  try {
    body = JSON.parse(text);
  } catch {
    return refuse(400, "The request could not be read.");
  }
  if (!CLAUDE_MODELS.includes(body.model)) return refuse(400, "That model is not allowed.");
  if (typeof body.max_tokens !== "number" || body.max_tokens > CLAUDE_MAX_TOKENS) body.max_tokens = CLAUDE_MAX_TOKENS;
  const upstream = await env.CLAUDE.fetch("https://relay/v1/messages", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "anthropic-version": request.headers.get("anthropic-version") || "2023-06-01",
    },
    body: JSON.stringify(body),
  });
  return new Response(upstream.body, {
    status: upstream.status,
    headers: { "content-type": upstream.headers.get("content-type") || "application/json" },
  });
}

function json(value, status = 200) {
  return new Response(JSON.stringify(value), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function publicPage(path) {
  const style = "font:17px/1.5 -apple-system,system-ui,sans-serif;max-width:40em;margin:8vh auto;padding:0 16px;color:#1d1d1f";
  const body = path === "/privacy" ? `
<h1>Ace: privacy</h1>
<p>Ace is a private app used by one small business, Ace Junk Removal in Massachusetts, to keep track of its own jobs, customers, dumpsters and crew hours. It is not offered to the public.</p>
<h2>What Ace keeps</h2>
<p>The business's own records: customer names, phone numbers and addresses, jobs, prices and payments, dumpster rentals and crew hours. They are stored on the business's own iPhones and Mac and on this server, so the devices stay in step.</p>
<h2>Google</h2>
<p>When the business connects its job sheet, Ace asks Google for access to that one Google Sheet only (the "drive.file" permission). Ace reads and writes that sheet to keep it and the app in step. It cannot see any other file in the Google account. Access can be removed at any time at myaccount.google.com, under Security, Third-party apps with account access.</p>
<h2>What Ace does not do</h2>
<p>Ace does not sell, share or advertise with any of this information, and does not track anyone. Notes spoken to the Assistant are turned into text on the device; the text of a note is sent to Anthropic's Claude service only to fill in the job form.</p>
<h2>Questions</h2>
<p>Contact the support email shown on the Google sign-in screen.</p>` : `
<h1>Ace</h1>
<p>Ace is the private job, customer and dumpster app of Ace Junk Removal, Massachusetts. It is used only by the business's own staff and is not available to the public.</p>
<p><a href="/privacy">Privacy</a></p>`;
  return new Response(`<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>Ace</title><body style="${style}">${body}</body>`, {
    headers: { "Content-Type": "text/html; charset=utf-8" },
  });
}
