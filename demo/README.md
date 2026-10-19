# Demo pages and their checks

The pages shown to Ashley, Alex and Kyle before the real app is on their
devices. They are published on claude.ai; these are the source files they
were published from, plus the automatic checks that drive the demo in a
test browser. Copied here from the cloud session on 2026-10-19 so a session
on Kyle's Mac can keep working on them.

## What is here

| Folder | What it is | Published at |
|---|---|---|
| `app-demo/index.html` | The clickable demo: iPhone and Mac, every tab, the Assistant. Version 21 has the Calendar tab. | https://claude.ai/artifact/Mv1yKwDUgPyxR2jaj8qQ3j (shared: anyone with the link) |
| `preview/` | The client Preview page (Kyle's favourite), with screenshots in `img/`. Not yet updated for Quotes, end times or Calendar. | https://claude.ai/artifact/8wvbCffQ4deC7uh8ThqXsC |
| `phone-slideshow/` | The slideshow made for reading on a phone. | https://claude.ai/artifact/MikLi52xrfdmSewj4KyLHb |
| `deck/` | The 14-slide deck (a claude.ai Slides artifact: `deck.json` plus one file per slide). | https://claude.ai/artifact/J8UKoRfm4Zg8qpaw8t1GLR |
| `checks/` | Automatic checks for the demo, and two scripts that keep the demo's and the app's instructions to Claude identical to `docs/assistant-actions.md`. | |

A stray second copy of the Preview page also exists
(https://claude.ai/artifact/KSMW87Xj4mE3o7LZtNkDxD). It is left alone until
Kyle says to delete it.

## Trying the demo without claude.ai

From this folder: `sh checks/build-standalone.sh`, then open
`demo/build/Ace-demo.html` in Safari. The `build/` folder is not saved to
GitHub.

## Running the checks (on a Mac)

Needs Node.js. Once:

```
cd demo/checks
npm install
npx playwright install chromium
```

Then `npm test` builds the standalone page and runs every check (203 on
2026-10-19, all passing in the cloud session's test browser). Each check
file can also be run alone, for example `node calendar.js`.

| File | Checks |
|---|---|
| `all-screens.js` | Every tab, forms, the Assistant with a stand-in for Claude, the Mac window, menus and keys (108) |
| `quotes.js` | The Quotes tab (21) |
| `assistant-quotes.js` | The Assistant creating and updating quotes (16) |
| `end-times.js` | End times and overlap warnings (25) |
| `move-keeps-length.js` | A moved job keeps its length (1) |
| `calendar.js` | The Calendar tab, Settings › Calendar, the Mac calendar (32) |

`harness.js` is shared by the Assistant checks: it opens the page and
answers in place of Claude, so no API key or network is needed. Screenshots
from the checks go to `checks/shots/` (not saved to GitHub).

## Keeping the demo and the app in step with the spec

- `python3 checks/sync-assistant-prompt.py` copies the instructions and
  answer shape from `docs/assistant-actions.md` into the demo.
- `python3 checks/check-contract.py` compares the app's copy
  (`Ace/Assistant/AssistantPlan.swift`) with the same spec and prints any
  difference.

## Publishing a change (for a Claude session)

Publish to the existing link so it keeps working for everyone who has it:
the Artifact tool with `file_path` set to the page and `url` set to the link
above. The demo keeps its stored settings (it asks Claude through the
viewer's own claude.ai sign-in). The Preview page and the slideshow also
send their `img/` files.
