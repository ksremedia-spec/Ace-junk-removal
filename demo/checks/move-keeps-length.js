// Moving a job keeps its length: the check reads Linda Johnson's job length in the sample data, moves the
// job to 2:00 PM through the Assistant, and expects the same length after the move.
const { open, done, A, refIn } = require('./harness');
const toMin = t => { const [h, m] = t.split(':').map(Number); return h * 60 + m; };
(async () => {
  const h = await open(); const p = h.page;
  const before = (await h.state()).jobs.find(x => x.id === 'j1');
  const length = toMin(before.end) - toMin(before.time);
  h.plan = (note, records) => ({ reply: '', actions: [A({ type: 'update_job', ref: refIn(records, /- (J\d+) [^\n]*Linda Johnson[^\n]*not done/), newTime: '14:00' })], issues: [] });
  await h.say('move Johnson to 2', 800);
  await p.click('#overlay [data-action="assistant-update-save"]'); await p.waitForTimeout(200);
  if (await h.hasDialog()) { await p.click('#overlay .dialog button.bold'); await p.waitForTimeout(200); }
  const j = (await h.state()).jobs.find(x => x.id === 'j1');
  const ok = j.time === '14:00' && toMin(j.end) - toMin(j.time) === length && !h.errors.length;
  console.log((ok ? 'ok   ' : 'FAIL ') + `moved job keeps its length (${before.time} to ${before.end} became ${j.time} to ${j.end})` + (h.errors.length ? '  [' + h.errors.join(' | ') + ']' : ''));
  console.log(ok ? 'ALL MOVE CHECKS OK' : '1 FAILED');
  await h.close(); await done();
  if (!ok) process.exitCode = 1;
})();
