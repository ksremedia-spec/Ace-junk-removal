// Fills the stand-in Google's sheet with 40 jobs in Ashley's layout, for
// trying the apps against it (test/fake-google.mjs must be running).
const serial = (y, m, d) => Math.round((Date.UTC(y, m - 1, d) - Date.UTC(1899, 11, 30)) / 86400000);
const people = [["Linda Johnson", "42 Elm St", "Taunton, MA 02780"], ["Mark Pereira", "15 Bay Rd", "Fall River, MA 02720"],
  ["Joe Souza", "??? Main Rd", "Westport, MA 02790"], ["Ana Costa", "9 Hope St", "New Bedford, MA 02740"],
  ["Tom Walsh", "3 Pine St", "Dartmouth, MA 02747"], ["Rose Tavares", "77 Ocean Ave", "Fairhaven, MA 02719"],
  ["Dave Medeiros", "120 County St", "Somerset, MA 02726"], ["Karen Sullivan", "8 Shipyard Ln", "Mattapoisett, MA 02739"]];
const pay = ["check", "venmo", "cash", "cash app"];
const rows = [];
for (let i = 0; i < 40; i++) {
  const [name, street, city] = people[i % people.length];
  const day = new Date(Date.UTC(2026, 8, 1 + Math.floor(i * 1.3)));
  rows.push([serial(day.getUTCFullYear(), day.getUTCMonth() + 1, day.getUTCDate()), name, street, city,
    [150, 300, 450, 600, 250][i % 5], pay[i % 4], i % 4 === 0 ? 1100 + i : "", i % 9 === 0 ? "XXX" : "", i % 6 === 0]);
}
await fetch("http://localhost:8790/test/reset", { method: "POST", body: JSON.stringify({ rows }) });
console.log("seeded", rows.length, "rows");
