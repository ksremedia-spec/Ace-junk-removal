# Demo relay: the Assistant in the browser demo, with the key kept off the page

The browser demo (the claude.ai artifact) can fill in a job with Claude in
three ways:

1. A key pasted into the demo's Settings on that device. It stays in that
   browser. The person using the demo has to paste it once.
2. The viewer's own claude.ai account, when they are signed in. Nothing to
   paste, but they need an account and get a one-time permission prompt.
3. This relay. The demo page sends the request to a tiny web service that you
   run on Cloudflare; the service adds the API key and forwards the request
   to Anthropic. The key lives only in the service's settings. Anyone who
   opens the demo link gets the Assistant with nothing to type.

Option 3 is the one to use for a client who should just open the link.

## What it costs and what it risks

- Cloudflare Workers has a free plan that covers this many times over.
- Anyone with the demo link can make the relay call Claude, and each call is
  billed to your Anthropic account (a few cents each with Sonnet). The relay
  only accepts calls from the demo page's own web addresses and only sends the
  one kind of request the demo makes, but someone determined could still run
  it from the page. So: make a separate API key just for this, set a monthly
  spending limit on it in the Anthropic console, and delete the key when the
  demo is over.

## Setup, about ten minutes, done once

1. Sign in at https://dash.cloudflare.com (the client's account or your own).
2. Left sidebar: **Workers & Pages** → **Create** → **Create Worker**. Give
   it a name such as `ace-demo-relay`. Click **Deploy** to create it with the
   placeholder code.
3. Click **Edit code**. Delete everything in the editor, paste in the whole
   of `worker.js` from this folder, and click **Deploy**.
4. Back on the Worker's page: **Settings** → **Variables and Secrets** →
   **Add**. Type: Secret. Name: `ANTHROPIC_API_KEY`. Value: the API key made
   for the demo. Save, then **Deploy** if it asks.
5. On the Worker's **Overview** you will see its address, which looks like
   `https://ace-demo-relay.<something>.workers.dev`. Copy it.
6. Send that address to Claude in the project session. The demo page gets
   republished with the address inside (it is not a secret), and from then on
   the Assistant works for everyone who opens the demo link.

To turn it off later, delete the Worker, or delete the API key in the
Anthropic console. Either stops it at once.

## Checking it works

In the demo, open Settings (the gear on Today, or the Ace menu on the Mac
view). The "Connection" row says **Open** when the page can reach the relay
and **Blocked by this browser** when it cannot. Then open the Assistant, type
a note such as "Mrs. Johnson, 42 Elm Street, garage cleanout Friday morning,
three hundred cash", and tap Fill in the form.
