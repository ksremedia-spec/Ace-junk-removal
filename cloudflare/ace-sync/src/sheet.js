// Ashley's job sheet, read and written the same way as the Mac import
// (Ace/Import/SheetImport.swift, docs/ashley-spreadsheet.md): one row per
// job, columns found by their headings, red price = not paid.

export const COLUMNS = ["date", "name", "street", "city", "price", "payment", "check", "notMailing"];

const MATCH = {
  date: (h) => h === "date" || h.startsWith("date"),
  name: (h) => h.includes("customer") || h === "name",
  street: (h) => h.includes("street") || h.startsWith("#") || (h.includes("address") && !h.includes("mailing")),
  city: (h) => h.includes("city") || h.includes("zip") || h.includes("town"),
  price: (h) => h.includes("price") || h.includes("amount"),
  payment: (h) => h.includes("payment") || h.includes("paid by") || h === "form",
  check: (h) => h.includes("check"),
  notMailing: (h) => h.includes("mailing"),
};

// The business is in Massachusetts: a sheet date is that day in Boston.
const ZONE = "America/New_York";

export function clean(text) {
  return String(text ?? "").split(/\s+/).filter(Boolean).join(" ");
}

export function squash(text) {
  return String(text ?? "").toLowerCase().replace(/[^\p{L}\p{N}]/gu, "");
}

/// Name and address, lowercased without punctuation: the same person.
export function customerKey(name, address) {
  // "No name" (what Ace calls a nameless customer) and a blank name are the
  // same person (audit fix-now 28).
  const n = squash(name) === "noname" ? "" : squash(name);
  return n + "|" + squash(address);
}

/// Same rule as the Swift importer's PaymentType parsing.
export function paymentType(text) {
  switch (String(text ?? "").toLowerCase().replace(/[^a-z]/g, "")) {
    case "cash": return "Cash";
    case "check": case "cheque": return "Check";
    case "card": case "credit": case "creditcard": case "debit": return "Card";
    case "venmo": return "Venmo";
    case "cashapp": return "Cash App";
    default: return "Not set";
  }
}

/// How each payment type is written in her sheet.
export function paymentText(type) {
  return { Cash: "cash", Check: "check", Card: "card", Venmo: "venmo", "Cash App": "cash app" }[type] ?? "";
}

// MARK: Dates

/// Year, month, day of a moment, in Boston.
export function bostonDay(ms) {
  const parts = new Intl.DateTimeFormat("en-US", { timeZone: ZONE, year: "numeric", month: "numeric", day: "numeric" })
    .formatToParts(new Date(ms));
  const get = (t) => Number(parts.find((p) => p.type === t).value);
  return { y: get("year"), m: get("month"), d: get("day") };
}

/// Midnight in Boston on that day, as milliseconds (what the devices store
/// as the start of a day).
export function bostonMidnight(y, m, d) {
  for (const hours of [4, 5]) {
    const ms = Date.UTC(y, m - 1, d, hours);
    const hour = Number(new Intl.DateTimeFormat("en-US", { timeZone: ZONE, hour: "numeric", hourCycle: "h23" }).format(new Date(ms)));
    if (hour === 0) return ms;
  }
  return Date.UTC(y, m - 1, d, 5);
}

/// Spreadsheet day numbers count from December 30, 1899.
export function serialToDay(serial) {
  const date = new Date(Date.UTC(1899, 11, 30) + Math.floor(serial) * 86400000);
  return { y: date.getUTCFullYear(), m: date.getUTCMonth() + 1, d: date.getUTCDate() };
}

export function dayToSerial({ y, m, d }) {
  return Math.round((Date.UTC(y, m - 1, d) - Date.UTC(1899, 11, 30)) / 86400000);
}

// MARK: Reading the grid

function cellText(cell) {
  if (!cell) return "";
  if (cell.formattedValue !== undefined) return String(cell.formattedValue);
  const v = cell.effectiveValue ?? {};
  return String(v.stringValue ?? v.numberValue ?? "");
}

function cellNumber(cell) {
  const n = cell?.effectiveValue?.numberValue;
  return typeof n === "number" ? n : null;
}

/// Strong red, little green or blue (the importer's rule: r ≥ 180,
/// g and b ≤ 110 out of 255). A missing channel counts as 0.
export function isRed(cell) {
  const style = cell?.effectiveFormat?.backgroundColorStyle;
  const c = style?.rgbColor;
  if (!c) return false;
  return (c.red ?? 0) >= 180 / 255 && (c.green ?? 0) <= 110 / 255 && (c.blue ?? 0) <= 110 / 255;
}

function money(text) {
  const m = String(text).match(/[0-9][0-9,]*(\.[0-9]+)?|\.[0-9]+/);
  return m ? Number(m[0].replace(/,/g, "")) : null;
}

function findHeader(rows) {
  for (let i = 0; i < Math.min(rows.length, 10); i++) {
    const values = rows[i]?.values ?? [];
    const columns = {};
    values.forEach((cell, col) => {
      const h = cellText(cell).toLowerCase().trim();
      if (!h) return;
      const match = COLUMNS.find((c) => columns[c] === undefined && MATCH[c](h));
      if (match) columns[match] = col;
    });
    if (columns.name !== undefined && (columns.price !== undefined || columns.date !== undefined)) {
      return { index: i, columns };
    }
  }
  return null;
}

/// The tab that looks like the job list, read into rows. Every sheet row
/// is kept (with its position), so rows can be found again by position.
export function readSheet(spreadsheet) {
  const title = spreadsheet.properties?.title ?? "";
  const titleYear = (title.match(/\b(20\d\d)\b/) ?? [])[1];
  let best = null;
  for (const sheet of spreadsheet.sheets ?? []) {
    const data = sheet.data?.[0] ?? {};
    const rows = data.rowData ?? [];
    const header = findHeader(rows);
    if (!header) continue;
    const parsed = parseRows(rows, data.rowMetadata ?? [], header, Number(titleYear) || new Date().getUTCFullYear());
    if (!best || parsed.jobs.length > best.jobs.length) {
      best = { ...parsed, sheetId: sheet.properties.sheetId, tabName: sheet.properties.title, header };
    }
  }
  return best;
}

function parseRows(rows, rowMetadata, header, fallbackYear) {
  const jobs = [];
  const layout = []; // every row: { tag, day } for placing new rows
  let year = fallbackYear;
  let lastDay = null;
  const count = Math.max(rows.length, rowMetadata.length);
  for (let index = 0; index < count; index++) {
    const meta = rowMetadata[index]?.developerMetadata ?? [];
    const tag = meta.find((m) => m.metadataKey === "a")?.metadataId ?? null;
    const values = rows[index]?.values ?? [];
    const cell = (c) => (header.columns[c] === undefined ? undefined : values[header.columns[c]]);
    if (index <= header.index) { layout.push({ tag, day: null }); continue; }

    const name = clean(cellText(cell("name")));
    const street = clean(cellText(cell("street")));
    const city = clean(cellText(cell("city")));
    const priceCell = cell("price");
    const price = cellNumber(priceCell) ?? (cellText(priceCell) ? money(cellText(priceCell)) : null);
    // A repeated heading row says exactly what the heading says.
    const heading = clean(cellText(rows[header.index]?.values?.[header.columns.name])).toLowerCase();
    // A totals line says exactly "Total" or "Totals"; "Total Property
    // Management" is a customer (audit fix-now 28).
    if ((!name && !street && !city && price === null) || name.toLowerCase() === heading || /^totals?:?$/i.test(name)) {
      layout.push({ tag, day: null });
      continue;
    }

    let day = lastDay;
    const dateCell = cell("date");
    const serial = cellNumber(dateCell);
    if (serial !== null && serial > 30000 && serial < 80000) {
      day = serialToDay(serial);
    } else {
      const parts = cellText(dateCell).split(/[/.-]/).map(Number).filter((n) => !Number.isNaN(n));
      if (parts.length >= 2 && parts[0] >= 1 && parts[0] <= 12 && parts[1] >= 1 && parts[1] <= 31) {
        let y = parts.length >= 3 ? parts[2] : year;
        if (y < 100) y += 2000;
        day = { y, m: parts[0], d: parts[1] };
      }
    }
    if (!day) day = { y: year, m: 1, d: 1 };
    year = day.y;
    lastDay = day;

    const check = cell("check");
    const checkText = cellNumber(check) !== null ? String(Math.trunc(cellNumber(check))) : clean(cellText(check));
    const row = {
      index, tag, day, name, street, city, price,
      paymentRaw: cellText(cell("payment")),
      unpaid: isRed(priceCell),
      check: checkText,
      notMailing: clean(cellText(cell("notMailing"))) !== "",
    };
    row.hash = rowHash(row);
    jobs.push(row);
    layout.push({ tag, day });
  }
  return { jobs, layout };
}

/// A fingerprint of what the sheet holds for a job.
export function rowHash(r) {
  return JSON.stringify([`${r.day.y}-${r.day.m}-${r.day.d}`, r.name, r.street, r.city, r.price,
    paymentType(r.paymentRaw), !!r.unpaid, r.check || "", !!r.notMailing]);
}

// MARK: Rows ↔ Ace's records

const SHEET_NOTES = [/Check #\S+/g, /Not the mailing address\./g, /House number not known\./g];

/// The street without "???", and the address as Ace keeps it.
export function addressOf(row) {
  let street = row.street.replace(/\?/g, "").trim();
  if (street.startsWith(",")) street = street.slice(1).trim();
  return { street, address: [street, row.city].filter(Boolean).join(", "), unknownNumber: row.street.includes("?") };
}

/// The job's notes with the sheet's parts (check number, not the mailing
/// address, house number not known) replaced by what the row says.
export function mergedNotes(existing, row) {
  let notes = String(existing ?? "");
  for (const pattern of SHEET_NOTES) notes = notes.replace(pattern, "");
  const parts = [];
  if (row.check) parts.push(`Check #${row.check}`);
  if (row.notMailing) parts.push("Not the mailing address.");
  if (addressOf(row).unknownNumber) parts.push("House number not known.");
  const rest = clean(notes);
  return [...parts, rest].filter(Boolean).join(" ");
}

/// What a job looks like as a sheet row.
export function rowFromJob(job, customer) {
  const address = String(customer?.address ?? "");
  const comma = address.indexOf(",");
  let street = comma >= 0 ? address.slice(0, comma).trim() : address.trim();
  const city = comma >= 0 ? address.slice(comma + 1).trim() : "";
  const notes = String(job.notes ?? "");
  if (notes.includes("House number not known.") && street && !/\d/.test(street.split(" ")[0])) street = `??? ${street}`;
  return {
    day: bostonDay(job.scheduledAt),
    // Never write "No name" into her sheet; leave the cell as it is.
    name: String(customer?.name ?? "") === "No name" ? "" : String(customer?.name ?? ""),
    street,
    city,
    price: typeof job.price === "number" ? job.price : null,
    paymentRaw: paymentText(job.paymentType),
    unpaid: !job.isPaid,
    check: (notes.match(/Check #(\S+)/) ?? [])[1] ?? "",
    notMailing: notes.includes("Not the mailing address."),
  };
}

/// The cell writes for one row, column by column (Sheets API updateCells).
/// `only`: the columns to write (all when left out).
export function cellWrites(row, sheetId, rowIndex, columns, only) {
  const writes = [];
  const put = (column, value, fields = "userEnteredValue") => {
    if (columns[column] === undefined) return;
    if (only && !only.has(column)) return;
    writes.push({
      updateCells: {
        start: { sheetId, rowIndex, columnIndex: columns[column] },
        rows: [{ values: [value] }],
        fields,
      },
    });
  };
  const text = (s) => (s === "" || s === null || s === undefined ? {} : { userEnteredValue: { stringValue: String(s) } });
  put("date", { userEnteredValue: { numberValue: dayToSerial(row.day) } });
  put("name", text(row.name));
  put("street", text(row.street));
  put("city", text(row.city));
  // The price and its fill together: red when not paid, no fill when paid.
  put("price", {
    ...(row.price === null ? {} : { userEnteredValue: { numberValue: row.price } }),
    ...(row.unpaid ? { userEnteredFormat: { backgroundColorStyle: { rgbColor: { red: 1, green: 0, blue: 0 } } } } : {}),
  }, "userEnteredValue,userEnteredFormat.backgroundColorStyle");
  put("payment", text(row.paymentRaw));
  put("check", /^\d+$/.test(row.check) ? { userEnteredValue: { numberValue: Number(row.check) } } : text(row.check));
  put("notMailing", text(row.notMailing ? "XXX" : ""));
  return writes;
}

/// What to change in an existing row so it shows the job as Ace has it,
/// touching only what Ace really changed (audit Oct 21, M3 and M4):
/// - a cell that has something in it is never blanked;
/// - a job with no customer leaves the name and address alone;
/// - the sheet's own street/city split, payment spelling and marks are
///   kept when Ace's meaning is the same.
/// Returns the columns to write and the row as it will read afterwards.
export function rowChanges(current, wanted, { hasCustomer, customerAddress }) {
  const only = new Set();
  const merged = { ...current };
  const sameDay = (a, b) => a.y === b.y && a.m === b.m && a.d === b.d;
  if (!sameDay(current.day, wanted.day)) { only.add("date"); merged.day = wanted.day; }
  if (hasCustomer) {
    if (wanted.name && wanted.name !== current.name) { only.add("name"); merged.name = wanted.name; }
    const sheetAddress = addressOf(current).address;
    if (customerAddress && squash(customerAddress) !== squash(sheetAddress)) {
      if (wanted.street && wanted.street !== current.street) { only.add("street"); merged.street = wanted.street; }
      if (wanted.city && wanted.city !== current.city) { only.add("city"); merged.city = wanted.city; }
    }
  }
  const price = wanted.price ?? current.price;
  if (price !== current.price || !!wanted.unpaid !== !!current.unpaid) {
    only.add("price"); merged.price = price; merged.unpaid = !!wanted.unpaid;
  }
  const wantedPayment = paymentType(wanted.paymentRaw);
  if (wantedPayment !== "Not set" && wantedPayment !== paymentType(current.paymentRaw)) {
    only.add("payment"); merged.paymentRaw = wanted.paymentRaw;
  }
  if (wanted.check && wanted.check !== current.check) { only.add("check"); merged.check = wanted.check; }
  if (wanted.notMailing && !current.notMailing) { only.add("notMailing"); merged.notMailing = true; }
  merged.hash = rowHash(merged);
  return { only, merged };
}
