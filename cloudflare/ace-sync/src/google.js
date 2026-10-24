// The link to Ashley's Google Sheet (docs/google-sheet-sync.md): she signs
// in with Google once and picks the sheet (scope drive.file only); every
// minute the server reads the sheet into Ace and writes Ace's changes back.
import {
  addressOf, bostonDay, bostonMidnight, cellWrites, customerKey, mergedNotes,
  paymentType, readSheet, rowChanges, rowFromJob, rowHash,
} from "./sheet.js";

const SCOPE = "https://www.googleapis.com/auth/drive.file";
const SHEET_TYPE = "application/vnd.google-apps.spreadsheet";
const PENDING_MINUTES = 15;
/// Safety limits for one check; going past any of them pauses the link with
/// a plain reason instead of changing anything (audit Oct 21, M2 and M13).
/// Resume in Settings lets the next check through once.
const MAX_DELETES = 10;   // rows vanished from the sheet
const MAX_EDITED = 10;    // tagged rows changed in the sheet (a sort gone wrong looks like this)
const MAX_INSERTS = 20;   // new rows Ace would add to the sheet
const MAX_REWRITES = 25;  // existing rows Ace would change

/// Google's address, or the local stand-in when GOOGLE_TEST_URL is set
/// (test/fake-google.mjs; development only).
function google(env, url) {
  if (!env.GOOGLE_TEST_URL) return url;
  return url.replace(/^https:\/\/[a-z0-9.]+\.(googleapis|google)\.com/, env.GOOGLE_TEST_URL.replace(/\/$/, ""));
}

function redirectURL(env) {
  return `${env.PUBLIC_URL.replace(/\/$/, "")}/google/callback`;
}

// MARK: Connecting

/// The Google sign-in address for a device's Connect button.
export async function startConnect(env) {
  if (!env.GOOGLE_CLIENT_ID || !env.GOOGLE_CLIENT_SECRET || !env.PUBLIC_URL) {
    return { error: "Google is not set up on the server yet." };
  }
  const state = crypto.randomUUID();
  await env.DB.batch([
    env.DB.prepare("DELETE FROM google_pending WHERE created < ?1").bind(Date.now() - PENDING_MINUTES * 60000),
    env.DB.prepare("INSERT INTO google_pending (state, created) VALUES (?1, ?2)").bind(state, Date.now()),
  ]);
  const params = new URLSearchParams({
    client_id: env.GOOGLE_CLIENT_ID,
    redirect_uri: redirectURL(env),
    response_type: "code",
    scope: SCOPE,
    access_type: "offline",
    prompt: "consent",
    trigger_onepick: "true",
    mimetypes: SHEET_TYPE,
    state,
  });
  return { url: google(env, `https://accounts.google.com/o/oauth2/v2/auth?${params}`) };
}

/// Where Google sends the browser back: swaps the code for a lasting
/// token and remembers the picked sheet.
export async function finishConnect(request, env) {
  const url = new URL(request.url);
  const error = url.searchParams.get("error");
  if (error) return page("The sheet was not connected.", "Google said: " + error + ". Close this tab and try again from Ace.");

  // Google's picker page does not mention passing `state` through, so a
  // sign-in started from Ace in the last 15 minutes is accepted without it.
  const state = url.searchParams.get("state");
  // Google passes `state` back through its picker (seen Oct 21), so it is
  // required: a sign-in Ace did not start is never attached (fix-now 31).
  const pending = state
    ? await env.DB.prepare("SELECT state FROM google_pending WHERE state = ?1 AND created > ?2").bind(state, Date.now() - PENDING_MINUTES * 60000).first()
    : null;
  if (!pending) return page("The sheet was not connected.", "This sign-in was not started from Ace, or took more than 15 minutes. Start again from Ace.");

  const code = url.searchParams.get("code");
  const sheetId = (url.searchParams.get("picked_file_ids") ?? "").split(",")[0];
  if (!code || !sheetId) return page("The sheet was not connected.", "No sheet was picked. Start again from Ace and pick the job sheet.");

  const tokenReply = await fetch(google(env, "https://oauth2.googleapis.com/token"), {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      code, client_id: env.GOOGLE_CLIENT_ID, client_secret: env.GOOGLE_CLIENT_SECRET,
      redirect_uri: redirectURL(env), grant_type: "authorization_code",
    }),
  });
  const tokens = await tokenReply.json();
  if (!tokenReply.ok || !tokens.refresh_token) {
    return page("The sheet was not connected.", "Google did not give lasting access (" + (tokens.error ?? tokenReply.status) + "). Start again from Ace.");
  }

  const file = await googleJSON(google(env, `https://www.googleapis.com/drive/v3/files/${encodeURIComponent(sheetId)}?fields=name,mimeType`), tokens.access_token);
  if (file.mimeType !== SHEET_TYPE) return page("The sheet was not connected.", "That file is not a Google Sheet. Start again and pick the job sheet.");

  const connected = page(`Ace is connected to “${file.name ?? "the sheet"}”.`, "You can close this tab. Ace checks the sheet every minute.");
  // The same sheet again (after Disconnect or a sign-in error): only the
  // sign-in is replaced. The row tags and the place in Ace's changes are
  // kept, so changes made in between still reach the sheet and no job is
  // matched up a second time (audit Oct 24, 15).
  const existing = await env.DB.prepare("SELECT sheet_id FROM google_link WHERE id = 1").first();
  if (existing?.sheet_id === sheetId) {
    await env.DB.batch([
      env.DB.prepare("DELETE FROM google_pending"),
      env.DB.prepare("UPDATE google_link SET refresh_token = ?1, sheet_name = ?2, last_error = '' WHERE id = 1").bind(tokens.refresh_token, file.name ?? ""),
    ]);
    return connected;
  }

  // Ace's changes from before the connection are not copied into the sheet;
  // jobs already in both are matched up on the first check. Tag numbers
  // start at a random large number, so they cannot clash with hidden tags
  // something else put in the file (audit Oct 24, 55).
  const latest = await env.DB.prepare("SELECT COALESCE(MAX(seq), 0) AS latest FROM records").first();
  const firstTag = 1000000 + Math.floor(Math.random() * 1000000);
  await env.DB.batch([
    env.DB.prepare("DELETE FROM google_pending"),
    env.DB.prepare("DELETE FROM sheet_rows"),
    env.DB.prepare(`INSERT OR REPLACE INTO google_link
      (id, refresh_token, sheet_id, sheet_name, connected_at, last_version, last_seq, next_tag, paused, last_run, last_error)
      VALUES (1, ?1, ?2, ?3, ?4, '', ?5, ?6, '', 0, '')`).bind(tokens.refresh_token, sheetId, file.name ?? "", Date.now(), latest.latest, firstTag),
  ]);
  return connected;
}

export async function status(env) {
  // A link with no sign-in was disconnected (kept for connecting again).
  const link = await env.DB.prepare("SELECT sheet_name, connected_at, paused, last_run, last_error FROM google_link WHERE id = 1 AND refresh_token != ''").first();
  if (!link) return { connected: false, configured: !!(env.GOOGLE_CLIENT_ID && env.GOOGLE_CLIENT_SECRET && env.PUBLIC_URL) };
  return {
    connected: true, configured: true, sheetName: link.sheet_name, connectedAt: link.connected_at,
    paused: link.paused, lastRun: link.last_run, lastError: link.last_error,
  };
}

/// Forgets the sign-in and stops the checks. The row tags and the place in
/// Ace's changes stay, for when the same sheet is connected again; another
/// sheet starts afresh (audit Oct 24, 15).
export async function disconnect(env) {
  await env.DB.prepare("UPDATE google_link SET refresh_token = '', running_until = 0 WHERE id = 1").run();
  return { connected: false };
}

export async function resume(env) {
  await env.DB.prepare("UPDATE google_link SET paused = '', override = 1 WHERE id = 1 AND refresh_token != ''").run();
  return status(env);
}

// MARK: The minute-by-minute check

export async function runSheetSync(env) {
  // One check at a time: a slow run and the next minute's must not both
  // write to her sheet (audit fix-now 26). The lease lapses after 2 minutes
  // in case a run is cut off.
  const now = Date.now();
  const lease = await env.DB.prepare(
    "UPDATE google_link SET running_until = ?1 WHERE id = 1 AND paused = '' AND refresh_token != '' AND running_until < ?2"
  ).bind(now + 120000, now).run();
  if (!lease.meta?.changes) return;
  const link = await env.DB.prepare("SELECT * FROM google_link WHERE id = 1").first();
  if (!link) return;
  try {
    await runOnce(env, link);
    await env.DB.prepare("UPDATE google_link SET last_run = ?1, last_error = '', running_until = 0 WHERE id = 1").bind(Date.now()).run();
  } catch (error) {
    await env.DB.prepare("UPDATE google_link SET last_run = ?1, last_error = ?2, running_until = 0 WHERE id = 1").bind(Date.now(), String(error.message ?? error).slice(0, 300)).run();
  }
}

async function runOnce(env, link) {
  const token = await accessToken(env, link.refresh_token);
  const file = await googleJSON(google(env, `https://www.googleapis.com/drive/v3/files/${link.sheet_id}?fields=version,name`), token);
  const pending = await env.DB.prepare(
    "SELECT COUNT(*) AS n FROM records WHERE seq > ?1 AND device != 'sheet' AND type IN ('job', 'customer')"
  ).bind(link.last_seq).first();
  // Nothing new on either side: one cheap request and done.
  if (String(file.version) === link.last_version && pending.n === 0) return;

  // The theme turns a theme-colour fill into red, green and blue (audit Oct 24, 18).
  const fields = "properties(title,spreadsheetTheme),sheets(properties(sheetId,title),data(rowData(values(effectiveValue,formattedValue,effectiveFormat.backgroundColorStyle)),rowMetadata(developerMetadata(metadataId,metadataKey))))";
  const grid = await googleJSON(google(env, `https://sheets.googleapis.com/v4/spreadsheets/${link.sheet_id}?fields=${encodeURIComponent(fields)}`), token);
  // The tab the link has used so far is kept, even when another tab has
  // more rows (audit Oct 24, 56).
  const sheet = readSheet(grid, link.layout ? JSON.parse(link.layout)[0] : undefined);
  if (!sheet) throw new Error("The job list was not found in the sheet: no Customer Name and Price headings.");
  // The tab and its columns as first seen: a renamed or moved heading would
  // otherwise change every job at once (audit fix-now 30).
  const sheetLayout = JSON.stringify([sheet.sheetId, sheet.header.index, sheet.header.columns]);

  // Everything Ace holds for jobs and customers.
  const { results } = await env.DB.prepare(
    "SELECT type, id, updated_at, deleted, data, seq, device FROM records WHERE type IN ('job', 'customer')"
  ).all();
  const jobs = new Map(), customers = new Map();
  for (const r of results) {
    const record = { id: r.id, updatedAt: r.updated_at, deleted: r.deleted === 1, data: JSON.parse(r.data), seq: r.seq, device: r.device };
    (r.type === "job" ? jobs : customers).set(r.id, record);
  }
  const tagRows = (await env.DB.prepare("SELECT tag, job_id, hash FROM sheet_rows").all()).results;
  const byTag = new Map(tagRows.map((t) => [t.tag, t]));
  const tagOfJob = new Map(tagRows.map((t) => [t.job_id, t.tag]));

  const now = Date.now();
  const recordWrites = []; // records changed by the sheet
  const tagWrites = new Map(); // tag → { job_id, hash }
  const tagDeletes = new Set();
  const requests = []; // Sheets batchUpdate, in order
  // Tag numbers must be new to the whole sheet, including tags left from
  // an earlier connection.
  let nextTag = Math.max(link.next_tag, ...sheet.layout.map((r) => (r.tag ?? 0) + 1));
  // Device changes up to here are handled in this run; later ones next run.
  const seenSeq = results.reduce((max, r) => Math.max(max, r.seq), link.last_seq);

  const customerByKey = new Map();
  for (const c of customers.values()) {
    if (!c.deleted) customerByKey.set(customerKey(c.data.name, c.data.address), c);
  }
  const putRecord = (type, record) => {
    record.updatedAt = now;
    record.device = "sheet";
    recordWrites.push({ type, id: record.id, updatedAt: now, deleted: record.deleted ? 1 : 0, data: record.data });
  };

  // The customer a row belongs to: found by name and address, renamed when
  // it was this job's own customer, or new.
  const customerFor = (row, job) => {
    const { address } = addressOf(row);
    const key = customerKey(row.name, address);
    const found = customerByKey.get(key);
    if (found) return found;
    const current = job && customers.get(job.data.customer);
    const sharedWith = current ? [...jobs.values()].filter((j) => !j.deleted && j.data.customer === current.id).length : 0;
    if (current && !current.deleted && sharedWith <= 1) {
      customerByKey.delete(customerKey(current.data.name, current.data.address));
      current.data = { ...current.data, name: row.name || "No name", address };
      customerByKey.set(key, current);
      putRecord("customer", current);
      return current;
    }
    const fresh = { id: crypto.randomUUID().toUpperCase(), deleted: false,
      data: { name: row.name || "No name", phone: "", address, notes: "", createdAt: now } };
    customers.set(fresh.id, fresh);
    customerByKey.set(key, fresh);
    putRecord("customer", fresh);
    return fresh;
  };

  const today = bostonDay(now);
  // Before today counts as done; a job typed for today is still to do.
  const isPast = (day) => day.y * 10000 + day.m * 100 + day.d < today.y * 10000 + today.m * 100 + today.d;
  const applyRow = (row, job) => {
    const customer = customerFor(row, job);
    const midnight = bostonMidnight(row.day.y, row.day.m, row.day.d);
    const old = job?.data ?? {};
    // A job with a time keeps its time of day when its date changes.
    const timeOfDay = old.hasTime && old.scheduledAt ? old.scheduledAt - bostonMidnight(...Object.values(bostonDay(old.scheduledAt))) : 0;
    const data = {
      ...old,
      customer: customer.id,
      jobType: old.jobType ?? "Junk removal",
      scheduledAt: midnight + timeOfDay,
      // An end time moves with its job (fix-now 31).
      ...(old.endsAt && old.scheduledAt ? { endsAt: old.endsAt + (midnight + timeOfDay - old.scheduledAt) } : {}),
      hasTime: old.hasTime ?? false,
      price: row.price ?? undefined,
      paymentType: paymentType(row.paymentRaw),
      isPaid: !row.unpaid,
      isDone: old.isDone ?? isPast(row.day),
      notes: mergedNotes(old.notes, row),
      createdAt: old.createdAt ?? now,
    };
    if (data.price === undefined) delete data.price;
    const record = job ?? { id: crypto.randomUUID().toUpperCase(), deleted: false };
    record.data = data;
    record.deleted = false;
    jobs.set(record.id, record);
    putRecord("job", record);
    return record;
  };

  const guarded = !link.override;
  if (guarded && link.layout && link.layout !== sheetLayout) {
    await env.DB.prepare("UPDATE google_link SET paused = ?1 WHERE id = 1")
      .bind("The sheet's tab or column headings changed, so syncing with the sheet paused; nothing was changed. Check the headings, then Resume in Settings.").run();
    return;
  }
  const pause = async (reason) => {
    await env.DB.prepare("UPDATE google_link SET paused = ?1 WHERE id = 1")
      .bind(`${reason} Syncing with the sheet paused; nothing was changed. Check the sheet, then Resume in Settings.`).run();
  };

  // A sort or paste that moved row contents but not the hidden row tags
  // makes rows look edited, each now reading exactly as another edited
  // row's job did. Such a row is paired with that job again and nothing
  // changes in Ace; Resume would otherwise give every job another row's
  // contents (audit Oct 24, 6 and 44).
  const edited = sheet.jobs.filter((r) => r.tag !== null && byTag.has(r.tag) && byTag.get(r.tag).hash !== r.hash);
  const jobsByHash = new Map(); // fingerprint → jobs of edited rows that last read like that
  for (const r of edited) {
    const { job_id, hash } = byTag.get(r.tag);
    if (!jobsByHash.has(hash)) jobsByHash.set(hash, []);
    jobsByHash.get(hash).push(job_id);
  }
  const moved = new Map(); // tag → the job whose contents are now on its row
  for (const r of edited) {
    const job = jobsByHash.get(r.hash)?.shift();
    if (job !== undefined) moved.set(r.tag, job);
  }
  const claimed = new Set(moved.values());
  // Rows that really changed but whose own job moved to another row, and
  // the jobs that moved and changed (their contents are on no row as they
  // were). There are always as many of one as of the other.
  const displaced = edited.filter((r) => !moved.has(r.tag) && claimed.has(byTag.get(r.tag).job_id));
  const unplaced = edited.filter((r) => moved.has(r.tag) && !claimed.has(byTag.get(r.tag).job_id)).map((r) => byTag.get(r.tag));
  const undo = "If the sheet was sorted, undo the sort (Edit > Undo) before resuming.";
  if (guarded && displaced.length > 1) {
    await pause(`Rows were moved and changed in the sheet at the same time, so it is not clear which row is which job. ${undo}`);
    return;
  }
  // Rows whose contents Ace will take as edits.
  const changedRows = edited.length - moved.size;
  if (guarded && changedRows > MAX_EDITED) {
    await pause(`${changedRows} rows changed in the sheet at once (more than ${MAX_EDITED}). ${undo}`);
    return;
  }
  // One moved-and-changed row is that job, edited. After Resume, more than
  // one are paired in sheet order.
  const repaired = new Map(edited.filter((r) => moved.has(r.tag)).map((r) => [r.tag, { tag: r.tag, job_id: moved.get(r.tag), hash: r.hash }]));
  displaced.forEach((r, i) => repaired.set(r.tag, { ...unplaced[i], tag: r.tag }));
  for (const [tag, entry] of repaired) {
    byTag.set(tag, entry);
    tagOfJob.set(entry.job_id, tag);
    // Cleared and written again, since a job is on one row only.
    tagDeletes.add(tag);
    tagWrites.set(tag, { job_id: entry.job_id, hash: entry.hash });
  }

  // 1. The sheet into Ace.
  const seenTags = new Set(sheet.jobs.filter((r) => r.tag !== null && byTag.has(r.tag)).map((r) => r.tag));
  const missing = new Set([...byTag.keys()].filter((t) => !seenTags.has(t)));
  // Jobs a new row could be: their tag went missing (a copied or moved
  // row), or they are not tied to any row yet (the first check).
  const matchKey = (name, address, day, price) => `${customerKey(name, address)}|${day.y}-${day.m}-${day.d}|${price ?? ""}`;
  const candidates = new Map();
  const addCandidate = (job) => {
    if (job.deleted) return;
    const customer = customers.get(job.data.customer);
    const key = matchKey(customer?.data.name ?? "", customer?.data.address ?? "", bostonDay(job.data.scheduledAt), job.data.price);
    if (!candidates.has(key)) candidates.set(key, []);
    candidates.get(key).push(job);
  };
  for (const t of missing) { const j = jobs.get(byTag.get(t).job_id); if (j) addCandidate(j); }
  for (const j of jobs.values()) if (!tagOfJob.has(j.id)) addCandidate(j);

  const tagged = new Map(); // sheet row index → tag (new or kept)
  for (const row of sheet.jobs) {
    if (row.tag !== null && byTag.has(row.tag)) {
      const known = byTag.get(row.tag);
      tagged.set(row.index, row.tag);
      if (known.hash !== row.hash) {
        // Edited in the sheet: the sheet's version is the newer change.
        const job = jobs.get(known.job_id);
        const saved = applyRow(row, job && !job.deleted ? job : null);
        tagWrites.set(row.tag, { job_id: saved.id, hash: row.hash });
      }
      continue;
    }
    // A row with no tag: typed in the sheet, or there before the connection.
    const { address } = addressOf(row);
    const match = candidates.get(matchKey(row.name, address, row.day, row.price))?.shift();
    let job;
    if (match) {
      job = match;
      const oldTag = tagOfJob.get(job.id);
      if (oldTag !== undefined) { missing.delete(oldTag); tagDeletes.add(oldTag); }
    } else {
      job = applyRow(row, null);
    }
    // A row still carrying a tag from an earlier connection keeps it.
    const tag = row.tag ?? nextTag++;
    tagged.set(row.index, tag);
    tagWrites.set(tag, { job_id: job.id, hash: row.hash });
    tagOfJob.set(job.id, tag);
    if (row.tag === null) {
      requests.push({ createDeveloperMetadata: { developerMetadata: {
        metadataId: tag, metadataKey: "a", metadataValue: "1", visibility: "PROJECT",
        location: { dimensionRange: { sheetId: sheet.sheetId, dimension: "ROWS", startIndex: row.index, endIndex: row.index + 1 } },
      } } });
    }
  }

  // Rows whose tag is gone and that were not found again were deleted.
  if (guarded && missing.size > MAX_DELETES) {
    await pause(`${missing.size} rows disappeared from the sheet at once.`);
    return;
  }
  for (const t of missing) {
    const job = jobs.get(byTag.get(t).job_id);
    if (job && !job.deleted) { job.deleted = true; putRecord("job", job); }
    tagDeletes.add(t);
    tagOfJob.delete(byTag.get(t).job_id);
  }

  // 2. Ace into the sheet: jobs and customers changed on a device since the
  // last check.
  const changedJobs = new Set();
  for (const j of jobs.values()) if (j.seq > link.last_seq && j.device !== "sheet") changedJobs.add(j.id);
  for (const c of customers.values()) {
    if (c.seq > link.last_seq && c.device !== "sheet") {
      for (const j of jobs.values()) if (j.data.customer === c.id && tagOfJob.has(j.id)) changedJobs.add(j.id);
    }
  }
  const layout = sheet.layout.map((r, index) => ({ ...r, tag: tagged.get(index) ?? r.tag }));
  const rowOfTag = (tag) => layout.findIndex((r) => r.tag === tag);
  const deletes = [], updates = [], inserts = [];
  for (const id of changedJobs) {
    const job = jobs.get(id);
    const tag = tagOfJob.get(id);
    if (job.deleted) { if (tag !== undefined) deletes.push(tag); continue; }
    const row = rowFromJob(job.data, customers.get(job.data.customer)?.data);
    if (tag !== undefined) updates.push({ tag, row, job }); else inserts.push({ job, row });
  }
  const currentByTag = new Map(sheet.jobs.filter((r) => r.tag !== null).map((r) => [tagged.get(r.index) ?? r.tag, r]));
  const dayNumber = (d) => (d ? d.y * 10000 + d.m * 100 + d.d : null);
  // Rows with a blank Date cell take the date of the row above (sheet.js).
  // When Ace changes, adds or removes a dated row above them, their date is
  // written in first, so they keep meaning the same day (audit Oct 24, 16).
  const keepDates = (from, newDay) => {
    for (let i = from; i < layout.length; i++) {
      const r = layout[i];
      if (!r.day) continue;
      if (!r.dateBlank || dayNumber(r.day) === dayNumber(newDay)) break;
      requests.push(...cellWrites({ day: r.day }, sheet.sheetId, i, sheet.header.columns, new Set(["date"])));
      r.dateBlank = false;
    }
  };
  const redated = []; // [row index, new day]
  let rewrites = 0;
  for (const { tag, row, job } of updates) {
    const index = rowOfTag(tag);
    const current = currentByTag.get(tag);
    if (index < 0 || !current) continue;
    const customer = customers.get(job.data.customer);
    const { only, merged } = rowChanges(current, row, {
      hasCustomer: !!customer && !customer.deleted,
      customerAddress: customer?.data.address ?? "",
    });
    if (only.size) {
      requests.push(...cellWrites(merged, sheet.sheetId, index, sheet.header.columns, only));
      rewrites++;
    }
    if (only.has("date")) { layout[index].dateBlank = false; redated.push([index, merged.day]); }
    tagWrites.set(tag, { job_id: byTagJob(tag), hash: merged.hash });
  }
  for (const [index, day] of redated) keepDates(index + 1, day);
  // Deletions count too: nothing else limits how many rows Ace removes
  // from her books in one check (audit Oct 24, 14).
  const tooMany = inserts.length > MAX_INSERTS ? `Ace would add ${inserts.length} new rows to the sheet at once (more than ${MAX_INSERTS}).`
    : rewrites > MAX_REWRITES ? `Ace would change ${rewrites} rows in the sheet at once (more than ${MAX_REWRITES}).`
    : deletes.length > MAX_DELETES ? `Ace would delete ${deletes.length} rows from the sheet at once (more than ${MAX_DELETES}).`
    : "";
  if (guarded && tooMany) {
    await pause(tooMany);
    return;
  }
  // Deletions from the bottom up, so the rows above keep their places.
  for (const index of deletes.map(rowOfTag).filter((i) => i >= 0).sort((a, b) => b - a)) {
    let above = index - 1;
    while (above >= 0 && !layout[above].day) above--;
    keepDates(index + 1, above >= 0 ? layout[above].day : null);
    requests.push({ deleteDimension: { range: { sheetId: sheet.sheetId, dimension: "ROWS", startIndex: index, endIndex: index + 1 } } });
    tagDeletes.add(layout[index].tag);
    tagWrites.delete(layout[index].tag);
    layout.splice(index, 1);
  }
  // New jobs go in date order, after the last row on or before their day.
  for (const { job, row } of inserts.sort((a, b) => a.job.data.scheduledAt - b.job.data.scheduledAt)) {
    let at = layout.length;
    let lastData = -1;
    for (let i = 0; i < layout.length; i++) {
      if (layout[i].day) {
        lastData = i;
        if (dayNumber(layout[i].day) > dayNumber(row.day)) { at = i; break; }
      }
    }
    if (at === layout.length) at = lastData + 1;
    requests.push({ insertDimension: { range: { sheetId: sheet.sheetId, dimension: "ROWS", startIndex: at, endIndex: at + 1 }, inheritFromBefore: at > 0 } });
    requests.push(...cellWrites(row, sheet.sheetId, at, sheet.header.columns));
    const tag = nextTag++;
    requests.push({ createDeveloperMetadata: { developerMetadata: {
      metadataId: tag, metadataKey: "a", metadataValue: "1", visibility: "PROJECT",
      location: { dimensionRange: { sheetId: sheet.sheetId, dimension: "ROWS", startIndex: at, endIndex: at + 1 } },
    } } });
    layout.splice(at, 0, { tag, day: row.day });
    keepDates(at + 1, row.day);
    tagWrites.set(tag, { job_id: job.id, hash: rowHash(row) });
  }

  function byTagJob(tag) {
    return tagWrites.get(tag)?.job_id ?? byTag.get(tag)?.job_id;
  }

  // Write the sheet first (all or nothing), then Ace's side. If Ashley
  // changed the sheet since it was read, the row positions may be stale:
  // write nothing and try again next minute (audit fix-now 26). Drive's
  // version may lag behind her edits (Google does not say), so the tagged
  // rows are also read again: if any is no longer where it was, a row was
  // added, removed or moved meanwhile (audit Oct 24, 54).
  if (requests.length) {
    const check = await googleJSON(google(env, `https://www.googleapis.com/drive/v3/files/${link.sheet_id}?fields=version`), token);
    if (String(check.version) !== String(file.version)) return;
    const tagFields = "sheets(properties(sheetId),data(rowMetadata(developerMetadata(metadataId,metadataKey))))";
    const again = await googleJSON(google(env, `https://sheets.googleapis.com/v4/spreadsheets/${link.sheet_id}?fields=${encodeURIComponent(tagFields)}`), token);
    const tab = (again.sheets ?? []).find((s) => s.properties?.sheetId === sheet.sheetId);
    const tagsNow = (tab?.data?.[0]?.rowMetadata ?? []).map((r) => (r?.developerMetadata ?? []).find((m) => m.metadataKey === "a")?.metadataId ?? null);
    const places = (tags) => JSON.stringify(tags.flatMap((tag, index) => (tag === null ? [] : [[index, tag]])));
    if (!tab || places(tagsNow) !== places(sheet.layout.map((r) => r.tag))) return;
    try {
      await googleJSON(google(env, `https://sheets.googleapis.com/v4/spreadsheets/${link.sheet_id}:batchUpdate`), token, { requests });
    } catch (error) {
      // A tag number already used elsewhere in the file fails the whole
      // write; the next check tries numbers further on (audit Oct 24, 55).
      if (/metadata/i.test(String(error.message))) {
        await env.DB.prepare("UPDATE google_link SET next_tag = ?1 WHERE id = 1").bind(nextTag + 1000 + Math.floor(Math.random() * 100000)).run();
      }
      throw error;
    }
  }
  // The version from before this run's own write: an edit she made while it
  // ran is then seen next time, not skipped.
  const after = file;
  const statements = [];
  if (recordWrites.length) {
    // One statement for any number of records (the free plan allows 50
    // queries per run). Running numbers continue from the highest.
    statements.push(env.DB.prepare(
      `INSERT INTO records (type, id, updated_at, deleted, data, seq, device)
       SELECT json_extract(j.value, '$.type'), json_extract(j.value, '$.id'), json_extract(j.value, '$.updatedAt'),
              json_extract(j.value, '$.deleted'), json_extract(j.value, '$.data'),
              (SELECT COALESCE(MAX(seq), 0) FROM records) + j.key + 1, 'sheet'
       FROM json_each(?1) AS j WHERE true
       ON CONFLICT (type, id) DO UPDATE SET
         updated_at = excluded.updated_at, deleted = excluded.deleted, data = excluded.data,
         seq = excluded.seq, device = excluded.device
       WHERE excluded.updated_at >= records.updated_at`
    ).bind(JSON.stringify(recordWrites)));
  }
  if (tagDeletes.size) {
    statements.push(env.DB.prepare("DELETE FROM sheet_rows WHERE tag IN (SELECT value FROM json_each(?1))").bind(JSON.stringify([...tagDeletes])));
  }
  if (tagWrites.size) {
    statements.push(env.DB.prepare(
      `INSERT OR REPLACE INTO sheet_rows (tag, job_id, hash)
       SELECT json_extract(j.value, '$[0]'), json_extract(j.value, '$[1]'), json_extract(j.value, '$[2]') FROM json_each(?1) AS j`
    ).bind(JSON.stringify([...tagWrites].map(([tag, w]) => [tag, w.job_id, w.hash]))));
  }
  // Ace's changes up to here are now in the sheet; the sheet's own changes
  // (written just now with device 'sheet') are skipped next time anyway.
  statements.push(env.DB.prepare("UPDATE google_link SET last_version = ?1, last_seq = ?2, next_tag = ?3, override = 0, layout = ?4 WHERE id = 1")
    .bind(String(after.version), seenSeq, nextTag, sheetLayout));
  await env.DB.batch(statements);
}

// MARK: Google requests

async function accessToken(env, refreshToken) {
  const reply = await fetch(google(env, "https://oauth2.googleapis.com/token"), {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: env.GOOGLE_CLIENT_ID, client_secret: env.GOOGLE_CLIENT_SECRET,
      refresh_token: refreshToken, grant_type: "refresh_token",
    }),
  });
  const body = await reply.json();
  if (!reply.ok) throw new Error(`Google refused the sign-in (${body.error ?? reply.status}). Connect the sheet again from Ace.`);
  return body.access_token;
}

async function googleJSON(url, token, body) {
  const reply = await fetch(url, {
    method: body ? "POST" : "GET",
    headers: { Authorization: `Bearer ${token}`, ...(body ? { "Content-Type": "application/json" } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await reply.text();
  if (!reply.ok) throw new Error(`Google answered ${reply.status}: ${text.slice(0, 200)}`);
  return text ? JSON.parse(text) : {};
}

function escapeHTML(s) {
  return String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
}

function page(title, text) {
  return new Response(`<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width">
<title>Ace</title><body style="font:17px -apple-system,system-ui,sans-serif;max-width:32em;margin:15vh auto;padding:0 16px;color:#1d1d1f">
<h1 style="font-size:24px">${escapeHTML(title)}</h1><p>${escapeHTML(text)}</p></body>`, { headers: { "Content-Type": "text/html; charset=utf-8" } });
}
