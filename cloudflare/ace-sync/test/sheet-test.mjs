// End-to-end test of the Google Sheet link against the stand-in Google
// (test/fake-google.mjs). Plays Ashley editing the sheet and a device
// sending changes, and checks both sides after each step.
// Run with test/run-sheet-test.sh (starts the stand-in and a test server).
import { readFileSync } from "node:fs";

const SERVER = process.env.SERVER ?? "http://localhost:8788";
const FAKE = process.env.FAKE ?? "http://localhost:8790";
const KEY = process.env.SYNC_KEY ?? readFileSync(new URL("../.dev.vars", import.meta.url), "utf8").match(/SYNC_KEY="([^"]*)"/)[1];

let failures = 0;
function check(what, ok, detail = "") {
  console.log(`${ok ? "PASS" : "FAIL"}  ${what}${ok || !detail ? "" : "  — " + detail}`);
  if (!ok) failures++;
}

async function post(path, body = {}) {
  const r = await fetch(SERVER + path, {
    method: "POST", headers: { Authorization: `Bearer ${KEY}`, "Content-Type": "application/json" }, body: JSON.stringify(body),
  });
  return r.json();
}
const fake = async (path, body) => (await fetch(FAKE + path, { method: body ? "POST" : "GET", body: body ? JSON.stringify(body) : undefined })).json();
const run = () => post("/v1/google/run");

/// Everything on the server, as a device would see it.
async function records() {
  const all = new Map();
  let since = 0;
  for (;;) {
    const r = await post("/v1/sync", { device: "test", since, changes: [] });
    for (const c of r.changes) all.set(`${c.type}/${c.id}`, c);
    since = r.latest;
    if (!r.more) break;
  }
  return { all, latest: since };
}
const live = (all, type) => [...all.values()].filter((r) => r.type === type && !r.deleted);
const jobOf = (all, name, price) => live(all, "job").find((j) => {
  const c = all.get(`customer/${j.data.customer}`);
  return c?.data.name === name && (price === undefined || j.data.price === price);
});

const serial = (y, m, d) => Math.round((Date.UTC(y, m - 1, d) - Date.UTC(1899, 11, 30)) / 86400000);
function bostonMidnight(y, m, d) {
  for (const h of [4, 5]) {
    const ms = Date.UTC(y, m - 1, d, h);
    if (Number(new Intl.DateTimeFormat("en-US", { timeZone: "America/New_York", hour: "numeric", hourCycle: "h23" }).format(ms)) === 0) return ms;
  }
}
const uuid = () => crypto.randomUUID().toUpperCase();
const push = (changes) => post("/v1/sync", { device: "phone", since: 0, changes });

// ---- Setup: the sheet, and one job already in Ace (as after an import).
await fake("/test/reset", { rows: [
  [serial(2026, 10, 1), "Linda Johnson", "42 Elm St", "Taunton, MA 02780", 300, "check", 1234, "", false],
  [serial(2026, 10, 1), "Mark Pereira", "15 Bay Rd", "Fall River, MA", 450, "venmo", "", "", true],
  [serial(2026, 10, 5), "Joe Souza", "??? Main Rd", "Westport, MA", 200, "cash", "", "XXX", false],
  [serial(2026, 10, 8), "Linda Johnson", "42 Elm St", "Taunton, MA 02780", 150, "check", 1300, "", false],
  [serial(2026, 10, 12), "Ana Costa", "9 Hope St", "New Bedford, MA", 600, "cash app", "", "", false],
  [serial(2026, 10, 20), "Tom Walsh", "3 Pine St", "Dartmouth, MA", 350, "", "", "", true],
] });
const ana = uuid(), anaJob = uuid();
await push([
  { type: "customer", id: ana, updatedAt: Date.now(), deleted: false, data: { name: "Ana Costa", phone: "508-555-0101", address: "9 Hope St, New Bedford, MA", notes: "", createdAt: Date.now() } },
  { type: "job", id: anaJob, updatedAt: Date.now(), deleted: false, data: { customer: ana, jobType: "Junk removal", scheduledAt: bostonMidnight(2026, 10, 12), hasTime: false, price: 600, paymentType: "Cash App", isPaid: true, isDone: true, notes: "", createdAt: Date.now() } },
]);

// ---- 1. Connecting: Google sign-in and picking the sheet.
const start = await post("/v1/google/start");
check("Connect gives a Google sign-in address", typeof start.url === "string" && start.url.includes("trigger_onepick=true") && start.url.includes("drive.file"), JSON.stringify(start));
const toAce = (await fetch(start.url, { redirect: "manual" })).headers.get("location");
const pageText = await (await fetch(toAce)).text();
check("Google sends the browser back and Ace says connected", pageText.includes("Ace is connected to"), pageText.slice(0, 200));
const st = await post("/v1/google/status");
check("Status says connected to the test sheet", st.connected && st.sheetName === "2026 ACE Books (test)", JSON.stringify(st));

// ---- 2. First check: the sheet comes into Ace; the existing job is matched.
await run();
let { all, latest } = await records();
check("6 jobs in Ace (5 new, Ana's matched, not doubled)", live(all, "job").length === 6, `${live(all, "job").length} jobs`);
check("5 customers (Linda once)", live(all, "customer").length === 5, `${live(all, "customer").length} customers`);
check("Ana's job kept its ID and phone", !!all.get(`job/${anaJob}`) && all.get(`customer/${ana}`)?.data.phone === "508-555-0101");
let rows = await fake("/test/rows");
check("Every row got exactly one hidden tag", rows.every((r) => r.tag !== null && r.tags === 1), JSON.stringify(rows.map((r) => r.tags)));
const mark = jobOf(all, "Mark Pereira");
check("Red price came in as not paid", mark && mark.data.isPaid === false);
check("Payment types read (Check, Venmo, Cash, Not set)", jobOf(all, "Linda Johnson", 300)?.data.paymentType === "Check" && mark?.data.paymentType === "Venmo" && jobOf(all, "Joe Souza")?.data.paymentType === "Cash" && jobOf(all, "Tom Walsh")?.data.paymentType === "Not set");
const joe = jobOf(all, "Joe Souza");
check("Check number, not-mailing and unknown house number in notes", jobOf(all, "Linda Johnson", 300)?.data.notes.includes("Check #1234") && joe?.data.notes.includes("Not the mailing address.") && joe?.data.notes.includes("House number not known."), joe?.data.notes);
check("Date is that day in Massachusetts", mark?.data.scheduledAt === bostonMidnight(2026, 10, 1));

// ---- 3. Nothing changed: nothing written.
await run();
check("A check with no changes writes nothing", (await records()).latest === latest);

// ---- 4. Ashley edits a row: marks Mark paid and changes the price.
const latestBefore4 = (await records()).latest;
await fake("/test/set", { row: 2, col: 5, value: 475, red: false });
await run();
({ all, latest } = await records());
const mark2 = jobOf(all, "Mark Pereira");
check("Sheet edit reached Ace (paid, $475)", mark2?.data.isPaid === true && mark2?.data.price === 475, JSON.stringify(mark2?.data));
const changed4 = [...all.values()].filter((r) => r.seq > latestBefore4);
check("Only that job changed", changed4.length === 1 && changed4[0].id === mark2?.id, JSON.stringify(changed4.map((r) => [r.type, r.data.price])));

// ---- 5. A device edits a job: Linda's Oct 8 job to $175, not paid.
const lindaLater = jobOf(all, "Linda Johnson", 150);
await push([{ type: "job", id: lindaLater.id, updatedAt: Date.now(), deleted: false, data: { ...lindaLater.data, price: 175, isPaid: false } }]);
await run();
rows = await fake("/test/rows");
const lindaRow = rows.find((r) => r.name === "Linda Johnson" && r.check === 1300);
check("Device edit reached the sheet ($175, red)", lindaRow?.price === 175 && lindaRow?.red === true, JSON.stringify(lindaRow));

// ---- 6. A device adds a job: Ana, Oct 15, $800 cash.
const newJob = uuid();
await push([{ type: "job", id: newJob, updatedAt: Date.now(), deleted: false, data: { customer: ana, jobType: "Junk removal", scheduledAt: bostonMidnight(2026, 10, 15), hasTime: true, price: 800, paymentType: "Cash", isPaid: true, isDone: false, notes: "", createdAt: Date.now() } }]);
await run();
rows = await fake("/test/rows");
const at = rows.findIndex((r) => r.price === 800);
check("New job became a row in date order (between Oct 12 and Oct 20)", at > 0 && rows[at - 1].date === serial(2026, 10, 12) && rows[at + 1]?.date === serial(2026, 10, 20), JSON.stringify(rows.map((r) => r.date)));
check("New row has the date, name, address, price and payment", rows[at]?.date === serial(2026, 10, 15) && rows[at]?.name === "Ana Costa" && rows[at]?.street === "9 Hope St" && rows[at]?.city === "New Bedford, MA" && rows[at]?.payment === "cash" && rows[at]?.red === false && rows[at]?.tag !== null, JSON.stringify(rows[at]));
await run();
({ all } = await records());
check("The new row did not come back as a second job", live(all, "job").filter((j) => j.data.price === 800).length === 1);

// ---- 7. Ashley types a new row at the bottom.
const count = (await fake("/test/rows")).length;
await fake("/test/insert", { at: count + 1, row: [serial(2026, 10, 25), "Rose Tavares", "77 Ocean Ave", "Fairhaven, MA", 250, "check", 555, "", false] });
await run();
({ all } = await records());
const rose = jobOf(all, "Rose Tavares");
check("Row typed in the sheet became a job and a customer", rose?.data.price === 250 && rose?.data.notes.includes("Check #555"));

// ---- 8. A device renames a customer.
const tom = live(all, "customer").find((c) => c.data.name === "Tom Walsh");
await push([{ type: "customer", id: tom.id, updatedAt: Date.now(), deleted: false, data: { ...tom.data, name: "Tom Walsh Jr" } }]);
await run();
rows = await fake("/test/rows");
check("Customer renamed on a device: the sheet row followed", rows.some((r) => r.name === "Tom Walsh Jr") && !rows.some((r) => r.name === "Tom Walsh"));

// ---- 9. Ashley deletes a row.
rows = await fake("/test/rows");
await fake("/test/delete", { row: rows.findIndex((r) => r.name === "Joe Souza") + 1 });
await run();
({ all } = await records());
check("Row deleted in the sheet: the job is deleted in Ace", !jobOf(all, "Joe Souza") && [...all.values()].some((r) => r.type === "job" && r.deleted));

// ---- 10. A device deletes a job.
await push([{ type: "job", id: rose.id, updatedAt: Date.now(), deleted: true, data: {} }]);
await run();
rows = await fake("/test/rows");
check("Job deleted on a device: its row is gone", !rows.some((r) => r.name === "Rose Tavares"));

// ---- 11. Many rows vanish at once: the link pauses instead.
const before = (await fake("/test/rows")).length;
for (let i = 0; i < 12; i++) await fake("/test/insert", { at: before + 1 + i, row: [serial(2026, 10, 28), `Bulk ${i}`, `${i} Test St`, "Somerset, MA", 100, "cash", "", "", false] });
await run();
const jobsBefore = live((await records()).all, "job").length;
await fake("/test/delete", { row: before + 1, count: 12 });
await run();
const paused = await post("/v1/google/status");
check("12 rows vanishing at once pauses the sheet link", !!paused.paused, JSON.stringify(paused));
check("…and deletes nothing in Ace", live((await records()).all, "job").length === jobsBefore);

// ---- 12. Resume lets the paused check through once.
await post("/v1/google/resume");
await run();
const resumed = await post("/v1/google/status");
check("Resume lets the paused check through, then it runs normally", !resumed.paused, JSON.stringify(resumed));
({ all } = await records());
check("…and the 12 jobs are then deleted in Ace", live(all, "job").length === jobsBefore - 12 && !live(all, "job").some((j) => all.get(`customer/${j.data.customer}`)?.data.name.startsWith("Bulk ")));

// ---- 13. Deleting a customer leaves their rows' names and addresses alone (audit M3).
({ all } = await records());
const linda = live(all, "customer").find((c) => c.data.name === "Linda Johnson");
const lindaJobs = live(all, "job").filter((j) => j.data.customer === linda.id);
await push([
  { type: "customer", id: linda.id, updatedAt: Date.now(), deleted: true, data: {} },
  ...lindaJobs.map((j) => ({ type: "job", id: j.id, updatedAt: Date.now(), deleted: false, data: { ...j.data, customer: undefined } })),
]);
await run();
rows = await fake("/test/rows");
const lindaRows = rows.filter((r) => r.street === "42 Elm St");
check("Customer deleted in Ace: her rows keep name and address", lindaRows.length >= 2 && lindaRows.every((r) => r.name === "Linda Johnson" && r.city === "Taunton, MA 02780"), JSON.stringify(lindaRows));

// ---- 14. A small edit in Ace changes only that cell; the sheet's own spelling stays (audit M4).
({ all } = await records());
const anaRow = (await fake("/test/rows")).find((r) => r.name === "Ana Costa" && r.price === 600);
const anaJob600 = jobOf(all, "Ana Costa", 600);
await push([{ type: "job", id: anaJob600.id, updatedAt: Date.now(), deleted: false, data: { ...anaJob600.data, notes: "Gate code 1234" } }]);
await run();
const anaAfter = (await fake("/test/rows")).find((r) => r.name === "Ana Costa" && r.price === 600);
check("A notes-only edit in Ace leaves the row exactly as it was (\"cash app\" spelling kept)", JSON.stringify(anaAfter) === JSON.stringify(anaRow), JSON.stringify([anaRow, anaAfter]));
const last = await fake("/test/last-batch");
check("…and sends no cell writes for it", !last.some((q) => q.updateCells && q.updateCells.start.rowIndex === (rows.findIndex((r) => r.name === "Ana Costa" && r.price === 600) + 1)), JSON.stringify(last).slice(0, 300));

// ---- 15. Ace adding too many rows at once pauses instead (audit M2: sample data on a synced device).
const many = Array.from({ length: 25 }, (_, i) => ({ type: "job", id: uuid(), updatedAt: Date.now(), deleted: false,
  data: { customer: ana, jobType: "Junk removal", scheduledAt: bostonMidnight(2026, 11, 2), hasTime: false, price: 100 + i, paymentType: "Cash", isPaid: true, isDone: false, notes: "", createdAt: Date.now() } }));
const before15 = (await fake("/test/rows")).length;
await push(many.slice(0, 25));
await run();
const st15 = await post("/v1/google/status");
check("25 new jobs from Ace at once pause the link", !!st15.paused && (await fake("/test/rows")).length === before15, JSON.stringify(st15));
await post("/v1/google/resume");
await run();
check("…and Resume lets them in", (await fake("/test/rows")).length === before15 + 25);

// ---- 16. A sort that moves contents but not tags (audit M13; Oct 24, 6 and 44):
// each row is matched to its job again by its contents, and nothing in Ace changes.
const jobPrint = (all) => JSON.stringify(live(all, "job").map((j) => [j.id, all.get(`customer/${j.data.customer}`)?.data.name, j.data.price, j.data.scheduledAt, j.data.isPaid, j.data.paymentType]).sort());
const before16 = await records();
await fake("/test/scramble", {});
await run();
const st16 = await post("/v1/google/status");
let after16 = await records();
check("A sort that leaves the hidden tags behind does not pause", !st16.paused && !st16.lastError, JSON.stringify(st16));
check("…and changes no job in Ace", after16.latest === before16.latest && jobPrint(after16.all) === jobPrint(before16.all));
const tom16 = jobOf(after16.all, "Tom Walsh Jr");
await push([{ type: "job", id: tom16.id, updatedAt: Date.now(), deleted: false, data: { ...tom16.data, price: 360 } }]);
await run();
rows = await fake("/test/rows");
check("…and a device edit after the sort lands on that job's own row", rows.find((r) => r.name === "Tom Walsh Jr")?.price === 360 && rows.filter((r) => r.price === 360).length === 1, JSON.stringify(rows.filter((r) => r.price === 360 || r.name === "Tom Walsh Jr")));

// A sort plus one edit in the sheet: only the edited job changes.
await fake("/test/scramble", {});
rows = await fake("/test/rows");
await fake("/test/set", { row: rows.findIndex((r) => r.name === "Mark Pereira") + 1, col: 5, value: 480 });
const before16c = await records();
await run();
after16 = await records();
const changed16c = [...after16.all.values()].filter((r) => r.seq > before16c.latest);
check("A sort plus one edit: no pause, and only that job changed", !(await post("/v1/google/status")).paused && changed16c.length === 1 && changed16c[0].id === mark2.id && changed16c[0].data.price === 480, JSON.stringify(changed16c.map((r) => [r.type, r.data.price])));

// A sort plus two edits cannot be told apart: pause, with the way back.
const before16d = await records();
await fake("/test/scramble", {});
rows = await fake("/test/rows");
const saved16 = [rows[0].price, rows[1].price];
await fake("/test/set", { row: 1, col: 5, value: 901 });
await fake("/test/set", { row: 2, col: 5, value: 902 });
await run();
const st16d = await post("/v1/google/status");
check("A sort plus two edits pauses and says how to undo the sort", !!st16d.paused && st16d.paused.includes("Edit > Undo"), JSON.stringify(st16d));
check("…and changes nothing in Ace", (await records()).latest === before16d.latest);
await fake("/test/set", { row: 1, col: 5, value: saved16[0] });
await fake("/test/set", { row: 2, col: 5, value: saved16[1] });
await fake("/test/scramble", {});
await post("/v1/google/resume"); await run();
after16 = await records();
check("…and after Undo and Resume every job is as it was", !(await post("/v1/google/status")).paused && after16.latest === before16d.latest && jobPrint(after16.all) === jobPrint(before16d.all));

// ---- 17. Two devices syncing at once never skip a change (audit M6).
const ids = Array.from({ length: 30 }, () => uuid());
const seenByA = new Map();
let sinceA = (await records()).latest;
const writerB = (async () => { for (const id of ids) await push([{ type: "customer", id, updatedAt: Date.now(), deleted: false, data: { name: "Race " + id.slice(0, 4), phone: "", address: "", notes: "", createdAt: Date.now() } }]); })();
for (let i = 0; i < 40; i++) {
  const r = await post("/v1/sync", { device: "A", since: sinceA, changes: [] });
  for (const c of r.changes) seenByA.set(c.id, c);
  sinceA = r.latest;
}
await writerB;
for (;;) { const r = await post("/v1/sync", { device: "A", since: sinceA, changes: [] }); for (const c of r.changes) seenByA.set(c.id, c); sinceA = r.latest; if (!r.more) break; }
check("Device A pulling while B writes 30 records gets all 30", ids.every((id) => seenByA.has(id)), `${ids.filter((id) => seenByA.has(id)).length}/30`);

// ---- 18. A renamed heading pauses instead of changing every job (fix-now 30).
await post("/v1/google/resume"); await run();
await fake("/test/set", { row: 0, col: 6, value: "Paid With" });
await run();
const st18 = await post("/v1/google/status");
check("Renamed heading pauses the link", !!st18.paused && st18.paused.includes("headings"), JSON.stringify(st18));
await fake("/test/set", { row: 0, col: 6, value: "Form of Payment" });
await post("/v1/google/resume"); await run();

// ---- 19. "Total Property Management" is a customer, not a totals line (fix-now 28).
const n19 = (await fake("/test/rows")).length;
await fake("/test/insert", { at: n19 + 1, row: [serial(2026, 10, 29), "Total Property Management", "5 Main St", "Fall River, MA", 500, "check", 777, "", false] });
await run();
({ all } = await records());
check("A customer named Total Property Management comes in", !!jobOf(all, "Total Property Management"));

// ---- 20. A sign-in that comes back without Ace's state token is refused (fix-now 31).
const bad = await (await fetch(SERVER + "/google/callback?code=fake-code&picked_file_ids=fake-sheet-1")).text();
check("A sign-in Ace did not start is refused", bad.includes("not connected"), bad.slice(0, 120));

// ---- 21. Ace deleting many jobs at once pauses instead of emptying her rows (Oct 24, 14 and 42).
const n21 = (await fake("/test/rows")).length;
for (let i = 0; i < 12; i++) await fake("/test/insert", { at: n21 + 1 + i, row: [serial(2026, 11, 20), `Gone ${i}`, `${i} Gone St`, "Swansea, MA", 90, "cash", "", "", false] });
await run();
({ all } = await records());
const gone = live(all, "job").filter((j) => all.get(`customer/${j.data.customer}`)?.data.name.startsWith("Gone "));
await push(gone.map((j) => ({ type: "job", id: j.id, updatedAt: Date.now(), deleted: true, data: {} })));
await run();
const st21 = await post("/v1/google/status");
check("12 jobs deleted in Ace at once pause the link", gone.length === 12 && st21.paused.includes("delete 12 rows"), JSON.stringify(st21));
check("…and no row leaves the sheet", (await fake("/test/rows")).length === n21 + 12);
await post("/v1/google/resume"); await run();
rows = await fake("/test/rows");
check("…and Resume lets them through", rows.length === n21 && !rows.some((r) => String(r.name).startsWith("Gone ")) && !(await post("/v1/google/status")).paused);

// ---- 22. Disconnect, then Connect the same sheet again (Oct 24, 15).
await post("/v1/google/disconnect");
check("Disconnect: status says not connected", (await post("/v1/google/status")).connected === false);
({ all } = await records());
const jobs22 = live(all, "job").length;
const tom22 = jobOf(all, "Tom Walsh Jr");
await push([{ type: "job", id: tom22.id, updatedAt: Date.now(), deleted: false, data: { ...tom22.data, price: 370, isPaid: false } }]);
await run();
check("…and the sheet is left alone while disconnected", (await fake("/test/rows")).find((r) => r.name === "Tom Walsh Jr")?.price === 360);
const start22 = await post("/v1/google/start");
const page22 = await (await fetch((await fetch(start22.url, { redirect: "manual" })).headers.get("location"))).text();
await run();
({ all } = await records());
rows = await fake("/test/rows");
const tomRow22 = rows.find((r) => r.name === "Tom Walsh Jr");
check("Connecting the same sheet again: a change made meanwhile reaches the sheet", page22.includes("Ace is connected to") && tomRow22?.price === 370 && tomRow22?.red === true, JSON.stringify(tomRow22));
check("…and no job is doubled", live(all, "job").length === jobs22 && rows.every((r) => r.tag !== null && r.tags === 1), `${live(all, "job").length} jobs, was ${jobs22}`);

// ---- 23. Rows with a blank Date cell keep their day when Ace changes the row above (Oct 24, 16).
const n23 = (await fake("/test/rows")).length;
const blanks = [[serial(2026, 12, 1), "Ann Blank"], ["", "Bob Blank"], ["", "Cat Blank"], [serial(2026, 12, 9), "Dan Blank"], ["", "Eve Blank"]];
for (const [i, [date, name]] of blanks.entries()) await fake("/test/insert", { at: n23 + 1 + i, row: [date, name, `${i + 1} Blank St`, "Westport, MA", 100 + i, "cash", "", "", false] });
await run();
({ all } = await records());
check("Rows with a blank date take the date above", jobOf(all, "Bob Blank")?.data.scheduledAt === bostonMidnight(2026, 12, 1) && jobOf(all, "Cat Blank")?.data.scheduledAt === bostonMidnight(2026, 12, 1) && jobOf(all, "Eve Blank")?.data.scheduledAt === bostonMidnight(2026, 12, 9));
const bob23 = jobOf(all, "Bob Blank");
await push([{ type: "job", id: bob23.id, updatedAt: Date.now(), deleted: false, data: { ...bob23.data, scheduledAt: bostonMidnight(2026, 12, 5) } }]);
await run(); await run();
({ all } = await records());
rows = await fake("/test/rows");
check("Moving a blank-date job in Ace leaves the next row on its day", jobOf(all, "Cat Blank")?.data.scheduledAt === bostonMidnight(2026, 12, 1) && rows.find((r) => r.name === "Bob Blank")?.date === serial(2026, 12, 5) && rows.find((r) => r.name === "Cat Blank")?.date === serial(2026, 12, 1), JSON.stringify(rows.filter((r) => /Blank/.test(r.name)).map((r) => [r.name, r.date])));
await push([{ type: "job", id: jobOf(all, "Dan Blank").id, updatedAt: Date.now(), deleted: true, data: {} }]);
await run(); await run();
({ all } = await records());
rows = await fake("/test/rows");
check("Deleting a dated row in Ace leaves the blank-date row under it on its day", !rows.some((r) => r.name === "Dan Blank") && jobOf(all, "Eve Blank")?.data.scheduledAt === bostonMidnight(2026, 12, 9) && rows.find((r) => r.name === "Eve Blank")?.date === serial(2026, 12, 9));

// ---- 24. A row typed while Ace is writing: nothing lands on the wrong row (Oct 24, 54).
({ all } = await records());
const ana24 = jobOf(all, "Ana Costa", 800);
await push([{ type: "job", id: ana24.id, updatedAt: Date.now(), deleted: false, data: { ...ana24.data, price: 820 } }]);
rows = await fake("/test/rows");
await fake("/test/insert-after-read", { at: rows.findIndex((r) => r.name === "Ana Costa" && r.price === 800) + 1, row: [serial(2026, 10, 15), "Late Typing", "6 Late St", "Westport, MA", 55, "cash", "", "", false] });
await run();
rows = await fake("/test/rows");
check("A row added between Ace's read and write: nothing is written", rows.find((r) => r.name === "Late Typing")?.price === 55 && rows.some((r) => r.name === "Ana Costa" && r.price === 800), JSON.stringify(rows.filter((r) => r.price === 820 || r.name === "Late Typing")));
await run();
({ all } = await records());
rows = await fake("/test/rows");
check("…and the next check writes to the right row", rows.some((r) => r.name === "Ana Costa" && r.price === 820) && rows.find((r) => r.name === "Late Typing")?.price === 55 && jobOf(all, "Late Typing")?.data.price === 55);

// ---- 25. A tag number something else in the file uses (Oct 24, 55).
const { ids: reserved } = await fake("/test/reserve-next-ids", { count: 3 });
const n25 = (await fake("/test/rows")).length;
await fake("/test/insert", { at: n25 + 1, row: [serial(2026, 12, 20), "Clash Test", "7 Clash St", "Westport, MA", 75, "cash", "", "", false] });
await run();
const st25 = await post("/v1/google/status");
check("A tag number already used elsewhere: that check fails", st25.lastError.includes("already in use"), JSON.stringify(st25));
await run();
({ all } = await records());
const clash = (await fake("/test/rows")).filter((r) => r.name === "Clash Test");
check("…and the next one uses other numbers", !(await post("/v1/google/status")).lastError && clash.length === 1 && clash[0].tag > Math.max(...reserved) && live(all, "job").filter((j) => j.data.price === 75).length === 1, JSON.stringify([reserved, clash]));

// ---- 26. Totals lines labelled other ways are not jobs (Oct 24, 17).
const n26 = (await fake("/test/rows")).length;
const jobs26 = live((await records()).all, "job").length;
await fake("/test/insert", { at: n26 + 1, row: ["TOTAL", "", "", "", 244250, "", "", "", false] });
await fake("/test/insert", { at: n26 + 2, row: ["", "October Total", "", "", 9000, "", "", "", false] });
await run();
({ all } = await records());
check("\"TOTAL\" in the Date column and \"October Total\" do not become jobs", live(all, "job").length === jobs26 && !(await post("/v1/google/status")).lastError);

// ---- 27. Reading rules on their own (src/sheet.js).
const { isRed, readSheet } = await import("../src/sheet.js");
const fill = (hex) => ({ effectiveFormat: { backgroundColorStyle: { rgbColor: { red: parseInt(hex.slice(0, 2), 16) / 255, green: parseInt(hex.slice(2, 4), 16) / 255, blue: parseInt(hex.slice(4, 6), 16) / 255 } } } });
check("Reds read as not paid: ff0000 cc0000 e06666 ea9999 f4cccc 990000 660000", ["ff0000", "cc0000", "e06666", "ea9999", "f4cccc", "990000", "660000"].every((h) => isRed(fill(h))));
check("Not red: orange, yellow, green, light magenta, grey, white", ["ff9900", "e69138", "fce5cd", "ffff00", "b6d7a8", "ead1dc", "cccccc", "ffffff", "000000"].every((h) => !isRed(fill(h))));
check("A theme colour that is red reads as red", isRed({ effectiveFormat: { backgroundColorStyle: { themeColor: "ACCENT2" } } }, { ACCENT2: { red: 0.92, green: 0.26, blue: 0.21 } }) && !isRed({ effectiveFormat: { backgroundColorStyle: { themeColor: "ACCENT3" } } }, { ACCENT3: { red: 0.98, green: 0.74, blue: 0.02 } }));
const textRow = (cells) => ({ values: cells.map((v) => (v === "" ? {} : typeof v === "number" ? { effectiveValue: { numberValue: v } } : { effectiveValue: { stringValue: v }, formattedValue: v })) });
const tab = (sheetId, title, rowsIn) => ({ properties: { sheetId, title }, data: [{ rowData: rowsIn.map(textRow) }] });
const book = {
  properties: { title: "2027 ACE Books" },
  sheets: [
    tab(0, "Client Job List", [["Date", "Customer Name", "# and Street Name", "City State & Zip", "Price"], [serial(2027, 1, 4), "Ann", "1 A St", "Westport", 100]]),
    tab(1, "Contracted Labor", [["Name", "Date", "Hours", "Amount"], ...Array.from({ length: 8 }, (_, i) => [`Crew ${i}`, serial(2027, 1, 4), 8, 160])]),
  ],
};
check("A new year's sheet picks the Client Job List tab, not a longer crew tab", readSheet(book)?.tabName === "Client Job List");
check("…and the tab already in use is kept", readSheet(book, 1)?.tabName === "Contracted Labor");

console.log(failures ? `\n${failures} failed` : "\nAll passed");
process.exit(failures ? 1 : 0);
