// A first connection to a 600-row sheet, like a real year of Ashley's.
// Run with: TEST=test/sheet-scale-test.mjs test/run-sheet-test.sh
import { readFileSync } from "node:fs";
const SERVER = "http://localhost:8788", FAKE = "http://localhost:8790";
const KEY = readFileSync(new URL("../.dev.vars", import.meta.url), "utf8").match(/SYNC_KEY="([^"]*)"/)[1];
const post = async (p, b = {}) => (await fetch(SERVER + p, { method: "POST", headers: { Authorization: `Bearer ${KEY}` }, body: JSON.stringify(b) })).json();
const fake = async (p, b) => (await fetch(FAKE + p, { method: b ? "POST" : "GET", body: b ? JSON.stringify(b) : undefined })).json();
const serial = (y, m, d) => Math.round((Date.UTC(y, m - 1, d) - Date.UTC(1899, 11, 30)) / 86400000);

const rows = [];
for (let i = 0; i < 600; i++) {
  const day = 1 + Math.floor(i / 2.1);
  const date = new Date(Date.UTC(2026, 0, 5 + day));
  rows.push([serial(date.getUTCFullYear(), date.getUTCMonth() + 1, date.getUTCDate()), `Customer ${i % 480}`, `${i % 480 + 1} Elm St`, "Dartmouth, MA 02747", 100 + (i % 12) * 50, ["check", "venmo", "cash", "cash app"][i % 4], i % 4 === 0 ? 1000 + i : "", "", i % 17 === 0]);
}
await fake("/test/reset", { rows });
const start = await post("/v1/google/start");
const back = (await fetch(start.url, { redirect: "manual" })).headers.get("location");
const connected = await (await fetch(back)).text();
console.log("connect:", JSON.stringify(start).slice(0, 80), connected.replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").slice(0, 160));
let t = Date.now();
await post("/v1/google/run");
const first = Date.now() - t;
console.log("after first check:", JSON.stringify(await post("/v1/google/status")));
let since = 0, jobs = 0, customers = 0;
for (;;) {
  const r = await post("/v1/sync", { device: "t", since, changes: [] });
  for (const c of r.changes) { if (!c.deleted && c.type === "job") jobs++; if (!c.deleted && c.type === "customer") customers++; }
  since = r.latest; if (!r.more) break;
}
const tagged = (await fake("/test/rows")).filter((r) => r.tag !== null && r.tags === 1).length;
t = Date.now(); await post("/v1/google/run"); const idle = Date.now() - t;
const st = await post("/v1/google/status");
console.log(`first check: ${first} ms, ${jobs} jobs, ${customers} customers, ${tagged}/600 rows tagged; next check with no changes: ${idle} ms; error: "${st.lastError}"`);
process.exit(jobs === 600 && customers === 480 && tagged === 600 && !st.lastError ? 0 : 1);
