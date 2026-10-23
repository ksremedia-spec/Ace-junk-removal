# Setting up Google for the sheet link (one time)

For the sheet link in `google-sheet-sync.md`. Done once in Google Cloud
Console, first with **Kyle's own Gmail and a copy of the fake test sheet**
(testing), later again in **the business's Gmail** (the real one). About 15
minutes. Free. Steps from Google's documentation (researched Oct 21, 2026);
Google renames buttons now and then, so the labels may differ slightly.

1. Go to console.cloud.google.com and sign in with the Gmail account.
2. Make a new project, named "Ace" ("Ace test" for Kyle's).
3. In the search bar, find and turn on (Enable) three things, one at a
   time: **Google Sheets API**, **Google Drive API**, **Google Picker API**.
4. Open **Google Auth Platform**:
   - **Branding**: app name "Ace", support email (the account's own). Leave
     logo, homepage and domains empty (we skipped the business name on the
     sign-in screen, Oct 21).
   - **Audience**: user type **External**, then click **Publish app** so the
     status says **In production**. (Left in "Testing", Google's access
     runs out after 7 days.)
   - **Data Access**: add one scope only,
     `https://www.googleapis.com/auth/drive.file` ("See, edit, create, and
     delete only the specific Google Drive files you use with this app").
     Nothing else, or Google shows its "unverified app" warning.
   - **Clients**: Create client → type **Web application** → under
     Authorized redirect URIs add the server's address plus
     `/google/callback`. For testing on Kyle's Mac:
     `http://localhost:8787/google/callback`. Create.
5. Google shows a **Client ID** and a **Client secret**. These go into the
   server's settings, never into the app or GitHub:
   - testing: the two lines in `cloudflare/ace-sync/.dev.vars` (Kyle pastes
     them between the quotes; the file is not committed);
   - the real server: Cloudflare's secrets `GOOGLE_CLIENT_ID` and
     `GOOGLE_CLIENT_SECRET`, plus `PUBLIC_URL` set to the server's address.

Then in Ace on the Mac: Settings › Google Sheet › Connect Google Sheet…
→ sign in → Allow → pick the sheet.
