// A stand-in for Google's sign-in, Drive and Sheets, for testing the sheet
// link on Kyle's Mac without a Google account (docs/google-sheet-sync.md).
// Holds one pretend copy of Ashley's sheet in memory and answers the
// requests src/google.js makes, plus /test/... hooks that play Ashley
// editing the sheet. Run: node test/fake-google.mjs (port 8790).
import http from "node:http";

const PORT = Number(process.env.PORT ?? 8790);
const SHEET_ID = "fake-sheet-1";
const COLS = ["", "Date", "Customer Name", "# and Street Name", "City, State & Zip", "Price", "Form of Payment", "Check #", "Not Mailing Address"];

let version = 1;
let rows = [];  // each: { cells: [ { v, red } ], meta: [ { metadataId, metadataKey } ] }
let lastBatch = [];
let highestId = 0;      // the largest tag number ever created
let afterRead = null;   // a row Ashley "types" right after the next full read

function reset(list) {
  rows = [{ cells: COLS.map((h) => ({ v: h || null })), meta: [] }];
  for (const r of list) rows.push(makeRow(r));
  version++;
}

/// [serial date, name, street, city, price, payment, check, notMailing, red]
function makeRow([date, name, street, city, price, payment, check, nm, red]) {
  const values = [null, date, name, street, city, price, payment, check, nm];
  return { cells: values.map((v, i) => ({ v: v === "" ? null : v, red: i === 5 && !!red })), meta: [] };
}

function formatted(col, v) {
  if (v === null || v === undefined) return undefined;
  if (col === 1 && typeof v === "number") {
    const d = new Date(Date.UTC(1899, 11, 30) + v * 86400000);
    return `${d.getUTCMonth() + 1}/${d.getUTCDate()}`;
  }
  return String(v);
}

function grid() {
  return {
    properties: { title: "2026 ACE Books (test)" },
    sheets: [
      {
        properties: { sheetId: 0, title: "Client Job List" },
        data: [{
          rowData: rows.map((r) => ({
            values: r.cells.map((c, col) => {
              const cell = {};
              if (c.v !== null && c.v !== undefined) {
                cell.effectiveValue = typeof c.v === "number" ? { numberValue: c.v } : { stringValue: c.v };
                cell.formattedValue = formatted(col, c.v);
              }
              if (c.red) cell.effectiveFormat = { backgroundColorStyle: { rgbColor: { red: 1 } } };
              return cell;
            }),
          })),
          rowMetadata: rows.map((r) => (r.meta.length ? { developerMetadata: r.meta } : {})),
        }],
      },
      { properties: { sheetId: 1, title: "Contracted Labor" }, data: [{ rowData: [] }] },
    ],
  };
}

function applyBatch(requests) {
  for (const q of requests) {
    if (q.createDeveloperMetadata) {
      const m = q.createDeveloperMetadata.developerMetadata;
      const used = rows.some((r) => r.meta.some((x) => x.metadataId === m.metadataId));
      if (used) throw new Error(`metadataId ${m.metadataId} is already in use`);
      rows[m.location.dimensionRange.startIndex].meta.push({ metadataId: m.metadataId, metadataKey: m.metadataKey });
      highestId = Math.max(highestId, m.metadataId);
    } else if (q.updateCells) {
      const { start, rows: values, fields } = q.updateCells;
      const row = rows[start.rowIndex];
      while (row.cells.length <= start.columnIndex) row.cells.push({ v: null });
      const cell = row.cells[start.columnIndex];
      const data = values[0].values[0];
      if (fields.includes("userEnteredValue")) {
        const u = data.userEnteredValue;
        cell.v = u ? (u.numberValue ?? u.stringValue ?? null) : null;
      }
      if (fields.includes("backgroundColorStyle")) {
        cell.red = !!data.userEnteredFormat?.backgroundColorStyle?.rgbColor?.red;
      }
    } else if (q.deleteDimension) {
      const { startIndex, endIndex } = q.deleteDimension.range;
      rows.splice(startIndex, endIndex - startIndex);
    } else if (q.insertDimension) {
      const { range, inheritFromBefore } = q.insertDimension;
      const above = rows[range.startIndex - 1];
      const fresh = { cells: COLS.map((_, i) => ({ v: null, red: inheritFromBefore && above ? !!above.cells[i]?.red : false })), meta: [] };
      rows.splice(range.startIndex, 0, fresh);
    } else {
      throw new Error("Unknown request " + Object.keys(q)[0]);
    }
  }
}

/// Plain rows for the test to look at.
function plain() {
  return rows.slice(1).map((r) => ({
    tag: r.meta.find((m) => m.metadataKey === "a")?.metadataId ?? null,
    tags: r.meta.length,
    date: r.cells[1]?.v ?? null, name: r.cells[2]?.v ?? null, street: r.cells[3]?.v ?? null,
    city: r.cells[4]?.v ?? null, price: r.cells[5]?.v ?? null, red: !!r.cells[5]?.red,
    payment: r.cells[6]?.v ?? null, check: r.cells[7]?.v ?? null, nm: r.cells[8]?.v ?? null,
  }));
}

function send(res, status, body, headers = {}) {
  res.writeHead(status, { "Content-Type": "application/json", ...headers });
  res.end(typeof body === "string" ? body : JSON.stringify(body));
}

http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://localhost:${PORT}`);
  let body = "";
  for await (const chunk of req) body += chunk;
  try {
    // Sign-in: play the person picking the sheet, straight back to Ace.
    if (url.pathname === "/o/oauth2/v2/auth") {
      const back = new URL(url.searchParams.get("redirect_uri"));
      back.searchParams.set("code", "fake-code");
      back.searchParams.set("picked_file_ids", SHEET_ID);
      back.searchParams.set("scope", url.searchParams.get("scope"));
      if (url.searchParams.get("state")) back.searchParams.set("state", url.searchParams.get("state"));
      return send(res, 302, "", { Location: back.toString() });
    }
    if (url.pathname === "/token") {
      const form = new URLSearchParams(body);
      if (form.get("grant_type") === "authorization_code") return send(res, 200, { access_token: "fake-access", refresh_token: "fake-refresh", expires_in: 3600 });
      if (form.get("refresh_token") === "fake-refresh") return send(res, 200, { access_token: "fake-access", expires_in: 3600 });
      return send(res, 400, { error: "invalid_grant" });
    }
    if (req.headers.authorization !== "Bearer fake-access" && !url.pathname.startsWith("/test/")) return send(res, 401, { error: "no token" });
    if (url.pathname === `/drive/v3/files/${SHEET_ID}`) {
      return send(res, 200, { name: "2026 ACE Books (test)", mimeType: "application/vnd.google-apps.spreadsheet", version: String(version) });
    }
    if (url.pathname === `/v4/spreadsheets/${SHEET_ID}`) {
      send(res, 200, grid());
      // A row typed between Ace's read and its write, which Drive's version
      // has not caught up with yet (the version is left as it was).
      if (afterRead && (url.searchParams.get("fields") ?? "").includes("rowData")) {
        rows.splice(afterRead.at, 0, makeRow(afterRead.row));
        afterRead = null;
      }
      return;
    }
    if (url.pathname === `/v4/spreadsheets/${SHEET_ID}:batchUpdate`) {
      const { requests } = JSON.parse(body);
      lastBatch = requests;
      // All or nothing, like Google.
      const backup = JSON.stringify(rows);
      try { applyBatch(requests); } catch (e) { rows = JSON.parse(backup); return send(res, 400, { error: { message: e.message } }); }
      version++;
      return send(res, 200, { replies: [] });
    }

    // Test hooks: what Ashley does in the sheet.
    const input = body ? JSON.parse(body) : {};
    if (url.pathname === "/test/reset") { reset(input.rows ?? []); return send(res, 200, { ok: true }); }
    if (url.pathname === "/test/rows") return send(res, 200, plain());
    if (url.pathname === "/test/last-batch") return send(res, 200, lastBatch);
    if (url.pathname === "/test/set") {
      // { row (1 = first job), col (1-8), value, red }
      const cell = rows[input.row].cells[input.col];
      if ("value" in input) cell.v = input.value;
      if ("red" in input) cell.red = input.red;
      version++;
      return send(res, 200, { ok: true });
    }
    if (url.pathname === "/test/insert") { rows.splice(input.at, 0, makeRow(input.row)); version++; return send(res, 200, { ok: true }); }
    if (url.pathname === "/test/scramble") {
      // A sort that moves the contents of the job rows but leaves each row's
      // hidden tag where it was (the case Google does not document).
      const body = rows.slice(1);
      const contents = body.map((r) => r.cells).reverse();
      body.forEach((r, i) => { r.cells = contents[i]; });
      version++;
      return send(res, 200, { ok: true });
    }
    if (url.pathname === "/test/insert-after-read") { afterRead = input; return send(res, 200, { ok: true }); }
    if (url.pathname === "/test/reserve-next-ids") {
      // Something else in the file (another tab, an add-on) holds the next
      // tag numbers Ace would pick.
      const ids = Array.from({ length: input.count ?? 3 }, (_, i) => highestId + 1 + i);
      for (const id of ids) rows[0].meta.push({ metadataId: id, metadataKey: "other" });
      return send(res, 200, { ids });
    }
    if (url.pathname === "/test/delete") { rows.splice(input.row, input.count ?? 1); version++; return send(res, 200, { ok: true }); }
    send(res, 404, { error: "not found" });
  } catch (e) {
    send(res, 500, { error: String(e) });
  }
}).listen(PORT, () => console.log(`fake Google on http://localhost:${PORT}`));
