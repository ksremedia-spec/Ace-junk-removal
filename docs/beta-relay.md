# Beta relay: the Assistant without a key on the tester's Mac

Oct 20, 2026. Kyle is sending a Mac beta to a non-technical tester before
visiting. The Assistant needs an Anthropic key; instead of putting the key in
the app, the beta sends notes to a small Cloudflare Worker that holds the key
as a secret and passes the note on to Anthropic.

- Code: `cloudflare/beta-relay/worker.js`. It forwards only Messages calls on
  `claude-haiku-5-5` and `claude-sonnet-5-5`, caps `max_tokens` at 16,000 and
  refuses anything else.
- The key: only in the Worker's secret `ANTHROPIC_API_KEY`, typed by Kyle in
  the Cloudflare dashboard. Never in the app, the repo or a file.
- The app: `Ace/Support/Beta.swift`, `relayURL`. When set, the Assistant
  sends there and needs no key on the device; Settings shows the key as
  "Provided for this test".
- Off switch: delete or deactivate the Worker in Cloudflare. A spending
  limit on the Anthropic key caps the cost.
- Anyone who has the beta (or finds the Worker's address) can use the
  Assistant on Kyle's key until it is switched off.
- Before the real build for Ashley and Alex: set `Beta.isBeta = false` and
  `relayURL = nil`.

## Setting it up (Kyle, once, about 10 minutes)

1. Sign in at dash.cloudflare.com (free account is enough).
2. Workers & Pages → Create → Create Worker (start from "Hello World").
   Name it `ace-beta-relay`. Deploy.
3. Edit code: delete what is there, paste all of
   `cloudflare/beta-relay/worker.js`, Deploy.
4. The Worker's Settings → Variables and Secrets → Add → type Secret,
   name `ANTHROPIC_API_KEY`, paste the key as the value. Deploy.
5. Copy the Worker's address (ends in `.workers.dev`) and give it to Claude.
